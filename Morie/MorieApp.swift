import AppKit
import SwiftUI

@main
struct MorieApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Morie", systemImage: controller.statusSymbol) {
            MorieMenuContent(controller: controller)
        }
        .menuBarExtraStyle(.window)

        Window("Morie Debug", id: "debug") {
            DiagnosticLogView()
        }
        .defaultSize(width: 820, height: 520)
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

            Text("Press ⌃Space to start / finish")
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

            Button("Recheck Capabilities", systemImage: "arrow.clockwise") {
                Task { await controller.bootstrap() }
            }

            Button("Quit Morie", systemImage: "power") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}
