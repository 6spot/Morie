import Combine
import Foundation

enum SetupRequirement: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case appleIntelligence
    case speechTranscription
    case microphone
    case speechRecognition
    case accessibility

    var id: Self { self }

    var title: String {
        switch self {
        case .appleIntelligence: "Apple 智能"
        case .speechTranscription: "中文语音转写"
        case .microphone: "麦克风"
        case .speechRecognition: "语音识别"
        case .accessibility: "辅助功能"
        }
    }

    var explanation: String {
        switch self {
        case .appleIntelligence: "在这台 Mac 上润色输入，并从日常沟通中学习个人记忆。"
        case .speechTranscription: "使用 Apple 的本机语音识别，将录音转成文字。"
        case .microphone: "仅在你主动开始录音后采集声音。"
        case .speechRecognition: "允许 Morie 使用 Apple 语音识别来转写你的录音。"
        case .accessibility: "用于全局录音快捷键，以及将文字输入到你正在使用的应用。"
        }
    }

    var systemImage: String {
        switch self {
        case .appleIntelligence: "apple.intelligence"
        case .speechTranscription: "waveform"
        case .microphone: "mic"
        case .speechRecognition: "text.bubble"
        case .accessibility: "accessibility"
        }
    }

    var isPermission: Bool {
        self == .microphone || self == .speechRecognition || self == .accessibility
    }

    var settingsURL: URL? {
        let destination: String
        switch self {
        case .appleIntelligence:
            destination = "com.apple.Siri-Settings.extension"
        case .microphone:
            destination = "com.apple.preference.security?Privacy_Microphone"
        case .speechRecognition:
            destination = "com.apple.preference.security?Privacy_SpeechRecognition"
        case .accessibility:
            destination = "com.apple.preference.security?Privacy_Accessibility"
        case .speechTranscription:
            return nil
        }
        return URL(string: "x-apple.systempreferences:\(destination)")
    }
}

struct CapabilityCheck: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Equatable, Sendable {
        case ready, notDetermined, denied, restricted, unavailable
    }

    enum Action: String, Codable, Equatable, Sendable {
        case requestPermission, openSettings

        var title: String {
            switch self {
            case .requestPermission: "授权"
            case .openSettings: "打开系统设置"
            }
        }
    }

    let requirement: SetupRequirement
    let state: State
    var detail: String? = nil
    var action: Action? = nil

    var id: SetupRequirement { requirement }
    var isReady: Bool { state == .ready }
    var actionTitle: String? {
        guard let action else { return nil }
        if requirement == .accessibility, action == .openSettings { return "授权" }
        return action.title
    }
    var statusTitle: String {
        switch state {
        case .ready: requirement.isPermission ? "已授权" : "已就绪"
        case .notDetermined: "待授权"
        case .denied: "未允许"
        case .restricted: "受系统限制"
        case .unavailable: "尚不可用"
        }
    }
}

/// Owns only inspection and explicit permission actions. Refreshing never
/// prepares Speech assets, installs a hotkey, or touches an input session.
@MainActor
final class PermissionSetupController: ObservableObject {
    @Published private(set) var checks: [CapabilityCheck] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var activeRequest: SetupRequirement?

    private let inspect: @MainActor () async -> [CapabilityCheck]
    private let requestPermission: @MainActor (SetupRequirement) async -> Void
    private let openSettings: @MainActor (SetupRequirement) async -> Void
    private var refreshTask: Task<Void, Never>?

    init(
        inspect: @escaping @MainActor () async -> [CapabilityCheck],
        requestPermission: @escaping @MainActor (SetupRequirement) async -> Void,
        openSettings: @escaping @MainActor (SetupRequirement) async -> Void
    ) {
        self.inspect = inspect
        self.requestPermission = requestPermission
        self.openSettings = openSettings
    }

    var isBusy: Bool { isRefreshing || activeRequest != nil }

    var isReady: Bool {
        // An empty or partial snapshot must never pass the mandatory gate.
        SetupRequirement.allCases.allSatisfy { requirement in
            checks.contains { $0.requirement == requirement && $0.isReady }
        }
    }

    var firstIssue: CapabilityCheck? { checks.first { !$0.isReady } }

    func applyExternalChecks(_ checks: [CapabilityCheck]) {
        refreshTask?.cancel()
        refreshTask = nil
        isRefreshing = false
        activeRequest = nil
        self.checks = checks
    }

    func refresh() async {
        if let refreshTask {
            await refreshTask.value
            return
        }
        // A request owns its final inspection. Activation notifications from
        // the system permission dialog cannot overwrite it with a stale read.
        guard activeRequest == nil else { return }
        isRefreshing = true
        let task = Task { @MainActor in
            checks = await inspect()
            isRefreshing = false
        }
        refreshTask = task
        await task.value
        refreshTask = nil
    }

    func performAction(for requirement: SetupRequirement) async {
        guard !isBusy else { return }
        activeRequest = requirement
        defer { activeRequest = nil }

        // Permission may have changed since this page was drawn. Decide from
        // a fresh snapshot before requesting or opening System Settings.
        checks = await inspect()
        guard let check = checks.first(where: { $0.requirement == requirement }),
              !check.isReady, let action = check.action else { return }
        switch action {
        case .requestPermission:
            await requestPermission(requirement)
        case .openSettings:
            await openSettings(requirement)
        }
        checks = await inspect()
    }
}
