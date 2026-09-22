import AppKit
import SwiftUI

@main
enum MorieControlCenterMain {
    @MainActor
    private static var applicationDelegate:
        MorieControlCenterApplicationDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MorieControlCenterApplicationDelegate()
        applicationDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}

@MainActor
private final class MorieControlCenterApplicationDelegate:
    NSObject,
    NSApplicationDelegate,
    NSWindowDelegate
{
    private let controller: ControlCenterController
    private let captureStore: CaptureStore?
    private var window: NSWindow?

    override init() {
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

        super.init()
    }

    func applicationDidFinishLaunching(
        _ notification: Notification
    ) {
        let content: AnyView
        if let captureStore {
            content = AnyView(
                MorieControlCenter(controller: controller)
                    .modelContainer(captureStore.container)
                    .environment(
                        \.locale,
                        Locale(identifier: "zh-Hans")
                    )
            )
        } else {
            content = AnyView(
                ContentUnavailableView(
                    "Morie 暂不可用",
                    systemImage: "exclamationmark.triangle",
                    description: Text(
                        "无法打开记录存储，请重新启动 Morie 后重试。"
                    )
                )
                .environment(
                    \.locale,
                    Locale(identifier: "zh-Hans")
                )
            )
        }

        let hostingController =
            NSHostingController(rootView: content)
        let window = NSWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: 1120,
                height: 720
            ),
            styleMask: [
                .titled,
                .closable,
                .miniaturizable,
                .resizable,
            ],
            backing: .buffered,
            defer: false
        )
        window.title = "Morie"
        window.minSize = NSSize(
            width: 960,
            height: 600
        )
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window

        installMainMenu()

        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()

        Diagnostics.record(
            "ControlCenterProcess",
            "Helper window appeared; pid=\(ProcessInfo.processInfo.processIdentifier)"
        )
        Diagnostics.recordMemory(
            "control-center-helper-window-ready"
        )

        if ControlCenterLaunchRoute.current == .settings {
            Task { @MainActor in
                await Task.yield()
                NotificationCenter.default.post(
                    name: .morieShowSettings,
                    object: nil
                )
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        Diagnostics.record(
            "ControlCenterProcess",
            "Helper window closed; terminating presentation process"
        )
        ControlCenterProcessBridge.notifyWillTerminate()
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }

    @objc
    private func showSettings() {
        NotificationCenter.default.post(
            name: .morieShowSettings,
            object: nil
        )
        window?.makeKeyAndOrderFront(nil)
    }

    private func installMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appItem.submenu = appMenu

        appMenu.addItem(
            withTitle: "设置…",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        appMenu.addItem(.separator())

        let closeItem = NSMenuItem(
            title: "关闭 Morie",
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        )
        closeItem.target = window
        appMenu.addItem(closeItem)

        mainMenu.addItem(appItem)
        NSApplication.shared.mainMenu = mainMenu
    }
}
