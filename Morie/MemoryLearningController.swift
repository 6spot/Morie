import Combine
import Foundation

@MainActor
final class MemoryLearningController: ObservableObject {
    typealias Analyze = @Sendable (MemoryLearningInput) async throws -> [MemorySuggestion]

    @Published private(set) var analyzingCaptureID: UUID?
    @Published private(set) var isInputActive = true
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
        store: MemoryStore, idleDelay: Duration = .seconds(30), batchSize: Int = 3,
        canUseModel: @escaping @MainActor () -> Bool = { true },
        analyze: @escaping Analyze = MemoryLearner.analyze
    ) {
        self.store = store
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
                try store.reconcileCompletedInputs()
                didReconcileAtStartup = true
            } catch {
                message = "个人记忆队列恢复失败，将在下次启动时重试。"
            }
        }

        schedule(minimumDelay: idleDelay)
    }

    func stop() {
        isRunning = false
        workerTask?.cancel()
    }

    func setInputActive(_ active: Bool) {
        isInputActive = active
        if active {
            workerTask?.cancel()
        } else if workerTask == nil {
            schedule(minimumDelay: idleDelay)
        } else {
            nextMinimumDelay = max(nextMinimumDelay, idleDelay)
        }
    }

    /// Called when one Capture reaches a durable terminal delivery state.
    /// This is the normal enqueue path; it avoids rescanning the entire Capture history.
    func captureDidComplete(_ captureID: UUID) {
        do {
            try store.enqueueCompletedInput(captureID: captureID)
            message = nil
        } catch {
            message = "个人记忆学习暂未排队，你的输入已保存。"
        }

        if !isInputActive {
            if workerTask == nil {
                schedule(minimumDelay: idleDelay)
            } else {
                nextMinimumDelay = max(nextMinimumDelay, idleDelay)
                workerTask?.cancel()
            }
        }
    }

    /// Optional explicit retry; ordinary input uses the same durable queue automatically.
    func retry(_ source: MemoryAnalysisSource) {
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

    // The input path never awaits this. Tests/shutdown can observe draining model work.
    func waitForCurrentBatch() async { await workerTask?.value }

    private func schedule(minimumDelay: Duration = .zero) {
        guard isRunning, !isInputActive, workerTask == nil else { return }

        let nextAttemptAt: Date
        do {
            guard let date = try store.nextPendingAttemptDate() else { return }
            nextAttemptAt = date
        } catch {
            message = "个人记忆队列暂不可用，将在后续输入或重试时再次检查。"
            return
        }

        let retryDelay = Duration.seconds(max(0, nextAttemptAt.timeIntervalSinceNow))
        let delay = max(minimumDelay, retryDelay)
        let id = UUID()
        workerID = id
        workerTask = Task { [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
                try Task.checkCancellation()
            } catch {
                self?.workerFinished(id)
                return
            }

            guard let self else { return }
            await self.processBatch()
            self.workerFinished(id)
        }
    }

    private func processBatch() async {
        guard !Task.isCancelled, !isInputActive, canUseModel() else { return }
        do {
            let sources = try store.pendingSources(limit: batchSize)
            for source in sources {
                try Task.checkCancellation()
                guard !isInputActive, canUseModel() else { return }
                do {
                    let input = try store.learningInput(for: source)
                    analyzingCaptureID = source.captureID
                    let suggestions = try await analyze(input)
                    try Task.checkCancellation()
                    guard !isInputActive else { throw CancellationError() }
                    try store.apply(suggestions, from: input)
                    message = nil
                } catch {
                    if Task.isCancelled || error is CancellationError { throw CancellationError() }
                    let failure: MemoryAnalysisFailure
                    switch error as? MemoryStore.StoreError {
                    case .sourceChanged, .sourceUnavailable, .sourceNotReady: failure = .sourceChanged
                    default: failure = (error as? MemoryAnalysisFailure) ?? .generationFailed
                    }
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

    private func workerFinished(_ id: UUID) {
        guard workerID == id else { return }
        analyzingCaptureID = nil
        workerTask = nil
        workerID = nil
        let minimumDelay = nextMinimumDelay
        nextMinimumDelay = .zero
        schedule(minimumDelay: minimumDelay)
    }
}
