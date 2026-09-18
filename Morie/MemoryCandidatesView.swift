import SwiftUI

struct CaptureCandidatesSection: View {
    @ObservedObject var store: MemoryStore
    @ObservedObject var controller: MemoryCandidateController
    let capture: CaptureRecord
    @State private var editor: MemoryEditorMode?

    private var input: MemoryExtractionInput { MemoryExtractionInput(capture: capture) }
    private var extraction: MemoryExtractionRecord? { store.extraction(for: input) }

    var body: some View {
        Section("Memory Candidates") {
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
                Text("Suggest vocabulary and projects from saved text, then choose what to keep.")
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
                        Button { editor = .reviewCandidate(candidate.id) } label: {
                            LabeledContent(candidate.suggestion.draft.name, value: "Review Suggestion…")
                        }
                    case .accepted:
                        if let memoryID = candidate.memoryID {
                            NavigationLink {
                                MemoryDetailView(store: store, memoryID: memoryID)
                            } label: {
                                LabeledContent(candidate.suggestion.draft.name, value: "Saved to Memory")
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
            LabeledContent("Based on", value: extraction.input?.textKind.title ?? "Saved text")
            Text(extraction.sourceText).textSelection(.enabled)
        }
    }
}
