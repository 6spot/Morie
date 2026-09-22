import AppKit
import SwiftUI

@main
struct MorieApp: App {
    private let controller: AppController

    init() {
        let wantsICloud = ICloudSyncSettings.isEnabled

        do {
            let store = try CaptureStore(
                cloudSyncEnabled: wantsICloud
            )
            controller = AppController(
                captureStore: store
            )
        } catch where wantsICloud {
            do {
                let store = try CaptureStore(
                    cloudSyncEnabled: false
                )
                controller = AppController(
                    captureStore: store,
                    cloudSyncStartupError: error
                )
            } catch {
                controller = AppController(
                    captureStore: nil,
                    persistenceError: error
                )
            }
        } catch {
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
        .commands {
            MorieCommands()
        }

        Window("欢迎使用 Morie", id: "setup") {
            MorieSetupView(controller: controller)
                .environment(
                    \.locale,
                    Locale(identifier: "zh-Hans")
                )
                .onAppear {
                    MorieApplicationActivation.windowDidAppear(
                        "setup"
                    )
                }
                .onDisappear {
                    MorieApplicationActivation.windowDidDisappear(
                        "setup"
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 700, height: 740)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
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

@MainActor
private struct MorieCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                ControlCenterProcessLauncher.open(.settings)
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
                if capabilities.needsSetup || !setup.isReady {
                    MorieApplicationActivation.prepareToOpenWindow()
                    openWindow(id: "setup")
                    NSApplication.shared.activate()
                } else {
                    ControlCenterProcessLauncher.open(.overview)
                }
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
