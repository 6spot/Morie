import SwiftData
import SwiftUI

struct OverviewMetrics: Equatable {
    let totalCaptures: Int
    let recognizedCharacters: Int
    let successfulInputs: Int
    let currentAppAttempts: Int
    let failedInputs: Int
    let averageRefinementSeconds: Double?
    let refinementSamples: Int

    init(captures: [CaptureRecord]) {
        totalCaptures = captures.count
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

        let durations = captures
            .compactMap(\.refinement?.durationSeconds)
            .filter { $0 >= 0 }
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

struct OverviewMetricsSnapshot: Equatable {
    let metrics: OverviewMetrics
    let recordCount: Int
    let latestUpdatedAt: Date?
}

@MainActor
struct OverviewView: View {
    @ObservedObject var controller: AppController
    @ObservedObject private var refinementModels: RefinementModelController
    @Environment(\.modelContext) private var modelContext
    @Binding private var metricsSnapshot: OverviewMetricsSnapshot?
    @State private var metricsError: String?

    init(
        controller: AppController,
        metricsSnapshot: Binding<OverviewMetricsSnapshot?>
    ) {
        self.controller = controller
        _refinementModels = ObservedObject(wrappedValue: controller.refinementModels)
        _metricsSnapshot = metricsSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ControlCenterMetrics.sectionSpacing) {
            Text("查看 Morie 的本地使用情况和当前实际使用的模型。")
                .foregroundStyle(.secondary)

            ControlCenterSectionGroup(
                "使用情况",
                footer: "“输入失败率”只统计 Morie 的输入流程是否成功，不等同于语音识别失误率。当前还没有足够的用户纠错真值样本，因此暂不计算可能误导的 ASR 错误率。"
            ) {
                if let metrics = metricsSnapshot?.metrics {
                    LazyVGrid(
                        columns: [
                            GridItem(
                                .adaptive(minimum: 190, maximum: 280),
                                spacing: 12
                            )
                        ],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        metricCard(
                            title: "累计识别字符",
                            value: metrics.recognizedCharacters.formatted(),
                            detail: "\(metrics.totalCaptures.formatted()) 条已完成记录",
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
                } else if let metricsError {
                    Label(metricsError, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView("正在读取使用统计…")
                }
            }

            ControlCenterSectionGroup(
                "当前模型",
                footer: "模型状态来自当前运行实例。语音识别发生回退时，这里会直接显示 DictationTranscriber 和“回退”，而不是仍然显示首选模型。"
            ) {
                modelRow(
                    title: "语音识别",
                    name: controller.speechBackend?.displayName ?? "正在准备…",
                    detail: speechDetail,
                    status: speechStatus
                )

                Divider()

                modelRow(
                    title: "输入润色",
                    name: refinementModels.modelName,
                    detail: refinementModels.modelDetail,
                    status: refinementModels.modelStatusTitle(
                        inputRefinementEnabled: controller.inputRefinementEnabled
                    )
                )
            }
        }
        .navigationTitle("总览")
        .task {
            await refreshMetricsIfNeeded()
        }
    }

    private func refreshMetricsIfNeeded() async {
        await Task.yield()

        do {
            let capturing = CaptureLifecycle.capturing.rawValue
            let baseDescriptor = FetchDescriptor<CaptureRecord>(
                predicate: #Predicate {
                    $0.lifecycleRawValue != capturing
                }
            )
            let recordCount = try modelContext.fetchCount(baseDescriptor)

            var latestDescriptor = FetchDescriptor<CaptureRecord>(
                predicate: #Predicate {
                    $0.lifecycleRawValue != capturing
                },
                sortBy: [
                    SortDescriptor(\.updatedAt, order: .reverse)
                ]
            )
            latestDescriptor.fetchLimit = 1
            let latestUpdatedAt = try modelContext
                .fetch(latestDescriptor)
                .first?
                .updatedAt

            if let cached = metricsSnapshot,
               cached.recordCount == recordCount,
               cached.latestUpdatedAt == latestUpdatedAt {
                metricsError = nil
                return
            }

            let captures = try modelContext.fetch(baseDescriptor)
            metricsSnapshot = OverviewMetricsSnapshot(
                metrics: OverviewMetrics(captures: captures),
                recordCount: recordCount,
                latestUpdatedAt: latestUpdatedAt
            )
            metricsError = nil
        } catch {
            metricsError = "无法读取使用统计。"
        }
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
                    .font(
                        .system(
                            size: 28,
                            weight: .semibold,
                            design: .rounded
                        )
                    )
                    .contentTransition(.numericText())
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 72,
                alignment: .leading
            )
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
        return value.formatted(
            .percent.precision(.fractionLength(1))
        )
    }

    private func duration(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(value.formatted(.number.precision(.fractionLength(2)))) 秒"
    }
}
