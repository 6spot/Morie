import SwiftData
import SwiftUI

struct MemoryCandidateDetailView: View {
    @ObservedObject var store: MemoryStore
    let candidateID: UUID
    @Query private var captures: [CaptureRecord]
    @State private var editor: MemoryEditorMode?
    @State private var errorMessage: String?

    private var currentCandidate: (MemoryExtractionRecord, MemoryCandidate)? {
        for extraction in store.extractions {
            guard let candidate = extraction.candidates.first(where: { $0.id == candidateID && $0.status == .pending }),
                  let capture = captures.first(where: { $0.id == extraction.sourceCaptureID }),
                  capture.lifecycle != .capturing, capture.lifecycle != .cancelled,
                  capture.refinement?.status != .running,
                  extraction.input == MemoryExtractionInput(capture: capture)
            else { continue }
            return (extraction, candidate)
        }
        return nil
    }

    var body: some View {
        Group {
            if let (extraction, candidate) = currentCandidate {
                ManagementDetailContent {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Suggested \(candidate.suggestion.draft.kind.title)", systemImage: "sparkles")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text(candidate.suggestion.draft.name).font(.title).textSelection(.enabled)
                        Text("Review and save this suggestion before Morie uses it in future input.")
                            .foregroundStyle(.secondary)
                    }
                    if !candidate.suggestion.draft.aliases.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Also Recognized As").font(.headline)
                            Text(candidate.suggestion.draft.aliases.joined(separator: ", ")).textSelection(.enabled)
                        }
                    }
                    if !candidate.suggestion.draft.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Context").font(.headline)
                            Text(candidate.suggestion.draft.notes).lineSpacing(5).textSelection(.enabled)
                        }
                    }
                    GroupBox {
                        Text(candidate.suggestion.evidence)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        Label("From Your Capture", systemImage: "quote.opening")
                    }
                    MemoryExtractionSource(extraction: extraction)
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .primaryAction) {
                        Button("Review & Save…", systemImage: "checkmark") { editor = .reviewCandidate(candidateID) }
                        Menu("Suggestion Actions", systemImage: "ellipsis") {
                            Button("Dismiss Suggestion", systemImage: "xmark") {
                                do { try store.dismissCandidate(candidateID); errorMessage = nil }
                                catch { errorMessage = error.localizedDescription }
                            }
                        }
                    }
                }
            } else {
                ContentUnavailableView(
                    "Suggestion No Longer Available",
                    systemImage: "sparkles",
                    description: Text("It may have been reviewed, or its source text has changed.")
                )
            }
        }
        .navigationTitle("Review Suggestion")
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
    }
}

struct CaptureCandidatesSection: View {
    @ObservedObject var store: MemoryStore
    @ObservedObject var controller: MemoryCandidateController
    let capture: CaptureRecord
    @State private var editor: MemoryEditorMode?

    private var input: MemoryExtractionInput { MemoryExtractionInput(capture: capture) }
    private var extraction: MemoryExtractionRecord? { store.extraction(for: input) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if controller.extractingCaptureID == capture.id {
                    ProgressView("Finding memories with Apple Intelligence…")
                    Button("Cancel Extraction") { controller.cancelExtraction() }
                } else if extraction == nil {
                    Button("Find Memory Candidates", systemImage: "sparkles") {
                        controller.findCandidates(for: capture.id)
                    }
                    .disabled(controller.isInputActive || controller.extractingCaptureID != nil
                              || capture.lifecycle == .capturing
                              || capture.refinement?.status == .running
                              || input.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("Find names and projects worth remembering for your next input.")
                        .foregroundStyle(.secondary)
                    if store.extractions.contains(where: { $0.sourceCaptureID == capture.id }) {
                        Text("The saved text has changed. Extract again to review suggestions based on the updated text.")
                            .foregroundStyle(.secondary)
                    }
                }
                if controller.messageCaptureID == capture.id, let message = controller.message {
                    Text(message).foregroundStyle(.secondary)
                }
                if let extraction {
                    if extraction.candidates.isEmpty {
                        Text("No vocabulary or project suggestions for this saved text.").foregroundStyle(.secondary)
                    }
                    ForEach(extraction.candidates) { candidate in
                        switch candidate.status {
                        case .pending:
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(candidate.suggestion.draft.name)
                                    Text(candidate.suggestion.draft.kind.title)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                Button("Review…") { editor = .reviewCandidate(candidate.id) }
                                    .accessibilityLabel("Review \(candidate.suggestion.draft.name)")
                            }
                        case .accepted:
                            if let memoryID = candidate.memoryID {
                                VStack(alignment: .leading, spacing: 4) {
                                    NavigationLink(candidate.suggestion.draft.name) {
                                        MemoryDetailView(store: store, memoryID: memoryID)
                                    }
                                    .buttonStyle(.link)
                                    Text("Saved to Memory").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        case .dismissed:
                            LabeledContent(candidate.suggestion.draft.name, value: "Dismissed")
                                .foregroundStyle(.secondary)
                        }
                    }
                    MemoryExtractionSource(extraction: extraction)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Memory Suggestions", systemImage: "sparkles")
        }
        .sheet(item: $editor) { MemoryEditorSheet(store: store, mode: $0) }
        .onDisappear {
            if controller.extractingCaptureID == capture.id { controller.cancelExtraction() }
        }
    }
}

struct MemoryExtractionSource: View {
    let extraction: MemoryExtractionRecord

    var body: some View {
        DisclosureGroup("Text Used for Extraction") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Based on", value: extraction.input?.textKind.title ?? "Saved text")
                Text(extraction.sourceText).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
        }
    }
}
