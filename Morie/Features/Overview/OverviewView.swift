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
    @ObservedObject private var capabilities: AppCapabilityController
    @ObservedObject private var preferences: AppPreferencesController
    @ObservedObject private var refinementModels: RefinementModelController
    @ObservedObject private var applicationContextInspector: ApplicationContextInspectionStore

    private let buildIdentity = AppBuildIdentity.current

    @Environment(\.modelContext) private var modelContext
    @Binding private var metricsSnapshot: OverviewMetricsSnapshot?
    @State private var metricsError: String?

    init(
        controller: AppController,
        metricsSnapshot: Binding<OverviewMetricsSnapshot?>
    ) {
        _capabilities = ObservedObject(
            wrappedValue: controller.capabilities
        )
        _preferences = ObservedObject(wrappedValue: controller.preferences)
        _refinementModels = ObservedObject(
            wrappedValue: controller.refinementModels
        )
        _applicationContextInspector = ObservedObject(
            wrappedValue: controller.applicationContextInspector
        )
        _metricsSnapshot = metricsSnapshot
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            buildSection
            Divider()
            usageSection
            Divider()
            modelSection
            if DevelopmentDiagnostics.isEnabled {
                Divider()
                applicationContextSection
            }
        }
        .frame(maxWidth: 820, alignment: .topLeading)
        .navigationTitle("总览")
        .navigationSubtitle("本地使用情况与当前运行状态")
        .task {
            await refreshMetricsIfNeeded()
        }
    }

    private var buildSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("运行版本")
                .font(.headline)

            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text("Morie \(buildIdentity.version)")
                    .font(.title3)
                    .bold()

                Text("Build \(buildIdentity.build)")
                    .foregroundStyle(.secondary)

                Text(buildIdentity.commitDisplay)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)

                Spacer(minLength: 16)

                if let branch = buildIdentity.branch {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(buildIdentity.configuration)
                    .font(.caption)
                    .foregroundStyle(
                        DevelopmentDiagnostics.isEnabled
                            ? .orange
                            : .secondary
                    )
            }

            Text(
                DevelopmentDiagnostics.isEnabled
                    ? "Git Commit 会在每次构建时写入 App；带 * 表示构建时工作区存在未提交改动。当前为开发构建，诊断日志可能包含语音正文、页面上下文和模型输入输出，请勿把日志公开上传。"
                    : "Git Commit 会在每次构建时写入 App；带 * 表示构建时工作区存在未提交改动。"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var applicationContextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Application Context 调试")
                .font(.headline)

            if let snapshot = applicationContextInspector.latest {
                HStack(spacing: 16) {
                    Text(snapshot.application.name ?? "未知应用")
                        .bold()
                    Text(snapshot.captureLabel)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(
                        snapshot.capturedAt.formatted(
                            .dateTime
                                .locale(Locale(identifier: "zh-Hans"))
                                .hour()
                                .minute()
                                .second()
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Spacer(minLength: 16)
                }

                Grid(
                    alignment: .leading,
                    horizontalSpacing: 24,
                    verticalSpacing: 8
                ) {
                    GridRow {
                        Text("上下文字符")
                            .foregroundStyle(.secondary)
                        Text(
                            "selected \(snapshot.selectedCharacterCount) · focused \(snapshot.focusedCharacterCount) · nearby \(snapshot.nearbyCharacterCount)"
                        )
                        .monospacedDigit()
                    }

                    GridRow {
                        Text("Speech hints")
                            .foregroundStyle(.secondary)
                        Text(
                            "Dictionary \(snapshot.dictionaryHintCount) + Application \(snapshot.hints.count) → \(snapshot.contextualHintCount)"
                        )
                        .monospacedDigit()
                    }

                    ForEach(ApplicationContextHintSource.allCases, id: \.self) { source in
                        let values = snapshot.hints
                            .filter { $0.source == source }
                            .map(\.value)

                        if !values.isEmpty {
                            GridRow {
                                Text(source.title)
                                    .foregroundStyle(.secondary)
                                Text(values.joined(separator: " · "))
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("本次原始上下文预览")
                        .font(.subheadline)
                        .bold()

                    contextPreviewRow(
                        title: "selected",
                        text: snapshot.selectedPreview
                    )
                    contextPreviewRow(
                        title: "focused",
                        text: snapshot.focusedPreview
                    )
                    contextPreviewRow(
                        title: "nearby",
                        text: snapshot.nearbyPreview
                    )
                }

                Text("这里只显示最近一次 Capture 的临时词汇决策与原始上下文预览；不会写入历史、Capture 数据库或个人记忆。当前为开发构建，原始上下文也会写入本机 Dev 诊断日志用于排查。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("完成一次语音输入后，这里会显示本次实际送给 Apple Speech 的 Application Context 临时词。")
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func contextPreviewRow(
        title: String,
        text: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: 64, alignment: .leading)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Text(text ?? "—")
                .font(.caption)
                .textSelection(.enabled)
                .foregroundStyle(text == nil ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("使用情况")
                .font(.headline)

            if let metrics = metricsSnapshot?.metrics {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 40,
                    verticalSpacing: 16
                ) {
                    GridRow {
                        metric(
                            title: "累计识别字符",
                            value: metrics.recognizedCharacters.formatted()
                        )
                        metric(
                            title: "已完成记录",
                            value: metrics.totalCaptures.formatted()
                        )
                    }

                    GridRow {
                        metric(
                            title: "成功输入",
                            value: metrics.successfulInputs.formatted()
                        )
                        metric(
                            title: "输入失败率",
                            value: percent(metrics.failureRate)
                        )
                    }

                    GridRow {
                        metric(
                            title: "平均润色耗时",
                            value: duration(metrics.averageRefinementSeconds)
                        )
                    }
                }

                Text(
                    "输入失败率只统计 Morie 是否成功将文字送入当前应用，不等同于语音识别错误率。"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
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
    }

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("当前模型")
                .font(.headline)

            modelRow(
                title: "语音识别",
                name:
                    capabilities.speechBackend?.displayName
                    ?? "正在准备…",
                detail: speechDetail,
                status: speechStatus
            )

            Divider()

            modelRow(
                title: "输入润色",
                name: refinementModels.modelName,
                detail: refinementModels.modelDetail,
                status:
                    refinementModels.modelStatusTitle(
                        inputRefinementEnabled:
                            preferences.inputRefinementEnabled
                    )
            )

            Text(
                "这里显示当前运行实例实际使用的后端；发生回退时会直接显示回退后的模型。"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func metric(
        title: String,
        value: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title2)
                .monospacedDigit()
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                    .bold()
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
        guard let backend = capabilities.speechBackend else {
            return "等待 Speech 资源准备完成"
        }
        return "\(backend.localeIdentifier) · Apple 本机"
    }

    private var speechStatus: String {
        guard let backend = capabilities.speechBackend else {
            return capabilities.isBootstrapping ? "准备中" : "未就绪"
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
