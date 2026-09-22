import AppKit
import SwiftUI

@main
struct MorieApp: App {
    @NSApplicationDelegateAdaptor(MorieAppDelegate.self)
    private var appDelegate

    private let controller = AppController()

    var body: some Scene {
        Window("Morie", id: "control-center") {
            MorieControlCenter(controller: controller)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
        }
        .defaultSize(width: 1120, height: 720)
        .windowToolbarStyle(.unified)
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
final class MorieAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(
        _ sender: NSApplication
    ) -> Bool {
        true
    }
}

extension Notification.Name {
    static let morieShowSettings =
        Notification.Name("MorieShowSettings")
}

private struct MorieCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("设置…") {
                openWindow(id: "control-center")
                NSApplication.shared.activate()
                Task { @MainActor in
                    await Task.yield()
                    NotificationCenter.default.post(
                        name: .morieShowSettings,
                        object: nil
                    )
                }
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}


