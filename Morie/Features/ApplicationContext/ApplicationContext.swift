import Foundation

/// A lightweight identity for the application that owned keyboard focus when a
/// Capture started.
struct ApplicationIdentity: Equatable, Sendable {
    let name: String?
    let bundleIdentifier: String?
}

/// Ephemeral context captured once when a voice-input Capture starts.
///
/// This type is intentionally not Codable. Raw application text must remain a
/// runtime-only aid and must never become part of Capture persistence, History,
/// diagnostics, Memory, or other durable user data.
struct ApplicationContextSnapshot: Equatable, Sendable {
    let application: ApplicationIdentity
    let selectedText: String?
    let focusedText: String?
    let nearbyText: String?
    let capturedAt: Date

    var selectedCharacterCount: Int { selectedText?.count ?? 0 }
    var focusedCharacterCount: Int { focusedText?.count ?? 0 }
    var nearbyCharacterCount: Int { nearbyText?.count ?? 0 }

    var hasReadableText: Bool {
        selectedCharacterCount > 0
            || focusedCharacterCount > 0
            || nearbyCharacterCount > 0
    }
}
