import AppKit
import SwiftUI

private enum ControlCenterWindowIdentity: String, Codable, Hashable {
    case main
}

@main
struct MorieApp: App {
    private let controller: AppController
    private let captureStore: CaptureStore?

    init() {
        let wantsICloud = ICloudSyncSettings.isEnabled
        do {
            let store = try CaptureStore(cloudSyncEnabled: wantsICloud)
            captureStore = store
            controller = AppController(captureStore: store)
        } catch where wantsICloud {
            // Optional iCloud must never make local input unusable. If the
            // CloudKit-backed SwiftData configuration cannot open, retry the
            // same current schema locally and surface the cloud failure.
            do {
                let store = try CaptureStore(cloudSyncEnabled: false)
                captureStore = store
                controller = AppController(
                    captureStore: store,
                    cloudSyncStartupError: error
                )
            } catch {
                captureStore = nil
                controller = AppController(
                    captureStore: nil,
                    persistenceError: error
                )
            }
        } catch {
            captureStore = nil
            controller = AppController(
                captureStore: nil,
                persistenceError: error
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

        WindowGroup(
            "Morie",
            id: "control-center",
            for: ControlCenterWindowIdentity.self
        ) { _ in
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
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .newItem) { }
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
    let controller: AppController
    @ObservedObject private var capabilities: AppCapabilityController
    @ObservedObject private var setup: PermissionSetupController
    @Environment(\.openWindow) private var openWindow
    @State private var inspectedStartup = false

    init(controller: AppController) {
        self.controller = controller
        _capabilities = ObservedObject(
            wrappedValue: controller.capabilities
        )
        _setup = ObservedObject(wrappedValue: controller.setup)
    }

    var body: some View {
        Label("Morie", systemImage: "waveform")
            .task {
                guard !inspectedStartup else { return }
                inspectedStartup = true
                await setup.refresh()
                guard capabilities.needsSetup || !setup.isReady else { return }
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
                    openWindow(
                        id: "control-center",
                        value: ControlCenterWindowIdentity.main
                    )
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
    let controller: AppController
    @ObservedObject private var runtime: AppRuntimeController
    @ObservedObject private var capabilities: AppCapabilityController
    @ObservedObject private var preferences: AppPreferencesController
    @ObservedObject private var setup: PermissionSetupController
    @Environment(\.openWindow) private var openWindow

    init(controller: AppController) {
        self.controller = controller
        _runtime = ObservedObject(wrappedValue: controller.runtime)
        _capabilities = ObservedObject(
            wrappedValue: controller.capabilities
        )
        _preferences = ObservedObject(wrappedValue: controller.preferences)
        _setup = ObservedObject(wrappedValue: controller.setup)
    }

    var body: some View {
        Text(controller.statusTitle)

        Divider()

        Button("打开 Morie") {
            Task {
                await setup.refresh()
                MorieApplicationActivation.prepareToOpenWindow()
                if capabilities.needsSetup || !setup.isReady {
                    openWindow(id: "setup")
                } else {
                    openWindow(
                        id: "control-center",
                        value: ControlCenterWindowIdentity.main
                    )
                }
                NSApplication.shared.activate()
            }
        }
        .disabled(capabilities.isBootstrapping)

        Divider()

        Text("录音快捷键：\(preferences.captureShortcut.displayName)")
        Text("录音中按 Esc 取消")

        Divider()

        Button("退出 Morie") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}

@MainActor
struct MorieSettingsView: View {
    let controller: AppController
    @ObservedObject private var preferences: AppPreferencesController
    @ObservedObject private var refinementModels: RefinementModelController
    @ObservedObject private var refinementPrompts: RefinementPromptController

    @State private var confirmsExpressionReset = false
    @State private var confirmsFactoryReset = false
    @State private var factoryResetInProgress = false
    @State private var factoryResetError: String?
    @State private var cloudBaseURL: String
    @State private var cloudModelName: String
    @State private var cloudAPIKey: String
    @State private var refinementInstructions: String

    init(controller: AppController) {
        self.controller = controller
        _preferences = ObservedObject(
            wrappedValue: controller.preferences
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
        ControlCenterPage {
            ControlCenterSectionBlock(
                "输入与润色",
                subtitle: "控制 Morie 如何整理语音输入，以及当前使用的润色后端。"
            ) {
                Toggle(
                    "自动润色语音输入",
                    isOn: Binding(
                        get: { preferences.inputRefinementEnabled },
                        set: { controller.setInputRefinementEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

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
                .pickerStyle(.menu)

                LabeledContent(
                    "当前状态",
                    value: refinementModels.modelStatusTitle(
                        inputRefinementEnabled:
                            preferences.inputRefinementEnabled
                    )
                )
            } footer: {
                Text(refinementModels.mode.detail)
            }

            Divider()

            ControlCenterSectionBlock(
                "个人化",
                subtitle: "决定 Morie 是否使用你的记忆、修正和表达习惯来改进后续输入。"
            ) {
                Toggle(
                    "使用个人记忆",
                    isOn: Binding(
                        get: { preferences.personalMemoryEnabled },
                        set: { controller.setPersonalMemoryEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    "修改输入后建议加入字典",
                    isOn: Binding(
                        get: { preferences.correctionSuggestionsEnabled },
                        set: {
                            controller.setCorrectionSuggestionsEnabled($0)
                        }
                    )
                )
                .toggleStyle(.switch)

                Toggle(
                    "学习我的表达习惯",
                    isOn: Binding(
                        get: { preferences.expressionLearningEnabled },
                        set: {
                            controller.setExpressionLearningEnabled($0)
                        }
                    )
                )
                .toggleStyle(.switch)

                Button(
                    "清除已学习的表达习惯…",
                    role: .destructive
                ) {
                    confirmsExpressionReset = true
                }
                .disabled(!preferences.expressionLearningEnabled)
            } footer: {
                Text(
                    "关闭个人记忆或学习只会停止后续使用与学习，不会自动删除已经保存的数据。"
                )
            }

            Divider()

            ControlCenterSectionBlock(
                "润色提示词",
                subtitle: "修改会从下一次录音开始生效；正在进行的录音继续使用开始时冻结的版本。"
            ) {
                TextEditor(text: $refinementInstructions)
                    .font(.body.monospaced())
                    .frame(minHeight: 180, idealHeight: 220)

                HStack(spacing: 10) {
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
                    .keyboardShortcut(.defaultAction)
                }

                if let message = refinementPrompts.settingsMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ControlCenterSectionBlock(
                "外部模型 API",
                subtitle: "Cloud 模式使用 OpenAI Chat Completions 兼容接口。API Key 仅保存在 macOS 钥匙串。"
            ) {
                LabeledContent("Base URL") {
                    TextField(
                        "Base URL",
                        text: $cloudBaseURL,
                        prompt: Text("https://api.example.com/v1")
                    )
                    .frame(maxWidth: 420)
                }

                LabeledContent("模型") {
                    TextField(
                        "模型",
                        text: $cloudModelName,
                        prompt: Text("model-name")
                    )
                    .frame(maxWidth: 420)
                }

                LabeledContent("API Key") {
                    SecureField(
                        "留空保持现有",
                        text: $cloudAPIKey
                    )
                    .frame(maxWidth: 420)
                }

                LabeledContent(
                    "配置状态",
                    value: refinementModels.configurationStatusTitle
                )

                HStack(spacing: 10) {
                    Button(
                        "清除 API Key",
                        role: .destructive
                    ) {
                        if refinementModels.clearCloudAPIKey() {
                            cloudAPIKey = ""
                        }
                    }

                    Spacer()

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
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            ControlCenterSectionBlock(
                "同步与存储",
                subtitle: "历史文字、字典、个人记忆和表达习惯可通过 iCloud 同步；原始录音只保存在当前 Mac。"
            ) {
                Toggle(
                    "使用 iCloud 同步与备份",
                    isOn: Binding(
                        get: { preferences.iCloudSyncEnabled },
                        set: { controller.setICloudSyncEnabled($0) }
                    )
                )
                .toggleStyle(.switch)
                .disabled(preferences.iCloudSyncState.isChecking)

                LabeledContent(
                    "iCloud 状态",
                    value: preferences.iCloudSyncState.detail
                )

                if preferences.iCloudSyncEnabled {
                    Button("重新检查 iCloud") {
                        controller.refreshICloudSyncState()
                    }
                    .disabled(preferences.iCloudSyncState.isChecking)
                }

                Stepper(
                    "原始录音保留 \(preferences.audioRetentionDays) 天",
                    value: Binding(
                        get: { preferences.audioRetentionDays },
                        set: { controller.setAudioRetentionDays($0) }
                    ),
                    in: 1...365
                )
            }

            Divider()

            ControlCenterSectionBlock(
                "快捷键与反馈",
                subtitle: "保持高频录音操作直接、可预测，不添加额外确认步骤。"
            ) {
                Toggle(
                    "录音开始和结束提示音",
                    isOn: Binding(
                        get: { preferences.soundFeedbackEnabled },
                        set: { controller.setSoundFeedbackEnabled($0) }
                    )
                )
                .toggleStyle(.switch)

                Picker(
                    "开始或结束录音",
                    selection: Binding(
                        get: { preferences.captureShortcut },
                        set: { controller.setCaptureShortcut($0) }
                    )
                ) {
                    ForEach(CaptureShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }
                .pickerStyle(.menu)

                LabeledContent("打开设置", value: "⌘,")
                LabeledContent("取消录音", value: "Esc")
            } footer: {
                Text(
                    "单独按下并松开 Fn / 地球仪键可切换录音状态；与其他按键组合时不会触发 Morie。"
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(
                    "恢复出厂设置…",
                    systemImage: "arrow.counterclockwise",
                    role: .destructive
                ) {
                    confirmsFactoryReset = true
                }
                .disabled(
                    factoryResetInProgress
                        || controller.isCaptureActive
                )
            }
        }
        .confirmationDialog(
            "恢复出厂设置？",
            isPresented: $confirmsFactoryReset,
            titleVisibility: .visible
        ) {
            Button("恢复出厂设置", role: .destructive) {
                factoryResetInProgress = true
                Task {
                    do {
                        try await controller.factoryReset()
                    } catch {
                        factoryResetInProgress = false
                        factoryResetError = error.localizedDescription
                    }
                }
            }

            Button("取消", role: .cancel) {}
        } message: {
            Text(
                "将永久删除历史记录、原始录音、字典、个人记忆、学习数据、诊断日志和外部 API 配置，并把所有 Morie 设置恢复默认。Morie 随后会退出。macOS 已授予的系统权限不会被撤销。"
            )
        }
        .alert(
            "恢复出厂设置失败",
            isPresented: Binding(
                get: { factoryResetError != nil },
                set: {
                    if !$0 {
                        factoryResetError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                factoryResetError = nil
            }
        } message: {
            Text(factoryResetError ?? "")
        }
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
