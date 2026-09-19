import Foundation

/// The Capture-first boundary between recognition and delivery. Live state is validated here; History persistence is queued independently.
@MainActor
final class CapturePersonalizer {
    static let enabledDefaultsKey = "inputRefinementEnabled"
    private static let cleanupMemoryContextLimit = 4

    private let store: CaptureStore
    private let memory: MemoryStore
    private let dictionary: DictionaryStore
    private let expressionProfile: ExpressionProfileStore?
    private let runner: InputRefinementRunner

    var isModelBusy: Bool { runner.isBusy }

    init(
        store: CaptureStore,
        memory: MemoryStore,
        dictionary: DictionaryStore,
        expressionProfile: ExpressionProfileStore? = nil,
        runner: InputRefinementRunner = InputRefinementRunner()
    ) {
        self.store = store
        self.memory = memory
        self.dictionary = dictionary
        self.expressionProfile = expressionProfile
        self.runner = runner
    }

    func refine(
        _ captureID: UUID,
        enabled: Bool,
        expressionStyleEnabled: Bool = false,
        otherModelWorkActive: Bool = false
    ) async throws -> String {
        try Task.checkCancellation()
        let started = ContinuousClock.now
        var skip: RefinementReason? = enabled ? nil : .disabled
        if enabled && (otherModelWorkActive || runner.isBusy) { skip = .modelBusy }
        let source = try store.capture(captureID).finalText
        let dictionaryEntries = (try? dictionary.relevantEntries(for: source)) ?? []
        let correctionEntries = (try? dictionary.relevantConfirmedCorrections(for: source)) ?? []
        let corrected = DictionaryCorrections.apply(source, using: correctionEntries)
        let prepared = DictionarySpelling.normalize(corrected.text, using: dictionaryEntries).text
        // Neither a missing personal profile nor retrieval failure disables day-one cleanup.
        let context = skip == nil
            ? ((try? memory.relevantContext(for: prepared, limit: Self.cleanupMemoryContextLimit)) ?? [])
            : []
        let expressionStyle = skip == nil && expressionStyleEnabled
            ? ((try? expressionProfile?.directives()) ?? [])
            : []
        let input = try store.refinementInput(
            for: captureID,
            context: context,
            dictionary: dictionaryEntries,
            corrections: correctionEntries,
            expressionStyle: expressionStyle
        )

        do {
            try store.beginRefinement(input)
        } catch {
            Diagnostics.record(
                "Refinement",
                "Could not attach refinement metadata to the current Capture; continuing from live text",
                level: .warning
            )
            return input.prepared.text
        }
        if let skip { return try keepOriginal(input, reason: skip, started: started) }
        do {
            let generation = try await runner.run(input)
            try Task.checkCancellation()
            try store.requireRefinementSource(input)

            guard (try? dictionary.relevantEntries(for: input.text)) == input.dictionary,
                  (try? dictionary.relevantConfirmedCorrections(for: input.text)) == input.confirmedCorrections else {
                return try keepOriginal(input, reason: .dictionaryChanged, started: started)
            }
            switch generation {
            case .keptOriginal(let reason):
                return try keepOriginal(input, reason: reason, started: started)
            case .text(let text):
                let current = (try? memory.relevantContext(
                    for: input.prepared.text,
                    limit: Self.cleanupMemoryContextLimit
                )) ?? []
                guard current == input.context else {
                    return try keepOriginal(input, reason: .memoryChanged, started: started)
                }
                let currentStyle = expressionStyleEnabled
                    ? ((try? expressionProfile?.directives()) ?? [])
                    : []
                guard currentStyle == input.expressionStyle else {
                    return try keepOriginal(input, reason: .expressionStyleChanged, started: started)
                }
                let result: ValidatedRefinement
                do {
                    result = try ValidatedRefinement.accepting(text, for: input)
                } catch {
                    return try keepOriginal(input, reason: .invalidEdits, started: started)
                }
                do {
                    return try store.saveRefinement(input, result: result, durationSeconds: elapsed(since: started))
                } catch {
                    Diagnostics.record(
                        "Refinement",
                        "Refinement result became stale before it could attach to the live Capture; using dictionary-prepared text",
                        level: .warning
                    )
                    return input.prepared.text
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
                && (try? dictionary.relevantConfirmedCorrections(for: input.text)) == input.confirmedCorrections
            let result = mayApplyDictionary ? input.prepared : ValidatedRefinement(text: input.text, edits: [])
            return try store.saveRefinement(input, result: result, reason: reason, durationSeconds: elapsed(since: started))
        } catch {
            // The live Capture changed while attaching metadata. Do not make delivery wait for History bookkeeping.
            try store.requireRefinementSource(input)
            Diagnostics.record("Refinement", "Could not attach refinement metadata; using the live original", level: .warning)
            return input.text
        }
    }

    private func elapsed(since start: ContinuousClock.Instant) -> Double {
        let value = (ContinuousClock.now - start).components
        return Double(value.seconds) + Double(value.attoseconds) / 1e18
    }
}
