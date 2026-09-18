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
        case sourceChanged
        case invalidCandidates
        case candidateUnavailable

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
            case .sourceChanged: "The saved text has changed. Extract candidates from the updated text before saving a suggestion."
            case .invalidCandidates: "The model returned an invalid candidate set. Your capture has been kept."
            case .candidateUnavailable: "This candidate has already been reviewed or is no longer available."
            }
        }
    }

    @Published private(set) var entries: [MemoryRecord] = []
    @Published private(set) var extractions: [MemoryExtractionRecord] = []

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
        extractions = try context.fetch(FetchDescriptor<MemoryExtractionRecord>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)]))
    }

    var pendingCandidates: [MemoryCandidate] {
        extractions.flatMap(\.candidates).filter { $0.status == .pending }
    }

    func extractionInput(for captureID: UUID) throws -> MemoryExtractionInput {
        let current = MemoryExtractionInput(capture: try requireSource(captureID))
        // Only committed text can be sent to the model, including after M-005 polishing.
        let reader = ModelContext(container)
        let request = FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == captureID })
        guard let saved = try reader.fetch(request).first else { throw StoreError.sourceUnavailable }
        guard saved.lifecycle != .capturing, saved.lifecycle != .cancelled,
              saved.refinement?.status != .running else { throw StoreError.sourceNotReady }
        let input = MemoryExtractionInput(capture: saved)
        guard input == current else { throw StoreError.sourceChanged }
        return input
    }

    func extraction(for input: MemoryExtractionInput) -> MemoryExtractionRecord? {
        extractions.first { $0.input == input }
    }

    func candidate(_ id: UUID) throws -> (extraction: MemoryExtractionRecord, candidate: MemoryCandidate) {
        try load()
        for extraction in extractions {
            if let candidate = extraction.candidates.first(where: { $0.id == id }) {
                return (extraction, candidate)
            }
        }
        throw StoreError.candidateUnavailable
    }

    func isCurrent(_ extraction: MemoryExtractionRecord) -> Bool {
        guard let input = try? extractionInput(for: extraction.sourceCaptureID) else { return false }
        return input == extraction.input
    }

    @discardableResult
    func saveCandidates(_ suggestions: [MemorySuggestion], for input: MemoryExtractionInput) throws -> UUID {
        guard try extractionInput(for: input.captureID) == input else { throw StoreError.sourceChanged }
        try load()
        if let existing = extraction(for: input) { return existing.id }
        guard suggestions.count <= 3 else { throw StoreError.invalidCandidates }
        var seen = Set<String>()
        let selected = suggestions.compactMap { suggestion -> MemorySuggestion? in
            guard suggestion.confidence.isFinite, (0.8...1).contains(suggestion.confidence),
                  let draft = try? validated(suggestion.draft) else { return nil }
            let evidence = suggestion.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
            let source = MemoryText.normalized(input.text)
            guard !evidence.isEmpty, evidence.count <= 500, input.text.contains(evidence),
                  MemoryText.normalized(evidence).contains(MemoryText.normalized(draft.name)),
                  draft.aliases.allSatisfy({ source.contains(MemoryText.normalized($0)) }),
                  seen.insert("\(draft.kind.rawValue):\(MemoryText.normalized(draft.name))").inserted
            else { return nil }
            return MemorySuggestion(draft: draft, evidence: evidence, confidence: suggestion.confidence)
        }
        let extraction = MemoryExtractionRecord(input: input, suggestions: selected)
        context.insert(extraction)
        try save()
        return extraction.id
    }

    @discardableResult
    func acceptCandidate(_ id: UUID, draft: MemoryDraft, existingMemoryID: UUID? = nil) throws -> UUID {
        let (extraction, candidate) = try candidate(id)
        guard candidate.status == .pending else { throw StoreError.candidateUnavailable }
        guard try extractionInput(for: extraction.sourceCaptureID) == extraction.input else { throw StoreError.sourceChanged }
        let record: MemoryRecord
        if let existingMemoryID {
            record = try editableMemory(existingMemoryID)
            guard record.status == .active else { throw StoreError.notEditable }
            if !record.sourceCaptureIDs.contains(extraction.sourceCaptureID) {
                record.sourceCaptureIDs.append(extraction.sourceCaptureID)
            }
            record.updatedAt = Date()
        } else {
            let draft = try validated(draft)
            try requireAvailableName(draft)
            record = MemoryRecord(draft: draft, sourceCaptureIDs: [extraction.sourceCaptureID])
            record.sourceCandidateID = id
            record.confidence = draft == candidate.suggestion.draft ? candidate.suggestion.confidence : nil
            context.insert(record)
        }
        updateCandidate(id, in: extraction, status: .accepted, memoryID: record.id)
        try save()
        return record.id
    }

    func dismissCandidate(_ id: UUID) throws {
        let (extraction, candidate) = try candidate(id)
        guard candidate.status == .pending else { throw StoreError.candidateUnavailable }
        updateCandidate(id, in: extraction, status: .dismissed)
        try save()
    }

    private func updateCandidate(_ id: UUID, in extraction: MemoryExtractionRecord, status: MemoryCandidateStatus, memoryID: UUID? = nil) {
        var candidates = extraction.candidates
        guard let index = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[index].status = status
        candidates[index].memoryID = memoryID
        extraction.candidates = candidates
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

    @discardableResult
    private func requireSource(_ id: UUID) throws -> CaptureRecord {
        // Read the Capture's authoritative context; this context only writes Memory.
        let request = FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })
        guard let capture = try container.mainContext.fetch(request).first else { throw StoreError.sourceUnavailable }
        guard capture.lifecycle != .capturing, capture.lifecycle != .cancelled,
              capture.refinement?.status != .running,
              !(capture.finalText + capture.recognizedText).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw StoreError.sourceNotReady }
        return capture
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
