import SwiftUI

struct CaptureMemorySection: View {
    @ObservedObject var store: MemoryStore
    @ObservedObject var controller: MemoryLearningController
    let capture: CaptureRecord

    private var analysis: MemoryAnalysisSnapshot? { store.analysis(for: MemoryAnalysisSource(capture: capture)) }
    private var linked: [MemoryRecord] { store.entries.filter { $0.sourceCaptureIDs.contains(capture.id) } }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if controller.analyzingCaptureID == capture.id {
                    ProgressView("正在从这次输入中学习…")
                } else if let analysis {
                    if let failure = analysis.failure {
                        Text(failure.message).foregroundStyle(.secondary)
                        if analysis.state == .skipped && failure != .disabled {
                            Button("重新学习个人记忆") { controller.retry(analysis.source) }
                                .disabled(controller.isInputActive || !controller.isEnabled)
                        }
                    } else if analysis.state == .pending {
                        Text("将在空闲时自动分析并学习个人记忆。").foregroundStyle(.secondary)
                    } else if linked.isEmpty {
                        Text("已完成分析，没有发现值得保留的新上下文。").foregroundStyle(.secondary)
                    } else {
                        Text("个人记忆已自动更新。").foregroundStyle(.secondary)
                    }
                    MemoryAnalysisSourceView(sourceText: analysis.sourceText)
                } else if capture.lifecycle == .delivered || capture.lifecycle == .deliveryFailed {
                    Text(controller.isEnabled ? "已保存的输入将在空闲时自动分析。" : "个人记忆已关闭，这次输入不会参与自动学习。").foregroundStyle(.secondary)
                }
                ForEach(linked) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        NavigationLink(entry.name) { MemoryDetailView(store: store, memoryID: entry.id) }.buttonStyle(.link)
                        Text(entry.status?.title ?? "不可用").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if linked.isEmpty && analysis == nil && capture.lifecycle != .delivered && capture.lifecycle != .deliveryFailed {
                    Text("这次输入尚未形成个人记忆。").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: { Label("个人记忆", systemImage: "person.text.rectangle") }
        .onAppear { try? store.load() }
    }
}

struct MemoryAnalysisSourceView: View {
    let sourceText: String

    var body: some View {
        DisclosureGroup("用于学习的文字") {
            VStack(alignment: .leading, spacing: 8) {
                Text("已保存的最终文字").font(.caption).foregroundStyle(.secondary)
                Text(sourceText).textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
    }
}
