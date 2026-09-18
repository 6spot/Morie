import AppKit
import AVKit
import SwiftData
import SwiftUI

struct CaptureHistoryView: View {
    @ObservedObject var history: CaptureHistoryController
    let memory: MemoryStore
    let canStartCapture: Bool
    let onRecord: () -> Void
    let onRecognize: (UUID) -> Void

    @Query(sort: \CaptureRecord.createdAt, order: .reverse)
    private var captures: [CaptureRecord]
    @State private var path: [UUID] = []

    var body: some View {
        NavigationStack(path: $path) {
            List(captures) { capture in
                NavigationLink(value: capture.id) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(capture.historySummary)
                            .lineLimit(3)

                        HStack(spacing: 8) {
                            Text(capture.createdAt, format: .dateTime)
                            if let applicationName = capture.sourceApplicationName {
                                Text(applicationName)
                            }
                            Text(capture.historyStatus)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .overlay {
                if captures.isEmpty {
                    ContentUnavailableView(
                        "No Captures Yet",
                        systemImage: "waveform",
                        description: Text("Completed voice captures will appear here.")
                    )
                }
            }
            .navigationTitle("History")
            .navigationDestination(for: UUID.self) { id in
                if let capture = captures.first(where: { $0.id == id }) {
                    CaptureDetailView(
                        capture: capture,
                        captureID: id,
                        history: history,
                        memory: memory,
                        canRecognize: canStartCapture,
                        onRecognize: onRecognize
                    )
                } else {
                    ContentUnavailableView("Capture No Longer Available", systemImage: "waveform")
                }
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Record Capture", systemImage: "mic") { onRecord() }
                    .disabled(!canStartCapture)
                    .help("Record an idea and save it to History.")
            }
        }
        .onChange(of: captures.map(\.id)) { _, ids in
            path.removeAll { !ids.contains($0) }
        }
    }
}

private struct CaptureDetailView: View {
    let capture: CaptureRecord
    let captureID: UUID
    @ObservedObject var history: CaptureHistoryController
    let memory: MemoryStore
    let canRecognize: Bool
    let onRecognize: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var confirmsDeletion = false
    @State private var deletionError: String?

    private var recognizedText: String {
        capture.recognizedText.isEmpty ? capture.finalText : capture.recognizedText
    }

    var body: some View {
        Form {
            Section("Capture") {
                LabeledContent("Created", value: capture.createdAt.formatted(date: .abbreviated, time: .standard))
                LabeledContent("Destination", value: capture.deliveryModeRawValue == CaptureDeliveryMode.captureOnly.rawValue ? "History" : "Current App")
                if let app = capture.sourceApplicationName {
                    LabeledContent("Source App", value: app)
                }
                LabeledContent("Original Outcome", value: capture.historyStatus)
                if let issue = capture.deliveryErrorDescription {
                    Text(issue).foregroundStyle(.secondary)
                }
            }

            Section("Recognition") {
                if recognizedText.isEmpty {
                    Text(capture.lifecycle == .capturing
                         ? "Recording… Finish with the capture controls or your shortcut."
                         : "No speech was recognized. You can listen to the recording and try again.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(recognizedText).textSelection(.enabled)
                    Button("Copy Text", systemImage: "doc.on.doc") {
                        copy(recognizedText)
                    }
                }
                if let date = capture.lastRecognitionAttemptAt {
                    LabeledContent("Last Attempt", value: date.formatted(date: .abbreviated, time: .standard))
                }
                if let error = capture.lastRecognitionErrorDescription {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                }
            }

            if !capture.finalText.isEmpty && capture.finalText != recognizedText {
                Section("Original Output") {
                    Text(capture.finalText).textSelection(.enabled)
                    Button("Copy Original Output", systemImage: "doc.on.doc") {
                        copy(capture.finalText)
                    }
                }
            }

            CaptureMemorySection(store: memory, capture: capture)

            Section("Source Recording") {
                if let player = history.player {
                    CaptureAudioPlayer(player: player)
                        .frame(height: 64)
                }
                if let message = history.audioMessage {
                    Text(message).foregroundStyle(.secondary)
                }
                if let duration = capture.sourceAudioDurationSeconds {
                    LabeledContent("Duration", value: Duration.seconds(duration).formatted(.time(pattern: .minuteSecond)))
                }
                if let expiresAt = capture.sourceAudioExpiresAt {
                    LabeledContent("Expires", value: expiresAt.formatted(date: .abbreviated, time: .shortened))
                }
                if history.recognizingCaptureID == captureID {
                    HStack {
                        ProgressView("Recognizing…").controlSize(.small)
                        Button("Cancel", role: .cancel) { history.cancelRecognition() }
                    }
                } else {
                    Button("Recognize Again", systemImage: "arrow.clockwise") {
                        onRecognize(captureID)
                    }
                    .disabled(!canRecognize || history.isInputActive || history.player == nil || history.recognizingCaptureID != nil)
                }
                if let message = history.recognitionMessage {
                    Text(message).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Capture")
        .toolbar {
            Button("Delete Capture", systemImage: "trash", role: .destructive) {
                confirmsDeletion = true
            }
            .disabled(capture.lifecycle == .capturing)
        }
        .confirmationDialog("Delete this capture?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Capture", role: .destructive) {
                let id = captureID
                Task {
                    do {
                        try await history.deleteCapture(id)
                        dismiss()
                    } catch {
                        deletionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("The saved text and source recording will be permanently deleted. Memories you saved separately remain.")
        }
        .alert("Couldn’t Delete Capture", isPresented: Binding(
            get: { deletionError != nil },
            set: { if !$0 { deletionError = nil } }
        )) {
            Button("OK", role: .cancel) { deletionError = nil }
        } message: {
            Text(deletionError ?? "")
        }
        .onAppear { history.open(captureID) }
        .onDisappear { history.close(captureID) }
        .onChange(of: capture.sourceAudioRelativePath) { _, _ in
            history.refreshAudio(for: captureID)
        }
        .task(id: capture.sourceAudioExpiresAt) {
            guard let expiresAt = capture.sourceAudioExpiresAt else { return }
            do {
                try await Task.sleep(for: .seconds(max(0, expiresAt.timeIntervalSinceNow)))
                try Task.checkCancellation()
                history.refreshAudio(for: captureID)
            } catch { }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        if !historyText.isEmpty { return historyText }
        return lifecycle == .capturing ? "Recording…" : "No speech recognized"
    }

    var historyStatus: String {
        switch lifecycle {
        case .capturing: "Recording"
        case .recognized: "Saved"
        case .delivered: "Delivered"
        case .deliveryFailed: "Not Delivered"
        case .cancelled: "Cancelled"
        case .failed: historyText.isEmpty ? "Not Recognized" : "Capture Failed"
        }
    }
}
