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
    let logFileURL: URL

    private init() {
        let logsDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Morie", isDirectory: true)
        logFileURL = logsDirectory.appendingPathComponent("morie-debug.log")

        do {
            try FileManager.default.createDirectory(
                at: logsDirectory,
                withIntermediateDirectories: true
            )
            FileManager.default.createFile(atPath: logFileURL.path, contents: nil)
        } catch {
            // The in-memory debug view remains usable if the file is unavailable.
        }
    }

    func append(
        _ message: String,
        category: String,
        level: DiagnosticLevel
    ) {
        let entry = Entry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message
        )
        entries.append(entry)
        appendToFile(entry)

        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        DiagnosticFileWriter.clear(logFileURL)
    }

    var plainText: String {
        entries.map(format)
        .joined(separator: "\n")
    }

    private func appendToFile(_ entry: Entry) {
        DiagnosticFileWriter.append(format(entry) + "\n", to: logFileURL)
    }

    private func format(_ entry: Entry) -> String {
        let time = entry.timestamp.formatted(
            .iso8601.year().month().day().dateSeparator(.dash)
                .time(includingFractionalSeconds: true)
        )
        return "\(time) [\(entry.level.rawValue)] [\(entry.category)] \(entry.message)"
    }
}

private enum DiagnosticFileWriter {
    private static let queue = DispatchQueue(label: "com.sixspot.morie.diagnostics-file")

    static func append(_ text: String, to url: URL) {
        queue.async {
            guard let data = text.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: url)
            else { return }

            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } catch {
                try? handle.close()
            }
        }
    }

    static func clear(_ url: URL) {
        queue.async {
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            do {
                try handle.truncate(atOffset: 0)
                try handle.close()
            } catch {
                try? handle.close()
            }
        }
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
                    description: Text("Start Morie or use the configured capture shortcut. Runtime events will appear here.")
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

                Button("Show Log File", systemImage: "doc.text.magnifyingglass") {
                    NSWorkspace.shared.activateFileViewerSelecting([store.logFileURL])
                }
            }
        }
        .frame(minWidth: 760, minHeight: 460)
    }
}
