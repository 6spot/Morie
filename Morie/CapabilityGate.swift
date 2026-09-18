import AppKit
@preconcurrency import ApplicationServices
import AVFoundation
import FoundationModels
import Speech

/// All probes are read-only; TCC prompts are limited to explicit setup actions.
@MainActor
struct CapabilityGate {
    func inspect(locale: Locale) async -> [CapabilityCheck] {
        let intelligence = inspectAppleIntelligence(locale: locale)
        let transcription = await inspectSpeech(locale: locale)
        let microphone: CapabilityCheck
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphone = .init(requirement: .microphone, state: .ready)
        case .notDetermined:
            microphone = .init(requirement: .microphone, state: .notDetermined, action: .requestPermission)
        case .denied:
            microphone = .init(requirement: .microphone, state: .denied,
                               detail: "在“隐私与安全性 → 麦克风”中允许 Morie 访问。", action: .openSettings)
        case .restricted:
            microphone = .init(requirement: .microphone, state: .restricted,
                               detail: "麦克风访问受系统或设备管理策略限制，请检查相关限制。")
        @unknown default:
            microphone = .init(requirement: .microphone, state: .unavailable, detail: "暂时无法读取麦克风权限，请重新检查。")
        }

        let recognition: CapabilityCheck
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            recognition = .init(requirement: .speechRecognition, state: .ready)
        case .notDetermined:
            recognition = .init(requirement: .speechRecognition, state: .notDetermined, action: .requestPermission)
        case .denied:
            recognition = .init(requirement: .speechRecognition, state: .denied,
                                detail: "在“隐私与安全性 → 语音识别”中允许 Morie 访问。", action: .openSettings)
        case .restricted:
            recognition = .init(requirement: .speechRecognition, state: .restricted,
                                detail: "语音识别受系统或设备管理策略限制，请检查相关限制。")
        @unknown default:
            recognition = .init(requirement: .speechRecognition, state: .unavailable, detail: "暂时无法读取语音识别权限，请重新检查。")
        }

        let accessibility: CapabilityCheck = AXIsProcessTrusted()
            ? .init(requirement: .accessibility, state: .ready)
            : .init(requirement: .accessibility, state: .denied,
                    detail: "在“隐私与安全性 → 辅助功能”中开启 Morie，然后返回这里。", action: .openSettings)
        let checks = [intelligence, transcription, microphone, recognition, accessibility]
        Diagnostics.record("Capability", checks.map { "\($0.requirement)=\($0.state)" }.joined(separator: "; "))
        return checks
    }

    func requestPermission(_ requirement: SetupRequirement) async {
        switch requirement {
        case .microphone:
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
            Diagnostics.record("Permission", "Requesting microphone access from setup")
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speechRecognition:
            guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
            Diagnostics.record("Permission", "Requesting Speech authorization from setup")
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                SFSpeechRecognizer.requestAuthorization { _ in continuation.resume() }
            }
        default:
            break
        }
    }

    func openSettings(for requirement: SetupRequirement) {
        guard let url = requirement.settingsURL else { return }
        Diagnostics.record("Permission", "Opening System Settings for \(requirement)")
        if requirement == .accessibility, !AXIsProcessTrusted() {
            // Register this signed app with TCC only after the explicit action.
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
        NSWorkspace.shared.open(url)
    }

    private func inspectAppleIntelligence(locale: Locale) -> CapabilityCheck {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            guard model.supportsLocale(locale) else {
                return .init(requirement: .appleIntelligence, state: .unavailable,
                             detail: "Apple 智能暂不支持当前输入语言（\(locale.identifier)）。")
            }
            return .init(requirement: .appleIntelligence, state: .ready)
        case .unavailable(.deviceNotEligible):
            return .init(requirement: .appleIntelligence, state: .unavailable,
                         detail: "这台 Mac 不支持 Apple 智能，无法运行 Morie 所需的本机智能功能。")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .init(requirement: .appleIntelligence, state: .unavailable,
                         detail: "请在系统设置中开启 Apple 智能。", action: .openSettings)
        case .unavailable(.modelNotReady):
            return .init(requirement: .appleIntelligence, state: .unavailable,
                         detail: "本机模型仍在下载或准备中，完成后请重新检查。", action: .openSettings)
        case .unavailable:
            return .init(requirement: .appleIntelligence, state: .unavailable,
                         detail: "Apple 智能暂时不可用，请检查系统设置后重试。", action: .openSettings)
        }
    }

    private func inspectSpeech(locale: Locale) async -> CapabilityCheck {
        guard SpeechTranscriber.isAvailable else {
            return .init(requirement: .speechTranscription, state: .unavailable,
                         detail: "这台 Mac 暂时无法使用 Apple 本机语音转写。")
        }
        guard await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil else {
            return .init(requirement: .speechTranscription, state: .unavailable,
                         detail: "Apple 语音转写暂不支持当前输入语言（\(locale.identifier)）。")
        }
        return .init(requirement: .speechTranscription, state: .ready)
    }
}

extension PermissionSetupController {
    convenience init(locale: Locale) {
        let gate = CapabilityGate()
        self.init(
            inspect: { await gate.inspect(locale: locale) },
            requestPermission: { await gate.requestPermission($0) },
            openSettings: { gate.openSettings(for: $0) }
        )
    }
}
