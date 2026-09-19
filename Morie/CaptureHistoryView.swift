import AppKit
import AVKit
import SwiftData
import SwiftUI

private enum CaptureHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All Captures"
    case captureOnly = "History Only"
    case needsAttention = "Needs Attention"

    var id: Self { self }

    var title: String {
        switch self {
        case .all: "全部记录"
        case .captureOnly: "仅存于历史记录"
        case .needsAttention: "需要处理"
        }
    }

    func includes(_ capture: CaptureRecord) -> Bool {
        switch self {
        case .all: true
        case .captureOnly: capture.deliveryModeRawValue == CaptureDeliveryMode.captureOnly.rawValue
        case .needsAttention: capture.lifecycle == .failed || capture.lifecycle == .deliveryFailed
        }
    }
}

struct CaptureHistoryView: View {
    let captures: [CaptureRecord]
    @Binding var selection: UUID?
    let canStartCapture: Bool
    let onRecord: () -> Void
    @State private var search = ""
    @State private var filter: CaptureHistoryFilter = .all

    private var visibleCaptures: [CaptureRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return captures.filter { capture in
            filter.includes(capture) && (query.isEmpty || [
                capture.finalText, capture.recognizedText, capture.sourceApplicationName ?? ""
            ].contains { $0.localizedStandardContains(query) })
        }
    }

    var body: some View {
        List(visibleCaptures, selection: $selection) { capture in
            VStack(alignment: .leading, spacing: 8) {
                Text(capture.historySummary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(capture.createdAt, format: .dateTime.month(.abbreviated).day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    if let applicationName = capture.sourceApplicationName {
                        Text(applicationName).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(capture.historyStatus)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
            .tag(capture.id)
        }
        .listStyle(.inset)
        .overlay {
            if visibleCaptures.isEmpty {
                ContentUnavailableView {
                    Label(captures.isEmpty ? "还没有记录" : "没有匹配的记录", systemImage: "waveform")
                } description: {
                    Text(captures.isEmpty
                         ? "开始录音，将你的表达保存在这里。"
                         : "试试其他搜索词或筛选条件。")
                } actions: {
                    if captures.isEmpty {
                        Button("开始录音", systemImage: "mic", action: onRecord)
                            .disabled(!canStartCapture)
                    } else {
                        Button("显示全部记录") { search = ""; filter = .all }
                    }
                }
            }
        }
        .navigationTitle("历史记录")
        .navigationSubtitle("\(visibleCaptures.count) 条记录")
        .searchable(text: $search, prompt: "搜索历史记录")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("筛选记录", selection: $filter) {
                    ForEach(CaptureHistoryFilter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .help(filter.title)
                Button("开始录音", systemImage: "mic", action: onRecord)
                    .disabled(!canStartCapture)
                    .help("录音并保存到历史记录。")
            }
        }
        .onChange(of: visibleCaptures.map(\.id), initial: true) { _, ids in
            if let selection, !ids.contains(selection) { self.selection = nil }
        }
    }
}

struct CaptureDetailView: View {
    let capture: CaptureRecord
    let captureID: UUID
    @ObservedObject var history: CaptureHistoryController
    let memory: MemoryStore
    let learning: MemoryLearningController
    let canRecognize: Bool
    let onRecognize: (UUID) -> Void

    @State private var confirmsDeletion = false
    @State private var deletionError: String?

    var body: some View {
        ManagementDetailContent {
            VStack(alignment: .leading, spacing: 10) {
                Text(capture.finalText.isEmpty ? "识别文字" : "最终文字")
                    .font(.title)
                Text(capture.createdAt, format: .dateTime.month(.wide).day().year().hour().minute())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(capture.historyStatus, systemImage: "waveform")
                    if let app = capture.sourceApplicationName { Text(app) }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let issue = capture.deliveryErrorDescription {
                    Label(issue, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                if capture.historyText.isEmpty {
                    Text(capture.lifecycle == .capturing
                         ? "正在录音… 使用录音控件或快捷键结束。"
                         : "未识别到语音，可以播放录音后重新识别。")
                        .foregroundStyle(.secondary)
                } else {
                    Text(capture.historyText)
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            CaptureMemorySection(store: memory, controller: learning, capture: capture)

            DisclosureGroup("识别与润色") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("语音识别").font(.headline)
                        Text(capture.recognizedText.isEmpty ? "暂无识别文字。" : capture.recognizedText)
                            .textSelection(.enabled)
                        if let date = capture.lastRecognitionAttemptAt {
                            LabeledContent("上次识别", value: date.formatted(.dateTime.locale(Locale(identifier: "zh-Hans")).year().month().day().hour().minute()))
                        }
                        if let error = capture.lastRecognitionErrorDescription {
                            Label(error, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let refinement = capture.refinement {
                        Divider()
                        CaptureRefinementSection(refinement: refinement)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
            }

            DisclosureGroup("原始录音") {
                recording
                    .padding(.top, 12)
            }
        }
        .navigationTitle("记录")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("复制最终文字", systemImage: "doc.on.doc") { copy(capture.finalText) }
                    .disabled(capture.finalText.isEmpty)
                Menu("记录操作", systemImage: "ellipsis") {
                    Button("复制识别文字", systemImage: "doc.on.doc") { copy(capture.recognizedText) }
                        .disabled(capture.recognizedText.isEmpty)
                    Divider()
                    Button("删除记录…", systemImage: "trash", role: .destructive) {
                        confirmsDeletion = true
                    }
                    .disabled(capture.lifecycle == .capturing || capture.refinement?.status == .running)
                }
            }
        }
        .confirmationDialog("删除这条记录？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("删除记录", role: .destructive) {
                let id = captureID
                Task {
                    do { try await history.deleteCapture(id) }
                    catch { deletionError = error.localizedDescription }
                }
            }
        } message: {
            Text("此记录的文字、原始录音和记忆分析快照将被永久删除。已单独保存的个人记忆会保留。")
        }
        .alert("无法删除记录", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("好", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .onAppear { history.open(captureID) }
        .onDisappear { history.close(captureID) }
        .onChange(of: capture.sourceAudioRelativePath) { _, _ in history.refreshAudio(for: captureID) }
        .onChange(of: capture.refinement?.status) { _, _ in history.refreshAudio(for: captureID) }
        .task(id: capture.sourceAudioExpiresAt) {
            guard let expiresAt = capture.sourceAudioExpiresAt else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow)))
                try Task.checkCancellation()
                history.refreshAudio(for: captureID)
            } catch { }
        }
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("保存位置", value: capture.deliveryModeRawValue == CaptureDeliveryMode.captureOnly.rawValue ? "历史记录" : "当前应用")
            if let player = history.player {
                CaptureAudioPlayer(player: player).frame(height: 64)
            }
            if let message = history.audioMessage { Text(message).foregroundStyle(.secondary) }
            if let duration = capture.sourceAudioDurationSeconds {
                LabeledContent("录音时长", value: Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
            }
            if let expiresAt = capture.sourceAudioExpiresAt {
                LabeledContent("录音到期时间", value: expiresAt.formatted(.dateTime.locale(Locale(identifier: "zh-Hans")).year().month().day().hour().minute()))
            }
            if history.recognizingCaptureID == captureID {
                HStack {
                    ProgressView("正在识别…").controlSize(.small)
                    Button("取消", role: .cancel) { history.cancelRecognition() }
                }
            } else {
                Button("重新识别", systemImage: "arrow.clockwise") { onRecognize(captureID) }
                    .disabled(!canRecognize || history.isInputActive || history.player == nil || history.recognizingCaptureID != nil)
            }
            if let message = history.recognitionMessage { Text(message).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct CaptureRefinementSection: View {
    let refinement: CaptureRefinement

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("输入润色").font(.headline)
            LabeledContent("处理结果", value: refinement.status.title)
            if let reason = refinement.reason {
                Text(reason.message).foregroundStyle(.secondary)
            }
            if let seconds = refinement.durationSeconds {
                LabeledContent("耗时", value: "\(seconds.formatted(.number.precision(.fractionLength(2)))) 秒")
            }
            if !refinement.edits.isEmpty {
                DisclosureGroup("修改内容") {
                    ForEach(Array(refinement.edits.enumerated()), id: \.offset) { _, edit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(edit.original) → \(edit.replacement)")
                                .textSelection(.enabled)
                            Text(edit.dictionaryEntryID == nil ? "AI 润色" : "自定义字典")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            DisclosureGroup("润色前的文字") {
                Text(refinement.input.text)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !refinement.input.dictionary.isEmpty {
                DisclosureGroup("本次使用的字典") {
                    ForEach(refinement.input.dictionary) { entry in
                        Text(entry.name).font(.headline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("这里保留本次输入使用的字典内容，后续编辑字典不会改变这条记录。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !refinement.input.context.isEmpty {
                DisclosureGroup("本次参考的个人记忆") {
                    ForEach(refinement.input.context) { match in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(match.memory.name, systemImage: match.memory.kind.systemImage)
                            if !match.memory.notes.isEmpty { Text(match.memory.notes) }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("这里保留本次输入参考的个人记忆，后续编辑记忆不会改变这条记录。")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct CaptureAudioPlayer: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.updatesNowPlayingInfoCenter = false
        view.allowsVideoFrameAnalysis = false
        view.player = player
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player {
            view.player?.pause()
            view.player = player
        }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

private extension CaptureRecord {
    var historyText: String { finalText.isEmpty ? recognizedText : finalText }

    var historySummary: String {
        if !historyText.isEmpty {
            return historyText.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        return lifecycle == .capturing ? "正在录音…" : "未识别到语音"
    }

    var historyStatus: String {
        switch lifecycle {
        case .capturing: "录音中"
        case .recognized: "已保存"
        case .delivered: "已输入"
        case .deliveryFailed: "未能输入"
        case .cancelled: "已取消"
        case .failed: historyText.isEmpty ? "未能识别" : "录音失败"
        }
    }
}
