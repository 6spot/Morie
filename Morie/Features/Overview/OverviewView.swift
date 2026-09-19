import SwiftData
import SwiftUI

struct OverviewMetrics {
    let recognizedCharacters: Int
    let successfulInputs: Int
    let currentAppAttempts: Int
    let failedInputs: Int
    let averageRefinementSeconds: Double?
    let refinementSamples: Int

    init(captures: [CaptureRecord]) {
        recognizedCharacters = captures.reduce(0) { $0 + $1.recognizedText.count }

        let currentApp = captures.filter {
            $0.deliveryModeRawValue == CaptureDeliveryMode.currentApp.rawValue
                && [.delivered, .deliveryFailed, .failed].contains($0.lifecycle)
        }
        currentAppAttempts = currentApp.count
        successfulInputs = currentApp.filter { $0.lifecycle == .delivered }.count
        failedInputs = currentApp.filter {
            $0.lifecycle == .deliveryFailed || $0.lifecycle == .failed
        }.count

        let durations = captures.compactMap(\.refinement?.durationSeconds).filter { $0 >= 0 }
        refinementSamples = durations.count
        averageRefinementSeconds = durations.isEmpty
            ? nil
            : durations.reduce(0, +) / Double(durations.count)
    }

    var failureRate: Double? {
        guard currentAppAttempts > 0 else { return nil }
        return Double(failedInputs) / Double(currentAppAttempts)
    }
}

struct OverviewView: View {
    @ObservedObject var controller: AppController
    @Query private var captures: [CaptureRecord]

    init(controller: AppController) {
        self.controller = controller
        let capturing = CaptureLifecycle.capturing.rawValue
        _captures = Query(
            filter: #Predicate<CaptureRecord> { $0.lifecycleRawValue != capturing },
            sort: [SortDescriptor(\.createdAt, order: .reverse)]
        )
    }

    private var metrics: OverviewMetrics {
        OverviewMetrics(captures: captures)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("总览")
                        .font(.largeTitle.bold())
                    Text("查看 Morie 的本地使用情况和当前实际使用的模型。")
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    metricCard(
                        title: "累计识别字符",
                        value: metrics.recognizedCharacters.formatted(),
                        detail: "\(captures.count.formatted()) 条已完成记录",
                        systemImage: "textformat"
                    )
                    metricCard(
                        title: "成功输入",
                        value: metrics.successfulInputs.formatted(),
                        detail: "已送达当前应用",
                        systemImage: "text.cursor"
                    )
                    metricCard(
                        title: "输入失败率",
                        value: percent(metrics.failureRate),
                        detail: metrics.currentAppAttempts == 0
                            ? "暂无可统计的当前应用输入"
                            : "\(metrics.failedInputs) / \(metrics.currentAppAttempts) 次",
                        systemImage: "exclamationmark.triangle"
                    )
                    metricCard(
                        title: "平均润色耗时",
                        value: duration(metrics.averageRefinementSeconds),
                        detail: metrics.refinementSamples == 0
                            ? "暂无润色耗时样本"
                            : "\(metrics.refinementSamples) 次润色样本",
                        systemImage: "wand.and.stars"
                    )
                }

                Text("“输入失败率”只统计 Morie 的输入流程是否成功，不等同于语音识别失误率。当前还没有足够的用户纠错真值样本，因此暂不计算可能误导的 ASR 错误率。")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                GroupBox {
                    VStack(spacing: 0) {
                        modelRow(
                            title: "语音识别",
                            name: controller.speechBackend?.displayName ?? "正在准备…",
                            detail: speechDetail,
                            status: speechStatus
                        )

                        Divider()
                            .padding(.vertical, 12)

                        modelRow(
                            title: "输入润色",
                            name: controller.refinementModelName,
                            detail: controller.refinementModelDetail,
                            status: controller.refinementModelStatusTitle
                        )
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                } label: {
                    Label("当前模型", systemImage: "cpu")
                }

                Text("模型状态来自当前运行实例。语音识别发生回退时，这里会直接显示 DictationTranscriber 和“回退”，而不是仍然显示首选模型。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("总览")
    }

    private var speechDetail: String {
        guard let backend = controller.speechBackend else {
            return "等待 Speech 资源准备完成"
        }
        return "\(backend.localeIdentifier) · Apple 本机"
    }

    private var speechStatus: String {
        guard let backend = controller.speechBackend else {
            return controller.isBootstrapping ? "准备中" : "未就绪"
        }
        return backend.isFallback ? "回退" : "首选"
    }

    private func metricCard(
        title: String,
        value: String,
        detail: String,
        systemImage: String
    ) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(value)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        } label: {
            Label(title, systemImage: systemImage)
        }
    }

    private func modelRow(
        title: String,
        name: String,
        detail: String,
        status: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(name)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(status)
                .font(.callout.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(1)))
    }

    private func duration(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(2)))) 秒"
    }
}
