import Foundation

/// The Capture-first boundary between recognition and delivery. Model output is never returned before save.
@MainActor
final class CapturePersonalizer {
    static let enabledDefaultsKey = "inputRefinementEnabled"

    private let store: CaptureStore
    private let memory: MemoryStore
    private let runner: InputRefinementRunner

    var isModelBusy: Bool { runner.isBusy }

    init(store: CaptureStore, memory: MemoryStore, runner: InputRefinementRunner = InputRefinementRunner()) {
        self.store = store
        self.memory = memory
        self.runner = runner
    }

    func refine(_ captureID: UUID, enabled: Bool, otherModelWorkActive: Bool = false) async throws -> String {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        var skip: RefinementReason? = enabled ? nil : .disabled
        if enabled && (otherModelWorkActive || runner.isBusy) { skip = .modelBusy }
        var context: [MemoryContextMatch] = []
        if skip == nil {
            do {
                context = try memory.relevantContext(for: store.capture(captureID).finalText)
            } catch {
                skip = .contextUnavailable
            }
        }
        let input = try store.refinementInput(for: captureID, context: context)
        if let skip { return try keepOriginal(input, reason: skip, started: started) }

        do {
            try store.beginRefinement(input)
        } catch {
            return try keepOriginal(input, reason: .saveFailed, started: started)
        }
        do {
            let generation = try await runner.run(input)
            try Task.checkCancellation()
            try store.requireRefinementSource(input)

            switch generation {
            case .keptOriginal(let reason):
                return try keepOriginal(input, reason: reason, started: started)
            case .edits(let proposals):
                let current: [MemoryContextMatch]
                do {
                    current = try memory.relevantContext(for: input.text)
                } catch {
                    return try keepOriginal(input, reason: .contextUnavailable, started: started)
                }
                guard current == input.context else {
                    return try keepOriginal(input, reason: .memoryChanged, started: started)
                }
                let result: ValidatedRefinement
                do {
                    result = try RefinementValidator.validate(proposals, for: input)
                } catch {
                    return try keepOriginal(input, reason: .invalidEdits, started: started)
                }
                do {
                    return try store.saveRefinement(input, result: result, durationSeconds: elapsed(since: started))
                } catch {
                    return try keepOriginal(input, reason: .saveFailed, started: started)
                }
            }
        } catch {
            // Also releases capture-only History actions; no model join is needed for cancellation.
            try? store.interruptRefinement(input)
            throw error
        }
    }

    private func keepOriginal(_ input: RefinementInput, reason: RefinementReason, started: ContinuousClock.Instant) throws -> String {
        try store.requireRefinementSource(input)
        do {
            return try store.saveRefinement(input, reason: reason, durationSeconds: elapsed(since: started))
        } catch {
            // saveRefinement rolls back. Verify the durable original again before returning it.
            try store.requireRefinementSource(input)
            Diagnostics.record("Refinement", "Could not save refinement metadata; using the durable original", level: .warning)
            return input.text
        }
    }

    private func elapsed(since start: ContinuousClock.Instant) -> Double {
        let value = (ContinuousClock.now - start).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
