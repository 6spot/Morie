import Foundation
import CoreGraphics
import SwiftData

struct CapturedSourceAudio: Sendable {
    let url: URL
    let duration: TimeInterval
    let hasMeaningfulAudio: Bool

    init(url: URL, duration: TimeInterval, hasMeaningfulAudio: Bool = true) {
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
    var originalWindowNumber: Int64?
    var deliveryErrorDescription: String?
    var sourceAudioRelativePath: String?
    var sourceAudioDurationSeconds: Double?
    var sourceAudioByteCount: Int64?
    var sourceAudioExpiresAt: Date?
    var sourceAudioHasMeaningfulContent: Bool?

    init(
        id: UUID,
        sourceApplicationName: String?,
        sourceBundleIdentifier: String?,
        originalWindowNumber: CGWindowID?
    ) {
        self.id = id
        self.sourceApplicationName = sourceApplicationName
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.originalWindowNumber = originalWindowNumber.map(Int64.init)
    }

    var lifecycle: CaptureLifecycle {
        get { CaptureLifecycle(rawValue: lifecycleRawValue) ?? .failed }
        set { lifecycleRawValue = newValue.rawValue }
    }
}
