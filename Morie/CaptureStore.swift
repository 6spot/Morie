import Foundation
import CoreGraphics
import SwiftData

@MainActor
final class CaptureStore {
    let container: ModelContainer

    private var records: [UUID: CaptureRecord] = [:]
    private var lastProgressiveSave: [UUID: ContinuousClock.Instant] = [:]

    init(inMemory: Bool = false, storageURL: URL? = nil) throws {
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
    }

    func beginVoiceCapture(
        id: UUID,
        applicationName: String?,
        bundleIdentifier: String?,
        windowNumber: CGWindowID?
    ) throws {
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

    private func label(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
