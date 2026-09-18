import Combine
import Foundation
import SwiftData

@MainActor
final class MemoryStore: ObservableObject {
    enum StoreError: LocalizedError {
        case invalidName, invalidNotes, duplicateName, memoryUnavailable, sourceUnavailable
        case sourceNotReady, notEditable, sourceChanged, invalidAnalysis

        var errorDescription: String? {
            switch self {
            case .invalidName: "请填写 1–120 个字符的记忆主题，且不换行。"
            case .invalidNotes: "请填写 1–2,000 个字符的个人信息。"
            case .duplicateName: "已有相同主题的个人记忆正在使用，请编辑现有记忆。"
            case .memoryUnavailable: "此个人记忆已不存在。"
            case .sourceUnavailable: "来源输入已不存在。"
            case .sourceNotReady: "请先完成输入并保存最终文字，再学习个人记忆。"
            case .notEditable: "此个人记忆已被替代，请查看替代后的记忆。"
            case .sourceChanged: "保存的输入已发生变化，此前的分析结果未被使用。"
            case .invalidAnalysis: "个人记忆分析结果无效，你的输入已保存。"
            }
        }
    }

    @Published private(set) var entries: [MemoryRecord] = []
    @Published private(set) var analyses: [MemoryAnalysisRecord] = []
    private let container: ModelContainer
    private let context: ModelContext
    private let commit: (ModelContext) throws -> Void

    init(container: ModelContainer, commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) {
        self.container = container
        self.commit = commit
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load() throws {
        entries = try context.fetch(FetchDescriptor<MemoryRecord>(sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
        analyses = try context.fetch(FetchDescriptor<MemoryAnalysisRecord>(sortBy: [SortDescriptor(\.sourceCapturedAt)]))
    }

    func analysisSource(for captureID: UUID) throws -> MemoryAnalysisSource {
        let capture = try requireSource(captureID)
        let reader = ModelContext(container)
        let saved = try reader.fetch(FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == captureID })).first
        guard let saved else { throw StoreError.sourceUnavailable }
        guard eligibleForLearning(capture), eligibleForLearning(saved) else { throw StoreError.sourceNotReady }
        let source = MemoryAnalysisSource(capture: saved)
        guard source == MemoryAnalysisSource(capture: capture) else { throw StoreError.sourceChanged }
        return source
    }

    func analysis(for source: MemoryAnalysisSource) -> MemoryAnalysisRecord? { analyses.first { $0.source == source } }

    /// The durable Capture log is the queue source; restart also discovers input saved just before a crash.
    func enqueueCompletedInputs() throws {
        try load()
        let captures = try container.mainContext.fetch(FetchDescriptor<CaptureRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        var inserted = false
        for capture in captures where eligibleForLearning(capture) {
            guard let source = try? analysisSource(for: capture.id), analysis(for: source) == nil else { continue }
            context.insert(MemoryAnalysisRecord(source: source))
            inserted = true
        }
        if inserted { try save() }
    }

    func pendingSources(now: Date = Date(), limit: Int = 3) throws -> [MemoryAnalysisSource] {
        try load()
        return analyses.filter { $0.state == .pending && $0.nextAttemptAt <= now }.prefix(max(0, limit)).map(\.source)
    }

    func learningInput(for source: MemoryAnalysisSource) throws -> MemoryLearningInput {
        guard try analysisSource(for: source.captureID) == source else { throw StoreError.sourceChanged }
        try load()
        let related = MemoryContextRetriever.retrieve(for: source.text, from: entries.compactMap(\.snapshot)).map(\.memory)
        // A small profile lets explicit changes such as a new home city find the previous fact.
        let profile = entries.compactMap(\.snapshot).filter {
            $0.status == .active && ($0.kind == .fact || $0.kind == .preference) && !related.contains($0)
        }.prefix(4)
        return MemoryLearningInput(source: source, context: Array((related + profile).prefix(12)))
    }

    func recordFailure(_ failure: MemoryAnalysisFailure, for source: MemoryAnalysisSource, now: Date = Date()) throws {
        try load()
        guard let analysis = analysis(for: source), analysis.state == .pending else { return }
        analysis.attempts += 1
        analysis.failureRawValue = failure.rawValue
        analysis.stateRawValue = (failure.retryable ? MemoryAnalysisState.pending : .skipped).rawValue
        analysis.nextAttemptAt = now.addingTimeInterval(min(3_600, 30 * pow(2, Double(min(analysis.attempts - 1, 7)))))
        try save()
    }

    func retry(_ source: MemoryAnalysisSource) throws {
        guard try analysisSource(for: source.captureID) == source else { throw StoreError.sourceChanged }
        try load()
        guard let analysis = analysis(for: source), analysis.state != .completed else { return }
        analysis.stateRawValue = MemoryAnalysisState.pending.rawValue
        analysis.nextAttemptAt = Date()
        analysis.failureRawValue = nil
        try save()
    }

    /// Analysis outcome and Memory changes share one save. A failed save leaves both retryable.
    func apply(_ suggestions: [MemorySuggestion], from input: MemoryLearningInput) throws {
        guard try analysisSource(for: input.source.captureID) == input.source else { throw StoreError.sourceChanged }
        guard suggestions.count <= 3 else { throw StoreError.invalidAnalysis }
        try load()
        guard let analysis = analysis(for: input.source) else { throw StoreError.sourceUnavailable }
        guard analysis.state != .completed else { return }
        do {
            var seen = Set<String>()
            var observations: [MemoryObservation] = []
            for suggestion in suggestions {
                guard let suggestion = grounded(suggestion, in: input.source.text),
                      seen.insert(MemoryLearningBlock.key(for: suggestion.draft)).inserted else { continue }
                var observation = MemoryObservation(suggestion: suggestion)
                try admit(&observation, input: input)
                observations.append(observation)
            }
            analysis.observations = observations
            analysis.contextSnapshot = input.context
            analysis.stateRawValue = MemoryAnalysisState.completed.rawValue
            analysis.failureRawValue = nil
            analysis.attempts += 1
            try save()
        } catch {
            // A fetch can fail after an earlier suggestion mutated this transaction too.
            context.rollback()
            try? load()
            throw error
        }
    }

    private func admit(_ observation: inout MemoryObservation, input: MemoryLearningInput) throws {
        let suggestion = observation.suggestion
        let draft = suggestion.draft
        let key = MemoryLearningBlock.key(for: draft)
        if try context.fetch(FetchDescriptor<MemoryLearningBlock>()).contains(where: { $0.keyHash == key }) {
            observation.disposition = .ignored
            return
        }
        let matching = entries.filter { $0.draft.map(MemoryLearningBlock.key(for:)) == key }
        let existing: MemoryRecord?
        if let id = suggestion.existingMemoryID {
            guard let snapshot = input.context.first(where: { $0.id == id }),
                  let current = entries.first(where: { $0.id == id }), current.snapshot == snapshot,
                  snapshot.kind == draft.kind else { observation.disposition = .conflict; return }
            existing = current
        } else {
            existing = matching.first(where: { $0.status == .active }) ?? matching.first
        }

        if let existing {
            guard existing.status == .active else { observation.disposition = .ignored; return }
            if suggestion.action == .update {
                guard suggestion.existingMemoryID == existing.id,
                      existing.origin == .automatic,
                      suggestion.evidenceKind == .explicitPersonal, suggestion.confidence >= 0.9,
                      input.source.capturedAt > existing.lastEvidenceAt,
                      hasExplicitUpdate(suggestion.evidence),
                      MemoryText.normalized(draft.notes) != MemoryText.normalized(existing.notes)
                else { observation.disposition = .conflict; return }
                // The topic identity is kept, even if the source phrases the update differently.
                let replacementDraft = MemoryDraft(kind: draft.kind, name: existing.name, notes: draft.notes)
                let replacement = learned(replacementDraft, suggestion: suggestion, sources: [input.source])
                replacement.supersedesID = existing.id
                existing.statusRawValue = MemoryStatus.superseded.rawValue
                existing.updatedAt = Date()
                context.insert(replacement)
                observation.disposition = .learned
                observation.memoryID = replacement.id
                return
            }
            guard suggestion.existingMemoryID == existing.id
                    || MemoryText.normalized(existing.notes) == MemoryText.normalized(draft.notes)
            else { observation.disposition = .conflict; return }
            if !existing.sourceCaptureIDs.contains(input.source.captureID) { existing.sourceCaptureIDs.append(input.source.captureID) }
            existing.lastEvidenceAt = max(existing.lastEvidenceAt, input.source.capturedAt)
            existing.updatedAt = Date()
            observation.disposition = .learned
            observation.memoryID = existing.id
            return
        }

        guard suggestion.action == .remember else { observation.disposition = .conflict; return }
        var sources = [input.source]
        let supports = analyses.filter { analysis in
            analysis.state == .completed && analysis.sourceCaptureID != input.source.captureID
                && analysis.observations.contains { prior in
                    prior.disposition == .accumulating && prior.suggestion.draft == draft
                }
        }.filter { (try? analysisSource(for: $0.sourceCaptureID)) == $0.source }
        sources += supports.map(\.source)
        let sourceIDs = Set(sources.map(\.captureID))
        guard (suggestion.evidenceKind == .explicitPersonal && suggestion.confidence >= 0.9) || sourceIDs.count >= 2 else { return }
        let memory = learned(draft, suggestion: suggestion, sources: sources)
        context.insert(memory)
        observation.disposition = .learned
        observation.memoryID = memory.id
        for support in supports {
            support.observations = support.observations.map { previous in
                var previous = previous
                if previous.disposition == .accumulating && previous.suggestion.draft == draft {
                    previous.disposition = .learned
                    previous.memoryID = memory.id
                }
                return previous
            }
        }
    }

    private func learned(_ draft: MemoryDraft, suggestion: MemorySuggestion, sources: [MemoryAnalysisSource]) -> MemoryRecord {
        let memory = MemoryRecord(draft: draft, sourceCaptureIDs: Array(Set(sources.map(\.captureID))).sorted { $0.uuidString < $1.uuidString })
        memory.originRawValue = MemoryOrigin.automatic.rawValue
        memory.confidence = suggestion.confidence
        memory.lastEvidenceAt = sources.map(\.capturedAt).max() ?? Date()
        return memory
    }

    private func grounded(_ suggestion: MemorySuggestion, in source: String) -> MemorySuggestion? {
        guard suggestion.confidence.isFinite, (0.8...1).contains(suggestion.confidence),
              suggestion.evidenceKind == .explicitPersonal || suggestion.evidenceKind == .recurringPersonal,
              let draft = try? validated(suggestion.draft) else { return nil }
        let evidence = suggestion.evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty, evidence.count <= 500,
              let range = source.range(of: evidence, options: .literal), evidence.contains(draft.notes),
              hasPersonalReference(evidence), !isQuoted(range, in: source),
              !["可能", "也许", "假如", "假设", "如果", "或许"].contains(where: evidence.contains),
              !["maybe", "perhaps", "if", "hypothetically"].contains(where: { !InputText.literalRanges(of: $0, in: evidence).isEmpty })
        else { return nil }
        if (draft.kind == .person || draft.kind == .project) && suggestion.existingMemoryID == nil {
            guard !InputText.literalRanges(of: draft.name, in: evidence).isEmpty else { return nil }
        }
        var accepted = suggestion
        accepted.draft = draft
        return accepted
    }

    private func hasPersonalReference(_ text: String) -> Bool {
        ["我", "本人", "咱"].contains(where: text.contains)
            || !InputText.ranges(#"(?i)\b(?:i|my|me|we|our)\b"#, in: text).isEmpty
    }

    private func isQuoted(_ evidence: Range<String.Index>, in text: String) -> Bool {
        let quotes = InputText.ranges(#"“[^”]*”|「[^」]*」|『[^』]*』|\"[^\"]*\"|(?m:^>[^\n]*)"#, in: text)
        if quotes.contains(where: { $0.lowerBound <= evidence.lowerBound && $0.upperBound >= evidence.upperBound }) { return true }
        let prefix = text[..<evidence.upperBound].split(whereSeparator: { "。！？\n".contains($0) }).last.map(String.init) ?? ""
        return ["他说", "她说", "引用", "he said", "she said", "quote:"].contains(where: { prefix.localizedCaseInsensitiveContains($0) })
    }

    private func hasExplicitUpdate(_ text: String) -> Bool {
        ["现在", "改为", "改成", "不再", "已经", "其实", "之前"].contains(where: text.contains)
            || ["now", "instead", "changed", "no longer", "actually"].contains(where: { !InputText.literalRanges(of: $0, in: text).isEmpty })
    }

    func memory(_ id: UUID) throws -> MemoryRecord {
        guard let record = try context.fetch(FetchDescriptor<MemoryRecord>(predicate: #Predicate { $0.id == id })).first
        else { throw StoreError.memoryUnavailable }
        return record
    }

    @discardableResult
    func create(_ draft: MemoryDraft, sourceCaptureID: UUID? = nil) throws -> UUID {
        let draft = try validated(draft)
        try requireAvailableName(draft)
        if let sourceCaptureID { try requireSource(sourceCaptureID) }
        let record = MemoryRecord(draft: draft, sourceCaptureIDs: sourceCaptureID.map { [$0] } ?? [])
        try removeBlock(draft)
        context.insert(record)
        try save()
        return record.id
    }

    func update(_ id: UUID, draft: MemoryDraft) throws {
        let record = try editableMemory(id)
        let draft = try validated(draft)
        if record.status == .active { try requireAvailableName(draft, excluding: id) }
        if let prior = record.draft, MemoryLearningBlock.key(for: prior) != MemoryLearningBlock.key(for: draft) { context.insert(MemoryLearningBlock(draft: prior)) }
        record.kindRawValue = draft.kind.rawValue
        record.name = draft.name
        record.notes = draft.notes
        record.originRawValue = MemoryOrigin.user.rawValue
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
        let record = try memory(id)
        let analyses = try context.fetch(FetchDescriptor<MemoryAnalysisRecord>())
        if let draft = record.draft {
            context.insert(MemoryLearningBlock(draft: draft))
            let key = MemoryLearningBlock.key(for: draft)
            for analysis in analyses {
                analysis.observations.removeAll { $0.memoryID == id || MemoryLearningBlock.key(for: $0.suggestion.draft) == key }
            }
        }
        context.delete(record)
        try save()
    }

    func relevantContext(for text: String, limit: Int = 8) throws -> [MemoryContextMatch] {
        try load()
        return MemoryContextRetriever.retrieve(for: text, from: entries.compactMap(\.snapshot), limit: limit)
    }

    private func removeBlock(_ draft: MemoryDraft) throws {
        let key = MemoryLearningBlock.key(for: draft)
        for block in try context.fetch(FetchDescriptor<MemoryLearningBlock>()) where block.keyHash == key { context.delete(block) }
    }

    private func editableMemory(_ id: UUID) throws -> MemoryRecord {
        let record = try memory(id)
        guard record.status != .superseded else { throw StoreError.notEditable }
        return record
    }

    @discardableResult
    private func requireSource(_ id: UUID) throws -> CaptureRecord {
        guard let capture = try container.mainContext.fetch(FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })).first
        else { throw StoreError.sourceUnavailable }
        guard capture.lifecycle != .capturing, capture.lifecycle != .cancelled, capture.refinement?.status != .running,
              !capture.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw StoreError.sourceNotReady }
        return capture
    }

    private func eligibleForLearning(_ capture: CaptureRecord) -> Bool {
        capture.deliveryModeRawValue == CaptureDeliveryMode.currentApp.rawValue
            && (capture.lifecycle == .delivered || capture.lifecycle == .deliveryFailed)
            && capture.refinement?.status != .running
            && !capture.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func requireAvailableName(_ draft: MemoryDraft, excluding id: UUID? = nil) throws {
        let key = MemoryLearningBlock.key(for: draft)
        guard try !context.fetch(FetchDescriptor<MemoryRecord>()).contains(where: {
            $0.id != id && $0.status == .active && $0.draft.map(MemoryLearningBlock.key(for:)) == key
        }) else { throw StoreError.duplicateName }
    }

    private func validated(_ draft: MemoryDraft) throws -> MemoryDraft {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 120,
              !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else { throw StoreError.invalidName }
        guard !notes.isEmpty, notes.count <= 2_000 else { throw StoreError.invalidNotes }
        return MemoryDraft(kind: draft.kind, name: name, notes: notes)
    }

    private func save() throws {
        do { try commit(context) }
        catch { context.rollback(); throw error }
        try load()
    }
}
