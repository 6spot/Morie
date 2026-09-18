import AppKit
import AVKit
import SwiftData
import SwiftUI

private enum CaptureHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All Captures"
    case captureOnly = "History Only"
    case needsAttention = "Needs Attention"

    var id: Self { self }

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
                    Label(captures.isEmpty ? "No Captures Yet" : "No Matching Captures", systemImage: "waveform")
                } description: {
                    Text(captures.isEmpty
                         ? "Record an idea to keep your words here."
                         : "Try another search or filter.")
                } actions: {
                    if captures.isEmpty {
                        Button("Record Capture", systemImage: "mic", action: onRecord)
                            .disabled(!canStartCapture)
                    } else {
                        Button("Show All Captures") { search = ""; filter = .all }
                    }
                }
            }
        }
        .navigationTitle("History")
        .navigationSubtitle("\(visibleCaptures.count) captures")
        .searchable(text: $search, prompt: "Search captures")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Menu("Filter Captures", systemImage: "line.3.horizontal.decrease") {
                    Picker("Captures", selection: $filter) {
                        ForEach(CaptureHistoryFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                .help(filter.rawValue)
                Button("Record Capture", systemImage: "mic", action: onRecord)
                    .disabled(!canStartCapture)
                    .help("Record an idea and save it to History.")
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
    let candidates: MemoryCandidateController
    let canRecognize: Bool
    let onRecognize: (UUID) -> Void

    @State private var confirmsDeletion = false
    @State private var deletionError: String?

    var body: some View {
        ManagementDetailContent {
            VStack(alignment: .leading, spacing: 10) {
                Text(capture.finalText.isEmpty ? "Recognized Text" : "Final Text")
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
                         ? "Recording… Finish with the capture controls or your shortcut."
                         : "No speech was recognized. Listen to the recording and try again.")
                        .foregroundStyle(.secondary)
                } else {
                    Text(capture.historyText)
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            CaptureCandidatesSection(store: memory, controller: candidates, capture: capture)
            CaptureMemorySection(store: memory, capture: capture)

            DisclosureGroup("Recognition & Refinement") {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recognition").font(.headline)
                        Text(capture.recognizedText.isEmpty ? "No recognized text." : capture.recognizedText)
                            .textSelection(.enabled)
                        if let date = capture.lastRecognitionAttemptAt {
                            LabeledContent("Last Attempt", value: date.formatted(date: .abbreviated, time: .shortened))
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

            DisclosureGroup("Source Recording") {
                recording
                    .padding(.top, 12)
            }
        }
        .navigationTitle("Capture")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Copy Final Text", systemImage: "doc.on.doc") { copy(capture.finalText) }
                    .disabled(capture.finalText.isEmpty)
                Menu("Capture Actions", systemImage: "ellipsis") {
                    Button("Copy Recognition", systemImage: "doc.on.doc") { copy(capture.recognizedText) }
                        .disabled(capture.recognizedText.isEmpty)
                    Divider()
                    Button("Delete Capture…", systemImage: "trash", role: .destructive) {
                        confirmsDeletion = true
                    }
                    .disabled(capture.lifecycle == .capturing || capture.refinement?.status == .running)
                }
            }
        }
        .confirmationDialog("Delete this capture?", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("Delete Capture", role: .destructive) {
                let id = captureID
                Task {
                    do { try await history.deleteCapture(id) }
                    catch { deletionError = error.localizedDescription }
                }
            }
        } message: {
            Text("The saved text, source recording and memory candidate snapshots will be permanently deleted. Memories you saved separately remain.")
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
            LabeledContent("Destination", value: capture.deliveryModeRawValue == CaptureDeliveryMode.captureOnly.rawValue ? "History" : "Current App")
            if let player = history.player {
                CaptureAudioPlayer(player: player).frame(height: 64)
            }
            if let message = history.audioMessage { Text(message).foregroundStyle(.secondary) }
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
                Button("Recognize Again", systemImage: "arrow.clockwise") { onRecognize(captureID) }
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
            Text("Input Refinement").font(.headline)
            LabeledContent("Result", value: refinement.status.title)
            if let reason = refinement.reason {
                Text(reason.message).foregroundStyle(.secondary)
            }
            if let seconds = refinement.durationSeconds {
                LabeledContent("Time", value: "\(seconds.formatted(.number.precision(.fractionLength(2)))) s")
            }
            if !refinement.edits.isEmpty {
                DisclosureGroup("Changes") {
                    ForEach(Array(refinement.edits.enumerated()), id: \.offset) { _, edit in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(edit.proposal.original) → \(edit.proposal.replacement)")
                                .textSelection(.enabled)
                            Text(edit.memoryID == nil ? "Punctuation and spacing" : "Confirmed name")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if refinement.status != .skipped {
                DisclosureGroup("Text Before Refinement") {
                    Text(refinement.input.text)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !refinement.input.context.isEmpty {
                DisclosureGroup("Memory Considered") {
                    ForEach(refinement.input.context) { match in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(match.memory.name, systemImage: match.memory.kind.systemImage)
                            if !match.memory.aliases.isEmpty {
                                Text("Aliases: \(match.memory.aliases.joined(separator: ", "))")
                            }
                            if !match.memory.notes.isEmpty { Text(match.memory.notes) }
                        }
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("These are the saved memory details considered for this input. Later memory edits do not change this record.")
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
