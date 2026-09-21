import AppKit
import Darwin
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

    private let maximumEntries = DevelopmentDiagnostics.isEnabled ? 5_000 : 1_000
    private let fileFlushDelay: Duration = .milliseconds(400)
    private var pendingFileText = ""
    private var fileFlushTask: Task<Void, Never>?
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
        pendingFileText += format(entry) + "\n"

        if entries.count > maximumEntries {
            entries.removeFirst(entries.count - maximumEntries)
        }

        if level == .error {
            flushPendingFile()
        } else {
            scheduleFileFlush()
        }
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        pendingFileText.removeAll(keepingCapacity: true)
        fileFlushTask?.cancel()
        fileFlushTask = nil
        DiagnosticFileWriter.clear(logFileURL)
    }

    var plainText: String {
        text(for: entries)
    }

    func text(for entries: [Entry]) -> String {
        entries.map(format)
            .joined(separator: "\n")
    }

    private func scheduleFileFlush() {
        guard fileFlushTask == nil else { return }
        fileFlushTask = Task { @MainActor [weak self, fileFlushDelay] in
            do {
                try await Task.sleep(for: fileFlushDelay)
                try Task.checkCancellation()
            } catch {
                return
            }
            self?.flushPendingFile()
        }
    }

    private func flushPendingFile() {
        fileFlushTask?.cancel()
        fileFlushTask = nil
        guard !pendingFileText.isEmpty else { return }
        let text = pendingFileText
        pendingFileText.removeAll(keepingCapacity: true)
        DiagnosticFileWriter.append(text, to: logFileURL)
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
    private static let maximumFileSize: UInt64 =
        (DevelopmentDiagnostics.isEnabled ? 20 : 5) * 1_024 * 1_024

    static func append(_ text: String, to url: URL) {
        queue.async {
            guard let data = text.data(using: .utf8),
                  let handle = try? FileHandle(forWritingTo: url)
            else { return }

            do {
                let size = try handle.seekToEnd()
                if size >= maximumFileSize {
                    try handle.truncate(atOffset: 0)
                    try handle.seek(toOffset: 0)
                }
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

private struct ProcessMemorySnapshot {
    let residentBytes: UInt64
    let physicalFootprintBytes: UInt64
    let heapInUseBytes: UInt64
    let heapAllocatedBytes: UInt64

    static func current() -> ProcessMemorySnapshot? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    rebound,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var heap = malloc_statistics_t()
        malloc_zone_statistics(malloc_default_zone(), &heap)

        return ProcessMemorySnapshot(
            residentBytes: UInt64(info.resident_size),
            physicalFootprintBytes: UInt64(info.phys_footprint),
            heapInUseBytes: UInt64(heap.size_in_use),
            heapAllocatedBytes: UInt64(heap.size_allocated)
        )
    }
}

struct AppBuildIdentity: Equatable {
    let version: String
    let build: String
    let commit: String
    let branch: String?
    let configuration: String
    let sdk: String
    let archs: String
    let xcodeVersion: String
    let isDirty: Bool

    static let current = AppBuildIdentity(bundle: .main)

    init(bundle: Bundle) {
        version =
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String
            ?? "dev"
        build =
            bundle.object(forInfoDictionaryKey: "CFBundleVersion")
            as? String
            ?? "0"

        let metadata = Self.metadata(from: bundle)
        commit = metadata["commit"] as? String ?? "unknown"

        if let value = metadata["branch"] as? String,
           !value.isEmpty,
           value != "detached" {
            branch = value
        } else {
            branch = nil
        }
        configuration = metadata["configuration"] as? String ?? "unknown"
        sdk = metadata["sdk"] as? String ?? "unknown"
        archs = metadata["archs"] as? String ?? "unknown"
        xcodeVersion = metadata["xcodeVersion"] as? String ?? "unknown"
        isDirty = metadata["dirty"] as? Bool ?? false
    }

    var commitDisplay: String {
        isDirty ? "\(commit)*" : commit
    }

    var compactDisplay: String {
        "\(version) (\(build)) · \(commitDisplay)"
    }

    var logValue: String {
        var value = "version=\(version); build=\(build); commit=\(commitDisplay)"
        if let branch {
            value += "; branch=\(branch)"
        }
        value += "; configuration=\(configuration); sdk=\(sdk); archs=\(archs); xcode=\(xcodeVersion)"
        return value
    }

    private static func metadata(from bundle: Bundle) -> [String: Any] {
        guard let url = bundle.url(
            forResource: "MorieBuildIdentity",
            withExtension: "plist"
        ),
        let data = try? Data(contentsOf: url),
        let value = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ),
        let dictionary = value as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }
}

/// Verbose local diagnostics for development builds.
///
/// A build stamped as Debug is a development build even when a local build
/// setting changes Swift optimization. Release builds keep only the existing
/// privacy-preserving summary logs.
///
/// Development diagnostics may contain user-authored text and current-app text.
/// They must never contain credentials, API keys, authorization headers, or
/// unrelated clipboard contents.
enum DevelopmentDiagnostics {
    static var isEnabled: Bool {
        _isDebugAssertConfiguration()
            || AppBuildIdentity.current.configuration
                .caseInsensitiveCompare("Debug") == .orderedSame
    }

    static func record(
        _ category: String,
        captureID: UUID? = nil,
        level: DiagnosticLevel = .info,
        _ message: @autoclosure () -> String
    ) {
        guard isEnabled else { return }
        Diagnostics.record(
            "Dev/\(category)",
            prefix(captureID) + sanitizeSingleLine(message()),
            level: level
        )
    }

    static func text(
        _ category: String,
        captureID: UUID? = nil,
        label: String,
        _ value: String?,
        limit: Int = 8_000
    ) {
        guard isEnabled else { return }
        let rendered: String
        if let value {
            let normalized = value
                .replacingOccurrences(of: "\u{0000}", with: "")
                .replacingOccurrences(of: "\r\n", with: "\n")
                .replacingOccurrences(of: "\r", with: "\n")
            if normalized.count > limit {
                rendered = String(normalized.prefix(limit))
                    + "…<truncated \(normalized.count - limit) chars>"
            } else {
                rendered = normalized
            }
        } else {
            rendered = "<nil>"
        }

        Diagnostics.record(
            "Dev/\(category)",
            prefix(captureID)
                + "\(label)=\(rendered.replacingOccurrences(of: "\n", with: "\\n"))"
        )
    }

    static func list(
        _ category: String,
        captureID: UUID? = nil,
        label: String,
        _ values: [String],
        limit: Int = 128
    ) {
        guard isEnabled else { return }
        let bounded = Array(values.prefix(limit))
        let suffix = values.count > bounded.count
            ? " …(+\(values.count - bounded.count))"
            : ""
        record(
            category,
            captureID: captureID,
            "\(label)=[\(bounded.joined(separator: " | "))]\(suffix)"
        )
    }

    static func recordEnvironment() {
        guard isEnabled else { return }
        let process = ProcessInfo.processInfo
        record(
            "Environment",
            "\(AppBuildIdentity.current.logValue); "
                + "pid=\(process.processIdentifier); "
                + "os=\(process.operatingSystemVersionString); "
                + "locale=\(Locale.current.identifier); "
                + "bundle=\(Bundle.main.bundleIdentifier ?? "unknown"); "
                + "executable=\(Bundle.main.executableURL?.lastPathComponent ?? "unknown"); "
                + "rawDevelopmentTextLogging=true"
        )
    }

    static func errorType(_ error: Error) -> String {
        String(reflecting: type(of: error))
    }

    private static func prefix(_ captureID: UUID?) -> String {
        guard let captureID else { return "" }
        return "Capture \(String(captureID.uuidString.prefix(8))); "
    }

    private static func sanitizeSingleLine(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{0000}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}

enum Diagnostics {
    static func recordMemory(_ phase: String) {
        guard let memory = ProcessMemorySnapshot.current() else { return }
        let divisor = 1_048_576.0
        record(
            "Memory",
            String(
                format: "%@; resident=%.1fMB; footprint=%.1fMB; heapInUse=%.1fMB; heapAllocated=%.1fMB",
                phase,
                Double(memory.residentBytes) / divisor,
                Double(memory.physicalFootprintBytes) / divisor,
                Double(memory.heapInUseBytes) / divisor,
                Double(memory.heapAllocatedBytes) / divisor
            )
        )
    }

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
    @Binding var search: String
    @Binding var level: DiagnosticLevel?
    @Binding var confirmsClear: Bool

    @State private var selection: UUID?

    private var visibleEntries: [DiagnosticLogStore.Entry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        return store.entries.filter { entry in
            (level == nil || entry.level == level)
                && (
                    query.isEmpty
                        || entry.category.localizedStandardContains(query)
                        || entry.message.localizedStandardContains(query)
                )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ControlCenterCommandBar {
                TextField("搜索诊断日志", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)

                Text("\(visibleEntries.count) 条")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

                    Button(
                        "清空诊断日志…",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        confirmsClear = true
                    }
                    .disabled(store.entries.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            VSplitView {
                Table(visibleEntries, selection: $selection) {
                    TableColumn("时间") { entry in
                        Text(
                            entry.timestamp.formatted(
                                .dateTime
                                    .locale(Locale(identifier: "zh-Hans"))
                                    .hour()
                                    .minute()
                                    .second()
                            )
                        )
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 94, max: 120)

                    TableColumn("级别") { entry in
                        Label(
                            entry.level.title,
                            systemImage: entry.level.systemImage
                        )
                        .foregroundStyle(entry.level.color)
                    }
                    .width(min: 80, ideal: 94, max: 110)

                    TableColumn("类别") { entry in
                        Text(entry.category)
                    }
                    .width(min: 90, ideal: 120, max: 200)

                    TableColumn("内容") { entry in
                        Text(entry.message)
                            .lineLimit(1)
                    }
                }
                .overlay {
                    if visibleEntries.isEmpty {
                        ContentUnavailableView(
                            store.entries.isEmpty
                                ? "暂无诊断日志"
                                : "没有匹配的日志",
                            systemImage: "ladybug",
                            description: Text(
                                store.entries.isEmpty
                                    ? "录音和识别过程的诊断信息会显示在这里。"
                                    : "试试其他搜索词或日志级别。"
                            )
                        )
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    maxHeight: .infinity
                )

                diagnosticDetail
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 160,
                        idealHeight: 220,
                        maxHeight: 320
                    )
            }
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: .topLeading
            )
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .confirmationDialog(
            "清空诊断日志？",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("清空诊断日志", role: .destructive) {
                store.clear()
            }
        } message: {
            Text("将清空当前显示的全部日志和本地诊断日志文件。")
        }
        .onChange(of: visibleEntries.map(\.id)) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
    }

    @ViewBuilder
    private var diagnosticDetail: some View {
        if let entry = visibleEntries.first(
            where: { $0.id == selection }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Label(
                            entry.level.title,
                            systemImage: entry.level.systemImage
                        )
                        .foregroundStyle(entry.level.color)

                        Text(entry.category)

                        Spacer()

                        Text(entry.timestamp, format: .dateTime)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)

                    Text(entry.message)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .contentMargins(.vertical, 14, for: .scrollContent)
        } else {
            ContentUnavailableView(
                "选择一条日志",
                systemImage: "doc.text.magnifyingglass",
                description: Text("查看完整的诊断信息。")
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
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
