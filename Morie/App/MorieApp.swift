import AppKit
import SwiftUI

@main
struct MorieApp: App {
    private let processRole: MorieProcessRole
    private let runtimeController: AppController?
    private let controlCenterController: ControlCenterController?
    private let captureStore: CaptureStore?

    init() {
        let role = MorieProcessRole.current
        processRole = role

        let wantsICloud = ICloudSyncSettings.isEnabled
        var resolvedStore: CaptureStore?
        var persistenceError: Error?
        var cloudSyncStartupError: Error?

        do {
            resolvedStore = try CaptureStore(
                cloudSyncEnabled: wantsICloud,
                performsLaunchMaintenance: role == .runtime
            )
        } catch where wantsICloud {
            cloudSyncStartupError = error
            do {
                resolvedStore = try CaptureStore(
                    cloudSyncEnabled: false,
                    performsLaunchMaintenance: role == .runtime
                )
            } catch {
                persistenceError = error
            }
        } catch {
            persistenceError = error
        }

        captureStore = resolvedStore

        if role == .runtime {
            runtimeController = AppController(
                captureStore: resolvedStore,
                persistenceError: persistenceError,
                cloudSyncStartupError: cloudSyncStartupError,
                processRole: .runtime
            )
            controlCenterController = nil
        } else {
            runtimeController = nil
            controlCenterController = ControlCenterController(
                captureStore: resolvedStore,
                persistenceError: persistenceError,
                cloudSyncStartupError: cloudSyncStartupError
            )
        }
    }

    var body: some Scene {
        MenuBarExtra(
            isInserted: .constant(processRole == .runtime)
        ) {
            if let runtimeController {
                MorieMenuContent(controller: runtimeController)
            }
        } label: {
            if let runtimeController {
                MorieMenuBarLabel(controller: runtimeController)
            }
        }
        .menuBarExtraStyle(.menu)

        Window("Morie", id: "control-center") {
            Group {
                if processRole == .controlCenter {
                    if let captureStore, let controlCenterController {
                        MorieControlCenter(
                            controller: controlCenterController
                        )
                        .modelContainer(captureStore.container)
                    } else {
                        ContentUnavailableView(
                            "Morie 暂不可用",
                            systemImage: "exclamationmark.triangle",
                            description: Text(
                                "无法打开记录存储，请重新启动 Morie 后重试。"
                            )
                        )
                    }
                } else {
                    EmptyView()
                }
            }
            .environment(
                \.locale,
                Locale(identifier: "zh-Hans")
            )
            .onAppear {
                guard processRole == .controlCenter else {
                    return
                }

                MorieApplicationActivation.windowDidAppear(
                    "control-center"
                )
                Diagnostics.record(
                    "ControlCenterProcess",
                    "Window appeared; pid=\(ProcessInfo.processInfo.processIdentifier)"
                )

                guard ControlCenterLaunchRoute.current
                    == .settings else {
                    return
                }
                Task { @MainActor in
                    await Task.yield()
                    NotificationCenter.default.post(
                        name: .morieShowSettings,
                        object: nil
                    )
                }
            }
            .onDisappear {
                guard processRole == .controlCenter else {
                    return
                }

                Diagnostics.record(
                    "ControlCenterProcess",
                    "Window closed; terminating presentation process"
                )
                ControlCenterProcessBridge.notifyWillTerminate()
                MorieApplicationActivation.windowDidDisappear(
                    "control-center"
                )
                NSApplication.shared.terminate(nil)
            }
        }
        .defaultSize(width: 1120, height: 720)
        .defaultLaunchBehavior(
            processRole == .controlCenter
                ? .presented
                : .suppressed
        )
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) { }
            SidebarCommands()
            MorieCommands(processRole: processRole)
        }

        Window("欢迎使用 Morie", id: "setup") {
            Group {
                if processRole == .runtime,
                   let runtimeController {
                    MorieSetupView(controller: runtimeController)
                } else {
                    EmptyView()
                }
            }
            .environment(
                \.locale,
                Locale(identifier: "zh-Hans")
            )
            .onAppear {
                guard processRole == .runtime else {
                    return
                }
                MorieApplicationActivation.windowDidAppear(
                    "setup"
                )
            }
            .onDisappear {
                guard processRole == .runtime else {
                    return
                }
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
    let processRole: MorieProcessRole

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                if processRole == .controlCenter {
                    NotificationCenter.default.post(
                        name: .morieShowSettings,
                        object: nil
                    )
                } else {
                    ControlCenterProcessLauncher.open(.settings)
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
