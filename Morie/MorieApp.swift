import AppKit
import SwiftUI

@main
struct MorieApp: App {
    @StateObject private var controller: AppController
    @Environment(\.openWindow) private var openWindow
    private let captureStore: CaptureStore?

    init() {
        do {
            let store = try CaptureStore()
            captureStore = store
            _controller = StateObject(wrappedValue: AppController(captureStore: store))
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
        .frame(maxWidth: 700)
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("设置")
    }
}
