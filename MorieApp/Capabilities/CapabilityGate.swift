import ApplicationServices
import AVFoundation
import CloudKit
import Foundation
import FoundationModels
import Speech

struct CapabilityIssue: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let detail: String
}

struct CapabilityReport: Sendable, Equatable {
    let issues: [CapabilityIssue]
    var isReady: Bool { issues.isEmpty }
}

actor CapabilityGate {
    func evaluate(locale requestedLocale: Locale) async -> CapabilityReport {
        var issues: [CapabilityIssue] = []

        let os = ProcessInfo.processInfo.operatingSystemVersion
        if os.majorVersion < 27 {
            issues.append(.init(
                id: "macos-version",
                title: "macOS 27 or newer is required",
                detail: "Morie V0 intentionally does not provide a compatibility path for older macOS versions."
            ))
        }

        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            if !model.supportsLocale(requestedLocale) {
                issues.append(.init(
                    id: "foundation-model-locale",
                    title: "Apple Foundation Model does not support this locale",
                    detail: requestedLocale.identifier
                ))
            }
        default:
            issues.append(.init(
                id: "foundation-model",
                title: "Apple Intelligence is not ready",
                detail: String(describing: model.availability)
            ))
        }

        if !SpeechTranscriber.isAvailable {
            issues.append(.init(
                id: "speech-device",
                title: "SpeechTranscriber is unavailable on this device",
                detail: "Morie does not fall back to legacy or third-party speech engines."
            ))
        } else if let speechLocale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) {
            let transcriber = SpeechTranscriber(locale: speechLocale, preset: .progressiveTranscription)
            do {
                try await ensureSpeechAssets(for: transcriber)
            } catch {
                issues.append(.init(
                    id: "speech-assets",
                    title: "Required Apple Speech assets are not ready",
                    detail: error.localizedDescription
                ))
            }
        } else {
            issues.append(.init(
                id: "speech-locale",
                title: "Apple Speech does not support this locale",
                detail: requestedLocale.identifier
            ))
        }

        let microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if microphoneStatus != .authorized {
            issues.append(.init(
                id: "microphone-permission",
                title: "Microphone permission is required",
                detail: microphoneStatus == .notDetermined
                    ? "Grant microphone access from the Morie menu."
                    : "Enable microphone access for Morie in System Settings."
            ))
        }

        if !AXIsProcessTrusted() {
            issues.append(.init(
                id: "accessibility-permission",
                title: "Accessibility permission is required",
                detail: "Morie needs Accessibility permission to restore focus and insert text into the app you were using."
            ))
        }

        do {
            let accountStatus = try await CKContainer.default().accountStatus()
            if accountStatus != .available {
                issues.append(.init(
                    id: "icloud-account",
                    title: "iCloud is required for Private Mode",
                    detail: "CloudKit account status: \(String(describing: accountStatus))"
                ))
            }
        } catch {
            issues.append(.init(
                id: "icloud-account",
                title: "Unable to verify iCloud / CloudKit",
                detail: error.localizedDescription
            ))
        }

        return CapabilityReport(issues: issues)
    }

    private func ensureSpeechAssets(for transcriber: SpeechTranscriber) async throws {
        switch await AssetInventory.status(forModules: [transcriber]) {
        case .installed:
            return
        case .supported, .downloading:
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            guard await AssetInventory.status(forModules: [transcriber]) == .installed else {
                throw CapabilityGateError.speechAssetsNotInstalled
            }
        case .unsupported:
            throw CapabilityGateError.speechAssetsUnsupported
        }
    }
}

enum CapabilityGateError: LocalizedError {
    case speechAssetsNotInstalled
    case speechAssetsUnsupported

    var errorDescription: String? {
        switch self {
        case .speechAssetsNotInstalled:
            "Apple Speech assets did not reach the installed state."
        case .speechAssetsUnsupported:
            "Apple Speech assets are unsupported for the selected configuration."
        }
    }
}
