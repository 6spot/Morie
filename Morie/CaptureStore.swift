import Foundation
import CoreGraphics
import SwiftData

@MainActor
final class CaptureStore {
    static let audioRetentionDaysDefaultsKey = "captureAudioRetentionDays"
    static let defaultAudioRetentionDays = 7

    let container: ModelContainer
    let audioDirectory: URL

    private var records: [UUID: CaptureRecord] = [:]
    private var lastProgressiveSave: [UUID: ContinuousClock.Instant] = [:]

    init(inMemory: Bool = false, storageURL: URL? = nil, audioDirectory: URL? = nil) throws {
        let schema = Schema([CaptureRecord.self])
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
        try pruneExpiredAudio()
    }

    func beginVoiceCapture(
        id: UUID,
        applicationName: String?,
        bundleIdentifier: String?,
        windowNumber: CGWindowID?
    ) throws -> URL {
        let record = CaptureRecord(
            id: id,
            sourceApplicationName: applicationName,
            sourceBundleIdentifier: bundleIdentifier,
            originalWindowNumber: windowNumber
        )
        container.mainContext.insert(record)
        records[id] = record
        try container.mainContext.save()
        Diagnostics.record("CaptureStore", "Durably created voice Capture \(label(id))")
        return audioDirectory.appending(path: "\(id.uuidString).m4a")
    }

    func attachSourceAudio(url: URL, duration: TimeInterval, for id: UUID) throws {
        guard let record = records[id] else { return }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount > 0 else { return }
        record.sourceAudioRelativePath = url.lastPathComponent
        record.sourceAudioDurationSeconds = duration
        record.sourceAudioByteCount = byteCount
        record.sourceAudioExpiresAt = Calendar.current.date(
            byAdding: .day,
            value: Self.audioRetentionDays,
            to: Date()
        )
        record.updatedAt = Date()
        try container.mainContext.save()
        Diagnostics.record("CaptureStore", "Source audio saved for \(label(id)); bytes=\(byteCount)")
    }

    func updateRecognizedText(_ text: String, for id: UUID) throws {
        guard let record = records[id] else { return }
        record.recognizedText = text
        record.updatedAt = Date()

        let now = ContinuousClock.now
        if let lastSave = lastProgressiveSave[id], now - lastSave < .milliseconds(500) {
            return
        }

        try container.mainContext.save()
        lastProgressiveSave[id] = now
    }

    func completeRecognition(_ text: String, for id: UUID) throws {
        guard let record = records[id] else { return }
        record.recognizedText = text
        record.finalText = text
        record.lifecycle = .recognized
        record.updatedAt = Date()
        try container.mainContext.save()
        lastProgressiveSave[id] = nil
        Diagnostics.record("CaptureStore", "Capture \(label(id)) recognition saved; characters=\(text.count)")
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

    func cancel(_ id: UUID) throws {
        guard let record = records.removeValue(forKey: id) else { return }
        deleteAudio(for: record)
        lastProgressiveSave[id] = nil
        container.mainContext.delete(record)
        try container.mainContext.save()
        Diagnostics.record("CaptureStore", "Cancelled Capture \(label(id)) removed")
    }

    private func finish(_ id: UUID, lifecycle: CaptureLifecycle, error: String?) throws {
        guard let record = records[id] else { return }
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
            guard let expiry = $0.sourceAudioExpiresAt else { return false }
            return expiry <= now
        }
        guard !expired.isEmpty else { return }

        for record in expired {
            deleteAudio(for: record)
            record.sourceAudioRelativePath = nil
            record.sourceAudioDurationSeconds = nil
            record.sourceAudioByteCount = nil
            record.sourceAudioExpiresAt = nil
            record.updatedAt = now
        }
        try container.mainContext.save()
        Diagnostics.record("CaptureStore", "Expired source audio for \(expired.count) Capture(s)")
    }

    func setAudioRetentionDays(_ days: Int) throws {
        let clamped = min(max(days, 1), 365)
        UserDefaults.standard.set(clamped, forKey: Self.audioRetentionDaysDefaultsKey)
        let descriptor = FetchDescriptor<CaptureRecord>()
        for record in try container.mainContext.fetch(descriptor) where record.sourceAudioRelativePath != nil {
            record.sourceAudioExpiresAt = Calendar.current.date(byAdding: .day, value: clamped, to: record.createdAt)
        }
        try container.mainContext.save()
        try pruneExpiredAudio()
    }

    private func deleteAudio(for record: CaptureRecord) {
        guard let path = record.sourceAudioRelativePath else { return }
        try? FileManager.default.removeItem(at: audioDirectory.appending(path: path))
    }

    static var audioRetentionDays: Int {
        let saved = UserDefaults.standard.integer(forKey: audioRetentionDaysDefaultsKey)
        return saved > 0 ? saved : defaultAudioRetentionDays
    }

    private func label(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
