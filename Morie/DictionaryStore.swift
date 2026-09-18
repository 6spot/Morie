import Combine
import Foundation
import NaturalLanguage
import SwiftData

struct DictionaryDraft: Equatable, Sendable {
    var name = ""
    var aliases: [String] = []
}

struct DictionarySnapshot: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let aliases: [String]
    let updatedAt: Date
}

@Model
final class DictionaryEntry {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var name: String = ""
    var aliases: [String] = []

    init(_ draft: DictionaryDraft) { name = draft.name; aliases = draft.aliases }

    var draft: DictionaryDraft { DictionaryDraft(name: name, aliases: aliases) }
    var snapshot: DictionarySnapshot { DictionarySnapshot(id: id, name: name, aliases: aliases, updatedAt: updatedAt) }
}

@MainActor
final class DictionaryStore: ObservableObject {
    enum StoreError: LocalizedError {
        case invalidName, invalidAliases, conflictingTerm, unavailable

        var errorDescription: String? {
            switch self {
            case .invalidName: "请填写 1–120 个字符的词语或名称，且不换行。"
            case .invalidAliases: "最多可添加 20 个别名，每行一个，每个 1–120 个字符。"
            case .conflictingTerm: "此写法或别名已属于其他字典词语，请先编辑该词语。"
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
        try requireAvailableTerms(draft)
        let entry = DictionaryEntry(draft)
        context.insert(entry)
        try save()
        return entry.id
    }

    func update(_ id: UUID, draft: DictionaryDraft) throws {
        let draft = try validate(draft)
        try requireAvailableTerms(draft, excluding: id)
        let entry = try entry(id)
        entry.name = draft.name
        entry.aliases = draft.aliases
        entry.updatedAt = Date()
        try save()
    }

    func delete(_ id: UUID) throws { context.delete(try entry(id)); try save() }

    func relevantEntries(for text: String) throws -> [DictionarySnapshot] {
        try load()
        return entries.map(\.snapshot).filter { entry in
            ([entry.name] + entry.aliases).contains { !InputText.literalRanges(of: $0, in: text).isEmpty }
        }
    }

    func speechHints() throws -> [String] {
        try load()
        // A bounded native Speech context; explicit aliases remain post-recognition corrections.
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
        func term(_ raw: String) -> String? {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 120,
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { return nil }
            return value
        }
        guard let name = term(draft.name) else { throw StoreError.invalidName }
        guard draft.aliases.count <= 20 else { throw StoreError.invalidAliases }
        var seen = Set([MemoryText.normalized(name)])
        var aliases: [String] = []
        for raw in draft.aliases {
            guard let alias = term(raw) else { throw StoreError.invalidAliases }
            if seen.insert(MemoryText.normalized(alias)).inserted { aliases.append(alias) }
        }
        return DictionaryDraft(name: name, aliases: aliases)
    }

    private func requireAvailableTerms(_ draft: DictionaryDraft, excluding id: UUID? = nil) throws {
        try load()
        let terms = Set(([draft.name] + draft.aliases).map(MemoryText.normalized))
        guard !entries.contains(where: { entry in
            entry.id != id && ([entry.name] + entry.aliases).contains { terms.contains(MemoryText.normalized($0)) }
        }) else { throw StoreError.conflictingTerm }
    }

    private func save() throws {
        do { try context.save() }
        catch { context.rollback(); throw error }
        try load()
    }
}

enum DictionaryReplacer {
    static func replace(_ text: String, using entries: [DictionarySnapshot]) -> ValidatedRefinement {
        let protected = InputText.technicalRanges(in: text)
        var matches: [(range: Range<String.Index>, entry: DictionarySnapshot)] = []
        for entry in entries {
            for term in [entry.name] + entry.aliases {
                for range in InputText.literalRanges(of: term, in: text) {
                    guard String(text[range]) != entry.name,
                          !protected.contains(where: { $0.overlaps(range) }) else { continue }
                    matches.append((range, entry))
                }
            }
        }
        matches.sort {
            if $0.range.lowerBound != $1.range.lowerBound { return $0.range.lowerBound < $1.range.lowerBound }
            return $0.range.upperBound > $1.range.upperBound
        }
        var selected: [(range: Range<String.Index>, entry: DictionarySnapshot)] = []
        for match in matches where !selected.contains(where: { $0.range.overlaps(match.range) }) { selected.append(match) }
        var output = text
        for match in selected.reversed() { output.replaceSubrange(match.range, with: match.entry.name) }
        return ValidatedRefinement(text: output, edits: selected.map {
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
