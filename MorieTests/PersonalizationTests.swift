import Foundation
import SwiftData
import XCTest

@MainActor
final class PersonalizationTests: XCTestCase {
    func testConfirmedAliasCorrectionPreservesNegationToneAndNumbers() throws {
        let input = request("嗯 今天不要发布 more e 2.0")
        let result = try RefinementValidator.validate([correction()], for: input)
        XCTAssertEqual(result.text, "嗯 今天不要发布 Morie 2.0")
        XCTAssertEqual(result.edits.first?.memoryID, input.context.first?.id)
    }

    func testLightCleanupKeepsWordsAndExistingPunctuation() throws {
        let input = request("okay  keep this")
        let result = try RefinementValidator.validate([
            RefinementProposal(original: input.text, replacement: "okay, keep this.")
        ], for: input)
        XCTAssertEqual(result.text, "okay, keep this.")
        XCTAssertNil(result.edits.first?.memoryID)
        XCTAssertEqual(try RefinementValidator.validate([], for: input).text, input.text)
    }

    func testCleanupCannotRemoveAcknowledgmentsNegationsOrAnswerTheUser() {
        let changes = [
            ("嗯 好的", "好的"), ("do not deploy", "deploy"),
            ("what should I do", "You should restart the app."),
            ("I guess we can try", "We will proceed."), ("OK", "Okay")
        ]
        for (original, replacement) in changes {
            XCTAssertThrowsError(try RefinementValidator.validate([
                RefinementProposal(original: original, replacement: replacement)
            ], for: request(original)))
        }
    }

    func testNumericAndTechnicalTokensCannotBeRewritten() {
        for original in ["3.14", "v2.0", "git status --short", "https://morie.app", "/tmp/morie",
                         "me@morie.app", "some_name", "`more e`", "echo more; exit", "a && b"] {
            XCTAssertThrowsError(try RefinementValidator.validate([
                RefinementProposal(original: original, replacement: original + ".")
            ], for: request(original)), original)
        }
        XCTAssertThrowsError(try RefinementValidator.validate([
            RefinementProposal(original: "more e", replacement: "Morie")
        ], for: request("`more e`")))
    }

    func testCleanupCannotMovePunctuationChangeToneOrMergeAcrossAnchorBoundaries() {
        let changes = [
            ("no, thanks", "no thanks,"), ("why?", "why?."), ("really!", "really."),
            ("hello world", "helloworld"), ("already", "al.ready"), ("line\nbreak", "line break")
        ]
        for (original, replacement) in changes {
            XCTAssertThrowsError(try RefinementValidator.validate([
                RefinementProposal(original: original, replacement: replacement)
            ], for: request(original)))
        }
        XCTAssertThrowsError(try RefinementValidator.validate([
            RefinementProposal(original: "hello ", replacement: "hello")
        ], for: request("hello world")))
        XCTAssertThrowsError(try RefinementValidator.validate([
            RefinementProposal(original: "more e ", replacement: "Morie")
        ], for: request("more e project")))
    }

    func testTerminologyMustBeConfirmedActiveAndMatchAWholeAlias() {
        for context in [[], request("more e", status: .archived).context,
                        request("more e", confirmed: false).context] {
            let input = RefinementInput(captureID: UUID(), text: "more e", context: context)
            XCTAssertThrowsError(try RefinementValidator.validate([correction()], for: input))
        }
        XCTAssertThrowsError(try RefinementValidator.validate([
            RefinementProposal(original: "more e", replacement: "Memory")
        ], for: request("more e")))
        XCTAssertThrowsError(try RefinementValidator.validate([correction()], for: request("more extra")))
    }

    func testEditsUseLiteralOccurrenceAndNeverOverlap() throws {
        let input = request("more e and more e")
        let result = try RefinementValidator.validate([
            RefinementProposal(original: "more e", replacement: "Morie", occurrence: 2)
        ], for: input)
        XCTAssertEqual(result.text, "more e and Morie")
        for edits in [
            [correction(), correction()],
            [RefinementProposal(original: "", replacement: "Morie")],
            [RefinementProposal(original: "more e", replacement: "Morie", occurrence: 0)],
            [RefinementProposal(original: "more e", replacement: "Morie", occurrence: 3)],
            [RefinementProposal(original: "missing", replacement: "Morie")],
            Array(repeating: correction(), count: 9)
        ] {
            XCTAssertThrowsError(try RefinementValidator.validate(edits, for: input))
        }
    }

    func testDurableRecognitionPrecedesModelAndFinalSavePrecedesDelivery() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("more e is my project", mode: .currentApp)
        let memoryID = try fixture.addMemory()
        let proposals = [correction()]
        let runner = InputRefinementRunner { input in
            try await MainActor.run {
                let saved = try fixture.saved(input.captureID)
                XCTAssertEqual(saved.recognizedText, input.text)
                XCTAssertEqual(saved.finalText, input.text)
                XCTAssertEqual(saved.refinement?.status, .running)
                XCTAssertEqual(input.context.map(\.id), [memoryID])
                return proposals
            }
        }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
        let deliveredText = try await personalizer.refine(id, enabled: true)
        XCTAssertEqual(deliveredText, "Morie is my project")
        let saved = try fixture.saved(id)
        XCTAssertEqual(saved.finalText, deliveredText)
        XCTAssertEqual(saved.recognizedText, "more e is my project")
        XCTAssertEqual(saved.refinement?.input.text, saved.recognizedText)
        XCTAssertEqual(saved.refinement?.edits.first?.memoryID, memoryID)
        XCTAssertEqual(saved.refinement?.status, .applied)
        XCTAssertEqual(saved.lifecycle, .recognized)
        try fixture.store.markDelivered(id)
        XCTAssertEqual(try fixture.saved(id).lifecycle, .delivered)
    }

    func testRefinementWithoutRelevantMemoryCanOnlyCleanPunctuation() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("okay keep this")
        let runner = InputRefinementRunner { _ in [RefinementProposal(original: "this", replacement: "this.")] }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
        let text = try await personalizer.refine(id, enabled: true)
        XCTAssertEqual(text, "okay keep this.")
        XCTAssertTrue(try XCTUnwrap(fixture.saved(id).refinement).input.context.isEmpty)
    }

    func testDisabledAndBusyRefinementDoNotInvokeModel() async throws {
        for enabled in [false, true] {
            let fixture = try Fixture()
            let id = try fixture.capture("Keep my words")
            let runner = InputRefinementRunner { _ in XCTFail("Model must not run"); return [] }
            let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
            let text = try await personalizer.refine(id, enabled: enabled, otherModelWorkActive: true)
            XCTAssertEqual(text, "Keep my words")
            XCTAssertEqual(try fixture.saved(id).refinement?.reason, enabled ? .modelBusy : .disabled)
        }
    }

    func testModelFailuresAndInvalidEditsKeepDurableOriginalWithoutPrivateErrors() async throws {
        for reason in [RefinementReason.unavailable, .unsupportedLanguage, .textTooLong, .declined, .generationFailed] {
            let fixture = try Fixture()
            let id = try fixture.capture("My original words")
            let runner = InputRefinementRunner { _ in throw reason }
            let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
            let text = try await personalizer.refine(id, enabled: true)
            XCTAssertEqual(text, "My original words")
            XCTAssertEqual(try fixture.saved(id).refinement?.reason, reason)
        }
        let fixture = try Fixture()
        let first = try fixture.capture("My original words")
        let failing = InputRefinementRunner { _ in
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "private prompt contents"])
        }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: failing)
        _ = try await personalizer.refine(first, enabled: true)
        let metadata = try XCTUnwrap(fixture.saved(first).refinement)
        XCTAssertEqual(metadata.reason, .generationFailed)
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(metadata), as: UTF8.self).contains("private prompt contents"))

        let second = try fixture.capture("Do not expand this")
        let invalid = InputRefinementRunner { _ in [RefinementProposal(original: "Do not expand this", replacement: "Here is an explanation.")] }
        let guarded = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: invalid)
        let text = try await guarded.refine(second, enabled: true)
        XCTAssertEqual(text, "Do not expand this")
        XCTAssertEqual(try fixture.saved(second).refinement?.reason, .invalidEdits)
    }

    func testSavedRefinedCaptureOnlyOutputSurvivesRecognitionRetryAndLateDiscard() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("more e is my project")
        try fixture.addMemory()
        let personalizer = fixture.personalizer(edits: [correction()])
        _ = try await personalizer.refine(id, enabled: true)
        try fixture.store.cancel(id)
        try fixture.store.saveReRecognition("A newer Speech result", for: id)
        let reopened = try CaptureStore(storageURL: fixture.storageURL)
        let saved = try reopened.capture(id)
        XCTAssertEqual(saved.recognizedText, "A newer Speech result")
        XCTAssertEqual(saved.finalText, "Morie is my project")
        XCTAssertEqual(saved.refinement?.input.text, "more e is my project")
        XCTAssertEqual(saved.lifecycle, .recognized)
        XCTAssertEqual(try MemoryStore(container: reopened.container).extractionInput(for: id).text, saved.finalText)
    }

    func testUnchangedRefinementRetainsItsInputAfterRetry() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("Already good")
        let output = try await fixture.personalizer(edits: []).refine(id, enabled: true)
        XCTAssertEqual(output, "Already good")
        XCTAssertEqual(try fixture.saved(id).refinement?.status, .unchanged)
        try fixture.store.saveReRecognition("New recognition", for: id)
        XCTAssertEqual(try fixture.saved(id).finalText, "Already good")
    }

    func testRefinementStartRejectsUncommittedSourceAndLatePartialsCannotOverwriteFinal() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("Original", mode: .currentApp)
        try fixture.store.updateRecognizedText("Late partial", for: id)
        XCTAssertEqual(try fixture.store.capture(id).recognizedText, "Original")
        let record = try fixture.store.capture(id)
        record.finalText = "unsaved"
        XCTAssertThrowsError(try fixture.store.refinementInput(for: id, context: []))
        XCTAssertEqual(record.finalText, "unsaved")
        fixture.store.container.mainContext.rollback()
    }

    func testFailedRefinedSaveRollsBackBeforeReturningOriginal() async throws {
        var commits = 0
        let fixture = try Fixture { context in
            commits += 1
            if commits == 2 { throw TestFailure.diskFull }
            try context.save()
        }
        let id = try fixture.capture("more e is my project")
        try fixture.addMemory()
        let output = try await fixture.personalizer(edits: [correction()]).refine(id, enabled: true)
        XCTAssertEqual(output, "more e is my project")
        let saved = try fixture.saved(id)
        XCTAssertEqual(saved.finalText, output)
        XCTAssertEqual(saved.recognizedText, output)
        XCTAssertEqual(saved.refinement?.reason, .saveFailed)
        XCTAssertTrue(saved.refinement?.edits.isEmpty == true)
    }

    func testFailureToSaveRefinementStartDoesNotCallModelOrLoseOriginal() async throws {
        let fixture = try Fixture { _ in throw TestFailure.diskFull }
        let id = try fixture.capture("Already saved")
        let runner = InputRefinementRunner { _ in XCTFail("Do not infer before recording refinement start"); return [] }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
        let text = try await personalizer.refine(id, enabled: true)
        XCTAssertEqual(text, "Already saved")
        XCTAssertEqual(try fixture.saved(id).finalText, text)
        XCTAssertNil(try fixture.saved(id).refinement)
    }

    func testFailedRefinementMetadataSaveCannotEraseADeliveryOutcome() async throws {
        var commits = 0
        let fixture = try Fixture { context in
            commits += 1
            if commits > 1 { throw TestFailure.diskFull }
            try context.save()
        }
        let id = try fixture.capture("more e is my project", mode: .currentApp)
        try fixture.addMemory()
        let output = try await fixture.personalizer(edits: [correction()]).refine(id, enabled: true)
        XCTAssertEqual(output, "more e is my project")
        try fixture.store.markDelivered(id)
        let reopened = try CaptureStore(storageURL: fixture.storageURL)
        let saved = try reopened.capture(id)
        XCTAssertEqual(saved.lifecycle, .delivered)
        XCTAssertEqual(saved.finalText, output)
        XCTAssertEqual(saved.refinement?.reason, .saveFailed)
    }

    func testRestartClearsRunningRefinementWithoutInferringOrDelivering() throws {
        for mode in [CaptureDeliveryMode.currentApp, .captureOnly] {
            let fixture = try Fixture()
            let id = try fixture.capture("Durable original", mode: mode)
            let input = try fixture.store.refinementInput(for: id, context: [])
            try fixture.store.beginRefinement(input)
            let reopened = try CaptureStore(storageURL: fixture.storageURL)
            let saved = try reopened.capture(id)
            XCTAssertEqual(saved.refinement?.status, .interrupted)
            XCTAssertEqual(saved.refinement?.input, input)
            XCTAssertEqual(saved.recognizedText, "Durable original")
            XCTAssertEqual(saved.finalText, "Durable original")
            XCTAssertEqual(saved.lifecycle, mode == .currentApp ? .failed : .recognized)
            XCTAssertEqual(try MemoryStore(container: reopened.container).extractionInput(for: id).text, "Durable original")
        }
    }

    func testRunningRefinementBlocksHistoryMutationAndExtraction() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("more e is my project")
        try fixture.addMemory()
        let pending = PendingRefinement()
        let runner = InputRefinementRunner { input in try await pending.run(input) }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
        let task = Task { try await personalizer.refine(id, enabled: true) }
        await pending.waitUntilStarted()
        XCTAssertThrowsError(try fixture.store.sourceAudioURL(for: id))
        XCTAssertThrowsError(try fixture.store.saveReRecognition("new words", for: id))
        XCTAssertThrowsError(try fixture.store.recordReRecognitionFailure("test", for: id))
        XCTAssertThrowsError(try fixture.store.deleteCapture(id))
        XCTAssertThrowsError(try fixture.memory.extractionInput(for: id))
        await pending.finish([correction()])
        _ = try await task.value
        XCTAssertEqual(try fixture.memory.extractionInput(for: id).text, "Morie is my project")
    }

    func testChangedArchivedOrDeletedMemoryCannotApplyAnOldCorrection() async throws {
        for change in 0..<3 {
            let fixture = try Fixture()
            let id = try fixture.capture("more e is my project")
            let memoryID = try fixture.addMemory()
            let pending = PendingRefinement()
            let runner = InputRefinementRunner { input in try await pending.run(input) }
            let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
            let task = Task { try await personalizer.refine(id, enabled: true) }
            await pending.waitUntilStarted()
            switch change {
            case 0: try fixture.memory.archive(memoryID)
            case 1: try fixture.memory.update(memoryID, draft: MemoryDraft(kind: .project, name: "New name", aliases: ["more e"]))
            default: try fixture.memory.delete(memoryID)
            }
            await pending.finish([correction()])
            let text = try await task.value
            XCTAssertEqual(text, "more e is my project")
            XCTAssertEqual(try fixture.saved(id).refinement?.reason, .memoryChanged)
        }
    }

    func testChangedOrDeletedSourceRejectsLateResultWithoutRecreatingData() async throws {
        for delete in [false, true] {
            let fixture = try Fixture()
            let id = try fixture.capture("more e is my project")
            try fixture.addMemory()
            let pending = PendingRefinement()
            let runner = InputRefinementRunner { input in try await pending.run(input) }
            let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
            let task = Task { try await personalizer.refine(id, enabled: true) }
            await pending.waitUntilStarted()
            // Simulate an authoritative store change outside the guarded History actions.
            let record = try fixture.store.capture(id)
            if delete {
                fixture.store.container.mainContext.delete(record)
            } else {
                record.recognizedText = "Changed source"
                record.finalText = "Changed source"
            }
            try fixture.store.container.mainContext.save()
            await pending.finish([correction()])
            do {
                _ = try await task.value
                XCTFail("A stale result must not reach delivery")
            } catch is CaptureStore.StoreError { }
            if delete {
                XCTAssertThrowsError(try fixture.store.capture(id))
            } else {
                XCTAssertEqual(try fixture.saved(id).finalText, "Changed source")
                XCTAssertEqual(try fixture.saved(id).refinement?.status, .interrupted)
            }
        }
    }

    func testDeadlineReturnsBeforeUncooperativeModelAndPreventsOverlapOrLateWrites() async throws {
        let fixture = try Fixture()
        let first = try fixture.capture("more e is my project")
        try fixture.addMemory()
        let pending = PendingRefinement()
        let runner = InputRefinementRunner(budget: .milliseconds(20)) { input in try await pending.run(input) }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
        let rescue = modelRescue(pending)
        defer { rescue.cancel() }
        let start = ContinuousClock.now
        let text = try await personalizer.refine(first, enabled: true)
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
        XCTAssertEqual(text, "more e is my project")
        XCTAssertEqual(try fixture.saved(first).refinement?.status, .timedOut)
        XCTAssertTrue(runner.isBusy)
        let waiting = await pending.isWaiting
        XCTAssertTrue(waiting, "Returning must not require the cancelled model to finish")

        let second = try fixture.capture("Second input")
        let secondText = try await personalizer.refine(second, enabled: true)
        XCTAssertEqual(secondText, "Second input")
        XCTAssertEqual(try fixture.saved(second).refinement?.reason, .modelBusy)
        let candidates = MemoryCandidateController(store: fixture.memory, canUseModel: { !runner.isBusy }) { _ in
            XCTFail("Candidate extraction must not overlap a draining refinement"); return []
        }
        candidates.findCandidates(for: first, automatically: true)
        XCTAssertNil(candidates.extractingCaptureID)

        await pending.finish([correction()])
        await runner.waitForModelToFinish()
        XCTAssertFalse(runner.isBusy)
        XCTAssertEqual(try fixture.saved(first).finalText, text)
        XCTAssertEqual(try fixture.saved(second).finalText, secondText)
        let count = await pending.calls
        XCTAssertEqual(count, 1)
    }

    func testCallerCancellationUnblocksWithoutDeliveringEvenIfModelIgnoresCancellation() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("more e is my project")
        try fixture.addMemory()
        let pending = PendingRefinement()
        let runner = InputRefinementRunner(budget: .seconds(10)) { input in try await pending.run(input) }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
        let task = Task { try await personalizer.refine(id, enabled: true) }
        await pending.waitUntilStarted()
        let rescue = modelRescue(pending)
        defer { rescue.cancel() }
        let start = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled input must not return text for delivery")
        } catch is CancellationError { }
        XCTAssertLessThan(ContinuousClock.now - start, .seconds(1))
        XCTAssertTrue(runner.isBusy)
        XCTAssertEqual(try fixture.saved(id).refinement?.status, .interrupted)
        XCTAssertEqual(try fixture.saved(id).finalText, "more e is my project")
        await pending.finish([correction()])
        await runner.waitForModelToFinish()
        XCTAssertEqual(try fixture.saved(id).refinement?.status, .interrupted)
        XCTAssertEqual(try fixture.saved(id).finalText, "more e is my project")
    }

    func testCancellationBeforeStartNeverLaunchesModelOrCreatesMetadata() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("Do not run")
        let runner = InputRefinementRunner { _ in XCTFail("Cancelled work must not run"); return [] }
        let personalizer = CapturePersonalizer(store: fixture.store, memory: fixture.memory, runner: runner)
        let task = Task { try await personalizer.refine(id, enabled: true) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError { }
        XCTAssertNil(try fixture.saved(id).refinement)
        XCTAssertFalse(runner.isBusy)
    }

    func testAutomaticExtractionUsesSavedRefinedTextAndStillRequiresReview() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("more e is my personal input project")
        try fixture.addMemory()
        let finalText = try await fixture.personalizer(edits: [correction()]).refine(id, enabled: true)
        let candidates = MemoryCandidateController(store: fixture.memory, extract: { input in
            XCTAssertEqual(input.text, finalText)
            XCTAssertEqual(input.textKind, .finalText)
            return [MemorySuggestion(draft: MemoryDraft(kind: .project, name: "Morie", notes: "Personal input project"),
                                     evidence: finalText, confidence: 0.9)]
        })
        candidates.findCandidates(for: id, automatically: true)
        await candidates.waitForExtraction()
        XCTAssertEqual(fixture.memory.extractions.first?.sourceText, finalText)
        XCTAssertEqual(fixture.memory.pendingCandidates.count, 1)
        XCTAssertEqual(fixture.memory.entries.count, 1, "Extraction must not auto-confirm Memory")
        XCTAssertEqual(try fixture.saved(id).recognizedText, "more e is my personal input project")
    }

    func testChangedFinalTextInvalidatesEarlierPendingCandidates() async throws {
        let fixture = try Fixture()
        let id = try fixture.capture("more e is my personal input project")
        try fixture.addMemory()
        let original = try fixture.memory.extractionInput(for: id)
        try fixture.memory.saveCandidates([
            MemorySuggestion(draft: MemoryDraft(kind: .project, name: "more e", notes: "Personal input project"),
                             evidence: original.text, confidence: 0.9)
        ], for: original)
        let extraction = try XCTUnwrap(fixture.memory.extraction(for: original))
        let candidate = try XCTUnwrap(extraction.candidates.first)
        _ = try await fixture.personalizer(edits: [correction()]).refine(id, enabled: true)
        XCTAssertFalse(fixture.memory.isCurrent(extraction))
        XCTAssertThrowsError(try fixture.memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft))
        XCTAssertEqual(extraction.sourceText, original.text)
        XCTAssertEqual(try fixture.memory.extractionInput(for: id).text, "Morie is my personal input project")
    }

    private func modelRescue(_ pending: PendingRefinement) -> Task<Void, Never> {
        Task {
            do {
                try await Task.sleep(for: .seconds(2))
                await pending.finish([])
            } catch { }
        }
    }

    private func request(_ text: String, status: MemoryStatus = .active, confirmed: Bool = true) -> RefinementInput {
        let memory = MemorySnapshot(id: UUID(), kind: .project, status: status, name: "Morie", aliases: ["more e"],
                                    notes: "Personal input project", userConfirmed: confirmed, updatedAt: Date())
        return RefinementInput(captureID: UUID(), text: text, context: [MemoryContextMatch(memory: memory, matchedTerm: "more e")])
    }

    private func correction() -> RefinementProposal { RefinementProposal(original: "more e", replacement: "Morie") }
}

private enum TestFailure: Error { case diskFull }

@MainActor
private final class Fixture {
    let directory: URL
    let storageURL: URL
    let store: CaptureStore
    let memory: MemoryStore

    init(commit: @escaping (ModelContext) throws -> Void = { try $0.save() }) throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MorieRefinement-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storageURL = directory.appending(path: "captures.store")
        store = try CaptureStore(storageURL: storageURL, commitRefinement: commit)
        memory = MemoryStore(container: store.container)
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func capture(_ text: String, mode: CaptureDeliveryMode = .captureOnly) throws -> UUID {
        let id = UUID()
        _ = try store.beginVoiceCapture(id: id, deliveryMode: mode, applicationName: "Test", bundleIdentifier: nil, windowNumber: nil)
        try store.completeRecognition(text, for: id)
        return id
    }

    @discardableResult
    func addMemory() throws -> UUID {
        try memory.create(MemoryDraft(kind: .project, name: "Morie", aliases: ["more e"], notes: "Personal input project"))
    }

    struct SavedCapture {
        let recognizedText: String
        let finalText: String
        let lifecycle: CaptureLifecycle
        let refinement: CaptureRefinement?
    }

    func saved(_ id: UUID) throws -> SavedCapture {
        let reader = ModelContext(store.container)
        let record = try XCTUnwrap(reader.fetch(FetchDescriptor<CaptureRecord>(predicate: #Predicate { $0.id == id })).first)
        return SavedCapture(recognizedText: record.recognizedText, finalText: record.finalText,
                            lifecycle: record.lifecycle, refinement: record.refinement)
    }

    func personalizer(edits: [RefinementProposal]) -> CapturePersonalizer {
        CapturePersonalizer(store: store, memory: memory, runner: InputRefinementRunner { _ in edits })
    }
}

private actor PendingRefinement {
    private var continuation: CheckedContinuation<[RefinementProposal], Error>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    var isWaiting: Bool { continuation != nil }

    func run(_ input: RefinementInput) async throws -> [RefinementProposal] {
        calls += 1
        return try await withCheckedThrowingContinuation {
            continuation = $0
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(_ edits: [RefinementProposal]) {
        continuation?.resume(returning: edits)
        continuation = nil
    }
}
