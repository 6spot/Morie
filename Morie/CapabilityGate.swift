@preconcurrency import ApplicationServices
import AVFoundation
import Foundation
import FoundationModels
import Speech

struct CapabilityGate {
    enum GateError: LocalizedError {
        case appleIntelligenceUnsupportedDevice
        case appleIntelligenceNotEnabled
        case appleIntelligenceModelNotReady
        case appleIntelligenceLocaleUnsupported(String)
        case appleIntelligenceUnavailable(String)
        case speechUnavailable
        case localeUnsupported(String)
        case microphoneDenied
        case speechPermissionDenied
        case accessibilityDenied

        var errorDescription: String? {
            switch self {
            case .appleIntelligenceUnsupportedDevice:
                "This Mac does not support Apple Intelligence, which is required for Morie Private Mode."
            case .appleIntelligenceNotEnabled:
                "Apple Intelligence is supported on this Mac but is not enabled. Turn it on in System Settings, then recheck Morie."
            case .appleIntelligenceModelNotReady:
                "Apple Intelligence is enabled, but the on-device model is not ready yet. It may still be downloading or preparing."
            case .appleIntelligenceLocaleUnsupported(let locale):
                "Apple Intelligence does not support the current locale (\(locale)) for Morie Private Mode."
            case .appleIntelligenceUnavailable(let reason):
                "Apple Intelligence is unavailable: \(reason)"
            case .speechUnavailable:
                "SpeechTranscriber is unavailable on this Mac."
            case .localeUnsupported(let locale):
                "Speech transcription does not support the current locale (\(locale))."
            case .microphoneDenied:
                "Microphone permission is required."
            case .speechPermissionDenied:
                "Speech recognition permission is required."
            case .accessibilityDenied:
                "Accessibility permission is required for the global shortcut and text delivery."
            }
        }
    }

    func requirePrivateMode() async throws {
        try requireAppleIntelligence()
        try await requireSpeech()
        try await requireMicrophone()
        try await requireSpeechAuthorization()
        try requireAccessibility()
    }

    private func requireAppleIntelligence() throws {
        let model = SystemLanguageModel.default

        switch model.availability {
        case .available:
            guard model.supportsLocale(.current) else {
                throw GateError.appleIntelligenceLocaleUnsupported(Locale.current.identifier)
            }
        case .unavailable(.deviceNotEligible):
            throw GateError.appleIntelligenceUnsupportedDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            throw GateError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            throw GateError.appleIntelligenceModelNotReady
        case .unavailable(let reason):
            throw GateError.appleIntelligenceUnavailable(String(describing: reason))
        }
    }

    private func requireSpeech() async throws {
        guard SpeechTranscriber.isAvailable else {
            throw GateError.speechUnavailable
        }

        guard await SpeechTranscriber.supportedLocale(equivalentTo: .current) != nil else {
            throw GateError.localeUnsupported(Locale.current.identifier)
        }
    }

    private func requireMicrophone() async throws {
        let allowed: Bool

        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            allowed = true
        case .notDetermined:
            allowed = await AVCaptureDevice.requestAccess(for: .audio)
        default:
            allowed = false
        }

        guard allowed else { throw GateError.microphoneDenied }
    }

    private func requireSpeechAuthorization() async throws {
        let status: SFSpeechRecognizerAuthorizationStatus

        if SFSpeechRecognizer.authorizationStatus() == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        } else {
            status = SFSpeechRecognizer.authorizationStatus()
        }

        guard status == .authorized else {
            throw GateError.speechPermissionDenied
        }
    }

    private func requireAccessibility() throws {
        // ApplicationServices is a C framework and its option-key global is not
        // annotated for Swift 6 concurrency. `@preconcurrency import` keeps the
        // native API while acknowledging that legacy annotation boundary; this
        // method is only called from Morie's serialized capability check.
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary

        guard AXIsProcessTrustedWithOptions(options) else {
            throw GateError.accessibilityDenied
        }
    }
}
