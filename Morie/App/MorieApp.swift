import AppKit
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
struct MorieSettingsView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var refinementModels: RefinementModelController
    @ObservedObject private var refinementPrompts: RefinementPromptController
    @State private var confirmsExpressionReset = false
    @State private var cloudBaseURL: String
    @State private var cloudModelName: String
    @State private var cloudAPIKey: String
    @State private var refinementInstructions: String

    init(controller: AppController) {
        self.controller = controller
        _refinementModels = ObservedObject(wrappedValue: controller.refinementModels)
        _refinementPrompts = ObservedObject(wrappedValue: controller.refinementPrompts)
        _cloudBaseURL = State(initialValue: controller.refinementModels.cloudBaseURL)
        _cloudModelName = State(initialValue: controller.refinementModels.cloudModelName)
        _cloudAPIKey = State(initialValue: "")
        _refinementInstructions = State(initialValue: controller.refinementPrompts.instructions)
    }

    var body: some View {
        ControlCenterContentPage {
            ControlCenterSectionGroup("输入润色") {
                Toggle(
                    "自动润色语音输入",
                    isOn: Binding(
                        get: { controller.inputRefinementEnabled },
                        set: { controller.setInputRefinementEnabled($0) }
                    )
                )

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

                Text("保留原意和语气，删除口头语，整理标点、段落和结构明确的列表。关闭 AI 润色后，字典仍然生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlCenterSectionGroup("个人记忆") {
                Toggle(
                    "使用个人记忆",
                    isOn: Binding(
                        get: { controller.personalMemoryEnabled },
                        set: { controller.setPersonalMemoryEnabled($0) }
                    )
                )

                Text("Morie 会在空闲时从完成的日常输入中维护少量有用上下文，并自动区分稳定信息和暂时的工作上下文。关闭后不再学习新输入，也不会在润色时使用已有个人记忆；已经保存的内容仍会保留。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlCenterSectionGroup("润色提示词") {
                TextEditor(text: $refinementInstructions)
                    .frame(minHeight: 180)

                HStack {
                    Button("恢复默认") {
                        refinementPrompts.restoreDefault()
                        refinementInstructions = refinementPrompts.instructions
                    }
                    .disabled(
                        refinementPrompts.isDefault
                            && refinementInstructions == refinementPrompts.instructions
                    )

                    Spacer()

                    Button("保存提示词") {
                        if refinementPrompts.save(refinementInstructions) {
                            refinementInstructions = refinementPrompts.instructions
                        }
                    }
                }

                if let message = refinementPrompts.settingsMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("修改后从下一次开始录音时生效；正在进行的录音继续使用开始时冻结的版本。Apple 本机模型和外部 API 共用这份润色指令。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlCenterSectionGroup("外部模型 API") {
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

                HStack {
                    LabeledContent(
                        "状态",
                        value: refinementModels.configurationStatusTitle
                    )
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

                Text("兼容 OpenAI Chat Completions 的服务都可以接入。Base URL 填到服务根路径或 /v1 即可，不要包含 /chat/completions。API Key 仅保存于 macOS 钥匙串；无需鉴权的本地服务可以留空。Morie 启动时不会读取 Key；此处留空保存会保持现有 Key 不变。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("选择“外部 API”或“自动”后，润色所需的识别文字、相关字典候选和少量个人上下文会发送到你配置的服务。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlCenterSectionGroup("字典学习") {
                Toggle(
                    "修改输入后建议加入字典",
                    isOn: Binding(
                        get: { controller.correctionSuggestionsEnabled },
                        set: { controller.setCorrectionSuggestionsEnabled($0) }
                    )
                )

                Text("输入完成后的 30 秒内，检查当前文本框中的词语修改，并询问是否加入字典。离开文本框或开始下一次输入即停止检查。默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlCenterSectionGroup("表达习惯") {
                Toggle(
                    "学习我的表达习惯",
                    isOn: Binding(
                        get: { controller.expressionLearningEnabled },
                        set: { controller.setExpressionLearningEnabled($0) }
                    )
                )

                Text("只观察 Morie 刚输入的文字是否被你修改；仅学习标点、分段、列表和中英文空格等表达习惯，不保存修改后的原文。默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("清除已学习的表达习惯…", role: .destructive) {
                    confirmsExpressionReset = true
                }
            }

            ControlCenterSectionGroup("iCloud") {
                Toggle(
                    "使用 iCloud 同步与备份",
                    isOn: Binding(
                        get: { controller.iCloudSyncEnabled },
                        set: { controller.setICloudSyncEnabled($0) }
                    )
                )
                .disabled(controller.iCloudSyncState.isChecking)

                Text("同步历史文字、字典、个人记忆和表达习惯到你的 iCloud 私有数据库。原始录音仍只保存在这台 Mac 上。默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent(
                    "状态",
                    value: controller.iCloudSyncState.detail
                )

                if controller.iCloudSyncEnabled {
                    Button("重新检查 iCloud") {
                        controller.refreshICloudSyncState()
                    }
                    .disabled(controller.iCloudSyncState.isChecking)
                }
            }

            ControlCenterSectionGroup("输入反馈") {
                Toggle(
                    "录音开始和结束提示音",
                    isOn: Binding(
                        get: { controller.soundFeedbackEnabled },
                        set: { controller.setSoundFeedbackEnabled($0) }
                    )
                )

                Text("开始录音和正常结束录音时播放轻提示音，帮助确认 Morie 已进入或结束录音状态。取消录音不会播放结束提示音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ControlCenterSectionGroup("快捷键") {
                Picker(
                    "开始或结束录音",
                    selection: Binding(
                        get: { controller.captureShortcut },
                        set: { controller.setCaptureShortcut($0) }
                    )
                ) {
                    ForEach(CaptureShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }

                Text("单独按下并松开 Fn / 地球仪键可切换录音状态。Fn 与其他按键组合使用时不会触发 Morie。录音中按 Esc 取消。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("打开设置", value: "⌘,")
            }

            ControlCenterSectionGroup("原始录音") {
                Stepper(
                    "录音保留 \(controller.audioRetentionDays) 天",
                    value: Binding(
                        get: { controller.audioRetentionDays },
                        set: { controller.setAudioRetentionDays($0) }
                    ),
                    in: 1...365
                )

                Text("录音保存在这台 Mac 上，可用于重新识别。到期仅删除录音，保留文字和历史记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
            Text("只会清除表达习惯统计，不会删除历史记录、字典或个人记忆。")
        }
        .navigationTitle("设置")
    }
}
