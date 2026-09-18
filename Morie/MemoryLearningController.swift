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
    private var isRunning = false

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

    func start() { isRunning = true; schedule() }

    func stop() { isRunning = false; workerTask?.cancel() }

    func setInputActive(_ active: Bool) {
        isInputActive = active
        if active { workerTask?.cancel() }
        else { schedule() }
    }

    /// Optional explicit retry; ordinary input uses the same durable queue automatically.
    func retry(_ source: MemoryAnalysisSource) {
        do { try store.retry(source); message = nil; schedule() }
        catch { message = "Memory learning could not be scheduled. Your input is saved." }
    }

    // The input path never awaits this. Tests/shutdown can observe draining model work.
    func waitForCurrentBatch() async { await workerTask?.value }

    private func schedule() {
        guard isRunning, !isInputActive, workerTask == nil else { return }
        workerTask = Task { [weak self, idleDelay] in
            do { try await Task.sleep(for: idleDelay) }
            catch { self?.workerFinished(); return }
            guard let self else { return }
            await self.processBatch()
            self.workerFinished()
        }
    }

    private func processBatch() async {
        guard !Task.isCancelled, !isInputActive, canUseModel() else { return }
        do {
            try store.enqueueCompletedInputs()
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
                message = "Memory learning could not finish. Saved input will be retried during idle time."
            }
        }
    }

    private func workerFinished() {
        analyzingCaptureID = nil
        workerTask = nil
        schedule()
    }
}
