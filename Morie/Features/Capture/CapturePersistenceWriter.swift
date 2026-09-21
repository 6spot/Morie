import Foundation
import SwiftData

struct CapturePersistenceSnapshot: Sendable {
    let id: UUID
    let revision: Int
    let enqueuedAt: Date
    let createdAt: Date
    let updatedAt: Date
    let lifecycleRawValue: String
    let deliveryModeRawValue: String
    let recognizedText: String
    let finalText: String
    let sourceApplicationName: String?
    let sourceBundleIdentifier: String?
    let deliveryErrorDescription: String?
    let sourceAudioRelativePath: String?
    let sourceAudioDurationSeconds: Double?
    let sourceAudioByteCount: Int64?
    let sourceAudioExpiresAt: Date?
    let sourceAudioHasMeaningfulContent: Bool?
    let lastRecognitionAttemptAt: Date?
    let lastRecognitionErrorDescription: String?
    let refinement: CaptureRefinement?

    init(record: CaptureRecord, revision: Int, enqueuedAt: Date = Date()) {
        id = record.id
        self.revision = revision
        self.enqueuedAt = enqueuedAt
        createdAt = record.createdAt
        updatedAt = record.updatedAt
        lifecycleRawValue = record.lifecycleRawValue
        deliveryModeRawValue = record.deliveryModeRawValue
        recognizedText = record.recognizedText
        finalText = record.finalText
        sourceApplicationName = record.sourceApplicationName
        sourceBundleIdentifier = record.sourceBundleIdentifier
        deliveryErrorDescription = record.deliveryErrorDescription
        sourceAudioRelativePath = record.sourceAudioRelativePath
        sourceAudioDurationSeconds = record.sourceAudioDurationSeconds
        sourceAudioByteCount = record.sourceAudioByteCount
        sourceAudioExpiresAt = record.sourceAudioExpiresAt
        sourceAudioHasMeaningfulContent = record.sourceAudioHasMeaningfulContent
        lastRecognitionAttemptAt = record.lastRecognitionAttemptAt
        lastRecognitionErrorDescription = record.lastRecognitionErrorDescription
        refinement = record.refinement
    }
}

actor CapturePersistenceWriter {
    private let context: ModelContext
    private var latestRevision: [UUID: Int] = [:]
    private var acceptsWrites = true

    init(container: ModelContainer) {
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func beginFactoryReset() {
        acceptsWrites = false
        latestRevision.removeAll(keepingCapacity: false)
    }

    func persist(_ snapshot: CapturePersistenceSnapshot) throws {
        guard acceptsWrites else { return }
        let latest = latestRevision[snapshot.id] ?? -1
        guard snapshot.revision > latest else { return }

        let id = snapshot.id
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        guard let record = try context.fetch(descriptor).first else {
            Diagnostics.record(
                "CapturePersistence",
                "Skipped revision \(snapshot.revision) for missing Capture \(label(snapshot.id))",
                level: .warning
            )
            return
        }

        apply(snapshot, to: record)
        let writeStarted = ContinuousClock.now
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        latestRevision[snapshot.id] = snapshot.revision

        Diagnostics.record(
            "CapturePersistence",
            "Persisted \(label(snapshot.id)) revision=\(snapshot.revision) lifecycle=\(snapshot.lifecycleRawValue); queueMs=\(milliseconds(since: snapshot.enqueuedAt)); writeMs=\(milliseconds(since: writeStarted))"
        )
    }

    func delete(_ id: UUID, revision: Int) throws {
        guard acceptsWrites else { return }
        let latest = latestRevision[id] ?? -1
        guard revision > latest else { return }

        // Claim the tombstone revision before disk I/O. Even if deletion fails,
        // an older queued snapshot must never resurrect an explicitly cancelled Capture.
        latestRevision[id] = revision

        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        if let record = try context.fetch(descriptor).first {
            context.delete(record)
            do {
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
        Diagnostics.record(
            "CapturePersistence",
            "Persisted cancellation tombstone for \(label(id)) revision=\(revision)"
        )
    }

    private func apply(_ snapshot: CapturePersistenceSnapshot, to record: CaptureRecord) {
        record.createdAt = snapshot.createdAt
        record.updatedAt = snapshot.updatedAt
        record.lifecycleRawValue = snapshot.lifecycleRawValue
        record.deliveryModeRawValue = snapshot.deliveryModeRawValue
        record.recognizedText = snapshot.recognizedText
        record.finalText = snapshot.finalText
        record.sourceApplicationName = snapshot.sourceApplicationName
        record.sourceBundleIdentifier = snapshot.sourceBundleIdentifier
        record.deliveryErrorDescription = snapshot.deliveryErrorDescription
        record.sourceAudioRelativePath = snapshot.sourceAudioRelativePath
        record.sourceAudioDurationSeconds = snapshot.sourceAudioDurationSeconds
        record.sourceAudioByteCount = snapshot.sourceAudioByteCount
        record.sourceAudioExpiresAt = snapshot.sourceAudioExpiresAt
        record.sourceAudioHasMeaningfulContent = snapshot.sourceAudioHasMeaningfulContent
        record.lastRecognitionAttemptAt = snapshot.lastRecognitionAttemptAt
        record.lastRecognitionErrorDescription = snapshot.lastRecognitionErrorDescription
        record.refinement = snapshot.refinement
    }

    private func milliseconds(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1_000))
    }

    private func milliseconds(since instant: ContinuousClock.Instant) -> Int {
        let value = ContinuousClock.now - instant
        let parts = value.components
        return max(0, Int(Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15))
    }

    private func label(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }
}
