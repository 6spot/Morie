import Combine
import Foundation
import NaturalLanguage
import SwiftData

enum SpeechTranscriptAssembler {
    /// SpeechTranscriber owns whitespace and punctuation across result segments.
    /// Inserting a separator here breaks Chinese into text such as "常 蚊 子".
    static func join(_ lhs: String, _ rhs: String) -> String { lhs + rhs }
}

struct DictionaryDraft: Equatable, Sendable {
    var name = ""
}

enum DictionaryEntrySource: String, Codable, Equatable, Sendable {
    case builtIn
    case manual
    case correction

    var helpText: String {
        switch self {
        case .builtIn: "Morie 内置词语"
        case .manual: "手动添加"
        case .correction: "纠错确认添加"
        }
    }
}

struct DictionaryDisplayEntry: Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let source: DictionaryEntrySource

    var isEditable: Bool { source != .builtIn }
}

private enum BuiltinDictionary {
    private static let updatedAt = Date(timeIntervalSince1970: 0)

    static let entries: [DictionaryDisplayEntry] = [
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000001")!, name: "Morie", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000002")!, name: "GitHub", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000003")!, name: "ChatGPT", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000004")!, name: "Claude", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000005")!, name: "Claude Code", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000006")!, name: "Codex", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000007")!, name: "Gemini", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000008")!, name: "OpenAI", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-000000000009")!, name: "DeepSeek", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-00000000000A")!, name: "Qwen", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-00000000000B")!, name: "MCP", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-00000000000C")!, name: "Xcode", source: .builtIn),
        .init(id: UUID(uuidString: "B17D0000-0000-0000-0000-00000000000D")!, name: "SwiftUI", source: .builtIn),
    ]

    static var snapshots: [DictionarySnapshot] {
        entries.map { DictionarySnapshot(id: $0.id, name: $0.name, updatedAt: updatedAt) }
    }
}

struct DictionarySnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let updatedAt: Date
}


struct DictionaryCorrectionSnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let original: String
    let replacement: String
    let updatedAt: Date
}

@Model
final class DictionaryCorrectionRule {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var original: String = ""
    var replacement: String = ""
    var confirmationCount: Int = 1

    init(original: String, replacement: String) {
        self.original = original
        self.replacement = replacement
    }

    var snapshot: DictionaryCorrectionSnapshot {
        DictionaryCorrectionSnapshot(
            id: id,
            original: original,
            replacement: replacement,
            updatedAt: updatedAt
        )
    }
}

@Model
final class DictionaryEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var name: String = ""
    // Optional so current development data written before source tracking remains readable.
    var sourceRawValue: String?

    init(_ draft: DictionaryDraft, source: DictionaryEntrySource = .manual) {
        name = draft.name
        sourceRawValue = source == .correction ? DictionaryEntrySource.correction.rawValue : DictionaryEntrySource.manual.rawValue
    }

    var source: DictionaryEntrySource {
        DictionaryEntrySource(rawValue: sourceRawValue ?? "") ?? .manual
    }

    var snapshot: DictionarySnapshot { DictionarySnapshot(id: id, name: name, updatedAt: updatedAt) }
}

@MainActor
final class DictionaryStore: ObservableObject {
    enum StoreError: LocalizedError {
        case invalidName, duplicateWord, unavailable

        var errorDescription: String? {
            switch self {
            case .invalidName: "请输入 1–120 个字符的词语，不要换行。"
            case .duplicateWord: "字典中已有这个词语。"
            case .unavailable: "此字典词语已不存在。"
            }
        }
    }

    @Published private(set) var entries: [DictionaryEntry] = []

    var displayEntries: [DictionaryDisplayEntry] {
        let user = entries.map { DictionaryDisplayEntry(id: $0.id, name: $0.name, source: $0.source) }
        let userKeys = Set(user.map { Self.wordKey($0.name) })
        let builtIns = BuiltinDictionary.entries.filter { !userKeys.contains(Self.wordKey($0.name)) }
        return (user + builtIns).sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws {
        entries = try context.fetch(FetchDescriptor<DictionaryEntry>(sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    func create(_ draft: DictionaryDraft, source: DictionaryEntrySource = .manual) throws -> UUID {
        let draft = try validate(draft)
        try requireNewWord(draft.name)
        let entry = DictionaryEntry(draft, source: source)
        context.insert(entry)
        try save()
        return entry.id
    }

    func update(_ id: UUID, draft: DictionaryDraft) throws {
        let draft = try validate(draft)
        try requireNewWord(draft.name, excluding: id)
        let entry = try entry(id)
        entry.name = draft.name
        entry.updatedAt = Date()
        try save()
    }

    func delete(_ id: UUID) throws {
        let removed = try entry(id)
        let removedKey = Self.correctionKey(removed.name)
        let rules = try context.fetch(FetchDescriptor<DictionaryCorrectionRule>())
        for rule in rules where Self.correctionKey(rule.replacement) == removedKey {
            context.delete(rule)
        }
        context.delete(removed)
        try save()
    }

    @discardableResult
    func saveConfirmedCorrection(original: String, replacement: String) throws -> UUID {
        let original = try validateCorrectionText(original)
        let replacement = try validateCorrectionText(replacement)
        guard Self.correctionKey(original) != Self.correctionKey(replacement) else {
            throw StoreError.invalidName
        }

        if try !containsEffectiveWord(replacement) {
            _ = try create(DictionaryDraft(name: replacement), source: .correction)
        }

        let originalKey = Self.correctionKey(original)
        let rules = try context.fetch(FetchDescriptor<DictionaryCorrectionRule>())
        if let existing = rules.first(where: { Self.correctionKey($0.original) == originalKey }) {
            existing.original = original
            existing.replacement = replacement
            existing.updatedAt = Date()
            existing.confirmationCount += 1
            try save()
            return existing.id
        }

        let rule = DictionaryCorrectionRule(original: original, replacement: replacement)
        context.insert(rule)
        try save()
        return rule.id
    }

    func confirmedCorrections() throws -> [DictionaryCorrectionSnapshot] {
        let rules = try context.fetch(
            FetchDescriptor<DictionaryCorrectionRule>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )
        var characters = 0
        return rules.prefix(100).compactMap { rule in
            let cost = rule.original.count + rule.replacement.count
            guard characters + cost <= 2_000 else { return nil }
            characters += cost
            return rule.snapshot
        }
    }


    func hasConfirmedCorrection(original: String, replacement: String) throws -> Bool {
        let originalKey = Self.correctionKey(original)
        let replacementKey = Self.correctionKey(replacement)
        return try context.fetch(FetchDescriptor<DictionaryCorrectionRule>()).contains {
            Self.correctionKey($0.original) == originalKey
                && Self.correctionKey($0.replacement) == replacementKey
        }
    }


    func relevantEntries(for text: String) throws -> [DictionarySnapshot] {
        _ = text
        return try contextualEntries()
    }

    func speechHints() throws -> [String] {
        try contextualEntries().map(\.name)
    }

    func containsEffectiveWord(_ name: String) throws -> Bool {
        try load()
        let key = Self.wordKey(name)
        return entries.contains { Self.wordKey($0.name) == key }
            || BuiltinDictionary.entries.contains { Self.wordKey($0.name) == key }
    }

    /// Speech and cleanup receive the same bounded dictionary. Requiring an
    /// exact transcript match here would hide the correct spelling precisely
    /// when recognition produced a near-homophone such as Coldex for Codex.
    private func contextualEntries() throws -> [DictionarySnapshot] {
        try load()
        let userKeys = Set(entries.map { Self.wordKey($0.name) })
        let candidates = entries.sorted { $0.updatedAt > $1.updatedAt }.map(\.snapshot)
            + BuiltinDictionary.snapshots.filter { !userKeys.contains(Self.wordKey($0.name)) }
        var characters = 0
        return candidates.prefix(100).compactMap { entry in
            guard characters + entry.name.count <= 2_000 else { return nil }
            characters += entry.name.count
            return entry
        }
    }

    private func entry(_ id: UUID) throws -> DictionaryEntry {
        guard let entry = try context.fetch(FetchDescriptor<DictionaryEntry>(predicate: #Predicate { $0.id == id })).first
        else { throw StoreError.unavailable }
        return entry
    }

    private func validate(_ draft: DictionaryDraft) throws -> DictionaryDraft {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet.controlCharacters.union(.newlines)
        guard !name.isEmpty, name.count <= 120,
              !name.unicodeScalars.contains(where: invalidCharacters.contains) else { throw StoreError.invalidName }
        return DictionaryDraft(name: name)
    }


    private func validateCorrectionText(_ text: String) throws -> String {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let invalidCharacters = CharacterSet.controlCharacters.union(.newlines)
        guard (2...64).contains(text.count),
              !text.unicodeScalars.contains(where: invalidCharacters.contains) else {
            throw StoreError.invalidName
        }
        return text
    }

    private func requireNewWord(_ name: String, excluding id: UUID? = nil) throws {
        try load()
        let key = Self.wordKey(name)
        guard !entries.contains(where: { entry in
            entry.id != id && Self.wordKey(entry.name) == key
        }) else { throw StoreError.duplicateWord }
    }

    private static func wordKey(_ text: String) -> String {
        text.folding(options: [.caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }


    private static func correctionKey(_ text: String) -> String {
        text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
        try load()
    }
}

enum DictionaryCorrections {
    static func apply(
        _ text: String,
        using rules: [DictionaryCorrectionSnapshot]
    ) -> ValidatedRefinement {
        guard !rules.isEmpty, !text.isEmpty else {
            return ValidatedRefinement(text: text, edits: [])
        }

        let protected = InputText.technicalRanges(in: text)
        let wordRanges = InputText.words(in: text)
        var candidates: [(range: Range<String.Index>, rule: DictionaryCorrectionSnapshot)] = []

        for rule in rules {
            let ranges: [Range<String.Index>]
            if containsCJK(rule.original) {
                ranges = literalSubstringRanges(of: rule.original, in: text)
            } else {
                ranges = InputText.literalRanges(of: rule.original, in: text, wordRanges: wordRanges)
            }
            for range in ranges {
                guard !protected.contains(where: { $0.overlaps(range) }) else { continue }
                candidates.append((range, rule))
            }
        }

        candidates.sort {
            if $0.range.lowerBound != $1.range.lowerBound {
                return $0.range.lowerBound < $1.range.lowerBound
            }
            let lhs = text.distance(from: $0.range.lowerBound, to: $0.range.upperBound)
            let rhs = text.distance(from: $1.range.lowerBound, to: $1.range.upperBound)
            return lhs > rhs
        }

        var selected: [(range: Range<String.Index>, rule: DictionaryCorrectionSnapshot)] = []
        for candidate in candidates where !selected.contains(where: { $0.range.overlaps(candidate.range) }) {
            selected.append(candidate)
        }

        var output = text
        var edits: [RefinementEdit] = []
        for match in selected.reversed() {
            let original = String(text[match.range])
            guard original != match.rule.replacement else { continue }
            output.replaceSubrange(match.range, with: match.rule.replacement)
            edits.append(
                RefinementEdit(
                    original: original,
                    replacement: match.rule.replacement,
                    correctionRuleID: match.rule.id
                )
            )
        }
        edits.reverse()
        return ValidatedRefinement(text: output, edits: edits)
    }

    private static func literalSubstringRanges(
        of term: String,
        in text: String
    ) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }
        var start = text.startIndex
        var ranges: [Range<String.Index>] = []
        while start < text.endIndex,
              let range = text.range(
                of: term,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: start..<text.endIndex
              ) {
            ranges.append(range)
            start = range.upperBound
        }
        return ranges
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
                true
            default:
                false
            }
        }
    }
}

enum DictionarySpelling {
    /// Normalize only the same word's letter case; a saved word never implies a substitution rule.
    static func normalize(_ text: String, using entries: [DictionarySnapshot]) -> ValidatedRefinement {
        let protected = InputText.technicalRanges(in: text)
        let wordRanges = InputText.words(in: text)
        var matches: [(range: Range<String.Index>, entry: DictionarySnapshot)] = []
        for entry in entries {
            for range in InputText.literalRanges(of: entry.name, in: text, wordRanges: wordRanges) {
                guard !protected.contains(where: { $0.overlaps(range) }) else { continue }
                matches.append((range, entry))
            }
        }
        matches.sort {
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.range.upperBound > $1.range.upperBound
        }
        var selected: [(range: Range<String.Index>, entry: DictionarySnapshot)] = []
        for match in matches where !selected.contains(where: { $0.range.overlaps(match.range) }) { selected.append(match) }
        // An already-correct longer term still takes precedence over a shorter overlapping word.
        let changes = selected.filter { String(text[$0.range]) != $0.entry.name }
        var output = text
        for match in changes.reversed() { output.replaceSubrange(match.range, with: match.entry.name) }
        return ValidatedRefinement(text: output, edits: changes.map {
            RefinementEdit(original: String(text[$0.range]), replacement: $0.entry.name, dictionaryEntryID: $0.entry.id)
        })
    }
}

/// Native word boundaries prevent a short dictionary term from replacing part of another word.
enum InputText {
    static func words(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var result: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in result.append(range); return true }
        return result
    }

    static func literalRanges(of term: String, in text: String) -> [Range<String.Index>] {
        literalRanges(of: term, in: text, wordRanges: words(in: text))
    }

    static func literalRanges(
        of term: String,
        in text: String,
        wordRanges: [Range<String.Index>]
    ) -> [Range<String.Index>] {
        guard !term.isEmpty else { return [] }
        var start = text.startIndex
        var matches: [Range<String.Index>] = []
        while start < text.endIndex,
              let range = text.range(of: term, options: [.caseInsensitive], range: start..<text.endIndex) {
            if !wordRanges.contains(where: {
                ($0.lowerBound < range.lowerBound && range.lowerBound < $0.upperBound)
                    || ($0.lowerBound < range.upperBound && range.upperBound < $0.upperBound)
            }) { matches.append(range) }
            start = range.upperBound
        }
        return matches
    }

    static func ranges(_ pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text))
            .compactMap { Range($0.range, in: text) }
    }

    static func technicalRanges(in text: String) -> [Range<String.Index>] {
        // Code, addresses, paths, flags and identifiers must not be interpreted as dictated prose.
        ranges(#"(?s)```.*?```|`[^`]*`|(?:https?://|www\.)[^\s<>]+|[\w.+-]+@[\w.-]+\.[A-Za-z]+|(?:/|~/)[\w./-]+|\b[\w]+_[\w]+\b|(?<!\w)--[\w-]+|\b[A-Za-z]+\+\+|\b[A-Za-z]+#|\b[A-Za-z]+\d+(?:\.\d+)+"#, in: text)
    }
}
