import Combine
import Foundation
import SwiftData

@MainActor
final class MemoryStore: ObservableObject {
    enum StoreError: LocalizedError {
        case invalidName
        case invalidAliases
        case notesTooLong
        case duplicateName
        case memoryUnavailable
        case sourceUnavailable
        case sourceNotReady
        case notEditable

        var errorDescription: String? {
            switch self {
            case .invalidName: "Enter a name of 1–120 characters on one line."
            case .invalidAliases: "Use up to 20 aliases, each with 1–120 characters on one line."
            case .notesTooLong: "Keep memory notes within 2,000 characters."
            case .duplicateName: "An active memory of this type already has that name. Open the existing entry to edit it."
            case .memoryUnavailable: "This memory is no longer available."
            case .sourceUnavailable: "The source capture is no longer available."
            case .sourceNotReady: "Finish the capture and save its text before creating memory from it."
            case .notEditable: "This memory has been superseded. Open its replacement to make changes."
            }
        }
    }

    @Published private(set) var entries: [MemoryRecord] = []

    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        // Memory edits must never roll back a live Capture's unsaved checkpoint.
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws {
        entries = try context.fetch(FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
    }

    func memory(_ id: UUID) throws -> MemoryRecord {
        let request = FetchDescriptor<MemoryRecord>(predicate: #Predicate { $0.id == id })
        guard let record = try context.fetch(request).first else { throw StoreError.memoryUnavailable }
        return record
    }

    @discardableResult
    func create(_ draft: MemoryDraft, sourceCaptureID: UUID? = nil) throws -> UUID {
        let draft = try validated(draft)
        try requireAvailableName(draft)
        if let sourceCaptureID { try requireSource(sourceCaptureID) }
        let record = MemoryRecord(draft: draft, sourceCaptureIDs: sourceCaptureID.map { [$0] } ?? [])
        context.insert(record)
        try save()
        return record.id
    }

    func update(_ id: UUID, draft: MemoryDraft) throws {
        let record = try editableMemory(id)
        let draft = try validated(draft)
        if record.status == .active { try requireAvailableName(draft, excluding: id) }
        record.kindRawValue = draft.kind.rawValue
        record.name = draft.name
        record.aliases = draft.aliases
        record.notes = draft.notes
        record.userConfirmed = true
        record.confidence = nil
        record.updatedAt = Date()
        try save()
    }

    @discardableResult
    func replace(_ id: UUID, with draft: MemoryDraft) throws -> UUID {
        let previous = try editableMemory(id)
        let draft = try validated(draft)
        try requireAvailableName(draft, excluding: id)
        let replacement = MemoryRecord(draft: draft, sourceCaptureIDs: previous.sourceCaptureIDs, supersedesID: id)
        previous.statusRawValue = MemoryStatus.superseded.rawValue
        previous.updatedAt = Date()
        context.insert(replacement)
        try save()
        return replacement.id
    }

    func addSource(_ captureID: UUID, to id: UUID) throws {
        let record = try editableMemory(id)
        try requireSource(captureID)
        guard !record.sourceCaptureIDs.contains(captureID) else { return }
        record.sourceCaptureIDs.append(captureID)
        record.updatedAt = Date()
        try save()
    }

    func archive(_ id: UUID) throws {
        let record = try editableMemory(id)
        record.statusRawValue = MemoryStatus.archived.rawValue
        record.updatedAt = Date()
        try save()
    }

    func restore(_ id: UUID) throws {
        let record = try editableMemory(id)
        guard let draft = record.draft else { throw StoreError.memoryUnavailable }
        try requireAvailableName(draft, excluding: id)
        record.statusRawValue = MemoryStatus.active.rawValue
        record.updatedAt = Date()
        try save()
    }

    func delete(_ id: UUID) throws {
        context.delete(try memory(id))
        try save()
    }

    func relevantContext(for text: String, limit: Int = 8) throws -> [MemoryContextMatch] {
        try load()
        return MemoryContextRetriever.retrieve(for: text, from: entries.compactMap(\.snapshot), limit: limit)
    }

    private func editableMemory(_ id: UUID) throws -> MemoryRecord {
        let record = try memory(id)
        guard let status = record.status else { throw StoreError.memoryUnavailable }
        guard status != .superseded else { throw StoreError.notEditable }
        return record
    }

    private func requireSource(_ id: UUID) throws {
        // Read the Capture's authoritative context; this context only writes Memory.
        let request = FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })
        guard let capture = try container.mainContext.fetch(request).first else { throw StoreError.sourceUnavailable }
        guard capture.lifecycle != .capturing,
              !(capture.finalText + capture.recognizedText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw StoreError.sourceNotReady }
    }

    private func requireAvailableName(_ draft: MemoryDraft, excluding id: UUID? = nil) throws {
        let name = MemoryText.normalized(draft.name)
        let records = try context.fetch(FetchDescriptor<MemoryRecord>())
        guard !records.contains(where: {
            $0.id != id && $0.status == .active && $0.kind == draft.kind && MemoryText.normalized($0.name) == name
        }) else { throw StoreError.duplicateName }
    }

    private func validated(_ draft: MemoryDraft) throws -> MemoryDraft {
        func name(_ value: String) -> String? {
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, value.count <= 120,
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
            else { return nil }
            return value
        }
        guard let title = name(draft.name) else { throw StoreError.invalidName }
        guard draft.aliases.count <= 20 else { throw StoreError.invalidAliases }
        var aliases: [String] = []
        var seen = Set([MemoryText.normalized(title)])
        for rawAlias in draft.aliases {
            guard let alias = name(rawAlias) else { throw StoreError.invalidAliases }
            if seen.insert(MemoryText.normalized(alias)).inserted { aliases.append(alias) }
        }
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard notes.count <= 2_000 else { throw StoreError.notesTooLong }
        return MemoryDraft(kind: draft.kind, name: title, aliases: aliases, notes: notes)
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        try load()
    }
}
