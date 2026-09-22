import Combine
import Foundation
import SwiftData

@MainActor
final class CaptureStore: ObservableObject {
    enum StoreError: LocalizedError {
        case captureNotFound
        case captureInProgress
        case audioExpired
        case audioUnavailable
        case emptyRecognition
        case invalidDeliveryMode
        case refinementSourceChanged

        var errorDescription: String? {
            switch self {
            case .captureNotFound: "此记录已不存在。"
            case .captureInProgress: "请等待这次录音结束。"
            case .audioExpired: "原始录音已到期，保存的文字仍可查看。"
            case .audioUnavailable: "原始录音已不存在。"
            case .emptyRecognition: "未识别到语音，已保存的文字和录音均已保留。"
            case .invalidDeliveryMode: "此记录的输入方式无效。"
            case .refinementSourceChanged: "润色期间记录发生变化，已保留当前文字，未使用过期的润色结果。"
            }
        }
    }

    static let audioRetentionDaysDefaultsKey = "captureAudioRetentionDays"
    static let defaultAudioRetentionDays = 7

    let container: ModelContainer
    let audioDirectory: URL
    let cloudSyncEnabled: Bool

    @Published private(set) var historyRevision: UInt64 = 0

    var onHistoryChange: (() -> Void)?

    private var records: [UUID: CaptureRecord] = [:]
    private var lastProgressiveSave: [UUID: ContinuousClock.Instant] = [:]
    private var persistenceRevision: [UUID: Int] = [:]
    private let persistenceWriter: CapturePersistenceWriter

    init(
        inMemory: Bool = false, storageURL: URL? = nil, audioDirectory: URL? = nil,
        cloudSyncEnabled requestedCloudSync: Bool = false,
        performsLaunchMaintenance: Bool = true
    ) throws {
        let schema = Schema([
            CaptureRecord.self,
            CaptureUsageMetricsRecord.self,
            DictionaryEntry.self,
            DictionaryCorrectionRule.self,
            MemoryRecord.self,
            MemoryEvidenceRecord.self,
            MemoryAnalysisRecord.self,
            MemoryLearningBlock.self,
            ExpressionProfileRecord.self,
        ])
        precondition(!(inMemory && storageURL != nil), "An in-memory store cannot also use a storage URL.")

        // Tests and explicit storage URLs are always local. Production uses the
        // same SwiftData store and opts into Apple's managed private CloudKit
        // sync only when the user explicitly enables it.
        cloudSyncEnabled = requestedCloudSync && !inMemory && storageURL == nil
        let cloudDatabase: ModelConfiguration.CloudKitDatabase = cloudSyncEnabled ? .automatic : .none

        let configuration: ModelConfiguration
        if let storageURL {
            configuration = ModelConfiguration(
                "MorieCaptures",
                schema: schema,
                url: storageURL,
                cloudKitDatabase: .none
            )
        } else {
            configuration = ModelConfiguration(
                "MorieCaptures",
                schema: schema,
                isStoredInMemoryOnly: inMemory,
                cloudKitDatabase: cloudDatabase
            )
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
        container.mainContext.autosaveEnabled = false
        persistenceWriter = CapturePersistenceWriter(container: container)
        if let audioDirectory {
            self.audioDirectory = audioDirectory
        } else if let storageURL {
            self.audioDirectory = storageURL.deletingLastPathComponent()
                .appending(path: "CaptureAudio", directoryHint: .isDirectory)
        } else if inMemory {
            self.audioDirectory = FileManager.default.temporaryDirectory
                .appending(path: "MorieCaptureAudio-\(UUID().uuidString)", directoryHint: .isDirectory)
        } else {
            self.audioDirectory = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            ).appending(path: "Morie/CaptureAudio", directoryHint: .isDirectory)
        }
        try FileManager.default.createDirectory(at: self.audioDirectory, withIntermediateDirectories: true)
        if performsLaunchMaintenance {
            try recoverInterruptedCaptures()
            try pruneExpiredAudio()
            try ensureUsageMetricsRecord()
        }
    }

    func beginVoiceCapture(
        id: UUID,
        deliveryMode: CaptureDeliveryMode,
        applicationName: String?,
        bundleIdentifier: String?
    ) throws -> URL {
        let record = CaptureRecord(
            id: id,
            deliveryMode: deliveryMode,
            sourceApplicationName: applicationName,
            sourceBundleIdentifier: bundleIdentifier
        )
        record.sourceAudioRelativePath = "\(id.uuidString).m4a"
        record.sourceAudioExpiresAt = Calendar.current.date(
            byAdding: .day, value: Self.audioRetentionDays, to: record.createdAt
        )
        container.mainContext.insert(record)
        records[id] = record
        try container.mainContext.save()
        persistenceRevision[id] = 0
        Diagnostics.record("CaptureStore", "Durably created voice Capture \(label(id))")
        DevelopmentDiagnostics.record(
            "Persistence",
            captureID: id,
            "beginVoiceCapture; deliveryMode=\(deliveryMode.rawValue); sourceApp=\(applicationName ?? "unknown"); sourceBundle=\(bundleIdentifier ?? "unknown"); initialRevision=0"
        )
        return audioDirectory.appending(path: "\(id.uuidString).m4a")
    }

    func attachSourceAudio(_ source: CapturedSourceAudio, for id: UUID) throws {
        guard let record = records[id] else { return }
        let size = try source.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size > 0 else { return }
        record.sourceAudioRelativePath = source.url.lastPathComponent
        record.sourceAudioDurationSeconds = source.duration
        record.sourceAudioByteCount = Int64(size)
        record.sourceAudioExpiresAt = Calendar.current.date(byAdding: .day, value: Self.audioRetentionDays, to: Date())
        record.sourceAudioHasMeaningfulContent = source.hasMeaningfulAudio
        record.updatedAt = Date()
        schedulePersistence(for: record)
        Diagnostics.record("CaptureStore", "Source audio queued for \(label(id)); bytes=\(size)")
        DevelopmentDiagnostics.record(
            "Persistence",
            captureID: id,
            "audioAttached; bytes=\(size); durationSeconds=\(source.duration); meaningful=\(String(describing: source.hasMeaningfulAudio)); expiresAt=\(record.sourceAudioExpiresAt?.timeIntervalSince1970 ?? 0)"
        )
    }

    func updateRecognizedText(_ text: String, for id: UUID) throws {
        guard let record = records[id], record.lifecycle == .capturing else { return }
        record.recognizedText = text
        record.updatedAt = Date()

        let now = ContinuousClock.now
        if let lastSave = lastProgressiveSave[id], now - lastSave < .milliseconds(500) {
            return
        }

        schedulePersistence(for: record)
        lastProgressiveSave[id] = now
    }

    func finalizeCaptureOnlyUsage(_ id: UUID) throws {
        guard let record = records[id] else {
            throw StoreError.captureNotFound
        }
        record.usageMetricsFinalized = true
        record.updatedAt = Date()
        schedulePersistence(for: record)
    }

    @discardableResult
    func completeRecognition(_ text: String, for id: UUID) throws -> CaptureDeliveryMode {
        guard let record = records[id] else { throw StoreError.captureNotFound }
        guard let deliveryMode = CaptureDeliveryMode(rawValue: record.deliveryModeRawValue) else {
            throw StoreError.invalidDeliveryMode
        }
        record.recognizedText = text
        record.finalText = text
        record.lifecycle = .recognized
        record.updatedAt = Date()
        schedulePersistence(for: record)
        lastProgressiveSave[id] = nil
        Diagnostics.record("CaptureStore", "Capture \(label(id)) recognition queued; characters=\(text.count)")
        DevelopmentDiagnostics.record(
            "Persistence",
            captureID: id,
            "recognitionCommittedInMemory; lifecycle=recognized; characters=\(text.count); revision=\(persistenceRevision[id] ?? 0)"
        )
        return deliveryMode
    }

    func refinementInput(
        for id: UUID,
        context: [MemoryContextMatch],
        dictionary: [DictionarySnapshot] = [],
        corrections: [DictionaryCorrectionSnapshot] = [],
        expressionStyle: [String] = []
    ) throws -> RefinementInput {
        let record = try capture(id)
        guard record.refinement == nil else { throw StoreError.refinementSourceChanged }
        let input = RefinementInput(
            captureID: id,
            text: record.finalText,
            context: context,
            dictionary: dictionary,
            corrections: corrections,
            expressionStyle: expressionStyle
        )
        try requireRefinementSource(input)
        return input
    }

    func beginRefinement(_ input: RefinementInput) throws {
        let record = try requireRefinementSource(input)
        guard record.refinement == nil else { throw StoreError.refinementSourceChanged }
        record.refinement = CaptureRefinement(input: input, startedAt: Date())
        record.updatedAt = Date()
        schedulePersistence(for: record)
    }

    @discardableResult
    func saveRefinement(
        _ input: RefinementInput, result: ValidatedRefinement? = nil,
        reason: RefinementReason? = nil, durationSeconds: Double
    ) throws -> String {
        let record = try requireRefinementSource(input)
        guard result != nil || reason != nil,
              record.refinement == nil || record.refinement?.status == .running,
              result?.edits.isEmpty != false || record.refinement?.status == .running else {
            throw StoreError.refinementSourceChanged
        }
        var refinement = record.refinement ?? CaptureRefinement(input: input, startedAt: Date())
        refinement.reason = reason
        refinement.status = result?.edits.isEmpty == false ? .applied : (reason?.status ?? .unchanged)
        refinement.edits = result?.edits ?? []
        refinement.durationSeconds = durationSeconds
        record.finalText = result?.text ?? input.text
        record.refinement = refinement
        record.updatedAt = Date()
        schedulePersistence(for: record)
        Diagnostics.record("Refinement", "Capture \(label(input.captureID)); status=\(refinement.status.rawValue); edits=\(refinement.edits.count); milliseconds=\(Int(durationSeconds * 1_000))")
        return record.finalText
    }

    func interruptRefinement(_ input: RefinementInput) throws {
        let record = try capture(input.captureID)
        guard var refinement = record.refinement, refinement.input.id == input.id,
              refinement.status == .running else { return }
        refinement.status = .interrupted
        refinement.reason = .interrupted
        record.refinement = refinement
        record.updatedAt = Date()
        schedulePersistence(for: record)
    }

    @discardableResult
    func requireRefinementSource(_ input: RefinementInput) throws -> CaptureRecord {
        let record = try capture(input.captureID)
        guard record.lifecycle == .recognized,
              !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.recognizedText == input.text,
              record.finalText == input.text,
              record.refinement == nil || record.refinement?.input == input else {
            throw StoreError.refinementSourceChanged
        }
        return record
    }

    func markDelivered(
        _ id: UUID,
        applicationName: String?,
        bundleIdentifier: String?
    ) throws {
        guard let record = records[id] else { return }
        record.sourceApplicationName = applicationName
        record.sourceBundleIdentifier = bundleIdentifier
        try finish(id, lifecycle: .delivered, error: nil)
    }

    func markDeliveryFailed(_ id: UUID, error: String) throws {
        try finish(id, lifecycle: .deliveryFailed, error: error)
    }

    func markFailed(_ id: UUID, error: String) throws {
        try finish(id, lifecycle: .failed, error: error)
    }

    /// Empty final recognition is never a History item.
    ///
    /// Audio evidence decides whether saved-audio recognition gets a chance,
    /// not whether a Capture with no usable transcript should survive. By the
    /// time this method is called, both live and saved-audio recognition have
    /// produced no usable text, so the unfinished Capture and its source audio
    /// are discarded together.
    func finishEmptyRecognition(for id: UUID) throws {
        guard records[id] != nil else { throw StoreError.captureNotFound }
        try cancel(id)
    }

    func capture(_ id: UUID) throws -> CaptureRecord {
        if let record = records[id] {
            return record
        }
        var descriptor = FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try container.mainContext.fetch(descriptor).first else {
            throw StoreError.captureNotFound
        }
        return record
    }

    func releaseCaptureOwnership(_ id: UUID) {
        guard records[id]?.lifecycle != .capturing else { return }
        records[id] = nil
        lastProgressiveSave[id] = nil
    }

    func sourceAudioURL(for id: UUID, now: Date = Date()) throws -> URL {
        let record = try capture(id)
        guard records[id] == nil, record.lifecycle != .capturing, record.refinement?.status != .running else {
            throw StoreError.captureInProgress
        }
        if let expiresAt = record.sourceAudioExpiresAt, expiresAt <= now {
            throw StoreError.audioExpired
        }
        guard let url = audioURL(for: record), FileManager.default.isReadableFile(atPath: url.path) else {
            throw StoreError.audioUnavailable
        }
        return url
    }

    func saveReRecognition(_ text: String, for id: UUID) throws {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw StoreError.emptyRecognition }
        let record = try capture(id)
        guard records[id] == nil, record.lifecycle != .capturing, record.refinement?.status != .running else { throw StoreError.captureInProgress }

        record.recognizedText = text
        // Refined capture-only output is also a committed expression, independent of a later Speech retry.
        if record.lifecycle != .delivered && record.lifecycle != .deliveryFailed
            && record.refinement?.preservesFinalText != true {
            record.finalText = text
            record.lifecycle = .recognized
            record.deliveryErrorDescription = nil
        }
        record.lastRecognitionAttemptAt = Date()
        record.lastRecognitionErrorDescription = nil
        record.updatedAt = Date()
        do {
            try container.mainContext.save()
        } catch {
            container.mainContext.rollback()
            throw error
        }
        markHistoryChanged()
        Diagnostics.record("History", "Recognition updated for \(label(id)); characters=\(text.count)")
    }

    func recordReRecognitionFailure(_ message: String, for id: UUID) throws {
        let record = try capture(id)
        guard records[id] == nil, record.lifecycle != .capturing, record.refinement?.status != .running else { throw StoreError.captureInProgress }
        record.lastRecognitionAttemptAt = Date()
        record.lastRecognitionErrorDescription = message
        record.updatedAt = Date()
        do {
            try container.mainContext.save()
        } catch {
            container.mainContext.rollback()
            throw error
        }
        markHistoryChanged()
    }

    func deleteCapture(_ id: UUID) throws {
        let record = try capture(id)
        guard records[id] == nil, record.lifecycle != .capturing, record.refinement?.status != .running else { throw StoreError.captureInProgress }
        let extractions = try container.mainContext.fetch(FetchDescriptor<MemoryAnalysisRecord>(
            predicate: #Predicate { $0.sourceCaptureID == id }
        ))
        let url = audioURL(for: record)
        if let url, FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        for extraction in extractions { container.mainContext.delete(extraction) }
        container.mainContext.delete(record)
        try container.mainContext.save()
        markHistoryChanged()
        Diagnostics.record("History", "Deleted Capture \(label(id))")
    }

    func eraseAllDataForFactoryReset() async throws {
        guard records.isEmpty else {
            throw StoreError.captureInProgress
        }

        await persistenceWriter.beginFactoryReset()

        let context = container.mainContext
        do {
            for record in try context.fetch(FetchDescriptor<MemoryEvidenceRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MemoryAnalysisRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MemoryLearningBlock>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<MemoryRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<DictionaryCorrectionRule>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<DictionaryEntry>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<ExpressionProfileRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<CaptureRecord>()) {
                context.delete(record)
            }
            for record in try context.fetch(FetchDescriptor<CaptureUsageMetricsRecord>()) {
                context.delete(record)
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }

        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: audioDirectory.path) {
            for url in try fileManager.contentsOfDirectory(
                at: audioDirectory,
                includingPropertiesForKeys: nil
            ) {
                try fileManager.removeItem(at: url)
            }
        }

        records.removeAll(keepingCapacity: false)
        lastProgressiveSave.removeAll(keepingCapacity: false)
        persistenceRevision.removeAll(keepingCapacity: false)

        Diagnostics.record("FactoryReset", "Cleared SwiftData records and CaptureAudio files")
    }

    func cancel(_ id: UUID) throws {
        guard let record = records[id] else { return }
        try deleteAudio(for: record)
        lastProgressiveSave[id] = nil
        container.mainContext.delete(record)
        scheduleDelete(id)
        records[id] = nil
        Diagnostics.record("CaptureStore", "Cancelled Capture \(label(id)) queued for removal")
    }

    private func finish(_ id: UUID, lifecycle: CaptureLifecycle, error: String?) throws {
        guard let record = records[id] else { return }
        if var refinement = record.refinement, refinement.status == .running {
            // A refinement metadata snapshot may still be running when the session reaches a terminal state.
            let reason: RefinementReason = lifecycle == .delivered || lifecycle == .deliveryFailed ? .saveFailed : .interrupted
            refinement.status = reason.status
            refinement.reason = reason
            record.refinement = refinement
        }
        record.lifecycle = lifecycle
        record.deliveryErrorDescription = error
        record.usageMetricsFinalized = true
        record.updatedAt = Date()
        schedulePersistence(for: record)
        records[id] = nil
        lastProgressiveSave[id] = nil
        Diagnostics.record("CaptureStore", "Capture \(label(id)) queued with lifecycle=\(lifecycle.rawValue)")
        DevelopmentDiagnostics.record(
            "Persistence",
            captureID: id,
            "terminalLifecycleQueued=\(lifecycle.rawValue); errorPresent=\(error != nil); revision=\(persistenceRevision[id] ?? 0)"
        )
    }

    func flushPersistence(for id: UUID) async throws {
        let record = try capture(id)
        let revision = persistenceRevision[id] ?? 0
        let snapshot = persistenceSnapshot(for: record, revision: revision)
        DevelopmentDiagnostics.record(
            "Persistence",
            captureID: id,
            "flushStart; revision=\(revision); lifecycle=\(record.lifecycle.rawValue)"
        )
        do {
            try await persistenceWriter.persist(snapshot)
            if snapshot.usageMetricsFinalized {
                markHistoryChanged()
            }
            DevelopmentDiagnostics.record(
                "Persistence",
                captureID: id,
                "flushSucceeded; revision=\(revision); lifecycle=\(record.lifecycle.rawValue)"
            )
        } catch {
            DevelopmentDiagnostics.record(
                "Persistence",
                captureID: id,
                level: .error,
                "flushFailed; revision=\(revision); errorType=\(DevelopmentDiagnostics.errorType(error))"
            )
            throw error
        }
    }

    private func schedulePersistence(for record: CaptureRecord) {
        let id = record.id
        let revision = (persistenceRevision[id] ?? 0) + 1
        persistenceRevision[id] = revision
        let snapshot = persistenceSnapshot(for: record, revision: revision)
        DevelopmentDiagnostics.record(
            "Persistence",
            captureID: id,
            "backgroundPersistQueued; revision=\(revision); lifecycle=\(record.lifecycle.rawValue)"
        )
        Task(priority: .utility) { [weak self, persistenceWriter] in
            do {
                try await persistenceWriter.persist(snapshot)
                if snapshot.usageMetricsFinalized {
                    self?.markHistoryChanged()
                }
                DevelopmentDiagnostics.record(
                    "Persistence",
                    captureID: id,
                    "backgroundPersistSucceeded; revision=\(revision)"
                )
            } catch {
                DevelopmentDiagnostics.record(
                    "Persistence",
                    captureID: id,
                    level: .error,
                    "backgroundPersistFailed; revision=\(revision); errorType=\(DevelopmentDiagnostics.errorType(error))"
                )
                Diagnostics.record(
                    "CapturePersistence",
                    "Background persist failed for \(String(id.uuidString.prefix(8))) revision=\(revision): \(error.localizedDescription)",
                    level: .error
                )
            }
        }
    }

    private func scheduleDelete(_ id: UUID) {
        let revision = (persistenceRevision[id] ?? 0) + 1
        persistenceRevision[id] = revision
        Task(priority: .utility) { [persistenceWriter] in
            do {
                try await persistenceWriter.delete(id, revision: revision)
            } catch {
                Diagnostics.record(
                    "CapturePersistence",
                    "Background delete failed for \(String(id.uuidString.prefix(8))) revision=\(revision): \(error.localizedDescription)",
                    level: .error
                )
            }
        }
    }

    private func persistenceSnapshot(
        for record: CaptureRecord,
        revision: Int
    ) -> CapturePersistenceSnapshot {
        CapturePersistenceSnapshot(record: record, revision: revision)
    }

    func usageMetricsSnapshot() throws -> CaptureUsageMetricsSnapshot {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var descriptor = FetchDescriptor<CaptureUsageMetricsRecord>(
            predicate: #Predicate { $0.key == "overview" }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first?.snapshot ?? .empty
    }

    private func ensureUsageMetricsRecord() throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        var metricsDescriptor = FetchDescriptor<CaptureUsageMetricsRecord>(
            predicate: #Predicate { $0.key == "overview" }
        )
        metricsDescriptor.fetchLimit = 1
        guard try context.fetch(metricsDescriptor).first == nil else {
            return
        }

        let metrics = CaptureUsageMetricsRecord()
        let capturing = CaptureLifecycle.capturing.rawValue
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.lifecycleRawValue != capturing }
        )
        descriptor.propertiesToFetch = [
            \CaptureRecord.lifecycleRawValue,
            \CaptureRecord.deliveryModeRawValue,
            \CaptureRecord.recognizedText,
            \CaptureRecord.refinement,
        ]

        try context.enumerate(
            descriptor,
            batchSize: 128,
            allowEscapingMutations: false
        ) { capture in
            Self.accumulateUsage(capture, into: metrics)
        }

        context.insert(metrics)
        try context.save()
    }

    nonisolated static func accumulateUsage(
        _ capture: CaptureRecord,
        into metrics: CaptureUsageMetricsRecord
    ) {
        metrics.totalCaptures += 1
        metrics.recognizedCharacters += capture.recognizedText.count

        if capture.deliveryModeRawValue
            == CaptureDeliveryMode.currentApp.rawValue,
           [.delivered, .deliveryFailed, .failed].contains(capture.lifecycle) {
            metrics.currentAppAttempts += 1

            switch capture.lifecycle {
            case .delivered:
                metrics.successfulInputs += 1
            case .deliveryFailed, .failed:
                metrics.failedInputs += 1
            default:
                break
            }
        }

        if let duration = capture.refinement?.durationSeconds,
           duration >= 0 {
            metrics.refinementSamples += 1
            metrics.refinementDurationTotal += duration
        }
    }

    func pruneExpiredAudio(now: Date = Date()) throws {
        let noExpiry = Date.distantFuture
        let descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate {
                $0.sourceAudioRelativePath != nil
                    && ($0.sourceAudioExpiresAt ?? noExpiry) <= now
            }
        )
        let expired = try container.mainContext.fetch(descriptor).filter {
            records[$0.id] == nil && $0.refinement?.status != .running
        }
        guard !expired.isEmpty else { return }

        for record in expired {
            try deleteAudio(for: record)
            record.sourceAudioRelativePath = nil
        }
        try container.mainContext.save()
        markHistoryChanged()
        Diagnostics.record("CaptureStore", "Expired source audio for \(expired.count) Capture(s)")
    }

    func setAudioRetentionDays(_ days: Int) throws {
        let value = min(max(days, 1), 365)
        MorieDefaults.shared.set(value, forKey: Self.audioRetentionDaysDefaultsKey)
        let descriptor = FetchDescriptor<CaptureRecord>()
        for record in try container.mainContext.fetch(descriptor) where record.sourceAudioRelativePath != nil {
            record.sourceAudioExpiresAt = Calendar.current.date(byAdding: .day, value: value, to: record.createdAt)
        }
        try container.mainContext.save()
        markHistoryChanged()
        try pruneExpiredAudio()
    }

    static var audioRetentionDays: Int {
        let saved = MorieDefaults.shared.integer(forKey: audioRetentionDaysDefaultsKey)
        return saved > 0 ? saved : defaultAudioRetentionDays
    }

    private func deleteAudio(for record: CaptureRecord) throws {
        guard let url = audioURL(for: record) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
    }

    private func audioURL(for record: CaptureRecord) -> URL? {
        guard let path = record.sourceAudioRelativePath,
              path == "\(record.id.uuidString).m4a"
        else { return nil }
        return audioDirectory.appending(path: path)
    }

    private func recoverInterruptedCaptures() throws {
        let descriptor = FetchDescriptor<CaptureRecord>()
        let interrupted = try container.mainContext.fetch(descriptor).filter {
            $0.lifecycle == .capturing || $0.refinement?.status == .running
        }
        guard !interrupted.isEmpty else { return }
        for record in interrupted {
            if var refinement = record.refinement, refinement.status == .running {
                refinement.status = .interrupted
                refinement.reason = .interrupted
                record.refinement = refinement
                if record.deliveryModeRawValue == CaptureDeliveryMode.currentApp.rawValue,
                   record.lifecycle == .recognized {
                    record.lifecycle = .failed
                    record.deliveryErrorDescription = "输入处理已中断，已保存的文字和可用录音均已保留。"
                }
                record.updatedAt = Date()
                continue
            }
            let url = audioURL(for: record)
            let size = (try? url?.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            let hasText = !record.recognizedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !record.finalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if size == 0 && !hasText {
                try deleteAudio(for: record)
                container.mainContext.delete(record)
                continue
            }
            if size > 0 {
                record.sourceAudioByteCount = Int64(size)
            }
            record.lifecycle = .failed
            record.deliveryErrorDescription = "录音已中断，已保存的文字和可用录音均已保留。"
            record.updatedAt = Date()
        }
        try container.mainContext.save()
        Diagnostics.record("CaptureStore", "Recovered \(interrupted.count) interrupted Capture(s)")
    }

    func refreshHistoryAfterExternalChange() {
        historyRevision &+= 1
    }

    private func markHistoryChanged() {
        historyRevision &+= 1
        onHistoryChange?()
    }

    private func label(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
