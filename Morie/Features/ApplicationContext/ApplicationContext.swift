import Combine
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
/// This type is intentionally not Codable. Raw application text must never
/// become part of Capture persistence, History or Memory. Debug development
/// builds may emit bounded raw text into the local development diagnostic log
/// so context collection can be investigated; Release diagnostics never do.
struct ApplicationContextSnapshot: Equatable, Sendable {
    let application: ApplicationIdentity
    let selectedText: String?
    let cursorText: String?
    let capturedAt: Date

    var selectedCharacterCount: Int { selectedText?.count ?? 0 }
    var cursorCharacterCount: Int { cursorText?.count ?? 0 }

    var hasReadableText: Bool {
        selectedCharacterCount > 0 || cursorCharacterCount > 0
    }
}


/// The source of a transient Speech hint within the captured application context.
enum ApplicationContextHintSource: String, CaseIterable, Hashable, Sendable {
    case selected
    case cursor

    var title: String {
        switch self {
        case .selected: "选中文字"
        case .cursor: "光标上下文"
        }
    }
}

struct ApplicationContextVocabularyHint: Identifiable, Equatable, Sendable {
    let value: String
    let source: ApplicationContextHintSource

    var id: String {
        "\(source.rawValue):\(value.folding(options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX")))"
    }
}

/// Runtime-only UI visibility into the latest Application Context vocabulary
/// decision. This store itself is never serialized. Debug builds separately
/// emit an explicit Dev/* trace to the local diagnostic file.
@MainActor
final class ApplicationContextInspectionStore: ObservableObject {
    struct Snapshot: Equatable {
        let captureLabel: String
        let application: ApplicationIdentity
        let capturedAt: Date
        let selectedCharacterCount: Int
        let cursorCharacterCount: Int
        let selectedPreview: String?
        let cursorPreview: String?
        let dictionaryHintCount: Int
        let contextualHintCount: Int
        let hints: [ApplicationContextVocabularyHint]
    }

    @Published private(set) var latest: Snapshot?

    func publish(
        captureID: UUID,
        context: ApplicationContextSnapshot,
        hints: [ApplicationContextVocabularyHint],
        dictionaryHintCount: Int,
        contextualHintCount: Int
    ) {
        latest = Snapshot(
            captureLabel: String(captureID.uuidString.prefix(8)),
            application: context.application,
            capturedAt: context.capturedAt,
            selectedCharacterCount: context.selectedCharacterCount,
            cursorCharacterCount: context.cursorCharacterCount,
            selectedPreview: Self.preview(context.selectedText),
            cursorPreview: Self.preview(context.cursorText),
            dictionaryHintCount: dictionaryHintCount,
            contextualHintCount: contextualHintCount,
            hints: hints
        )
    }

    private static func preview(
        _ text: String?,
        limit: Int = 320
    ) -> String? {
        guard let text else { return nil }
        let normalized = text
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }
        if normalized.count <= limit {
            return normalized
        }
        return String(normalized.prefix(limit)) + "…"
    }
}

/// Extracts a small, high-signal vocabulary from ephemeral application text for
/// Apple Speech contextual biasing. It deliberately favors identifiers and
/// proper-name-like Latin tokens instead of sending page text to Speech.
enum ApplicationContextVocabulary {
    static let maximumTerms = 32

    static func inspect(
        from snapshot: ApplicationContextSnapshot,
        limit: Int = maximumTerms,
        captureID: UUID? = nil
    ) -> [ApplicationContextVocabularyHint] {
        guard limit > 0 else { return [] }

        let sources: [
            (
                text: String?,
                source: ApplicationContextHintSource,
                priority: Int
            )
        ] = [
            (snapshot.selectedText, .selected, 300),
            (snapshot.cursorText, .cursor, 200),
        ]

        struct RankedTerm {
            let value: String
            let source: ApplicationContextHintSource
            let score: Int
            let order: Int
        }

        var ranked: [String: RankedTerm] = [:]
        var order = 0

        for source in sources {
            guard let text = source.text, !text.isEmpty else { continue }
            for candidate in candidates(in: text) {
                defer { order += 1 }
                guard let quality = qualityScore(candidate) else {
                    DevelopmentDiagnostics.record(
                        "Vocabulary",
                        captureID: captureID,
                        "candidate=\(candidate); source=\(source.source.rawValue); decision=rejectedQuality"
                    )
                    continue
                }

                let key = canonical(candidate)
                let item = RankedTerm(
                    value: candidate,
                    source: source.source,
                    score: source.priority + quality,
                    order: order
                )
                if let current = ranked[key],
                   current.score > item.score
                    || (current.score == item.score && current.order <= item.order) {
                    DevelopmentDiagnostics.record(
                        "Vocabulary",
                        captureID: captureID,
                        "candidate=\(candidate); source=\(source.source.rawValue); quality=\(quality); score=\(item.score); decision=deduplicated; kept=\(current.value); keptSource=\(current.source.rawValue); keptScore=\(current.score)"
                    )
                    continue
                }
                DevelopmentDiagnostics.record(
                    "Vocabulary",
                    captureID: captureID,
                    "candidate=\(candidate); source=\(source.source.rawValue); quality=\(quality); score=\(item.score); decision=ranked"
                )
                ranked[key] = item
            }
        }

        let ordered = ranked.values.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.order < $1.order
        }
        let selected = Array(ordered.prefix(min(limit, maximumTerms)))
        DevelopmentDiagnostics.list(
            "Vocabulary",
            captureID: captureID,
            label: "selected",
            selected.map { "\($0.value)@\($0.source.rawValue):\($0.score)" }
        )
        if ordered.count > selected.count {
            DevelopmentDiagnostics.list(
                "Vocabulary",
                captureID: captureID,
                label: "droppedByLimit",
                ordered.dropFirst(selected.count).map {
                    "\($0.value)@\($0.source.rawValue):\($0.score)"
                }
            )
        }

        return selected.map {
            ApplicationContextVocabularyHint(
                value: $0.value,
                source: $0.source
            )
        }
    }

    static func extract(
        from snapshot: ApplicationContextSnapshot,
        limit: Int = maximumTerms
    ) -> [String] {
        inspect(from: snapshot, limit: limit).map(\.value)
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
        let dottedIdentifier =
            term.contains(".")
            && term.split(separator: ".").count >= 2
            && term.unicodeScalars.allSatisfy {
                CharacterSet.alphanumerics.contains($0) || $0 == "."
            }

        if identifierPunctuation { return 80 + min(term.count, 16) }
        if mixedCase { return 70 + min(term.count, 16) }
        if allUpper { return 60 + min(term.count, 12) }
        if hasDigit { return 55 + min(term.count, 12) }
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
