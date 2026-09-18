import Foundation

/// The Capture-first boundary between recognition and delivery. Model output is never returned before save.
@MainActor
final class CapturePersonalizer {
    static let enabledDefaultsKey = "inputRefinementEnabled"

    private let store: CaptureStore
    private let memory: MemoryStore
    private let dictionary: DictionaryStore
    private let runner: InputRefinementRunner

    var isModelBusy: Bool { runner.isBusy }

    init(store: CaptureStore, memory: MemoryStore, dictionary: DictionaryStore, runner: InputRefinementRunner = InputRefinementRunner()) {
        self.store = store
        self.memory = memory
        self.dictionary = dictionary
        self.runner = runner
    }

    func refine(_ captureID: UUID, enabled: Bool, otherModelWorkActive: Bool = false) async throws -> String {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        var skip: RefinementReason? = enabled ? nil : .disabled
        if enabled && (otherModelWorkActive || runner.isBusy) { skip = .modelBusy }
        let source = try store.capture(captureID).finalText
        let dictionaryEntries = (try? dictionary.relevantEntries(for: source)) ?? []
        let prepared = DictionaryReplacer.replace(source, using: dictionaryEntries).text
        // Neither a missing personal profile nor retrieval failure disables day-one cleanup.
        let context = skip == nil ? ((try? memory.relevantContext(for: prepared)) ?? []) : []
        let input = try store.refinementInput(for: captureID, context: context, dictionary: dictionaryEntries)

        do {
            try store.beginRefinement(input)
        } catch {
            return try keepOriginal(input, reason: .saveFailed, started: started)
        }
        if let skip { return try keepOriginal(input, reason: skip, started: started) }
        do {
            let generation = try await runner.run(input)
            try Task.checkCancellation()
            try store.requireRefinementSource(input)

            guard (try? dictionary.relevantEntries(for: input.text)) == input.dictionary else {
                return try keepOriginal(input, reason: .dictionaryChanged, started: started)
            }
            switch generation {
            case .keptOriginal(let reason):
                return try keepOriginal(input, reason: reason, started: started)
            case .text(let text):
                let current = (try? memory.relevantContext(for: input.prepared.text)) ?? []
                guard current == input.context else {
                    return try keepOriginal(input, reason: .memoryChanged, started: started)
                }
                let result: ValidatedRefinement
                do {
                    result = try RefinementValidator.validate(text, for: input)
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
            let mayApplyDictionary = reason != .dictionaryChanged && reason != .saveFailed
                && (try? dictionary.relevantEntries(for: input.text)) == input.dictionary
            let result = mayApplyDictionary ? input.prepared : ValidatedRefinement(text: input.text, edits: [])
            return try store.saveRefinement(input, result: result, reason: reason, durationSeconds: elapsed(since: started))
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
