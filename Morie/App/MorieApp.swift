import AppKit
import Combine
import SwiftUI

@main
struct MorieApp: App {
    @StateObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow
    private let captureStore: CaptureStore?

    init() {
        let wantsICloud = ICloudSyncSettings.isEnabled
        do {
            let store = try CaptureStore(cloudSyncEnabled: wantsICloud)
            captureStore = store
            _controller = StateObject(
                wrappedValue: AppController(captureStore: store)
            )
        } catch where wantsICloud {
            // Optional iCloud must never make local input unusable. If the
            // CloudKit-backed SwiftData configuration cannot open, retry the
            // same current schema locally and surface the cloud failure.
            do {
                let store = try CaptureStore(cloudSyncEnabled: false)
                captureStore = store
                _controller = StateObject(
                    wrappedValue: AppController(
                        captureStore: store,
                        cloudSyncStartupError: error
                    )
                )
            } catch {
                captureStore = nil
                _controller = StateObject(
                    wrappedValue: AppController(captureStore: nil, persistenceError: error)
                )
            }
        } catch {
            captureStore = nil
            _controller = StateObject(
                wrappedValue: AppController(captureStore: nil, persistenceError: error)
            )
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MorieMenuContent(controller: controller)
        } label: {
            MorieMenuBarLabel(controller: controller)
        }
        .menuBarExtraStyle(.menu)

        Window("Morie", id: "control-center") {
            Group {
                if let captureStore {
                    MorieControlCenter(controller: controller)
                        .modelContainer(captureStore.container)
                } else {
                    ContentUnavailableView(
                        "Morie 暂不可用",
                        systemImage: "exclamationmark.triangle",
                        description: Text("无法打开记录存储，请在使用引导中查看详情。")
                    )
                }
            }
            .environment(\.locale, Locale(identifier: "zh-Hans"))
            .onAppear {
                MorieApplicationActivation.windowDidAppear("control-center")
            }
            .onDisappear {
                MorieApplicationActivation.windowDidDisappear("control-center")
            }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            SidebarCommands()
            MorieCommands()
        }

        Window("欢迎使用 Morie", id: "setup") {
            MorieSetupView(controller: controller)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .onAppear {
                    MorieApplicationActivation.windowDidAppear("setup")
                }
                .onDisappear {
                    MorieApplicationActivation.windowDidDisappear("setup")
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 740)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

    }
}


@MainActor
private enum MorieApplicationActivation {
    private static var visibleWindowIDs = Set<String>()

    static func prepareToOpenWindow() {
        useRegularPolicy()
    }

    static func windowDidAppear(_ id: String) {
        visibleWindowIDs.insert(id)
        useRegularPolicy()
    }

    static func windowDidDisappear(_ id: String) {
        visibleWindowIDs.remove(id)
        guard visibleWindowIDs.isEmpty else { return }

        let application = NSApplication.shared
        application.deactivate()
        guard application.activationPolicy() != .accessory else { return }

        if !application.setActivationPolicy(.accessory) {
            Diagnostics.record(
                "UI",
                "Failed to restore accessory activation policy after closing Morie windows.",
                level: .warning
            )
        }
    }

    private static func useRegularPolicy() {
        let application = NSApplication.shared
        guard application.activationPolicy() != .regular else { return }

        if !application.setActivationPolicy(.regular) {
            Diagnostics.record(
                "UI",
                "Failed to switch to regular activation policy for Morie window.",
                level: .warning
            )
        }
    }
}

@MainActor
private struct MorieMenuBarLabel: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow
    @State private var inspectedStartup = false

    var body: some View {
        Label("Morie", systemImage: "waveform")
            .task {
                guard !inspectedStartup else { return }
                inspectedStartup = true
                await controller.setup.refresh()
                guard controller.needsSetup || !controller.setup.isReady else { return }
                MorieApplicationActivation.prepareToOpenWindow()
                openWindow(id: "setup")
                NSApplication.shared.activate()
            }
    }
}

extension Notification.Name {
    static let morieShowSettings = Notification.Name("MorieShowSettings")
}

private struct MorieCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                Task { @MainActor in
                    MorieApplicationActivation.prepareToOpenWindow()
                    openWindow(id: "control-center")
                    NSApplication.shared.activate()
                    await Task.yield()
                    NotificationCenter.default.post(name: .morieShowSettings, object: nil)
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}

@MainActor
private struct MorieMenuContent: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(controller.statusTitle)

        Divider()

        Button("打开 Morie") {
            Task {
                await controller.setup.refresh()
                MorieApplicationActivation.prepareToOpenWindow()
                openWindow(id: controller.needsSetup || !controller.setup.isReady ? "setup" : "control-center")
                NSApplication.shared.activate()
            }
        }
        .disabled(controller.isBootstrapping)

        Divider()

        Text("录音快捷键：\(controller.captureShortcut.displayName)")
        Text("录音中按 Esc 取消")

        Divider()

        Button("退出 Morie") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
private final class ControlCenterSettingsState: ObservableObject {
    @Published private(set) var inputRefinementEnabled: Bool
    @Published private(set) var personalMemoryEnabled: Bool
    @Published private(set) var correctionSuggestionsEnabled: Bool
    @Published private(set) var expressionLearningEnabled: Bool
    @Published private(set) var soundFeedbackEnabled: Bool
    @Published private(set) var iCloudSyncEnabled: Bool
    @Published private(set) var iCloudSyncState: ICloudSyncState
    @Published private(set) var captureShortcut: CaptureShortcut
    @Published private(set) var audioRetentionDays: Int

    private let controller: AppController
    private var cancellables = Set<AnyCancellable>()

    init(controller: AppController) {
        self.controller = controller
        inputRefinementEnabled = controller.inputRefinementEnabled
        personalMemoryEnabled = controller.personalMemoryEnabled
        correctionSuggestionsEnabled = controller.correctionSuggestionsEnabled
        expressionLearningEnabled = controller.expressionLearningEnabled
        soundFeedbackEnabled = controller.soundFeedbackEnabled
        iCloudSyncEnabled = controller.iCloudSyncEnabled
        iCloudSyncState = controller.iCloudSyncState
        captureShortcut = controller.captureShortcut
        audioRetentionDays = controller.audioRetentionDays

        controller.$inputRefinementEnabled
            .sink { [weak self] in self?.inputRefinementEnabled = $0 }
            .store(in: &cancellables)
        controller.$personalMemoryEnabled
            .sink { [weak self] in self?.personalMemoryEnabled = $0 }
            .store(in: &cancellables)
        controller.$correctionSuggestionsEnabled
            .sink { [weak self] in self?.correctionSuggestionsEnabled = $0 }
            .store(in: &cancellables)
        controller.$expressionLearningEnabled
            .sink { [weak self] in self?.expressionLearningEnabled = $0 }
            .store(in: &cancellables)
        controller.$soundFeedbackEnabled
            .sink { [weak self] in self?.soundFeedbackEnabled = $0 }
            .store(in: &cancellables)
        controller.$iCloudSyncEnabled
            .sink { [weak self] in self?.iCloudSyncEnabled = $0 }
            .store(in: &cancellables)
        controller.$iCloudSyncState
            .sink { [weak self] in self?.iCloudSyncState = $0 }
            .store(in: &cancellables)
        controller.$captureShortcut
            .sink { [weak self] in self?.captureShortcut = $0 }
            .store(in: &cancellables)
        controller.$audioRetentionDays
            .sink { [weak self] in self?.audioRetentionDays = $0 }
            .store(in: &cancellables)
    }

    func setInputRefinementEnabled(_ enabled: Bool) {
        controller.setInputRefinementEnabled(enabled)
    }

    func setPersonalMemoryEnabled(_ enabled: Bool) {
        controller.setPersonalMemoryEnabled(enabled)
    }

    func setCorrectionSuggestionsEnabled(_ enabled: Bool) {
        controller.setCorrectionSuggestionsEnabled(enabled)
    }

    func setExpressionLearningEnabled(_ enabled: Bool) {
        controller.setExpressionLearningEnabled(enabled)
    }

    func setSoundFeedbackEnabled(_ enabled: Bool) {
        controller.setSoundFeedbackEnabled(enabled)
    }

    func setICloudSyncEnabled(_ enabled: Bool) {
        controller.setICloudSyncEnabled(enabled)
    }

    func refreshICloudSyncState() {
        controller.refreshICloudSyncState()
    }

    func setCaptureShortcut(_ shortcut: CaptureShortcut) {
        controller.setCaptureShortcut(shortcut)
    }

    func setAudioRetentionDays(_ days: Int) {
        controller.setAudioRetentionDays(days)
    }
}

@MainActor
struct MorieSettingsView: View {
    let controller: AppController
    @StateObject private var settingsState: ControlCenterSettingsState
    @ObservedObject private var refinementModels: RefinementModelController
    @ObservedObject private var refinementPrompts: RefinementPromptController

    @State private var confirmsExpressionReset = false
    @State private var cloudBaseURL: String
    @State private var cloudModelName: String
    @State private var cloudAPIKey: String
    @State private var refinementInstructions: String

    init(controller: AppController) {
        self.controller = controller
        _settingsState = StateObject(
            wrappedValue: ControlCenterSettingsState(controller: controller)
        )
        _refinementModels = ObservedObject(
            wrappedValue: controller.refinementModels
        )
        _refinementPrompts = ObservedObject(
            wrappedValue: controller.refinementPrompts
        )
        _cloudBaseURL = State(
            initialValue: controller.refinementModels.cloudBaseURL
        )
        _cloudModelName = State(
            initialValue: controller.refinementModels.cloudModelName
        )
        _cloudAPIKey = State(initialValue: "")
        _refinementInstructions = State(
            initialValue: controller.refinementPrompts.instructions
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ControlCenterMetrics.sectionSpacing
        ) {
            ControlCenterGroup("输入润色") {
                Toggle(
                    "自动润色语音输入",
                    isOn: Binding(
                        get: { settingsState.inputRefinementEnabled },
                        set: { settingsState.setInputRefinementEnabled($0) }
                    )
                )

                Divider()

                Picker(
                    "润色模型",
                    selection: Binding(
                        get: { refinementModels.mode },
                        set: { refinementModels.setMode($0) }
                    )
                ) {
                    ForEach(RefinementModelMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                Text(refinementModels.mode.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(
                    "保留原意和语气，删除口头语，整理标点、段落和结构明确的列表。关闭 AI 润色后，字典仍然生效。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ControlCenterGroup("个人记忆") {
                Toggle(
                    "使用个人记忆",
                    isOn: Binding(
                        get: { settingsState.personalMemoryEnabled },
                        set: { settingsState.setPersonalMemoryEnabled($0) }
                    )
                )

                Text(
                    "关闭后不再学习新输入，也不会在润色时使用已有个人记忆；已经保存的内容仍会保留。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ControlCenterGroup("润色提示词") {
                TextEditor(text: $refinementInstructions)
                    .frame(minHeight: 180)

                HStack {
                    Button("恢复默认") {
                        refinementPrompts.restoreDefault()
                        refinementInstructions =
                            refinementPrompts.instructions
                    }
                    .disabled(
                        refinementPrompts.isDefault
                            && refinementInstructions
                                == refinementPrompts.instructions
                    )

                    Spacer()

                    Button("保存提示词") {
                        if refinementPrompts.save(
                            refinementInstructions
                        ) {
                            refinementInstructions =
                                refinementPrompts.instructions
                        }
                    }
                }

                if let message = refinementPrompts.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "修改后从下一次开始录音时生效；正在进行的录音继续使用开始时冻结的版本。Apple 本机模型和外部 API 共用这份润色指令。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ControlCenterGroup("外部模型 API") {
                TextField(
                    "Base URL",
                    text: $cloudBaseURL,
                    prompt: Text("https://api.example.com/v1")
                )
                .textFieldStyle(.roundedBorder)

                TextField(
                    "模型",
                    text: $cloudModelName,
                    prompt: Text("model-name")
                )
                .textFieldStyle(.roundedBorder)

                SecureField(
                    "API Key（留空保持现有）",
                    text: $cloudAPIKey,
                    prompt: Text("输入新 Key 才会访问钥匙串")
                )
                .textFieldStyle(.roundedBorder)

                LabeledContent(
                    "状态",
                    value: refinementModels.configurationStatusTitle
                )

                HStack {
                    Spacer()

                    Button("清除 API Key", role: .destructive) {
                        if refinementModels.clearCloudAPIKey() {
                            cloudAPIKey = ""
                        }
                    }

                    Button("保存 API 配置") {
                        if refinementModels.saveCloudConfiguration(
                            baseURL: cloudBaseURL,
                            modelName: cloudModelName,
                            apiKey: cloudAPIKey
                        ) {
                            cloudBaseURL = refinementModels.cloudBaseURL
                            cloudModelName = refinementModels.cloudModelName
                            cloudAPIKey = ""
                        }
                    }
                }

                if let message = refinementModels.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(
                    "兼容 OpenAI Chat Completions 的服务都可以接入。API Key 仅保存于 macOS 钥匙串；无需鉴权的本地服务可以留空。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ControlCenterGroup("字典学习") {
                Toggle(
                    "修改输入后建议加入字典",
                    isOn: Binding(
                        get: { settingsState.correctionSuggestionsEnabled },
                        set: {
                            settingsState.setCorrectionSuggestionsEnabled($0)
                        }
                    )
                )

                Text(
                    "输入完成后的 30 秒内检查当前文本框中的词语修改，并询问是否加入字典。默认关闭。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ControlCenterGroup("表达习惯") {
                Toggle(
                    "学习我的表达习惯",
                    isOn: Binding(
                        get: { settingsState.expressionLearningEnabled },
                        set: { settingsState.setExpressionLearningEnabled($0) }
                    )
                )

                Text(
                    "仅学习标点、分段、列表和中英文空格等表达习惯，不保存修改后的原文。默认关闭。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Button(
                    "清除已学习的表达习惯…",
                    role: .destructive
                ) {
                    confirmsExpressionReset = true
                }
            }

            ControlCenterGroup("iCloud") {
                Toggle(
                    "使用 iCloud 同步与备份",
                    isOn: Binding(
                        get: { settingsState.iCloudSyncEnabled },
                        set: { settingsState.setICloudSyncEnabled($0) }
                    )
                )
                .disabled(settingsState.iCloudSyncState.isChecking)

                Text(
                    "同步历史文字、字典、个人记忆和表达习惯到你的 iCloud 私有数据库。原始录音仍只保存在这台 Mac 上。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                LabeledContent(
                    "状态",
                    value: settingsState.iCloudSyncState.detail
                )

                if settingsState.iCloudSyncEnabled {
                    Button("重新检查 iCloud") {
                        settingsState.refreshICloudSyncState()
                    }
                    .disabled(settingsState.iCloudSyncState.isChecking)
                }
            }

            ControlCenterGroup("输入反馈") {
                Toggle(
                    "录音开始和结束提示音",
                    isOn: Binding(
                        get: { settingsState.soundFeedbackEnabled },
                        set: { settingsState.setSoundFeedbackEnabled($0) }
                    )
                )

                Text(
                    "开始录音和正常结束录音时播放轻提示音。取消录音不会播放结束提示音。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ControlCenterGroup("快捷键") {
                Picker(
                    "开始或结束录音",
                    selection: Binding(
                        get: { settingsState.captureShortcut },
                        set: { settingsState.setCaptureShortcut($0) }
                    )
                ) {
                    ForEach(CaptureShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }

                LabeledContent("打开设置", value: "⌘,")

                Text(
                    "单独按下并松开 Fn / 地球仪键可切换录音状态。录音中按 Esc 取消。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ControlCenterGroup("原始录音") {
                Stepper(
                    "录音保留 \(settingsState.audioRetentionDays) 天",
                    value: Binding(
                        get: { settingsState.audioRetentionDays },
                        set: { settingsState.setAudioRetentionDays($0) }
                    ),
                    in: 1...365
                )

                Text(
                    "录音保存在这台 Mac 上，可用于重新识别。到期仅删除录音，保留文字和历史记录。"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("设置")
        .confirmationDialog(
            "清除已学习的表达习惯？",
            isPresented: $confirmsExpressionReset,
            titleVisibility: .visible
        ) {
            Button("清除", role: .destructive) {
                controller.clearExpressionProfile()
            }
        } message: {
            Text(
                "只会清除表达习惯统计，不会删除历史记录、字典或个人记忆。"
            )
        }
    }
}
