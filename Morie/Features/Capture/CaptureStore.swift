import Foundation
import SwiftData

@MainActor
final class CaptureStore {
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

    enum EmptyRecognitionDisposition {
        case discarded
        case retainedForRetry
    }

    static let audioRetentionDaysDefaultsKey = "captureAudioRetentionDays"
    static let defaultAudioRetentionDays = 7

    let container: ModelContainer
    let audioDirectory: URL
    let cloudSyncEnabled: Bool

    private var records: [UUID: CaptureRecord] = [:]
    private var lastProgressiveSave: [UUID: ContinuousClock.Instant] = [:]
    private var persistenceRevision: [UUID: Int] = [:]
    private let persistenceWriter: CapturePersistenceWriter
    private let commitRefinement: (ModelContext) throws -> Void

    init(
        inMemory: Bool = false, storageURL: URL? = nil, audioDirectory: URL? = nil,
        cloudSyncEnabled requestedCloudSync: Bool = false,
        commitRefinement: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        self.commitRefinement = commitRefinement
        let schema = Schema([
            CaptureRecord.self,
            DictionaryEntry.self,
            MemoryRecord.self,
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
        try recoverInterruptedCaptures()
        try pruneExpiredAudio()
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
        return deliveryMode
    }

    func refinementInput(
        for id: UUID,
        context: [MemoryContextMatch],
        dictionary: [DictionarySnapshot] = [],
        expressionStyle: [String] = []
    ) throws -> RefinementInput {
        let record = try capture(id)
        guard record.refinement == nil else { throw StoreError.refinementSourceChanged }
        let input = RefinementInput(
            captureID: id,
            text: record.finalText,
            context: context,
            dictionary: dictionary,
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

    func finishEmptyRecognition(
        for id: UUID,
        sourceAudio: CapturedSourceAudio
    ) throws -> EmptyRecognitionDisposition {
        guard records[id] != nil else { throw StoreError.captureNotFound }
        if sourceAudio.hasMeaningfulAudio == false
            || (sourceAudio.duration == 0 && sourceAudio.hasMeaningfulAudio != true) {
            try cancel(id)
            return .discarded
        }

        try markFailed(id, error: "未识别到语音，可以在历史记录中播放录音或重新识别。")
        return .retainedForRetry
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
        Diagnostics.record("History", "Deleted Capture \(label(id))")
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
            // A refinement metadata save may have failed even though the durable original was usable.
            let reason: RefinementReason = lifecycle == .delivered || lifecycle == .deliveryFailed ? .saveFailed : .interrupted
            refinement.status = reason.status
            refinement.reason = reason
            record.refinement = refinement
        }
        record.lifecycle = lifecycle
        record.deliveryErrorDescription = error
        record.updatedAt = Date()
        schedulePersistence(for: record)
        records[id] = nil
        lastProgressiveSave[id] = nil
        Diagnostics.record("CaptureStore", "Capture \(label(id)) queued with lifecycle=\(lifecycle.rawValue)")
    }

    func flushPersistence(for id: UUID) async throws {
        let record = try capture(id)
        let revision = persistenceRevision[id] ?? 0
        let snapshot = persistenceSnapshot(for: record, revision: revision)
        try await persistenceWriter.persist(snapshot)
    }

    private func schedulePersistence(for record: CaptureRecord) {
        let id = record.id
        let revision = (persistenceRevision[id] ?? 0) + 1
        persistenceRevision[id] = revision
        let snapshot = persistenceSnapshot(for: record, revision: revision)
        Task(priority: .utility) { [persistenceWriter] in
            do {
                try await persistenceWriter.persist(snapshot)
            } catch {
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
        Diagnostics.record("CaptureStore", "Expired source audio for \(expired.count) Capture(s)")
    }

    func setAudioRetentionDays(_ days: Int) throws {
        let value = min(max(days, 1), 365)
        UserDefaults.standard.set(value, forKey: Self.audioRetentionDaysDefaultsKey)
        let descriptor = FetchDescriptor<CaptureRecord>()
        for record in try container.mainContext.fetch(descriptor) where record.sourceAudioRelativePath != nil {
            record.sourceAudioExpiresAt = Calendar.current.date(byAdding: .day, value: value, to: record.createdAt)
        }
        try container.mainContext.save()
        try pruneExpiredAudio()
    }

    static var audioRetentionDays: Int {
        let saved = UserDefaults.standard.integer(forKey: audioRetentionDaysDefaultsKey)
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

    private func label(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
