import AppKit
import Foundation
import SwiftUI

enum DiagnosticLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

@MainActor
final class DiagnosticLogStore: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let level: DiagnosticLevel
        let category: String
        let message: String
    }

    static let shared = DiagnosticLogStore()

    @Published private(set) var entries: [Entry] = []

    private let maximumEntries = 1_000

    private init() {}

    func append(
        _ message: String,
        category: String,
        level: DiagnosticLevel
    ) {
        entries.append(
            Entry(
                timestamp: Date(),
                level: level,
                category: category,
                message: message
            )
        )

        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
    }

    var plainText: String {
        entries.map { entry in
            let time = entry.timestamp.formatted(date: .omitted, time: .standard)
            return "\(time) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
        }
        .joined(separator: "\n")
    }
}

enum Diagnostics {
    static func record(
        _ category: String,
        _ message: String,
        level: DiagnosticLevel = .info
    ) {
        Task { @MainActor in
            DiagnosticLogStore.shared.append(
                message,
                category: category,
                level: level
            )
        }
    }
}

@MainActor
struct DiagnosticLogView: View {
    @ObservedObject private var store = DiagnosticLogStore.shared

    var body: some View {
        Group {
            if store.entries.isEmpty {
                ContentUnavailableView(
                    "No Diagnostics Yet",
                    systemImage: "ladybug",
                    description: Text("Start Morie or press Control + Space. Runtime events will appear here.")
                )
            } else {
                List(store.entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)

                        Text(entry.level.rawValue)
                            .font(.caption.monospaced())
                            .foregroundStyle(entry.level == .error ? .red : .secondary)
                            .frame(width: 42, alignment: .leading)

                        Text(entry.category)
                            .font(.caption.monospaced())
                            .frame(width: 92, alignment: .leading)

                        Text(entry.message)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Morie Debug")
        .toolbar {
            ToolbarItemGroup {
                Button("Copy All", systemImage: "doc.on.doc") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(store.plainText, forType: .string)
                }
                .disabled(store.entries.isEmpty)

                Button("Clear", systemImage: "trash") {
                    store.clear()
                }
                .disabled(store.entries.isEmpty)
            }
        }
        .frame(minWidth: 760, minHeight: 460)
    }
}
