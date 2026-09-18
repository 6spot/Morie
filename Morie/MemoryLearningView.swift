import SwiftUI

struct CaptureMemorySection: View {
    @ObservedObject var store: MemoryStore
    @ObservedObject var controller: MemoryLearningController
    let capture: CaptureRecord

    private var analysis: MemoryAnalysisRecord? { store.analysis(for: MemoryAnalysisSource(capture: capture)) }
    private var linked: [MemoryRecord] { store.entries.filter { $0.sourceCaptureIDs.contains(capture.id) } }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if controller.analyzingCaptureID == capture.id {
                    ProgressView("Learning from this input…")
                } else if let analysis {
                    if let failure = analysis.failure {
                        Text(failure.message).foregroundStyle(.secondary)
                        if analysis.state == .skipped {
                            Button("Retry Memory Learning") { controller.retry(analysis.source) }
                                .disabled(controller.isInputActive)
                        }
                    } else if analysis.state == .pending {
                        Text("Memory learning is scheduled for idle time.").foregroundStyle(.secondary)
                    } else if linked.isEmpty {
                        Text("Analyzed. No new durable personal information to remember.").foregroundStyle(.secondary)
                    } else {
                        Text("Personal memory updated automatically.").foregroundStyle(.secondary)
                    }
                    MemoryAnalysisSourceView(analysis: analysis)
                } else if capture.lifecycle == .delivered || capture.lifecycle == .deliveryFailed {
                    Text("Saved input will be analyzed during idle time.").foregroundStyle(.secondary)
                }
                ForEach(linked) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink(entry.name) { MemoryDetailView(store: store, memoryID: entry.id) }.buttonStyle(.link)
                        Text(entry.status?.title ?? "Unavailable").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if linked.isEmpty && analysis == nil && capture.lifecycle != .delivered && capture.lifecycle != .deliveryFailed {
                    Text("No personal memory learned from this input.").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("Personal Memory", systemImage: "person.text.rectangle") }
        .onAppear { try? store.load() }
    }
}

struct MemoryAnalysisSourceView: View {
    let analysis: MemoryAnalysisRecord

    var body: some View {
        DisclosureGroup("Text Used for Learning") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Saved final text").font(.caption).foregroundStyle(.secondary)
                Text(analysis.sourceText).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
    }
}
