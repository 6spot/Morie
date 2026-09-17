import AppKit
import SwiftUI

struct MenuBarContent: View {
    let model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: model.menuBarSymbol)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Morie")
                        .font(.headline)
                    Text(model.stateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !model.transcript.isEmpty {
                Divider()
                Text(model.transcript)
                    .font(.body)
                    .lineLimit(6)
                    .textSelection(.enabled)
            }

            if !model.capabilityReport.issues.isEmpty {
                Divider()
                ForEach(model.capabilityReport.issues) { issue in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(issue.title)
                            .font(.caption.weight(.semibold))
                        Text(issue.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Request permissions") {
                        Task { await model.requestPermissions() }
                    }
                    Button("Recheck") {
                        Task { await model.recheckCapabilities() }
                    }
                }
            }

            if let method = model.deliveryMethod {
                Text("Last delivery: \(method.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()
            HStack {
                Text("⌃⌥Space")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
