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
        Diagnostics.record("Capability", "Starting capability checks")
        try requireAppleIntelligence()
        try await requireSpeech()
        try await requireMicrophone()
        try await requireSpeechAuthorization()
        try requireAccessibility()
        Diagnostics.record("Capability", "All Phase 0 capability checks passed")
    }

    private func requireAppleIntelligence() throws {
        let model = SystemLanguageModel.default
        Diagnostics.record("Capability", "Apple Intelligence availability: \(String(describing: model.availability))")

        switch model.availability {
        case .available:
            guard model.supportsLocale(.current) else {
                Diagnostics.record("Capability", "Apple Intelligence locale unsupported: \(Locale.current.identifier)", level: .error)
                throw GateError.appleIntelligenceLocaleUnsupported(Locale.current.identifier)
            }
            Diagnostics.record("Capability", "Apple Intelligence ready for locale \(Locale.current.identifier)")
        case .unavailable(.deviceNotEligible):
            Diagnostics.record("Capability", "Apple Intelligence unavailable: device not eligible", level: .error)
            throw GateError.appleIntelligenceUnsupportedDevice
        case .unavailable(.appleIntelligenceNotEnabled):
            Diagnostics.record("Capability", "Apple Intelligence unavailable: not enabled", level: .error)
            throw GateError.appleIntelligenceNotEnabled
        case .unavailable(.modelNotReady):
            Diagnostics.record("Capability", "Apple Intelligence unavailable: model not ready", level: .warning)
            throw GateError.appleIntelligenceModelNotReady
        case .unavailable(let reason):
            Diagnostics.record("Capability", "Apple Intelligence unavailable: \(String(describing: reason))", level: .error)
            throw GateError.appleIntelligenceUnavailable(String(describing: reason))
        }
    }

    private func requireSpeech() async throws {
        Diagnostics.record("Capability", "SpeechTranscriber availability: \(SpeechTranscriber.isAvailable)")
        guard SpeechTranscriber.isAvailable else {
            throw GateError.speechUnavailable
        }

        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: .current) else {
            Diagnostics.record("Capability", "Speech locale unsupported: \(Locale.current.identifier)", level: .error)
            throw GateError.localeUnsupported(Locale.current.identifier)
        }

        Diagnostics.record("Capability", "Speech locale resolved: \(locale.identifier)")
    }

    private func requireMicrophone() async throws {
        let initialStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        Diagnostics.record("Permission", "Microphone authorization: \(String(describing: initialStatus))")

        let allowed: Bool
        switch initialStatus {
        case .authorized:
            allowed = true
        case .notDetermined:
            Diagnostics.record("Permission", "Requesting microphone access")
            allowed = await AVCaptureDevice.requestAccess(for: .audio)
            Diagnostics.record("Permission", "Microphone request result: \(allowed)")
        default:
            allowed = false
        }

        guard allowed else {
            Diagnostics.record("Permission", "Microphone permission denied", level: .error)
            throw GateError.microphoneDenied
        }
    }

    private func requireSpeechAuthorization() async throws {
        let initialStatus = SFSpeechRecognizer.authorizationStatus()
        Diagnostics.record("Permission", "Speech authorization: \(String(describing: initialStatus))")

        let status: SFSpeechRecognizerAuthorizationStatus
        if initialStatus == .notDetermined {
            Diagnostics.record("Permission", "Requesting Speech recognition authorization")
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
            Diagnostics.record("Permission", "Speech authorization result: \(String(describing: status))")
        } else {
            status = initialStatus
        }

        guard status == .authorized else {
            Diagnostics.record("Permission", "Speech recognition permission denied", level: .error)
            throw GateError.speechPermissionDenied
        }
    }

    private func requireAccessibility() throws {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        Diagnostics.record("Permission", "Accessibility trusted: \(trusted)")

        guard trusted else {
            Diagnostics.record("Permission", "Accessibility permission missing", level: .error)
            throw GateError.accessibilityDenied
        }
    }
}
