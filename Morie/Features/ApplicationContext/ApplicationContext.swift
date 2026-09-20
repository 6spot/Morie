import Foundation

/// A lightweight identity for the application that owned keyboard focus when a
/// Capture started.
struct ApplicationIdentity: Equatable, Sendable {
    let name: String?
    let bundleIdentifier: String?
}

/// Immutable request pinned at Capture Start before any Accessibility IPC runs.
struct ApplicationContextCaptureRequest: Equatable, Sendable {
    let application: ApplicationIdentity
    let processIdentifier: Int32
    let capturedAt: Date
}

/// Ephemeral context captured for one voice-input Capture.
///
/// This type is intentionally not Codable. Raw application text must remain a
/// runtime-only aid and must never become part of Capture persistence, History,
/// diagnostics, Memory, or other durable user data.
struct ApplicationContextSnapshot: Equatable, Sendable {
    let application: ApplicationIdentity
    let selectedText: String?
    let focusedText: String?
    let nearbyText: String?
    let capturedAt: Date

    var selectedCharacterCount: Int { selectedText?.count ?? 0 }
    var focusedCharacterCount: Int { focusedText?.count ?? 0 }
    var nearbyCharacterCount: Int { nearbyText?.count ?? 0 }

    var hasReadableText: Bool {
        selectedCharacterCount > 0
            || focusedCharacterCount > 0
            || nearbyCharacterCount > 0
    }
}


/// Extracts a small, high-signal vocabulary from ephemeral application text for
/// Apple Speech contextual biasing. It deliberately favors identifiers and
/// proper-name-like Latin tokens instead of sending page text to Speech.
enum ApplicationContextVocabulary {
    static let maximumTerms = 32

    static func extract(
        from snapshot: ApplicationContextSnapshot,
        limit: Int = maximumTerms
    ) -> [String] {
        guard limit > 0 else { return [] }

        let sources: [(text: String?, priority: Int)] = [
            (snapshot.selectedText, 300),
            (snapshot.focusedText, 200),
            (snapshot.nearbyText, 100),
        ]

        struct RankedTerm {
            let value: String
            let score: Int
            let order: Int
        }

        var ranked: [String: RankedTerm] = [:]
        var order = 0

        for source in sources {
            guard let text = source.text, !text.isEmpty else { continue }
            for candidate in candidates(in: text) {
                defer { order += 1 }
                guard let quality = qualityScore(candidate) else { continue }

                let key = canonical(candidate)
                let item = RankedTerm(
                    value: candidate,
                    score: source.priority + quality,
                    order: order
                )
                if let current = ranked[key],
                   current.score > item.score
                    || (current.score == item.score && current.order <= item.order) {
                    continue
                }
                ranked[key] = item
            }
        }

        return ranked.values
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.order < $1.order
            }
            .prefix(min(limit, maximumTerms))
            .map(\.value)
    }

    private static func candidates(in text: String) -> [String] {
        let pattern = #"(?<![A-Za-z0-9_])[A-Za-z][A-Za-z0-9._+-]{1,63}(?![A-Za-z0-9_])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap {
            guard let range = Range($0.range, in: text) else { return nil }
            return String(text[range])
                .trimmingCharacters(in: CharacterSet(charactersIn: "._+-"))
        }
        .filter { !$0.isEmpty }
    }

    private static func qualityScore(_ term: String) -> Int? {
        guard (2...64).contains(term.count) else { return nil }

        let scalars = term.unicodeScalars
        let hasUpper = scalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        let hasLower = scalars.contains { CharacterSet.lowercaseLetters.contains($0) }
        let hasDigit = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        let tailHasUpper = term.dropFirst().unicodeScalars.contains {
            CharacterSet.uppercaseLetters.contains($0)
        }
        let allUpper = hasUpper && !hasLower && term.count <= 12
        let mixedCase = hasUpper && hasLower && tailHasUpper
        let identifierPunctuation = term.contains("_")
            || term.contains("-")
            || term.contains("+")
        let dottedIdentifier = term.contains(".") && (hasUpper || hasDigit)

        if identifierPunctuation { return 80 + min(term.count, 16) }
        if mixedCase { return 70 + min(term.count, 16) }
        if allUpper { return 60 + min(term.count, 12) }
        if hasDigit && hasUpper { return 55 + min(term.count, 12) }
        if dottedIdentifier { return 50 + min(term.count, 12) }

        guard let first = term.unicodeScalars.first,
              CharacterSet.uppercaseLetters.contains(first),
              term.count >= 4,
              !commonCapitalizedWords.contains(term.lowercased())
        else {
            return nil
        }
        return 30 + min(term.count, 16)
    }

    private static func canonical(_ term: String) -> String {
        term.folding(
            options: [.caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static let commonCapitalizedWords: Set<String> = [
        "this", "that", "these", "those", "there", "here",
        "when", "where", "what", "which", "while", "with",
        "from", "into", "about", "please", "then", "than",
        "first", "second", "finally", "because", "however",
    ]
}
