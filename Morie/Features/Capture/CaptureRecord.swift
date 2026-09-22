import Foundation
import SwiftData

struct CapturedSourceAudio: Sendable {
    let url: URL
    let duration: TimeInterval
    // nil means the signal has not been confirmed as speech or silence; keep it for retry.
    let hasMeaningfulAudio: Bool?

    init(url: URL, duration: TimeInterval, hasMeaningfulAudio: Bool? = nil) {
        self.url = url
        self.duration = duration
        self.hasMeaningfulAudio = hasMeaningfulAudio
    }
}

enum CaptureLifecycle: String, Codable, Sendable {
    case capturing
    case recognized
    case delivered
    case deliveryFailed
    case cancelled
    case failed
}

enum CaptureDeliveryMode: String, Codable, Sendable {
    case currentApp
    case captureOnly
}

struct CaptureUsageMetricsSnapshot: Equatable, Sendable {
    let totalCaptures: Int
    let recognizedCharacters: Int
    let successfulInputs: Int
    let currentAppAttempts: Int
    let failedInputs: Int
    let refinementSamples: Int
    let refinementDurationTotal: Double

    static let empty = CaptureUsageMetricsSnapshot(
        totalCaptures: 0,
        recognizedCharacters: 0,
        successfulInputs: 0,
        currentAppAttempts: 0,
        failedInputs: 0,
        refinementSamples: 0,
        refinementDurationTotal: 0
    )

    var averageRefinementSeconds: Double? {
        guard refinementSamples > 0 else { return nil }
        return refinementDurationTotal / Double(refinementSamples)
    }

    var failureRate: Double? {
        guard currentAppAttempts > 0 else { return nil }
        return Double(failedInputs) / Double(currentAppAttempts)
    }
}

@Model
final class CaptureUsageMetricsRecord {
    var key: String = "overview"
    var totalCaptures: Int = 0
    var recognizedCharacters: Int = 0
    var successfulInputs: Int = 0
    var currentAppAttempts: Int = 0
    var failedInputs: Int = 0
    var refinementSamples: Int = 0
    var refinementDurationTotal: Double = 0

    init() {}

    var snapshot: CaptureUsageMetricsSnapshot {
        CaptureUsageMetricsSnapshot(
            totalCaptures: totalCaptures,
            recognizedCharacters: recognizedCharacters,
            successfulInputs: successfulInputs,
            currentAppAttempts: currentAppAttempts,
            failedInputs: failedInputs,
            refinementSamples: refinementSamples,
            refinementDurationTotal: refinementDurationTotal
        )
    }
}

@Model
final class CaptureRecord {
    var id: UUID = UUID()
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var lifecycleRawValue: String = CaptureLifecycle.capturing.rawValue
    var deliveryModeRawValue: String = CaptureDeliveryMode.currentApp.rawValue
    var recognizedText: String = ""
    var finalText: String = ""
    var sourceApplicationName: String?
    var sourceBundleIdentifier: String?
    var deliveryErrorDescription: String?
    var sourceAudioRelativePath: String?
    var sourceAudioDurationSeconds: Double?
    var sourceAudioByteCount: Int64?
    var sourceAudioExpiresAt: Date?
    var sourceAudioHasMeaningfulContent: Bool?
    var lastRecognitionAttemptAt: Date?
    var lastRecognitionErrorDescription: String?
    var refinement: CaptureRefinement?
    var usageMetricsFinalized: Bool = false
    var usageMetricsRecorded: Bool = false

    init(
        id: UUID,
        deliveryMode: CaptureDeliveryMode,
        sourceApplicationName: String?,
        sourceBundleIdentifier: String?
    ) {
        self.id = id
        self.deliveryModeRawValue = deliveryMode.rawValue
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
    }

    var lifecycle: CaptureLifecycle {
        get { CaptureLifecycle(rawValue: lifecycleRawValue) ?? .failed }
        set { lifecycleRawValue = newValue.rawValue }
    }
}
