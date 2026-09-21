import AppKit
import AVKit
import SwiftData
import SwiftUI

enum CaptureHistoryFilter: String, CaseIterable, Identifiable {
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
        case .all:
            true
        case .captureOnly:
            capture.deliveryModeRawValue
                == CaptureDeliveryMode.captureOnly.rawValue
        case .needsAttention:
            capture.lifecycle == .failed
                || capture.lifecycle == .deliveryFailed
        }
    }
}

@MainActor
struct CaptureHistoryWorkspace: View {
    let controller: AppController
    @ObservedObject private var runtime: AppRuntimeController
    @Binding var selection: UUID?
    @Binding var search: String
    @Binding var filter: CaptureHistoryFilter

    init(
        controller: AppController,
        selection: Binding<UUID?>,
        search: Binding<String>,
        filter: Binding<CaptureHistoryFilter>
    ) {
        self.controller = controller
        _runtime = ObservedObject(wrappedValue: controller.runtime)
        _selection = selection
        _search = search
        _filter = filter
    }

    private var canStartCapture: Bool {
        _ = runtime.state
        return controller.canStartCapture
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            Group {
                if let history = controller.history {
                    HSplitView {
                        CaptureHistoryView(
                            captures: history.captures,
                            selection: $selection,
                            search: $search,
                            filter: $filter,
                            canStartCapture: canStartCapture,
                            onRecord: controller.startCaptureOnly
                        )
                        .frame(
                            minWidth: 250,
                            idealWidth: 320,
                            maxWidth: 360,
                            maxHeight: .infinity,
                            alignment: .topLeading
                        )

                        CaptureHistoryDetailPane(
                            controller: controller,
                            history: history,
                            selectedCaptureID: selection
                        )
                        .frame(
                            minWidth: 0,
                            maxWidth: .infinity,
                            maxHeight: .infinity
                        )
                    }
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .topLeading
                    )
                    .onAppear {
                        history.setListVisible(true)
                    }
                    .onDisappear {
                        history.setListVisible(false)
                    }
                } else {
                    ContentUnavailableView(
                        "历史记录不可用",
                        systemImage: "exclamationmark.triangle",
                        description: Text("记录存储尚未初始化。")
                    )
                }
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
    }
}

struct CaptureHistoryView: View {
    let captures: [CaptureRecord]
    @Binding var selection: UUID?
    @Binding var search: String
    @Binding var filter: CaptureHistoryFilter
    let canStartCapture: Bool
    let onRecord: () -> Void

    private var visibleCaptures: [CaptureRecord] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)

        return captures.filter { capture in
            filter.includes(capture)
                && (
                    query.isEmpty
                        || [
                            capture.finalText,
                            capture.recognizedText,
                            capture.sourceApplicationName ?? ""
                        ].contains {
                            $0.localizedStandardContains(query)
                        }
                )
        }
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(visibleCaptures) { capture in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(capture.historySummary)
                            .lineLimit(2, reservesSpace: true)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )

                        HStack(spacing: 8) {
                            if let applicationName =
                                capture.sourceApplicationName {
                                Text(applicationName)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }

                            if let status = capture.historyStatus {
                                Text(status)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            Text(capture.historyListDate)
                                .lineLimit(1)
                                .fixedSize(
                                    horizontal: true,
                                    vertical: false
                                )
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .transaction { $0.animation = nil }
                    .tag(capture.id)
                }
            } header: {
                Text("\(visibleCaptures.count) 条记录")
            }
        }
        .listStyle(.inset)
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: .topLeading
        )
        .overlay {
            if visibleCaptures.isEmpty {
                ContentUnavailableView {
                    Label(
                        captures.isEmpty
                            ? "还没有记录"
                            : "没有匹配的记录",
                        systemImage: "waveform"
                    )
                } description: {
                    Text(
                        captures.isEmpty
                            ? "开始录音，将你的表达保存在这里。"
                            : "试试其他搜索词或筛选条件。"
                    )
                } actions: {
                    if captures.isEmpty {
                        Button(
                            "开始录音",
                            systemImage: "mic",
                            action: onRecord
                        )
                        .disabled(!canStartCapture)
                    } else {
                        Button("显示全部记录") {
                            search = ""
                            filter = .all
                        }
                    }
                }
            }
        }
        .onChange(
            of: visibleCaptures.map(\.id),
            initial: true
        ) { _, ids in
            if let selection, !ids.contains(selection) {
                self.selection = nil
            }
        }
    }
}

@MainActor
private struct CaptureHistoryDetailPane: View {
    let controller: AppController
    @ObservedObject private var runtime: AppRuntimeController
    @ObservedObject var history: CaptureHistoryController
    let selectedCaptureID: UUID?

    init(
        controller: AppController,
        history: CaptureHistoryController,
        selectedCaptureID: UUID?
    ) {
        self.controller = controller
        _runtime = ObservedObject(wrappedValue: controller.runtime)
        _history = ObservedObject(wrappedValue: history)
        self.selectedCaptureID = selectedCaptureID
    }

    private var capture: CaptureRecord? {
        guard let selectedCaptureID else { return nil }
        return history.captures.first { $0.id == selectedCaptureID }
    }

    private var canStartCapture: Bool {
        _ = runtime.state
        return controller.canStartCapture
    }

    var body: some View {
        if let selectedCaptureID,
           let capture {
            CaptureDetailView(
                capture: capture,
                captureID: selectedCaptureID,
                history: history,
                canRecognize: canStartCapture,
                onRecognize: controller.recognizeHistoryCapture
            )
        } else {
            ContentUnavailableView(
                "选择一条记录",
                systemImage: "waveform",
                description: Text(
                    "在这里查看保存的文字、识别结果和原始录音。"
                )
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity
            )
        }
    }
}

struct CaptureDetailView: View {
    let capture: CaptureRecord
    let captureID: UUID
    @ObservedObject var history: CaptureHistoryController
    let canRecognize: Bool
    let onRecognize: (UUID) -> Void

    @State private var confirmsDeletion = false
    @State private var deletionError: String?

    var body: some View {
        ControlCenterReadingContent {
            VStack(alignment: .leading, spacing: 20) {
                ControlCenterCommandBar {
                    Button("复制最终文字", systemImage: "doc.on.doc") {
                        copy(capture.finalText)
                    }
                    .disabled(capture.finalText.isEmpty)

                    Button("复制识别文字", systemImage: "doc.on.doc") {
                        copy(capture.recognizedText)
                    }
                    .disabled(capture.recognizedText.isEmpty)

                    Button(
                        "删除记录…",
                        systemImage: "trash",
                        role: .destructive
                    ) {
                        confirmsDeletion = true
                    }
                    .disabled(
                        capture.lifecycle == .capturing
                            || capture.refinement?.status == .running
                    )

                    Spacer(minLength: 0)
                }

                ControlCenterSectionBlock(
                    capture.finalText.isEmpty ? "识别文字" : "最终文字"
                ) {
                    HStack(spacing: 8) {
                        if let app = capture.sourceApplicationName {
                            Text(app)
                        }

                        Text(
                            capture.createdAt.formatted(
                                .dateTime
                                    .locale(Locale(identifier: "zh-Hans"))
                                    .year()
                                    .month()
                                    .day()
                                    .hour()
                                    .minute()
                            )
                        )

                        if let status = capture.historyStatus {
                            Label(status, systemImage: "waveform")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    if let issue = capture.deliveryErrorDescription {
                        Label(
                            issue,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                    }

                    if capture.historyText.isEmpty {
                        Text(
                            capture.lifecycle == .capturing
                                ? "正在录音… 使用录音控件或快捷键结束。"
                                : "未识别到语音，可以播放录音后重新识别。"
                        )
                        .foregroundStyle(.secondary)
                    } else {
                        Text(capture.historyText)
                            .lineSpacing(5)
                            .textSelection(.enabled)
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }
                }

                Divider()

                ControlCenterSectionBlock(
                    "识别与润色",
                    subtitle: "保留原始识别结果和本次润色处理信息，便于核对最终文字。"
                ) {
                    Text("原始语音识别")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text(
                        capture.recognizedText.isEmpty
                            ? "暂无识别文字。"
                            : capture.recognizedText
                    )
                    .textSelection(.enabled)

                    if let date = capture.lastRecognitionAttemptAt {
                        LabeledContent(
                            "上次识别",
                            value: date.formatted(
                                .dateTime
                                    .locale(Locale(identifier: "zh-Hans"))
                                    .year()
                                    .month()
                                    .day()
                                    .hour()
                                    .minute()
                            )
                        )
                    }

                    if let error =
                        capture.lastRecognitionErrorDescription {
                        Label(
                            error,
                            systemImage: "exclamationmark.triangle"
                        )
                        .foregroundStyle(.secondary)
                    }

                    if let refinement = capture.refinement {
                        Divider()
                        CaptureRefinementSection(
                            refinement: refinement
                        )
                    }
                }

                Divider()

                ControlCenterSectionBlock(
                    "原始录音",
                    subtitle: "原始录音只保存在当前 Mac，并按设置中的保留周期自动清理。"
                ) {
                    recording
                }
            }
        }
        .confirmationDialog(
            "删除这条记录？",
            isPresented: $confirmsDeletion,
            titleVisibility: .visible
        ) {
            Button("删除记录", role: .destructive) {
                let id = captureID
                Task {
                    do {
                        try await history.deleteCapture(id)
                    } catch {
                        deletionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(
                "此记录的文字、识别与润色信息和原始录音将被永久删除。"
            )
        }
        .alert(
            "无法删除记录",
            isPresented: Binding(
                get: { deletionError != nil },
                set: {
                    if !$0 {
                        deletionError = nil
                    }
                }
            )
        ) {
            Button("好", role: .cancel) {
                deletionError = nil
            }
        } message: {
            Text(deletionError ?? "")
        }
        .onAppear {
            history.open(captureID)
        }
        .onDisappear {
            history.close(captureID)
        }
        .onChange(of: capture.sourceAudioRelativePath) { _, _ in
            history.refreshAudio(for: captureID)
        }
        .onChange(of: capture.refinement?.status) { _, _ in
            history.refreshAudio(for: captureID)
        }
        .task(id: capture.sourceAudioExpiresAt) {
            guard let expiresAt = capture.sourceAudioExpiresAt else {
                return
            }

            do {
                try await Task.sleep(
                    for: .seconds(
                        max(0, expiresAt.timeIntervalSinceNow)
                    )
                )
                try Task.checkCancellation()
                history.refreshAudio(for: captureID)
            } catch {
            }
        }
    }

    private var recording: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent(
                "保存位置",
                value: capture.deliveryModeRawValue
                    == CaptureDeliveryMode.captureOnly.rawValue
                    ? "历史记录"
                    : "当前应用"
            )

            if let player = history.player {
                CaptureAudioPlayer(player: player)
                    .frame(height: 64)
            }

            if let message = history.audioMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            }

            if let duration = capture.sourceAudioDurationSeconds {
                LabeledContent(
                    "录音时长",
                    value: Duration.seconds(duration)
                        .formatted(.time(pattern: .minuteSecond))
                )
            }

            if let expiresAt = capture.sourceAudioExpiresAt {
                LabeledContent(
                    "录音到期时间",
                    value: expiresAt.formatted(
                        .dateTime
                            .locale(Locale(identifier: "zh-Hans"))
                            .year()
                            .month()
                            .day()
                            .hour()
                            .minute()
                    )
                )
            }

            if history.recognizingCaptureID == captureID {
                HStack {
                    ProgressView("正在识别…")
                        .controlSize(.small)

                    Button("取消", role: .cancel) {
                        history.cancelRecognition()
                    }
                }
            } else {
                Button("重新识别", systemImage: "arrow.clockwise") {
                    onRecognize(captureID)
                }
                .disabled(
                    !canRecognize
                        || history.isInputActive
                        || history.player == nil
                        || history.recognizingCaptureID != nil
                )
            }

            if let message = history.recognitionMessage {
                Text(message)
                    .foregroundStyle(.secondary)
            }
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
            Text("输入润色")
                .font(.headline)

            LabeledContent(
                "处理结果",
                value: refinement.status.title
            )

            if let seconds = refinement.durationSeconds {
                LabeledContent(
                    "耗时",
                    value: "\(seconds.formatted(.number.precision(.fractionLength(2)))) 秒"
                )
            }

            if let reason = refinement.reason {
                Text(reason.message)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    func updateNSView(
        _ view: AVPlayerView,
        context: Context
    ) {
        if view.player !== player {
            view.player?.pause()
            view.player = player
        }
    }

    static func dismantleNSView(
        _ view: AVPlayerView,
        coordinator: ()
    ) {
        view.player?.pause()
        view.player = nil
    }
}

private extension CaptureRecord {
    var historyText: String {
        finalText.isEmpty ? recognizedText : finalText
    }

    var historySummary: String {
        if !historyText.isEmpty {
            return historyText
                .split(whereSeparator: \.isWhitespace)
                .joined(separator: " ")
        }

        return lifecycle == .capturing
            ? "正在录音…"
            : "未识别到语音"
    }

    var historyListDate: String {
        createdAt.formatted(
            .dateTime
                .locale(Locale(identifier: "zh-Hans"))
                .month()
                .day()
                .hour()
                .minute()
        )
    }

    var historyStatus: String? {
        switch lifecycle {
        case .capturing:
            "录音中"
        case .recognized, .delivered:
            nil
        case .deliveryFailed:
            "未能输入"
        case .cancelled:
            "已取消"
        case .failed:
            historyText.isEmpty
                ? "未能识别"
                : "录音失败"
        }
    }
}
