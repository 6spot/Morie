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
    @State private var search = ""
    @State private var level: DiagnosticLevel?
    @State private var selection: UUID?
    @State private var confirmsClear = false

    private var visibleEntries: [DiagnosticLogStore.Entry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.entries.filter { entry in
            (level == nil || entry.level == level) && (query.isEmpty
                || entry.category.localizedStandardContains(query)
                || entry.message.localizedStandardContains(query))
        }
    }

    var body: some View {
        VSplitView {
            Table(visibleEntries, selection: $selection) {
                TableColumn("时间") { entry in
                    Text(entry.timestamp.formatted(.dateTime.locale(Locale(identifier: "zh-Hans")).hour().minute().second()))
                        .monospacedDigit().foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 94, max: 120)
                TableColumn("级别") { entry in
                    Label(entry.level.title, systemImage: entry.level.systemImage)
                        .foregroundStyle(entry.level.color)
                }
                .width(min: 80, ideal: 94, max: 110)
                TableColumn("类别") { entry in Text(entry.category) }
                    .width(min: 90, ideal: 120, max: 200)
                TableColumn("内容") { entry in
                    Text(entry.message).lineLimit(1)
                }
            }
            .overlay {
                if visibleEntries.isEmpty {
                    ContentUnavailableView(
                        store.entries.isEmpty ? "暂无诊断日志" : "没有匹配的日志",
                        systemImage: "ladybug",
                        description: Text(store.entries.isEmpty
                            ? "录音和识别过程的诊断信息会显示在这里。"
                            : "试试其他搜索词或日志级别。")
                    )
                }
            }
            .frame(minHeight: 200)

            if let entry = visibleEntries.first(where: { $0.id == selection }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 12) {
                            Label(entry.level.title, systemImage: entry.level.systemImage)
                                .foregroundStyle(entry.level.color)
                            Text(entry.category)
                            Text(entry.timestamp, format: .dateTime)
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption)
                        Text(entry.message)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)
                }
                .frame(minHeight: 100, idealHeight: 160, maxHeight: 240)
            }
        }
        .navigationTitle("诊断")
        .navigationSubtitle("\(visibleEntries.count) 条日志")
        .searchable(text: $search, prompt: "搜索诊断日志")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("筛选日志", selection: $level) {
                    Text("全部日志").tag(nil as DiagnosticLevel?)
                    ForEach([DiagnosticLevel.info, .warning, .error], id: \.self) {
                        Text($0.title).tag(Optional($0))
                    }
                }
                .pickerStyle(.menu)
                Button("复制全部日志", systemImage: "doc.on.doc") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(store.plainText, forType: .string)
                }
                .disabled(store.entries.isEmpty)
                Menu("诊断操作", systemImage: "ellipsis") {
                    Button("在访达中显示日志文件", systemImage: "doc.text.magnifyingglass") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.logFileURL])
                    }
                    Divider()
                    Button("清空诊断日志…", systemImage: "trash", role: .destructive) { confirmsClear = true }
                        .disabled(store.entries.isEmpty)
                }
            }
        }
        .confirmationDialog("清空诊断日志？", isPresented: $confirmsClear, titleVisibility: .visible) {
            Button("清空诊断日志", role: .destructive) { store.clear() }
        } message: {
            Text("将清空当前显示的全部日志和本地诊断日志文件。")
        }
        .onChange(of: visibleEntries.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }
}

private extension DiagnosticLevel {
    var title: String {
        switch self {
        case .info: "信息"
        case .warning: "警告"
        case .error: "错误"
        }
    }

    var systemImage: String {
        switch self {
        case .info: "info.circle"
        case .warning: "exclamationmark.triangle"
        case .error: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .info: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
