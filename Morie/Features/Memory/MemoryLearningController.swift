import Combine
import Foundation

@MainActor
final class MemoryLearningController: ObservableObject {
    typealias Analyze = @Sendable (MemoryLearningInput) async throws -> [MemorySuggestion]

    @Published private(set) var analyzingCaptureID: UUID?
    @Published private(set) var isInputActive = true
    @Published private(set) var isEnabled: Bool
    @Published private(set) var message: String?

    private let store: MemoryStore
    private let analyze: Analyze
    private let canUseModel: @MainActor () -> Bool
    private let idleDelay: Duration
    private let batchSize: Int
    private var workerTask: Task<Void, Never>?
    private var workerID: UUID?
    private var nextMinimumDelay: Duration = .zero
    private var isRunning = false
    private var didReconcileAtStartup = false

    var isModelBusy: Bool { analyzingCaptureID != nil }

    init(
        store: MemoryStore,
        enabled: Bool = true,
        idleDelay: Duration = .seconds(30),
        batchSize: Int = 3,
        canUseModel: @escaping @MainActor () -> Bool = { true },
        analyze: @escaping Analyze = MemoryLearner.analyze
    ) {
        self.store = store
        isEnabled = enabled
        self.idleDelay = idleDelay
        self.batchSize = max(1, min(3, batchSize))
        self.canUseModel = canUseModel
        self.analyze = analyze
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        if !didReconcileAtStartup {
            do {
                try store.reconcileCompletedInputs(learningEnabled: isEnabled)
                didReconcileAtStartup = true
            } catch {
                message = "个人记忆队列恢复失败，将在下次启动时重试。"
            }
        }

        if isEnabled {
            schedule(minimumDelay: idleDelay)
        }
    }

    func stop() {
        isRunning = false
        if workerTask != nil {
            Diagnostics.recordMemory(
                "memory-learning-stop-cancel worker=\(workerLabel)"
            )
        }
        workerTask?.cancel()
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled

        if !enabled {
            nextMinimumDelay = .zero
            workerTask?.cancel()
            message = nil
            return
        }

        do {
            // Disabled-period Captures were already recorded as skipped, so
            // reconciliation cannot unexpectedly backfill them.
            try store.reconcileCompletedInputs(learningEnabled: true)
            message = nil
        } catch {
            message = "个人记忆队列恢复失败，将在下次启动时重试。"
        }

        if isRunning && !isInputActive && workerTask == nil {
            schedule(minimumDelay: idleDelay)
        }
    }

    func setInputActive(_ active: Bool) {
        isInputActive = active
        if active {
            if workerTask != nil {
                Diagnostics.recordMemory(
                    "memory-learning-input-preempt worker=\(workerLabel) capture=\(captureLabel)"
                )
            }
            workerTask?.cancel()
        } else if isEnabled && workerTask == nil {
            schedule(minimumDelay: idleDelay)
        } else if isEnabled {
            nextMinimumDelay = max(nextMinimumDelay, idleDelay)
        }
    }

    /// Called after one current-app Capture reaches a durable terminal state.
    /// Disabled input receives a durable skipped marker so it is never silently
    /// learned later just because the user turns Memory back on.
    func captureDidComplete(_ captureID: UUID) {
        do {
            try store.enqueueCompletedInput(
                captureID: captureID,
                learningEnabled: isEnabled
            )
            message = nil
        } catch {
            message = "个人记忆学习暂未排队，你的输入已保存。"
        }

        guard isEnabled, !isInputActive else { return }
        if workerTask == nil {
            schedule(minimumDelay: idleDelay)
        } else {
            nextMinimumDelay = max(nextMinimumDelay, idleDelay)
            workerTask?.cancel()
        }
    }

    /// Explicit History retry can re-analyze an earlier skipped source after
    /// Memory is enabled; ordinary re-enable never backfills it automatically.
    func retry(_ source: MemoryAnalysisSource) {
        guard isEnabled else {
            message = MemoryAnalysisFailure.disabled.message
            return
        }
        do {
            try store.retry(source)
            message = nil
            if !isInputActive {
                nextMinimumDelay = .zero
                if let workerTask {
                    workerTask.cancel()
                } else {
                    schedule()
                }
            }
        } catch {
            message = "无法安排个人记忆学习，你的输入已保存。"
        }
    }

    func waitForCurrentBatch() async {
        await workerTask?.value
    }

    private func schedule(minimumDelay: Duration = .zero) {
        guard isRunning,
              isEnabled,
              !isInputActive,
              workerTask == nil
        else { return }

        let nextAttemptAt: Date
        do {
            guard let date = try store.nextPendingAttemptDate() else { return }
            nextAttemptAt = date
        } catch {
            message = "个人记忆队列暂不可用，将在后续输入或重试时再次检查。"
            return
        }

        let retryDelay = Duration.seconds(
            max(0, nextAttemptAt.timeIntervalSinceNow)
        )
        let delay = max(minimumDelay, retryDelay)
        let id = UUID()
        workerID = id
        Diagnostics.recordMemory(
            "memory-learning-scheduled worker=\(String(id.uuidString.prefix(8)))"
        )

        workerTask = Task { [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
            } catch {
                self?.workerCancelledBeforeWake(id)
                self?.workerFinished(id)
                return
            }

            guard let self else { return }
            Diagnostics.recordMemory(
                "memory-learning-wake worker=\(String(id.uuidString.prefix(8)))"
            )
            await self.processBatch()
            self.workerFinished(id)
        }
    }

    private func processBatch() async {
        guard !Task.isCancelled,
              isEnabled,
              !isInputActive,
              canUseModel()
        else { return }

        do {
            let sources = try store.pendingSources(limit: batchSize)
            Diagnostics.recordMemory(
                "memory-learning-batch count=\(sources.count)"
            )

            for source in sources {
                try Task.checkCancellation()
                guard isEnabled,
                      !isInputActive,
                      canUseModel()
                else { return }

                let sourceLabel = String(
                    source.captureID.uuidString.prefix(8)
                )

                do {
                    Diagnostics.recordMemory(
                        "memory-learning-input-load \(sourceLabel)"
                    )
                    let input = try store.learningInput(for: source)
                    Diagnostics.recordMemory(
                        "memory-learning-input-ready \(sourceLabel)"
                    )
                    DevelopmentDiagnostics.text(
                        "MemoryLearning",
                        captureID: source.captureID,
                        label: "source",
                        input.source.text,
                        limit: 16_000
                    )
                    DevelopmentDiagnostics.list(
                        "MemoryLearning",
                        captureID: source.captureID,
                        label: "activeContext",
                        input.context.map {
                            "\($0.name) | kind=\($0.kind.rawValue) | scope=\($0.scope.rawValue) | notes=\($0.notes)"
                        },
                        limit: 32
                    )
                    DevelopmentDiagnostics.list(
                        "MemoryLearning",
                        captureID: source.captureID,
                        label: "blockedContext",
                        input.blocked.map {
                            "\($0.name) | kind=\($0.kind.rawValue) | notes=\($0.notes)"
                        },
                        limit: 32
                    )
                    analyzingCaptureID = source.captureID
                    Diagnostics.recordMemory(
                        "memory-learning-start \(sourceLabel)"
                    )

                    let suggestions = try await analyze(input)
                    Diagnostics.recordMemory(
                        "memory-learning-model-finish \(sourceLabel)"
                    )
                    DevelopmentDiagnostics.list(
                        "MemoryLearning",
                        captureID: source.captureID,
                        label: "suggestions",
                        suggestions.map {
                            "\($0.action.rawValue) | \($0.draft.kind.rawValue) | \($0.draft.scope.rawValue) | \($0.draft.name) | notes=\($0.draft.notes) | evidence=\($0.evidence) | confidence=\($0.confidence) | existingID=\($0.existingMemoryID?.uuidString ?? "none")"
                        },
                        limit: 8
                    )
                    try Task.checkCancellation()
                    guard isEnabled, !isInputActive else {
                        throw CancellationError()
                    }

                    try store.apply(suggestions, from: input)
                    Diagnostics.recordMemory(
                        "memory-learning-commit \(sourceLabel)"
                    )
                    message = nil
                } catch {
                    if Task.isCancelled || error is CancellationError {
                        Diagnostics.recordMemory(
                            "memory-learning-cancelled \(sourceLabel)"
                        )
                        throw CancellationError()
                    }

                    let failure: MemoryAnalysisFailure
                    switch error as? MemoryStore.StoreError {
                    case .sourceChanged, .sourceUnavailable, .sourceNotReady:
                        failure = .sourceChanged
                    default:
                        failure = (error as? MemoryAnalysisFailure)
                            ?? .generationFailed
                    }
                    DevelopmentDiagnostics.record(
                        "MemoryLearning",
                        captureID: source.captureID,
                        level: .warning,
                        "failed; mappedFailure=\(failure.rawValue); errorType=\(DevelopmentDiagnostics.errorType(error))"
                    )
                    try store.recordFailure(failure, for: source)
                    message = failure.message
                }

                analyzingCaptureID = nil
            }
        } catch {
            if !Task.isCancelled && !(error is CancellationError) {
                message = "个人记忆学习未能完成，将在空闲时自动重试。"
            }
        }
    }

    private func workerCancelledBeforeWake(_ id: UUID) {
        guard workerID == id else { return }
        Diagnostics.recordMemory(
            "memory-learning-cancelled-before-wake worker=\(String(id.uuidString.prefix(8)))"
        )
    }

    private func workerFinished(_ id: UUID) {
        guard workerID == id else { return }
        analyzingCaptureID = nil
        workerTask = nil
        workerID = nil

        Diagnostics.recordMemory(
            "memory-learning-worker-finished worker=\(String(id.uuidString.prefix(8)))"
        )

        let minimumDelay = nextMinimumDelay
        nextMinimumDelay = .zero
        schedule(minimumDelay: minimumDelay)
    }

    private var workerLabel: String {
        workerID.map { String($0.uuidString.prefix(8)) } ?? "none"
    }

    private var captureLabel: String {
        analyzingCaptureID.map {
            String($0.uuidString.prefix(8))
        } ?? "none"
    }
}
