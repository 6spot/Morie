import AppKit
import SwiftUI

@main
struct MorieApp: App {
    @StateObject private var controller = AppController()

    var body: some Scene {
        MenuBarExtra("Morie", systemImage: controller.statusSymbol) {
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

                Text("Hold ⌃Space to talk")
                    .font(.caption)

                if !controller.transcript.isEmpty {
                    Text(controller.transcript)
                        .font(.callout)
                        .lineLimit(4)
                }

                Divider()

                Button("Recheck Capabilities") {
                    Task { await controller.bootstrap() }
                }

                Button("Quit Morie") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(14)
            .frame(width: 320)
        }
        .menuBarExtraStyle(.window)
    }
}
