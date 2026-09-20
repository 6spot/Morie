import Combine
import Foundation
import SwiftData

@MainActor
final class MemoryStore: ObservableObject {
    enum StoreError: LocalizedError {
        case invalidName
        case invalidNotes
        case duplicateName
        case memoryUnavailable
        case sourceUnavailable
        case sourceNotReady
        case notEditable
        case sourceChanged
        case invalidAnalysis

        var errorDescription: String? {
            switch self {
            case .invalidName:
                "请填写 1–120 个字符的记忆主题，且不换行。"
            case .invalidNotes:
                "请填写 1–2,000 个字符的记忆内容。"
            case .duplicateName:
                "已有完全相同的个人记忆正在使用。"
            case .memoryUnavailable:
                "此个人记忆已不存在。"
            case .sourceUnavailable:
                "来源输入已不存在。"
            case .sourceNotReady:
                "请先完成输入并保存最终文字，再学习个人记忆。"
            case .notEditable:
                "此个人记忆已被替代，请查看替代后的记忆。"
            case .sourceChanged:
                "保存的输入已发生变化，此前的分析结果未被使用。"
            case .invalidAnalysis:
                "个人记忆分析结果无效，你的输入已保存。"
            }
        }
    }

    static let workingContextLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let writerContextLimit = 24

    @Published private(set) var entries: [MemoryRecord] = []

    private let container: ModelContainer
    private var context: ModelContext
    private let commit: (ModelContext) throws -> Void

    init(
        container: ModelContainer,
        commit: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.commit = commit
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func load(now: Date = Date()) throws {
        var records = try context.fetch(
            FetchDescriptor<MemoryRecord>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
        )

        var expired = false
        for record in records
        where record.status == .active
            && record.scope == .workingContext
            && record.expiresAt.map({ $0 <= now }) == true {
            record.statusRawValue = MemoryStatus.archived.rawValue
            record.archiveReasonRawValue = MemoryArchiveReason.expired.rawValue
            record.updatedAt = now
            expired = true
        }

        if expired {
            try commit(context)
            resetContext()
            records = try context.fetch(
                FetchDescriptor<MemoryRecord>(
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
            )
        }
        entries = records
    }

    func analysisSource(for captureID: UUID) throws -> MemoryAnalysisSource {
        let capture = try requireSource(captureID)
        let reader = ModelContext(container)
        let saved = try reader.fetch(
            FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == captureID })
        ).first
        guard let saved else { throw StoreError.sourceUnavailable }
        guard eligibleForLearning(capture), eligibleForLearning(saved) else {
            throw StoreError.sourceNotReady
        }
        let source = MemoryAnalysisSource(capture: saved)
        guard source == MemoryAnalysisSource(capture: capture) else {
            throw StoreError.sourceChanged
        }
        return source
    }

    func analysis(for source: MemoryAnalysisSource) -> MemoryAnalysisSnapshot? {
        let reader = makeContext()
        do {
            guard let record = try analysis(in: reader, for: source) else { return nil }
            return MemoryAnalysisSnapshot(record)
        } catch {
            return nil
        }
    }

    func analyses(
        for captureID: UUID,
        linkedTo memoryID: UUID? = nil
    ) -> [MemoryAnalysisSnapshot] {
        let reader = makeContext()
        var descriptor = FetchDescriptor<MemoryAnalysisRecord>(
            predicate: #Predicate { $0.sourceCaptureID == captureID },
            sortBy: [SortDescriptor(\.sourceCapturedAt)]
        )
        descriptor.fetchLimit = 8
        guard let records = try? reader.fetch(descriptor) else { return [] }
        let filtered: [MemoryAnalysisRecord]
        if let memoryID {
            filtered = records.filter { analysis in
                analysis.observations.contains { $0.memoryID == memoryID }
            }
        } else {
            filtered = records
        }
        return filtered.map(MemoryAnalysisSnapshot.init)
    }

    var analyses: [MemoryAnalysisRecord] {
        (try? analysisRecords()) ?? []
    }

    func analysisCount() throws -> Int {
        try makeContext().fetchCount(FetchDescriptor<MemoryAnalysisRecord>())
    }

    func analysisRecords() throws -> [MemoryAnalysisRecord] {
        try makeContext().fetch(
            FetchDescriptor<MemoryAnalysisRecord>(
                sortBy: [SortDescriptor(\.sourceCapturedAt)]
            )
        )
    }

    func evidence(for memoryID: UUID) -> [MemoryEvidenceSnapshot] {
        let reader = makeContext()
        let descriptor = FetchDescriptor<MemoryEvidenceRecord>(
            predicate: #Predicate { $0.memoryID == memoryID },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        return ((try? reader.fetch(descriptor)) ?? []).map(MemoryEvidenceSnapshot.init)
    }

    /// Startup reconciliation is also the boundary that prevents disabled-period
    /// Captures from being silently learned later when Memory is re-enabled.
    func reconcileCompletedInputs(learningEnabled: Bool = true) throws {
        let reader = makeContext()
        let knownCaptureIDs = Set(
            try reader.fetch(FetchDescriptor<MemoryAnalysisRecord>()).map(\.sourceCaptureID)
        )
        let captures = try reader.fetch(
            FetchDescriptor<CaptureRecord>(
                sortBy: [SortDescriptor(\.createdAt)]
            )
        )

        var inserted = false
        for capture in captures where eligibleForLearning(capture) {
            guard !knownCaptureIDs.contains(capture.id) else { continue }
            let analysis = MemoryAnalysisRecord(source: MemoryAnalysisSource(capture: capture))
            if !learningEnabled {
                analysis.stateRawValue = MemoryAnalysisState.skipped.rawValue
                analysis.failureRawValue = MemoryAnalysisFailure.disabled.rawValue
            }
            context.insert(analysis)
            inserted = true
        }
        if inserted { try save() }
    }

    func enqueueCompletedInput(
        captureID: UUID,
        learningEnabled: Bool = true
    ) throws {
        guard let source = try? analysisSource(for: captureID) else { return }
        let reader = makeContext()
        guard try analysis(in: reader, captureID: captureID) == nil else { return }

        let analysis = MemoryAnalysisRecord(source: source)
        if !learningEnabled {
            analysis.stateRawValue = MemoryAnalysisState.skipped.rawValue
            analysis.failureRawValue = MemoryAnalysisFailure.disabled.rawValue
        }
        context.insert(analysis)
        try save()
    }

    func pendingSources(
        now: Date = Date(),
        limit: Int = 3
    ) throws -> [MemoryAnalysisSource] {
        let pending = MemoryAnalysisState.pending.rawValue
        var descriptor = FetchDescriptor<MemoryAnalysisRecord>(
            predicate: #Predicate {
                $0.stateRawValue == pending && $0.nextAttemptAt <= now
            },
            sortBy: [
                SortDescriptor(\.nextAttemptAt),
                SortDescriptor(\.sourceCapturedAt),
            ]
        )
        descriptor.fetchLimit = max(0, limit)
        return try makeContext().fetch(descriptor).map(\.source)
    }

    func nextPendingAttemptDate() throws -> Date? {
        let pending = MemoryAnalysisState.pending.rawValue
        var descriptor = FetchDescriptor<MemoryAnalysisRecord>(
            predicate: #Predicate { $0.stateRawValue == pending },
            sortBy: [SortDescriptor(\.nextAttemptAt)]
        )
        descriptor.fetchLimit = 1
        return try makeContext().fetch(descriptor).first?.nextAttemptAt
    }

    func learningInput(for source: MemoryAnalysisSource) throws -> MemoryLearningInput {
        guard try analysisSource(for: source.captureID) == source else {
            throw StoreError.sourceChanged
        }
        try load()

        let active = entries.compactMap(\.snapshot)
            .filter { $0.status == .active }
            .sorted { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt > rhs.updatedAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }

        let tombstones = try makeContext()
            .fetch(FetchDescriptor<MemoryLearningBlock>())
            .compactMap(\.snapshot)

        let userArchived = entries.compactMap { record -> MemoryBlockedSnapshot? in
            guard record.status == .archived,
                  record.archiveReason == .user,
                  let kind = record.kind
            else { return nil }
            return MemoryBlockedSnapshot(
                kind: kind,
                name: record.name,
                notes: record.notes
            )
        }

        return MemoryLearningInput(
            source: source,
            context: Array(active.prefix(Self.writerContextLimit)),
            blocked: Array((tombstones + userArchived).prefix(Self.writerContextLimit))
        )
    }

    func recordFailure(
        _ failure: MemoryAnalysisFailure,
        for source: MemoryAnalysisSource,
        now: Date = Date()
    ) throws {
        guard let analysis = try analysis(in: context, for: source),
              analysis.state == .pending
        else { return }

        analysis.attempts += 1
        analysis.failureRawValue = failure.rawValue
        analysis.stateRawValue = (
            failure.retryable ? MemoryAnalysisState.pending : .skipped
        ).rawValue
        analysis.nextAttemptAt = now.addingTimeInterval(
            min(3_600, 30 * pow(2, Double(min(analysis.attempts - 1, 7))))
        )
        try save()
    }

    func retry(_ source: MemoryAnalysisSource) throws {
        guard try analysisSource(for: source.captureID) == source else {
            throw StoreError.sourceChanged
        }
        guard let analysis = try analysis(in: context, for: source),
              analysis.state != .completed
        else { return }

        analysis.stateRawValue = MemoryAnalysisState.pending.rawValue
        analysis.nextAttemptAt = Date()
        analysis.failureRawValue = nil
        try save()
    }

    /// Model output describes semantic intent; code owns source freshness,
    /// user precedence, lifecycle and atomic persistence.
    func apply(
        _ suggestions: [MemorySuggestion],
        from input: MemoryLearningInput
    ) throws {
        guard try analysisSource(for: input.source.captureID) == input.source else {
            throw StoreError.sourceChanged
        }
        guard suggestions.count <= 3 else { throw StoreError.invalidAnalysis }
        try load()

        guard let analysis = try analysis(in: context, for: input.source) else {
            throw StoreError.sourceUnavailable
        }
        guard analysis.state != .completed else { return }

        do {
            var seen = Set<String>()
            var observations: [MemoryObservation] = []

            for suggestion in suggestions {
                guard let suggestion = grounded(suggestion, in: input.source.text)
                else { continue }

                let signature = [
                    suggestion.existingMemoryID?.uuidString ?? "new",
                    suggestion.action.rawValue,
                    MemoryText.normalized(suggestion.evidence),
                ].joined(separator: "|")
                guard seen.insert(signature).inserted else { continue }

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
            context.rollback()
            resetContext()
            try? load()
            throw error
        }
    }

    private func admit(
        _ observation: inout MemoryObservation,
        input: MemoryLearningInput
    ) throws {
        let suggestion = observation.suggestion
        let draft = suggestion.draft

        if isStructurallyBlocked(draft, blocked: input.blocked) {
            observation.disposition = .ignored
            return
        }

        if let id = suggestion.existingMemoryID {
            guard suggestion.action != .create,
                  let snapshot = input.context.first(where: { $0.id == id }),
                  let current = entries.first(where: { $0.id == id }),
                  current.snapshot == snapshot,
                  current.status == .active
            else {
                observation.disposition = .conflict
                return
            }

            if current.origin == .user {
                guard suggestion.action == .reinforce else {
                    observation.disposition = .conflict
                    return
                }
                try attachEvidence(
                    to: current,
                    suggestion: suggestion,
                    source: input.source
                )
                observation.disposition = .learned
                observation.memoryID = current.id
                return
            }

            switch suggestion.action {
            case .reinforce:
                break
            case .merge, .update:
                applyAutomaticDraft(draft, to: current)
            case .create:
                observation.disposition = .conflict
                return
            }

            try attachEvidence(
                to: current,
                suggestion: suggestion,
                source: input.source
            )
            observation.disposition = .learned
            observation.memoryID = current.id
            return
        }

        guard suggestion.action == .create else {
            observation.disposition = .conflict
            return
        }

        if let exact = entries.first(where: {
            $0.status == .active && structurallySame($0, draft)
        }) {
            try attachEvidence(
                to: exact,
                suggestion: suggestion,
                source: input.source
            )
            observation.disposition = .learned
            observation.memoryID = exact.id
            return
        }

        let memory = learned(
            draft,
            suggestion: suggestion,
            source: input.source
        )
        context.insert(memory)
        context.insert(
            MemoryEvidenceRecord(
                memoryID: memory.id,
                source: input.source,
                claim: suggestion.evidence,
                confidence: suggestion.confidence
            )
        )
        observation.disposition = .learned
        observation.memoryID = memory.id
    }

    private func learned(
        _ draft: MemoryDraft,
        suggestion: MemorySuggestion,
        source: MemoryAnalysisSource
    ) -> MemoryRecord {
        let memory = MemoryRecord(
            draft: draft,
            sourceCaptureIDs: [source.captureID]
        )
        memory.originRawValue = MemoryOrigin.automatic.rawValue
        memory.confidence = suggestion.confidence
        memory.lastEvidenceAt = source.capturedAt
        applyLifecycle(for: draft.scope, to: memory, evidenceAt: source.capturedAt)
        return memory
    }

    private func applyAutomaticDraft(
        _ draft: MemoryDraft,
        to memory: MemoryRecord
    ) {
        memory.kindRawValue = draft.kind.rawValue
        memory.scopeRawValue = draft.scope.rawValue
        memory.name = draft.name
        memory.notes = draft.notes
    }

    private func attachEvidence(
        to memory: MemoryRecord,
        suggestion: MemorySuggestion,
        source: MemoryAnalysisSource
    ) throws {
        if !memory.sourceCaptureIDs.contains(source.captureID) {
            memory.sourceCaptureIDs.append(source.captureID)
        }

        memory.lastEvidenceAt = max(memory.lastEvidenceAt, source.capturedAt)
        memory.updatedAt = Date()
        memory.confidence = max(memory.confidence ?? 0, suggestion.confidence)
        applyLifecycle(
            for: memory.scope ?? suggestion.draft.scope,
            to: memory,
            evidenceAt: source.capturedAt
        )

        let reader = makeContext()
        let memoryID = memory.id
        let sourceID = source.captureID
        let exists = try reader.fetch(
            FetchDescriptor<MemoryEvidenceRecord>(
                predicate: #Predicate {
                    $0.memoryID == memoryID && $0.sourceCaptureID == sourceID
                }
            )
        ).first != nil

        if !exists {
            context.insert(
                MemoryEvidenceRecord(
                    memoryID: memory.id,
                    source: source,
                    claim: suggestion.evidence,
                    confidence: suggestion.confidence
                )
            )
        }
    }

    private func applyLifecycle(
        for scope: MemoryScope,
        to memory: MemoryRecord,
        evidenceAt: Date
    ) {
        memory.scopeRawValue = scope.rawValue
        switch scope {
        case .longTerm:
            memory.expiresAt = nil
        case .workingContext:
            memory.expiresAt = evidenceAt.addingTimeInterval(
                Self.workingContextLifetime
            )
        }
    }

    private func grounded(
        _ suggestion: MemorySuggestion,
        in source: String
    ) -> MemorySuggestion? {
        guard suggestion.confidence.isFinite,
              (0.75...1).contains(suggestion.confidence),
              let draft = try? validated(suggestion.draft)
        else { return nil }

        let evidence = suggestion.evidence
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !evidence.isEmpty,
              evidence.count <= 500,
              source.range(of: evidence, options: .literal) != nil
        else { return nil }

        var accepted = suggestion
        accepted.draft = draft
        return accepted
    }

    func memory(_ id: UUID) throws -> MemoryRecord {
        guard let record = try context.fetch(
            FetchDescriptor<MemoryRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
        else { throw StoreError.memoryUnavailable }
        return record
    }

    @discardableResult
    func create(
        _ draft: MemoryDraft,
        sourceCaptureID: UUID? = nil
    ) throws -> UUID {
        var draft = try validated(draft)
        draft.scope = .longTerm
        try requireAvailableDraft(draft)

        let source: MemoryAnalysisSource?
        if let sourceCaptureID {
            let capture = try requireSource(sourceCaptureID)
            source = MemoryAnalysisSource(capture: capture)
        } else {
            source = nil
        }

        let record = MemoryRecord(
            draft: draft,
            sourceCaptureIDs: sourceCaptureID.map { [$0] } ?? []
        )
        record.originRawValue = MemoryOrigin.user.rawValue
        record.expiresAt = nil
        try removeBlock(draft)
        context.insert(record)

        if let source {
            context.insert(
                MemoryEvidenceRecord(
                    memoryID: record.id,
                    source: source,
                    claim: source.text,
                    confidence: nil
                )
            )
        }

        try save()
        return record.id
    }

    func update(_ id: UUID, draft: MemoryDraft) throws {
        let record = try editableMemory(id)
        var draft = try validated(draft)
        draft.scope = .longTerm
        if record.status == .active {
            try requireAvailableDraft(draft, excluding: id)
        }

        if let prior = record.draft,
           !structurallySame(prior, draft) {
            context.insert(MemoryLearningBlock(draft: prior))
        }

        record.kindRawValue = draft.kind.rawValue
        record.scopeRawValue = draft.scope.rawValue
        record.name = draft.name
        record.notes = draft.notes
        record.originRawValue = MemoryOrigin.user.rawValue
        record.confidence = nil
        record.expiresAt = nil
        record.updatedAt = Date()
        try save()
    }

    @discardableResult
    func replace(_ id: UUID, with draft: MemoryDraft) throws -> UUID {
        let previous = try editableMemory(id)
        var draft = try validated(draft)
        draft.scope = .longTerm
        try requireAvailableDraft(draft, excluding: id)

        let replacement = MemoryRecord(
            draft: draft,
            sourceCaptureIDs: previous.sourceCaptureIDs,
            supersedesID: id
        )
        replacement.originRawValue = MemoryOrigin.user.rawValue
        replacement.expiresAt = nil

        previous.statusRawValue = MemoryStatus.superseded.rawValue
        previous.archiveReasonRawValue = nil
        previous.updatedAt = Date()
        context.insert(replacement)

        let oldID = previous.id
        let evidence = try context.fetch(
            FetchDescriptor<MemoryEvidenceRecord>(
                predicate: #Predicate { $0.memoryID == oldID }
            )
        )
        for item in evidence {
            item.memoryID = replacement.id
        }

        try save()
        return replacement.id
    }

    func addSource(_ captureID: UUID, to id: UUID) throws {
        let record = try editableMemory(id)
        let capture = try requireSource(captureID)
        guard !record.sourceCaptureIDs.contains(captureID) else { return }

        record.sourceCaptureIDs.append(captureID)
        record.lastEvidenceAt = max(record.lastEvidenceAt, capture.createdAt)
        record.updatedAt = Date()
        context.insert(
            MemoryEvidenceRecord(
                memoryID: record.id,
                source: MemoryAnalysisSource(capture: capture),
                claim: capture.finalText,
                confidence: nil
            )
        )
        try save()
    }

    func archive(_ id: UUID) throws {
        let record = try editableMemory(id)
        record.statusRawValue = MemoryStatus.archived.rawValue
        record.archiveReasonRawValue = MemoryArchiveReason.user.rawValue
        record.updatedAt = Date()
        try save()
    }

    func restore(_ id: UUID) throws {
        let record = try editableMemory(id)
        guard let draft = record.draft else {
            throw StoreError.memoryUnavailable
        }
        try requireAvailableDraft(draft, excluding: id)
        record.statusRawValue = MemoryStatus.active.rawValue
        record.archiveReasonRawValue = nil
        if record.scope == .workingContext {
            record.expiresAt = Date().addingTimeInterval(
                Self.workingContextLifetime
            )
        }
        record.updatedAt = Date()
        try save()
    }

    func delete(_ id: UUID) throws {
        let record = try memory(id)
        if let draft = record.draft {
            context.insert(MemoryLearningBlock(draft: draft))
        }

        let memoryID = record.id
        for evidence in try context.fetch(
            FetchDescriptor<MemoryEvidenceRecord>(
                predicate: #Predicate { $0.memoryID == memoryID }
            )
        ) {
            context.delete(evidence)
        }

        for analysis in try context.fetch(FetchDescriptor<MemoryAnalysisRecord>()) {
            analysis.observations.removeAll { $0.memoryID == id }
        }

        context.delete(record)
        try save()
    }

    func relevantContext(
        for text: String,
        limit: Int = 8
    ) throws -> [MemoryContextMatch] {
        guard PersonalMemorySettings.isEnabled else { return [] }
        try load()
        return MemoryContextRetriever.retrieve(
            for: text,
            from: entries.compactMap(\.snapshot),
            limit: limit
        )
    }

    private func removeBlock(_ draft: MemoryDraft) throws {
        for block in try context.fetch(FetchDescriptor<MemoryLearningBlock>()) {
            guard let snapshot = block.snapshot else { continue }
            if structurallySame(snapshot, draft) {
                context.delete(block)
            }
        }
    }

    private func editableMemory(_ id: UUID) throws -> MemoryRecord {
        let record = try memory(id)
        guard record.status != .superseded else {
            throw StoreError.notEditable
        }
        return record
    }

    @discardableResult
    private func requireSource(_ id: UUID) throws -> CaptureRecord {
        guard let capture = try container.mainContext.fetch(
            FetchDescriptor<CaptureRecord>(
                predicate: #Predicate { $0.id == id }
            )
        ).first
        else { throw StoreError.sourceUnavailable }

        guard capture.lifecycle != .capturing,
              capture.lifecycle != .cancelled,
              capture.refinement?.status != .running,
              !capture.finalText.trimmingCharacters(
                in: .whitespacesAndNewlines
              ).isEmpty
        else { throw StoreError.sourceNotReady }

        return capture
    }

    private func eligibleForLearning(_ capture: CaptureRecord) -> Bool {
        capture.deliveryModeRawValue == CaptureDeliveryMode.currentApp.rawValue
            && (capture.lifecycle == .delivered
                || capture.lifecycle == .deliveryFailed)
            && capture.refinement?.status != .running
            && !capture.finalText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .isEmpty
    }

    private func requireAvailableDraft(
        _ draft: MemoryDraft,
        excluding id: UUID? = nil
    ) throws {
        guard try !context.fetch(FetchDescriptor<MemoryRecord>()).contains(where: {
            $0.id != id
                && $0.status == .active
                && structurallySame($0, draft)
        })
        else { throw StoreError.duplicateName }
    }

    private func validated(_ draft: MemoryDraft) throws -> MemoryDraft {
        let name = draft.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = draft.notes
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty,
              name.count <= 120,
              !name.contains("\n"),
              !name.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
              )
        else { throw StoreError.invalidName }

        guard !notes.isEmpty,
              notes.count <= 2_000,
              !notes.unicodeScalars.contains(where: { scalar in
                  CharacterSet.controlCharacters.contains(scalar)
                      && !CharacterSet.newlines.contains(scalar)
              })
        else { throw StoreError.invalidNotes }

        return MemoryDraft(
            kind: draft.kind,
            name: name,
            notes: notes,
            scope: draft.scope
        )
    }

    private func isStructurallyBlocked(
        _ draft: MemoryDraft,
        blocked: [MemoryBlockedSnapshot]
    ) -> Bool {
        blocked.contains { structurallySame($0, draft) }
    }

    private func structurallySame(
        _ record: MemoryRecord,
        _ draft: MemoryDraft
    ) -> Bool {
        guard let kind = record.kind else { return false }
        return kind == draft.kind
            && MemoryText.normalized(record.name)
                == MemoryText.normalized(draft.name)
            && MemoryText.normalized(record.notes)
                == MemoryText.normalized(draft.notes)
    }

    private func structurallySame(
        _ lhs: MemoryDraft,
        _ rhs: MemoryDraft
    ) -> Bool {
        lhs.kind == rhs.kind
            && MemoryText.normalized(lhs.name)
                == MemoryText.normalized(rhs.name)
            && MemoryText.normalized(lhs.notes)
                == MemoryText.normalized(rhs.notes)
    }

    private func structurallySame(
        _ lhs: MemoryBlockedSnapshot,
        _ rhs: MemoryDraft
    ) -> Bool {
        lhs.kind == rhs.kind
            && MemoryText.normalized(lhs.name)
                == MemoryText.normalized(rhs.name)
            && MemoryText.normalized(lhs.notes)
                == MemoryText.normalized(rhs.notes)
    }

    private func save() throws {
        do {
            try commit(context)
        } catch {
            context.rollback()
            resetContext()
            try? load()
            throw error
        }
        resetContext()
        try load()
    }

    private func analysis(
        in context: ModelContext,
        captureID: UUID
    ) throws -> MemoryAnalysisRecord? {
        var descriptor = FetchDescriptor<MemoryAnalysisRecord>(
            predicate: #Predicate { $0.sourceCaptureID == captureID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func analysis(
        in context: ModelContext,
        for source: MemoryAnalysisSource
    ) throws -> MemoryAnalysisRecord? {
        guard let record = try analysis(
            in: context,
            captureID: source.captureID
        ),
        record.source == source
        else { return nil }
        return record
    }

    private func makeContext() -> ModelContext {
        let context = ModelContext(container)
        context.autosaveEnabled = false
        return context
    }

    private func resetContext() {
        context = makeContext()
    }
}
