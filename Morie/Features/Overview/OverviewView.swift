import Observation
import SwiftData
import SwiftUI

struct OverviewMetrics: Equatable {
    private(set) var totalCaptures = 0
    private(set) var recognizedCharacters = 0
    private(set) var successfulInputs = 0
    private(set) var currentAppAttempts = 0
    private(set) var failedInputs = 0
    private(set) var refinementSamples = 0
    private var refinementDurationTotal = 0.0

    init() {}

    init(captures: [CaptureRecord]) {
        for capture in captures {
            accumulate(capture)
        }
    }

    mutating func accumulate(_ capture: CaptureRecord) {
        totalCaptures += 1
        recognizedCharacters += capture.recognizedText.count

        if capture.deliveryModeRawValue
            == CaptureDeliveryMode.currentApp.rawValue,
           [.delivered, .deliveryFailed, .failed].contains(capture.lifecycle) {
            currentAppAttempts += 1

            switch capture.lifecycle {
            case .delivered:
                successfulInputs += 1
            case .deliveryFailed, .failed:
                failedInputs += 1
            default:
                break
            }
        }

        if let duration = capture.refinement?.durationSeconds,
           duration >= 0 {
            refinementSamples += 1
            refinementDurationTotal += duration
        }
    }

    var averageRefinementSeconds: Double? {
        guard refinementSamples > 0 else { return nil }
        return refinementDurationTotal / Double(refinementSamples)
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
@Observable
final class OverviewPageState {
    var metricsSnapshot: OverviewMetricsSnapshot?
}


@MainActor
struct OverviewView: View {
    @ObservedObject private var capabilities: AppCapabilityController
    @ObservedObject private var preferences: AppPreferencesController
    @ObservedObject private var refinementModels: RefinementModelController
    @ObservedObject private var setup: PermissionSetupController
    @ObservedObject private var applicationContextInspector: ApplicationContextInspectionStore

    private let buildIdentity = AppBuildIdentity.current

    @Environment(\.modelContext) private var modelContext
    @Bindable var state: OverviewPageState
    @State private var metricsError: String?

    init(
        controller: AppController,
        state: OverviewPageState
    ) {
        _capabilities = ObservedObject(
            wrappedValue: controller.capabilities
        )
        _preferences = ObservedObject(wrappedValue: controller.preferences)
        _refinementModels = ObservedObject(
            wrappedValue: controller.refinementModels
        )
        _setup = ObservedObject(wrappedValue: controller.setup)
        _applicationContextInspector = ObservedObject(
            wrappedValue: controller.applicationContextInspector
        )
        self.state = state
    }

    var body: some View {
        ControlCenterPage {
            statusSection

            Divider()

            usageSection

            if DevelopmentDiagnostics.isEnabled {
                Divider()
                developmentSection
            }
        }
        .task {
            await refreshMetricsIfNeeded()
        }
    }

    private var statusSection: some View {
        ControlCenterSectionBlock(
            "当前状态",
            subtitle: "这里显示 Morie 当前真正使用的能力和模型，而不是配置中预期使用的值。"
        ) {
            LabeledContent("设备与权限") {
                Text(setup.isReady ? "已就绪" : "需要处理")
                    .foregroundStyle(setup.isReady ? .secondary : .primary)
            }

            LabeledContent("语音识别") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(
                        capabilities.speechBackend?.displayName
                            ?? "正在准备…"
                    )
                    Text("\(speechDetail) · \(speechStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            LabeledContent("输入润色") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(refinementModels.modelName)
                    Text(
                        refinementModels.modelStatusTitle(
                            inputRefinementEnabled:
                                preferences.inputRefinementEnabled
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var developmentSection: some View {
        ControlCenterSectionBlock(
            "开发信息",
            subtitle: "仅开发构建显示。用于确认当前构建与最近一次 Application Context。"
        ) {
            LabeledContent(
                "版本",
                value: "Morie \(buildIdentity.version) (\(buildIdentity.build))"
            )

            LabeledContent("Commit") {
                Text(buildIdentity.commitDisplay)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            }

            if let branch = buildIdentity.branch {
                LabeledContent("Branch", value: branch)
            }

            LabeledContent(
                "构建配置",
                value: buildIdentity.configuration
            )

            if let snapshot = applicationContextInspector.latest {
                Divider()

                LabeledContent(
                    "最近应用",
                    value: snapshot.application.name ?? "未知应用"
                )

                LabeledContent(
                    "上下文字符",
                    value:
                        "selected \(snapshot.selectedCharacterCount) · cursor \(snapshot.cursorCharacterCount)"
                )

                LabeledContent(
                    "Speech hints",
                    value:
                        "Dictionary \(snapshot.dictionaryHintCount) + Application \(snapshot.hints.count) → \(snapshot.contextualHintCount)"
                )

                if let selected = snapshot.selectedPreview,
                   !selected.isEmpty {
                    contextPreviewRow(
                        title: "selected",
                        text: selected
                    )
                }

                if let cursor = snapshot.cursorPreview,
                   !cursor.isEmpty {
                    contextPreviewRow(
                        title: "cursor",
                        text: cursor
                    )
                }
            } else {
                Text("完成一次语音输入后，这里会显示最近一次 Application Context 摘要。")
                    .foregroundStyle(.secondary)
            }

            Text(
                "开发诊断可能包含语音正文、页面上下文和模型输入输出，请勿公开上传。"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private func contextPreviewRow(
        title: String,
        text: String?
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .frame(width: 64, alignment: .leading)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Text(text ?? "—")
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var usageSection: some View {
        let metrics = state.metricsSnapshot?.metrics
        let isLoading = state.metricsSnapshot == nil && metricsError == nil

        return ControlCenterSectionBlock(
            "使用情况",
            subtitle: "这些统计只描述 Morie 的本地输入与处理情况。"
        ) {
            HStack(spacing: 24) {
                metric(
                    title: "累计识别字符",
                    value: metrics?.recognizedCharacters.formatted() ?? "—"
                )
                metric(
                    title: "已完成记录",
                    value: metrics?.totalCaptures.formatted() ?? "—"
                )
                metric(
                    title: "成功输入",
                    value: metrics?.successfulInputs.formatted() ?? "—"
                )
                metric(
                    title: "输入失败率",
                    value: percent(metrics?.failureRate)
                )
                metric(
                    title: "平均润色耗时",
                    value: duration(metrics?.averageRefinementSeconds)
                )
            }
            .overlay(alignment: .topTrailing) {
                ProgressView()
                    .controlSize(.small)
                    .opacity(isLoading ? 1 : 0)
            }

            if let metricsError {
                Label(
                    metricsError,
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.secondary)
            } else {
                Text(
                    "输入失败率只统计 Morie 是否成功将文字送入当前应用，不等同于语音识别错误率。"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
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

    private func refreshMetricsIfNeeded() async {
        await Task.yield()

        do {
            let capturing = CaptureLifecycle.capturing.rawValue
            var descriptor = FetchDescriptor<CaptureRecord>(
                predicate: #Predicate {
                    $0.lifecycleRawValue != capturing
                }
            )
            descriptor.propertiesToFetch = [
                \CaptureRecord.lifecycleRawValue,
                \CaptureRecord.deliveryModeRawValue,
                \CaptureRecord.recognizedText,
                \CaptureRecord.refinement
            ]

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
            latestDescriptor.propertiesToFetch = [
                \CaptureRecord.updatedAt
            ]

            let latestUpdatedAt = try modelContext
                .fetch(latestDescriptor)
                .first?
                .updatedAt

            if let cached = state.metricsSnapshot,
               cached.recordCount == recordCount,
               cached.latestUpdatedAt == latestUpdatedAt {
                metricsError = nil
                return
            }

            if DevelopmentDiagnostics.isEnabled {
                Diagnostics.recordMemory("overview-metrics-before")
            }

            var metrics = OverviewMetrics()
            try modelContext.enumerate(
                descriptor,
                batchSize: 128,
                allowEscapingMutations: false
            ) { capture in
                metrics.accumulate(capture)
            }

            state.metricsSnapshot = OverviewMetricsSnapshot(
                metrics: metrics,
                recordCount: recordCount,
                latestUpdatedAt: latestUpdatedAt
            )
            metricsError = nil

            if DevelopmentDiagnostics.isEnabled {
                Diagnostics.recordMemory("overview-metrics-after")
            }
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
