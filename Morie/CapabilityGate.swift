import ApplicationServices
import AVFoundation
import Foundation
import FoundationModels
import Speech

struct CapabilityGate {
    enum GateError: LocalizedError {
        case appleIntelligenceUnavailable(String)
        case speechUnavailable
        case localeUnsupported(String)
        case microphoneDenied
        case speechPermissionDenied
        case accessibilityDenied

        var errorDescription: String? {
            switch self {
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
                "Accessibility permission is required for global input and text delivery."
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
                throw GateError.appleIntelligenceUnavailable("current locale is unsupported")
            }
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
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary

        guard AXIsProcessTrustedWithOptions(options) else {
            throw GateError.accessibilityDenied
        }
    }
}
