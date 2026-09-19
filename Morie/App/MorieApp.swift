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
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            SidebarCommands()
            MorieCommands()
        }

        Window("欢迎使用 Morie", id: "setup") {
            MorieSetupView(controller: controller)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 740)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)

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
                openWindow(id: "setup")
                NSApplication.shared.activate(ignoringOtherApps: true)
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
                    openWindow(id: "control-center")
                    NSApplication.shared.activate(ignoringOtherApps: true)
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
                openWindow(id: controller.needsSetup || !controller.setup.isReady ? "setup" : "control-center")
                NSApplication.shared.activate(ignoringOtherApps: true)
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
    @State private var confirmsExpressionReset = false

    var body: some View {
        Form {
            Section("输入润色") {
                Toggle("自动润色语音输入", isOn: Binding(
                    get: { controller.inputRefinementEnabled },
                    set: { controller.setInputRefinementEnabled($0) }
                ))
                Text("保留原意和语气，删除口头语，整理标点、段落和结构明确的列表。关闭 AI 润色后，字典仍然生效。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("字典学习") {
                Toggle("修改输入后建议加入字典", isOn: Binding(
                    get: { controller.correctionSuggestionsEnabled },
                    set: { controller.setCorrectionSuggestionsEnabled($0) }
                ))
                Text("输入完成后的 30 秒内，检查当前文本框中的词语修改，并询问是否加入字典。离开文本框或开始下一次输入即停止检查。默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("表达习惯") {
                Toggle("学习我的表达习惯", isOn: Binding(
                    get: { controller.expressionLearningEnabled },
                    set: { controller.setExpressionLearningEnabled($0) }
                ))
                Text("只观察 Morie 刚输入的文字是否被你修改；仅学习标点、分段、列表和中英文空格等表达习惯，不保存修改后的原文。默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("清除已学习的表达习惯…", role: .destructive) {
                    confirmsExpressionReset = true
                }
            }

            Section("iCloud") {
                Toggle("使用 iCloud 同步与备份", isOn: Binding(
                    get: { controller.iCloudSyncEnabled },
                    set: { controller.setICloudSyncEnabled($0) }
                ))
                .disabled(controller.iCloudSyncState.isChecking)

                Text("同步历史文字、字典、个人记忆和表达习惯到你的 iCloud 私有数据库。原始录音仍只保存在这台 Mac 上。默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("状态", value: controller.iCloudSyncState.detail)

                if controller.iCloudSyncEnabled {
                    Button("重新检查 iCloud") {
                        controller.refreshICloudSyncState()
                    }
                    .disabled(controller.iCloudSyncState.isChecking)
                }
            }

            Section("输入反馈") {
                Toggle("录音开始和结束提示音", isOn: Binding(
                    get: { controller.soundFeedbackEnabled },
                    set: { controller.setSoundFeedbackEnabled($0) }
                ))
                Text("开始录音和正常结束录音时播放轻提示音，帮助确认 Morie 已进入或结束录音状态。取消录音不会播放结束提示音。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("快捷键") {
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

            Section("原始录音") {
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
        .formStyle(.grouped)
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
        .frame(maxWidth: 700)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("设置")
    }
}
