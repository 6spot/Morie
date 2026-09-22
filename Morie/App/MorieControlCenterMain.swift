import SwiftUI

@main
struct MorieControlCenterApp: App {
    private let controller: ControlCenterController
    private let captureStore: CaptureStore?

    init() {
        let wantsICloud = ICloudSyncSettings.isEnabled
        var resolvedStore: CaptureStore?
        var persistenceError: Error?
        var cloudSyncStartupError: Error?

        do {
            resolvedStore = try CaptureStore(
                cloudSyncEnabled: wantsICloud,
                performsLaunchMaintenance: false
            )
        } catch where wantsICloud {
            cloudSyncStartupError = error
            do {
                resolvedStore = try CaptureStore(
                    cloudSyncEnabled: false,
                    performsLaunchMaintenance: false
                )
            } catch {
                persistenceError = error
            }
        } catch {
            persistenceError = error
        }

        captureStore = resolvedStore
        controller = ControlCenterController(
            captureStore: resolvedStore,
            persistenceError: persistenceError,
            cloudSyncStartupError: cloudSyncStartupError
        )
    }

    var body: some Scene {
        Window("Morie", id: "control-center") {
            Group {
                if let captureStore {
                    MorieControlCenter(controller: controller)
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
            }
            .environment(
                \.locale,
                Locale(identifier: "zh-Hans")
            )
            .onAppear {
                Diagnostics.record(
                    "ControlCenterProcess",
                    "Helper window appeared; pid=\(ProcessInfo.processInfo.processIdentifier)"
                )
                Diagnostics.recordMemory(
                    "control-center-helper-window-ready"
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
                Diagnostics.record(
                    "ControlCenterProcess",
                    "Helper window closed; terminating presentation process"
                )
                ControlCenterProcessBridge.notifyWillTerminate()
                NSApplication.shared.terminate(nil)
            }
        }
        .defaultSize(width: 1120, height: 720)
        .windowResizability(.contentMinSize)
        .restorationBehavior(.disabled)
        .commands {
            CommandGroup(replacing: .newItem) { }
            SidebarCommands()
            ControlCenterHelperCommands()
        }
    }
}

@MainActor
private struct ControlCenterHelperCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                NotificationCenter.default.post(
                    name: .morieShowSettings,
                    object: nil
                )
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
