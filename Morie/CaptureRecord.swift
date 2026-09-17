import Foundation
import CoreGraphics
import SwiftData

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
