import Combine
import Foundation
import NaturalLanguage
import SwiftData

struct DictionaryDraft: Equatable, Sendable {
    var name = ""
}

struct DictionarySnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let updatedAt: Date
}

@Model
final class DictionaryEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var name: String = ""

    init(_ draft: DictionaryDraft) { name = draft.name }

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
    private let context: ModelContext

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws {
        entries = try context.fetch(FetchDescriptor<DictionaryEntry>(sortBy: [SortDescriptor(\.name)]))
    }

    @discardableResult
    func create(_ draft: DictionaryDraft) throws -> UUID {
        let draft = try validate(draft)
        try requireNewWord(draft.name)
        let entry = DictionaryEntry(draft)
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

    func delete(_ id: UUID) throws { context.delete(try entry(id)); try save() }

    func relevantEntries(for text: String) throws -> [DictionarySnapshot] {
        try load()
        return entries.map(\.snapshot).filter { entry in
            !InputText.literalRanges(of: entry.name, in: text).isEmpty
        }
    }

    func speechHints() throws -> [String] {
        try load()
        // A bounded native Speech context containing the user's saved words.
        var characters = 0
        return entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(100).compactMap { entry in
            guard characters + entry.name.count <= 2_000 else { return nil }
            characters += entry.name.count
            return entry.name
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

    private func requireNewWord(_ name: String, excluding id: UUID? = nil) throws {
        try load()
        let key = MemoryText.normalized(name)
        guard !entries.contains(where: { entry in
            entry.id != id && MemoryText.normalized(entry.name) == key
        }) else { throw StoreError.duplicateWord }
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
        try load()
    }
}

enum DictionarySpelling {
    /// Normalize only the same word's case/width; a saved word never implies a substitution rule.
    static func normalize(_ text: String, using entries: [DictionarySnapshot]) -> ValidatedRefinement {
        let protected = InputText.technicalRanges(in: text)
        var matches: [(range: Range<String.Index>, entry: DictionarySnapshot)] = []
        for entry in entries {
            for range in InputText.literalRanges(of: entry.name, in: text) {
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
        guard !term.isEmpty else { return [] }
        let words = words(in: text)
        var start = text.startIndex
        var matches: [Range<String.Index>] = []
        while start < text.endIndex,
              let range = text.range(of: term, options: [.caseInsensitive, .widthInsensitive], range: start..<text.endIndex) {
            if !words.contains(where: {
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
