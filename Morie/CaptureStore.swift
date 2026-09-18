import Foundation
import CoreGraphics
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
            case .captureNotFound: "This capture is no longer available."
            case .captureInProgress: "Wait for this recording to finish."
            case .audioExpired: "The source recording has expired. Saved text is still available."
            case .audioUnavailable: "The source recording is no longer available."
            case .emptyRecognition: "No speech was recognized. The saved text and recording have been kept."
            case .invalidDeliveryMode: "The capture has an invalid delivery mode."
            case .refinementSourceChanged: "The saved capture changed during refinement. Its current text has been kept; no stale result was used."
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

    private var records: [UUID: CaptureRecord] = [:]
    private var lastProgressiveSave: [UUID: ContinuousClock.Instant] = [:]
    private let commitRefinement: (ModelContext) throws -> Void

    init(
        inMemory: Bool = false, storageURL: URL? = nil, audioDirectory: URL? = nil,
        commitRefinement: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) throws {
        self.commitRefinement = commitRefinement
        let schema = Schema([CaptureRecord.self, DictionaryEntry.self, MemoryRecord.self, MemoryAnalysisRecord.self, MemoryLearningBlock.self])
        precondition(!(inMemory && storageURL != nil), "An in-memory store cannot also use a storage URL.")

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
                cloudKitDatabase: .none
            )
        }
        container = try ModelContainer(for: schema, configurations: [configuration])
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
        bundleIdentifier: String?,
        windowNumber: CGWindowID?
    ) throws -> URL {
        try pruneExpiredAudio()
        let record = CaptureRecord(
            id: id,
            deliveryMode: deliveryMode,
            sourceApplicationName: applicationName,
            sourceBundleIdentifier: bundleIdentifier,
            originalWindowNumber: windowNumber
        )
        record.sourceAudioRelativePath = "\(id.uuidString).m4a"
        record.sourceAudioExpiresAt = Calendar.current.date(
            byAdding: .day, value: Self.audioRetentionDays, to: record.createdAt
        )
        container.mainContext.insert(record)
        records[id] = record
        try container.mainContext.save()
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
        try container.mainContext.save()
        Diagnostics.record("CaptureStore", "Source audio saved for \(label(id)); bytes=\(size)")
    }

    func updateRecognizedText(_ text: String, for id: UUID) throws {
        guard let record = records[id], record.lifecycle == .capturing else { return }
        record.recognizedText = text
        record.updatedAt = Date()

        let now = ContinuousClock.now
        if let lastSave = lastProgressiveSave[id], now - lastSave < .milliseconds(500) {
            return
        }

        try container.mainContext.save()
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
        try container.mainContext.save()
        lastProgressiveSave[id] = nil
        if deliveryMode == .captureOnly {
            records[id] = nil
        }
        Diagnostics.record("CaptureStore", "Capture \(label(id)) recognition saved; characters=\(text.count)")
        return deliveryMode
    }

    func refinementInput(for id: UUID, context: [MemoryContextMatch], dictionary: [DictionarySnapshot] = []) throws -> RefinementInput {
        let record = try capture(id)
        guard record.refinement == nil else { throw StoreError.refinementSourceChanged }
        let input = RefinementInput(captureID: id, text: record.finalText, context: context, dictionary: dictionary)
        try requireRefinementSource(input)
        return input
    }

    func beginRefinement(_ input: RefinementInput) throws {
        let record = try requireRefinementSource(input)
        guard record.refinement == nil else { throw StoreError.refinementSourceChanged }
        record.refinement = CaptureRefinement(input: input, startedAt: Date())
        record.updatedAt = Date()
        try saveRefinementChanges()
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
        try saveRefinementChanges()
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
        try saveRefinementChanges()
    }

    @discardableResult
    func requireRefinementSource(_ input: RefinementInput) throws -> CaptureRecord {
        let record = try capture(input.captureID)
        let id = input.captureID
        let reader = ModelContext(container)
        let request = FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })
        guard let saved = try reader.fetch(request).first,
              record.lifecycle == .recognized, saved.lifecycle == .recognized,
              !input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              record.recognizedText == input.text, saved.recognizedText == input.text,
              record.finalText == input.text, saved.finalText == input.text,
              record.refinement == saved.refinement,
              record.refinement == nil || record.refinement?.input == input else {
            throw StoreError.refinementSourceChanged
        }
        return record
    }

    private func saveRefinementChanges() throws {
        do {
            try commitRefinement(container.mainContext)
        } catch {
            container.mainContext.rollback()
            throw error
        }
    }

    func markDelivered(_ id: UUID) throws {
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

        try markFailed(id, error: "No speech was recognized. Play the recording or recognize it again from History.")
        return .retainedForRetry
    }

    func capture(_ id: UUID) throws -> CaptureRecord {
        var descriptor = FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let record = try container.mainContext.fetch(descriptor).first else {
            throw StoreError.captureNotFound
        }
        return record
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
        try container.mainContext.save()
        records[id] = nil
        Diagnostics.record("CaptureStore", "Cancelled Capture \(label(id)) removed")
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
        try container.mainContext.save()
        records[id] = nil
        lastProgressiveSave[id] = nil
        Diagnostics.record("CaptureStore", "Capture \(label(id)) saved with lifecycle=\(lifecycle.rawValue)")
    }

    func pruneExpiredAudio(now: Date = Date()) throws {
        let descriptor = FetchDescriptor<CaptureRecord>()
        let expired = try container.mainContext.fetch(descriptor).filter {
            $0.sourceAudioRelativePath != nil && records[$0.id] == nil
                && $0.refinement?.status != .running
                && ($0.sourceAudioExpiresAt.map { $0 <= now } ?? false)
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
                    record.deliveryErrorDescription = "Input processing was interrupted. Saved text and available audio have been kept."
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
            record.deliveryErrorDescription = "Recording was interrupted. Saved text and available audio have been kept."
            record.updatedAt = Date()
        }
        try container.mainContext.save()
        Diagnostics.record("CaptureStore", "Recovered \(interrupted.count) interrupted Capture(s)")
    }

    private func label(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
