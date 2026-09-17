import AppKit
import SwiftUI

@main
struct MorieApp: App {
    @StateObject private var controller: AppController
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
        MenuBarExtra("Morie", systemImage: "waveform") {
            MorieMenuContent(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Window("Morie Debug", id: "debug") {
            DiagnosticLogView()
        }
        .defaultSize(width: 820, height: 520)

        Window("Morie History", id: "history") {
            if let captureStore {
                CaptureHistoryView()
                    .modelContainer(captureStore.container)
            } else {
                ContentUnavailableView(
                    "History Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Morie could not open Capture storage.")
                )
            }
        }
        .defaultSize(width: 680, height: 480)

        Settings {
            MorieSettingsView(controller: controller)
        }
    }
}

@MainActor
private struct MorieMenuContent: View {
    @ObservedObject var controller: AppController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(controller.statusTitle)
                .font(.headline)

            if let detail = controller.statusDetail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Text("Press \(controller.captureShortcut.displayName) to start / finish")
                .font(.caption)

            Text("Esc cancels while recording")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !controller.transcript.isEmpty {
                Text(controller.transcript)
                    .font(.callout)
                    .lineLimit(4)
            }

            Divider()

            Button("Open Debug Log", systemImage: "ladybug") {
                openWindow(id: "debug")
                NSApplication.shared.activate(ignoringOtherApps: true)
            }

            Button("History", systemImage: "clock.arrow.circlepath") {
                openWindow(id: "history")
                NSApplication.shared.activate()
            }

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
            }

            Button("Recheck Capabilities", systemImage: "arrow.clockwise") {
                Task { await controller.bootstrap() }
            }

            if controller.recoverySettingsURL != nil {
                Button("Open System Settings", systemImage: "gearshape.arrow.triangle.2.circlepath") {
                    controller.openRecoverySettings()
                }
            }

            Button("Quit Morie", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

@MainActor
private struct MorieSettingsView: View {
    @ObservedObject var controller: AppController

    var body: some View {
        Form {
            Section("Capture Shortcut") {
                Picker(
                    "Shortcut",
                    selection: Binding(
                        get: { controller.captureShortcut },
                        set: { controller.setCaptureShortcut($0) }
                    )
                ) {
                    ForEach(CaptureShortcut.allCases) { shortcut in
                        Text(shortcut.displayName).tag(shortcut)
                    }
                }

                Text("Fn / Globe toggles capture only after a solo press is released. Fn combined with another key passes through without triggering Morie.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 460)
    }
}
