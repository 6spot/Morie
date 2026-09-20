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
        Diagnostics.recordMemory("capability-inspect-finish")
        return checks
    }

    func requestPermission(_ requirement: SetupRequirement) async {
        let permissionWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        switch requirement {
        case .microphone:
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined else { return }
            Diagnostics.record("Permission", "Requesting microphone access from setup")
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        case .speechRecognition:
            guard SFSpeechRecognizer.authorizationStatus() == .notDetermined else { return }
            Diagnostics.record("Permission", "Requesting Speech authorization from setup")
            await Self.requestSpeechAuthorization()
        default:
            break
        }
        await restore(window: permissionWindow)
    }

    static func requestSpeechAuthorization(
        using recognizer: SFSpeechRecognizer.Type = SFSpeechRecognizer.self
    ) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            // Speech may call this Objective-C handler on a background queue.
            // Only resume the thread-safe continuation; do not inherit MainActor.
            recognizer.requestAuthorization { @Sendable _ in continuation.resume() }
        }
    }

    func openSettings(for requirement: SetupRequirement) async {
        guard let url = requirement.settingsURL else { return }
        let permissionWindow = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        Diagnostics.record("Permission", "Opening permission flow for \(requirement)")
        if requirement == .accessibility, !AXIsProcessTrusted() {
            // This is the only public API that registers the current signed
            // app in the Accessibility list. Let its single native prompt own
            // navigation to Settings instead of opening a second window here.
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            // Some TCC states register the app without presenting the prompt
            // again. Open the pane as part of the same click after registration
            // so the user never has to press Morie's button twice.
            try? await Task.sleep(for: .milliseconds(250))
            NSWorkspace.shared.open(url)
        } else {
            NSWorkspace.shared.open(url)
        }

        guard requirement.isPermission else { return }
        // macOS does not publish a TCC-change notification. Poll only while an
        // explicit Settings action is outstanding, then stop as soon as the
        // permission is granted or after five minutes.
        var didLeaveMorie = false
        for _ in 0..<600 {
            if permissionIsGranted(requirement) {
                Diagnostics.record("Permission", "Permission granted in System Settings for \(requirement)")
                await restore(window: permissionWindow)
                return
            }
            do { try await Task.sleep(for: .milliseconds(500)) }
            catch { return }
            // Returning to Morie without granting is also terminal; let the
            // controller perform its normal final inspection immediately.
            if NSApplication.shared.isActive {
                if didLeaveMorie { return }
            } else {
                didLeaveMorie = true
            }
        }
        Diagnostics.record("Permission", "Stopped waiting for System Settings permission for \(requirement)", level: .warning)
    }

    private func permissionIsGranted(_ requirement: SetupRequirement) -> Bool {
        switch requirement {
        case .microphone: AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        case .speechRecognition: SFSpeechRecognizer.authorizationStatus() == .authorized
        case .accessibility: AXIsProcessTrusted()
        default: false
        }
    }

    private func restore(window: NSWindow?) async {
        func bringForward() {
            NSApplication.shared.unhide(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            guard let window else { return }
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
            // Permission dialogs/System Settings can finish their own activation
            // transition after our first activation. Reordering the originating
            // native window keeps the explicit setup flow in front.
            window.orderFrontRegardless()
        }

        bringForward()
        await Task.yield()
        do { try await Task.sleep(for: .milliseconds(180)) }
        catch { return }
        bringForward()
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
        guard let backend = await SpeechRecognitionBackend.preferred(for: locale) else {
            return .init(requirement: .speechTranscription, state: .unavailable,
                         detail: "Apple 本机语音转写暂不支持当前输入语言（\(locale.identifier)）。")
        }
        Diagnostics.record(
            "Capability",
            "Preferred Speech backend for \(locale.identifier): \(backend.logName) (\(backend.locale.identifier))"
        )
        return .init(requirement: .speechTranscription, state: .ready)
    }
}

extension PermissionSetupController {
    convenience init(locale: Locale) {
        let gate = CapabilityGate()
        self.init(
            inspect: { await gate.inspect(locale: locale) },
            requestPermission: { await gate.requestPermission($0) },
            openSettings: { await gate.openSettings(for: $0) }
        )
    }
}
