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
        recognizedCharacters = captures.reduce(0) {
            $0 + $1.recognizedText.count
        }

        let currentApp = captures.filter {
            $0.deliveryModeRawValue == CaptureDeliveryMode.currentApp.rawValue
                && [.delivered, .deliveryFailed, .failed].contains($0.lifecycle)
        }
        currentAppAttempts = currentApp.count
        successfulInputs = currentApp.filter {
            $0.lifecycle == .delivered
        }.count
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
    let controller: AppController
    @ObservedObject private var runtime: AppRuntimeController
    @ObservedObject private var preferences: AppPreferencesController
    @ObservedObject private var refinementModels: RefinementModelController

    @Environment(\.modelContext) private var modelContext
    @Binding private var metricsSnapshot: OverviewMetricsSnapshot?
    @State private var metricsError: String?

    init(
        controller: AppController,
        metricsSnapshot: Binding<OverviewMetricsSnapshot?>
    ) {
        self.controller = controller
        _runtime = ObservedObject(wrappedValue: controller.runtime)
        _preferences = ObservedObject(wrappedValue: controller.preferences)
        _refinementModels = ObservedObject(
            wrappedValue: controller.refinementModels
        )
        _metricsSnapshot = metricsSnapshot
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: ControlCenterMetrics.sectionSpacing
        ) {
            Text("查看 Morie 的本地使用情况和当前运行状态。")
                .foregroundStyle(.secondary)

            ControlCenterGroup(
                "使用情况",
                footer: "输入失败率只统计 Morie 是否成功将文字送入当前应用，不等同于语音识别错误率。"
            ) {
                if let metrics = metricsSnapshot?.metrics {
                    infoRow(
                        title: "累计识别字符",
                        value: metrics.recognizedCharacters.formatted()
                    )
                    Divider()
                    infoRow(
                        title: "已完成记录",
                        value: metrics.totalCaptures.formatted()
                    )
                    Divider()
                    infoRow(
                        title: "成功输入",
                        value: metrics.successfulInputs.formatted()
                    )
                    Divider()
                    infoRow(
                        title: "输入失败率",
                        value: percent(metrics.failureRate)
                    )
                    Divider()
                    infoRow(
                        title: "平均润色耗时",
                        value: duration(metrics.averageRefinementSeconds)
                    )
                } else if let metricsError {
                    Label(
                        metricsError,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ProgressView("正在读取使用统计…")
                }
            }

            ControlCenterGroup(
                "当前模型",
                footer: "这里显示当前运行实例实际使用的后端；发生回退时会直接显示回退后的模型。"
            ) {
                modelRow(
                    title: "语音识别",
                    name: runtime.speechBackend?.displayName ?? "正在准备…",
                    detail: speechDetail,
                    status: speechStatus
                )

                Divider()

                modelRow(
                    title: "输入润色",
                    name: refinementModels.modelName,
                    detail: refinementModels.modelDetail,
                    status: refinementModels.modelStatusTitle(
                        inputRefinementEnabled: preferences.inputRefinementEnabled
                    )
                )
            }
        }
        .navigationTitle("总览")
        .task {
            await refreshMetricsIfNeeded()
        }
    }

    private func infoRow(
        title: String,
        value: String
    ) -> some View {
        LabeledContent(title) {
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func modelRow(
        title: String,
        name: String,
        detail: String,
        status: String
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                Text(name)
                    .fontWeight(.medium)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Text(status)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshMetricsIfNeeded() async {
        await Task.yield()

        do {
            let capturing = CaptureLifecycle.capturing.rawValue
            let descriptor = FetchDescriptor<CaptureRecord>(
                predicate: #Predicate {
                    $0.lifecycleRawValue != capturing
                }
            )
            let recordCount = try modelContext.fetchCount(descriptor)

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

            let captures = try modelContext.fetch(descriptor)
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
        guard let backend = runtime.speechBackend else {
            return "等待 Speech 资源准备完成"
        }
        return "\(backend.localeIdentifier) · Apple 本机"
    }

    private var speechStatus: String {
        guard let backend = runtime.speechBackend else {
            return runtime.isBootstrapping ? "准备中" : "未就绪"
        }
        return backend.isFallback ? "回退" : "首选"
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
