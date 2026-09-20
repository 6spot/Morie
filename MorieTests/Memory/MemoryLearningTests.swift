import Foundation
import SwiftData
import XCTest

@MainActor
final class MemoryLearningTests: XCTestCase {
    func testSavedFinalTextCreatesTopicAndEvidenceAndSurvivesRestart() async throws {
        let fixture = try LearningFixture()
        let source = try fixture.capture(
            "I work on Morie.",
            recognition: "I work on more e."
        )
        try await fixture.captures.flushPersistence(for: source)
        fixture.captures.releaseCaptureOwnership(source)

        try fixture.learn(source)

        let record = try XCTUnwrap(fixture.memory.entries.first)
        XCTAssertEqual(record.origin, .automatic)
        XCTAssertEqual(record.scope, .longTerm)
        XCTAssertEqual(record.sourceCaptureIDs, [source])
        XCTAssertEqual(record.notes, "I work on Morie.")
        XCTAssertEqual(fixture.memory.evidence(for: record.id).map(\.claim), ["I work on Morie."])
        XCTAssertEqual(
            try fixture.captures.capture(source).recognizedText,
            "I work on more e."
        )
        XCTAssertEqual(
            try fixture.captures.capture(source).finalText,
            "I work on Morie."
        )

        let reopened = try CaptureStore(storageURL: fixture.url)
        let memory = MemoryStore(container: reopened.container)
        try memory.load()

        XCTAssertEqual(memory.entries.first?.id, record.id)
        XCTAssertEqual(memory.analyses.first?.sourceText, "I work on Morie.")
        XCTAssertEqual(memory.analyses.first?.state, .completed)
        XCTAssertEqual(memory.evidence(for: record.id).first?.sourceText, "I work on Morie.")
        XCTAssertEqual(
            try memory.relevantContext(for: "Morie").map(\.id),
            [record.id]
        )

        let dictionary = DictionaryStore(container: reopened.container)
        try dictionary.load()
        XCTAssertTrue(
            dictionary.entries.isEmpty,
            "Automatic Memory learning must not create Dictionary entries."
        )
    }

    func testOnlyCompletedCurrentAppInputEntersQueue() throws {
        let fixture = try LearningFixture()
        _ = try fixture.capture("I work on Morie.", mode: .captureOnly)

        let pending = UUID()
        _ = try fixture.captures.beginVoiceCapture(
            id: pending,
            deliveryMode: .currentApp,
            applicationName: nil,
            bundleIdentifier: nil
        )
        try fixture.captures.completeRecognition(
            "I work on Morie.",
            for: pending
        )

        try fixture.memory.reconcileCompletedInputs()
        XCTAssertTrue(fixture.memory.analyses.isEmpty)
        XCTAssertThrowsError(
            try fixture.memory.analysisSource(for: pending)
        )

        try fixture.captures.markDeliveryFailed(
            pending,
            error: "test clipboard fallback"
        )
        try fixture.captures.container.mainContext.save()
        try fixture.memory.reconcileCompletedInputs()

        XCTAssertEqual(
            fixture.memory.analyses.map(\.sourceCaptureID),
            [pending]
        )
    }

    func testDisabledInputIsDurablySkippedAndNeverBackfilled() throws {
        let fixture = try LearningFixture()
        let source = try fixture.capture("I work on Morie.")

        try fixture.memory.enqueueCompletedInput(
            captureID: source,
            learningEnabled: false
        )
        XCTAssertEqual(fixture.memory.analyses.first?.state, .skipped)
        XCTAssertEqual(fixture.memory.analyses.first?.failure, .disabled)
        XCTAssertTrue(try fixture.memory.pendingSources().isEmpty)

        try fixture.memory.reconcileCompletedInputs(learningEnabled: true)
        XCTAssertTrue(try fixture.memory.pendingSources().isEmpty)
        XCTAssertTrue(fixture.memory.entries.isEmpty)
    }

    func testUnsavedSourceAndStaleModelResultsCannotBecomeMemory() throws {
        let fixture = try LearningFixture()
        let source = try fixture.capture("I work on Morie.")
        try fixture.memory.reconcileCompletedInputs()

        let input = try fixture.memory.learningInput(
            for: fixture.memory.analysisSource(for: source)
        )
        let capture = try fixture.captures.capture(source)
        capture.finalText = "I work on something else."

        XCTAssertThrowsError(
            try fixture.memory.analysisSource(for: source)
        )
        XCTAssertThrowsError(
            try fixture.memory.apply(
                [LearningFixture.suggestion()],
                from: input
            )
        )

        try fixture.captures.container.mainContext.save()
        XCTAssertThrowsError(
            try fixture.memory.apply(
                [LearningFixture.suggestion()],
                from: input
            )
        )
        XCTAssertTrue(fixture.memory.entries.isEmpty)
    }

    func testSemanticMergeUsesExistingUUIDInsteadOfGeneratedTitleIdentity() throws {
        let fixture = try LearningFixture()
        let first = try fixture.capture(
            "Morie is my Apple-native voice input project."
        )
        try fixture.learn(
            first,
            suggestion: LearningFixture.suggestion(
                name: "Morie",
                text: "Morie is my Apple-native voice input project.",
                notes: "Morie is my Apple-native voice input project."
            )
        )
        let memoryID = try XCTUnwrap(fixture.memory.entries.first?.id)

        let second = try fixture.capture(
            "For the voice input app, I want to keep dependencies minimal."
        )
        try fixture.learn(
            second,
            suggestion: LearningFixture.suggestion(
                name: "Apple-native voice input work",
                text: "For the voice input app, I want to keep dependencies minimal.",
                notes: "Morie is my Apple-native voice input project, with a preference for minimal dependencies.",
                action: .merge,
                existingMemoryID: memoryID
            )
        )

        XCTAssertEqual(fixture.memory.entries.count, 1)
        let current = try fixture.memory.memory(memoryID)
        XCTAssertEqual(current.name, "Apple-native voice input work")
        XCTAssertTrue(current.notes.contains("minimal dependencies"))
        XCTAssertEqual(
            Set(current.sourceCaptureIDs),
            Set([first, second])
        )
        XCTAssertEqual(fixture.memory.evidence(for: memoryID).count, 2)
    }

    func testSystemDoesNotRequireUpdateKeywordsOnceModelChoosesUpdate() throws {
        let fixture = try LearningFixture()
        let first = try fixture.capture("我住在北京。")
        try fixture.learn(
            first,
            suggestion: LearningFixture.suggestion(
                name: "居住城市",
                text: "我住在北京。",
                kind: .fact
            )
        )
        let id = try XCTUnwrap(fixture.memory.entries.first?.id)

        let second = try fixture.capture("我住上海。")
        try fixture.learn(
            second,
            suggestion: LearningFixture.suggestion(
                name: "居住城市",
                text: "我住上海。",
                kind: .fact,
                action: .update,
                existingMemoryID: id
            )
        )

        XCTAssertEqual(try fixture.memory.memory(id).notes, "我住上海。")
        XCTAssertEqual(fixture.memory.entries.count, 1)
    }

    func testUserEditedMemoryCannotBeAutomaticallyOverwritten() throws {
        let fixture = try LearningFixture()
        let first = try fixture.capture("我住在北京。")
        try fixture.learn(
            first,
            suggestion: LearningFixture.suggestion(
                name: "居住城市",
                text: "我住在北京。",
                kind: .fact
            )
        )
        let id = try XCTUnwrap(fixture.memory.entries.first?.id)

        try fixture.memory.update(
            id,
            draft: MemoryDraft(
                kind: .fact,
                name: "居住城市",
                notes: "我住在成都。"
            )
        )

        let second = try fixture.capture("我住上海。")
        try fixture.learn(
            second,
            suggestion: LearningFixture.suggestion(
                name: "居住城市",
                text: "我住上海。",
                kind: .fact,
                action: .update,
                existingMemoryID: id
            )
        )

        XCTAssertEqual(try fixture.memory.memory(id).notes, "我住在成都。")
        XCTAssertEqual(
            fixture.memory.analyses.last?.observations.first?.disposition,
            .conflict
        )
    }

    func testWorkingContextExpiresRefreshesAndCanPromote() throws {
        let fixture = try LearningFixture()
        let base = Date()
        let first = try fixture.capture(
            "I am debugging Morie memory this week.",
            date: base
        )
        try fixture.learn(
            first,
            suggestion: LearningFixture.suggestion(
                name: "Morie memory work",
                text: "I am debugging Morie memory this week.",
                scope: .workingContext
            )
        )

        let id = try XCTUnwrap(fixture.memory.entries.first?.id)
        let initialExpiry = try XCTUnwrap(
            fixture.memory.memory(id).expiresAt
        )
        XCTAssertEqual(
            initialExpiry.timeIntervalSince(base),
            MemoryStore.workingContextLifetime,
            accuracy: 0.1
        )

        let later = base.addingTimeInterval(24 * 60 * 60)
        let second = try fixture.capture(
            "I am still working on Morie memory.",
            date: later
        )
        try fixture.learn(
            second,
            suggestion: LearningFixture.suggestion(
                name: "Morie memory work",
                text: "I am still working on Morie memory.",
                notes: "I am still working on Morie memory.",
                scope: .workingContext,
                action: .reinforce,
                existingMemoryID: id
            )
        )
        let refreshedExpiry = try XCTUnwrap(
            fixture.memory.memory(id).expiresAt
        )
        XCTAssertGreaterThan(refreshedExpiry, initialExpiry)

        let third = try fixture.capture(
            "Memory is now a core long-term part of Morie.",
            date: later.addingTimeInterval(60)
        )
        try fixture.learn(
            third,
            suggestion: LearningFixture.suggestion(
                name: "Morie memory",
                text: "Memory is now a core long-term part of Morie.",
                notes: "Memory is a core long-term part of Morie.",
                scope: .longTerm,
                action: .update,
                existingMemoryID: id
            )
        )

        let promoted = try fixture.memory.memory(id)
        XCTAssertEqual(promoted.scope, .longTerm)
        XCTAssertNil(promoted.expiresAt)

        let expiringFixture = try LearningFixture()
        let expiringSource = try expiringFixture.capture(
            "I am testing a temporary feature.",
            date: base
        )
        try expiringFixture.learn(
            expiringSource,
            suggestion: LearningFixture.suggestion(
                name: "Temporary feature test",
                text: "I am testing a temporary feature.",
                scope: .workingContext
            )
        )
        let expiringID = try XCTUnwrap(
            expiringFixture.memory.entries.first?.id
        )
        try expiringFixture.memory.load(
            now: base.addingTimeInterval(
                MemoryStore.workingContextLifetime + 1
            )
        )
        XCTAssertEqual(
            try expiringFixture.memory.memory(expiringID).status,
            .archived
        )
        XCTAssertEqual(
            try expiringFixture.memory.memory(expiringID).archiveReason,
            .expired
        )
    }

    func testDeletedAndUserArchivedTopicsBecomeProtectedContext() throws {
        let fixture = try LearningFixture()
        let source = try fixture.capture("I work on Morie.")
        try fixture.learn(source)

        let first = try XCTUnwrap(fixture.memory.entries.first?.id)
        try fixture.memory.archive(first)

        let archivedSource = try fixture.capture("I work on Morie.")
        try fixture.memory.enqueueCompletedInput(captureID: archivedSource)
        let archivedInput = try fixture.memory.learningInput(
            for: fixture.memory.analysisSource(for: archivedSource)
        )
        XCTAssertTrue(
            archivedInput.blocked.contains {
                $0.name == "Morie" && $0.notes == "I work on Morie."
            }
        )

        try fixture.memory.delete(first)

        let deletedSource = try fixture.capture("I work on Morie.")
        try fixture.memory.enqueueCompletedInput(captureID: deletedSource)
        let deletedInput = try fixture.memory.learningInput(
            for: fixture.memory.analysisSource(for: deletedSource)
        )
        XCTAssertTrue(
            deletedInput.blocked.contains {
                $0.name == "Morie" && $0.notes == "I work on Morie."
            }
        )

        try fixture.memory.apply(
            [LearningFixture.suggestion()],
            from: deletedInput
        )
        XCTAssertTrue(fixture.memory.entries.isEmpty)

        let manual = try fixture.memory.create(
            MemoryDraft(
                kind: .project,
                name: "Morie",
                notes: "I work on Morie."
            )
        )
        XCTAssertEqual(fixture.memory.entries.map(\.id), [manual])
    }

    func testAdmissionValidatesSourceGroundingNotSemanticKeywords() throws {
        let fixture = try LearningFixture()

        let maybe = try fixture.capture("Maybe I will keep this as context.")
        try fixture.learn(
            maybe,
            suggestion: LearningFixture.suggestion(
                name: "Current thought",
                text: "Maybe I will keep this as context.",
                scope: .workingContext
            )
        )
        XCTAssertEqual(fixture.memory.entries.count, 1)

        let bad = try fixture.capture("I work on Morie.")
        let unsupported = LearningFixture.suggestion(
            name: "Ownership",
            text: "I own Morie."
        )
        try fixture.learn(bad, suggestion: unsupported)
        XCTAssertEqual(
            fixture.memory.entries.count,
            1,
            "Code should reject evidence not present in the source."
        )
    }

    func testSourceDeletionRemovesAnalysisButKeepsIndependentEvidence() throws {
        let fixture = try LearningFixture()
        let id = try fixture.capture("I work on Morie.")
        try fixture.learn(id)
        let memoryID = try XCTUnwrap(fixture.memory.entries.first?.id)

        try fixture.captures.deleteCapture(id)
        try fixture.memory.load()

        XCTAssertTrue(fixture.memory.analyses.isEmpty)
        XCTAssertEqual(
            try fixture.memory.memory(memoryID).sourceCaptureIDs,
            [id]
        )
        XCTAssertEqual(
            fixture.memory.evidence(for: memoryID).first?.sourceText,
            "I work on Morie."
        )
    }

    func testFailedAtomicSaveKeepsQueuePending() throws {
        let fixture = try LearningFixture()
        let id = try fixture.capture("I work on Morie.")
        try fixture.memory.reconcileCompletedInputs()

        let failing = MemoryStore(
            container: fixture.captures.container,
            commit: { _ in throw LearningTestError.diskFull }
        )
        let input = try failing.learningInput(
            for: failing.analysisSource(for: id)
        )

        XCTAssertThrowsError(
            try failing.apply(
                [LearningFixture.suggestion()],
                from: input
            )
        )

        try fixture.memory.load()
        XCTAssertTrue(fixture.memory.entries.isEmpty)
        XCTAssertEqual(fixture.memory.analyses.first?.state, .pending)

        try fixture.learn(id)
        XCTAssertEqual(fixture.memory.entries.count, 1)
    }

    func testRestartDiscoversUnqueuedInputAndPreservesBackoff() throws {
        let fixture = try LearningFixture()
        let id = try fixture.capture("I work on Morie.")
        let reopened = try CaptureStore(storageURL: fixture.url)
        let memory = MemoryStore(container: reopened.container)

        try memory.reconcileCompletedInputs()
        let source = try memory.analysisSource(for: id)
        let now = Date()

        try memory.recordFailure(.generationFailed, for: source, now: now)
        XCTAssertTrue(try memory.pendingSources(now: now).isEmpty)
        XCTAssertEqual(
            try memory.pendingSources(
                now: now.addingTimeInterval(31)
            ),
            [source]
        )

        try memory.recordFailure(.textTooLong, for: source)
        XCTAssertTrue(
            try memory.pendingSources(
                now: now.addingTimeInterval(3_600)
            ).isEmpty
        )

        try memory.retry(source)
        XCTAssertEqual(try memory.pendingSources(), [source])
    }

    func testInputPreemptsUncooperativeAnalysisWithoutLosingQueuedWork() async throws {
        let fixture = try LearningFixture()
        _ = try fixture.capture("I work on Morie.")
        let model = PendingLearning()
        let controller = MemoryLearningController(
            store: fixture.memory,
            idleDelay: .milliseconds(1),
            analyze: { try await model.run($0) }
        )

        controller.setInputActive(false)
        controller.start()
        await waitUntilStarted(model)
        controller.setInputActive(true)
        XCTAssertTrue(controller.isModelBusy)

        await model.finish([LearningFixture.suggestion()])
        await controller.waitForCurrentBatch()
        controller.stop()

        XCTAssertFalse(controller.isModelBusy)
        XCTAssertTrue(fixture.memory.entries.isEmpty)
        XCTAssertEqual(try fixture.memory.pendingSources().count, 1)

        let resumed = MemoryLearningController(
            store: fixture.memory,
            idleDelay: .milliseconds(1),
            analyze: { _ in [LearningFixture.suggestion()] }
        )
        resumed.setInputActive(false)
        resumed.start()
        await resumed.waitForCurrentBatch()
        resumed.stop()

        XCTAssertEqual(fixture.memory.entries.count, 1)
    }

    func testSourceDeletedDuringAnalysisCannotBeRecreated() async throws {
        let fixture = try LearningFixture()
        let id = try fixture.capture("I work on Morie.")
        let model = PendingLearning()
        let controller = MemoryLearningController(
            store: fixture.memory,
            idleDelay: .milliseconds(1),
            analyze: { try await model.run($0) }
        )

        controller.setInputActive(false)
        controller.start()
        await waitUntilStarted(model)

        try fixture.captures.deleteCapture(id)
        await model.finish([LearningFixture.suggestion()])
        await controller.waitForCurrentBatch()
        controller.stop()

        try fixture.memory.load()
        XCTAssertTrue(fixture.memory.entries.isEmpty)
        XCTAssertTrue(fixture.memory.analyses.isEmpty)
    }

    func testModelFailureUsesFixedPrivateMessageAndAutomaticRetry() async throws {
        let fixture = try LearningFixture()
        let source = try fixture.capture("I work on Morie.")
        try await fixture.captures.flushPersistence(for: source)
        fixture.captures.releaseCaptureOwnership(source)

        let controller = MemoryLearningController(
            store: fixture.memory,
            idleDelay: .milliseconds(1),
            analyze: { _ in
                throw NSError(
                    domain: "private input text",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey: "PRIVATE MODEL CONTENT"
                    ]
                )
            }
        )

        controller.setInputActive(false)
        controller.start()
        await controller.waitForCurrentBatch()
        controller.stop()

        XCTAssertFalse(controller.message?.contains("PRIVATE") == true)
        XCTAssertEqual(
            fixture.memory.analyses.first?.failure,
            .generationFailed
        )
        XCTAssertEqual(
            fixture.memory.analyses.first?.state,
            .pending
        )
    }

    func testInvalidAnalysisIsRetryableAndDoesNotPartiallyWrite() async throws {
        let fixture = try LearningFixture()
        _ = try fixture.capture("I work on Morie.")
        let controller = MemoryLearningController(
            store: fixture.memory,
            idleDelay: .milliseconds(1),
            analyze: { _ in
                Array(
                    repeating: LearningFixture.suggestion(),
                    count: 4
                )
            }
        )

        controller.setInputActive(false)
        controller.start()
        await controller.waitForCurrentBatch()
        controller.stop()

        XCTAssertTrue(fixture.memory.entries.isEmpty)
        XCTAssertEqual(
            fixture.memory.analyses.first?.failure,
            .generationFailed
        )
        XCTAssertEqual(
            fixture.memory.analyses.first?.state,
            .pending
        )
    }

    private func waitUntilStarted(_ model: PendingLearning) async {
        for _ in 0..<500 {
            if await model.isWaiting { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Analysis did not start")
    }
}

private enum LearningTestError: Error {
    case diskFull
}

@MainActor
private final class LearningFixture {
    let directory: URL
    let url: URL
    let captures: CaptureStore
    let memory: MemoryStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appending(
                path: "MorieLearning-(UUID())",
                directoryHint: .isDirectory
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        url = directory.appending(path: "store")
        captures = try CaptureStore(storageURL: url)
        memory = MemoryStore(container: captures.container)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func capture(
        _ text: String,
        recognition: String? = nil,
        mode: CaptureDeliveryMode = .currentApp,
        date: Date = Date()
    ) throws -> UUID {
        let id = UUID()
        _ = try captures.beginVoiceCapture(
            id: id,
            deliveryMode: mode,
            applicationName: "Test",
            bundleIdentifier: nil
        )
        try captures.capture(id).createdAt = date
        try captures.completeRecognition(
            recognition ?? text,
            for: id
        )
        try captures.capture(id).finalText = text
        try captures.container.mainContext.save()

        if mode == .currentApp {
            try captures.markDelivered(
                id,
                applicationName: "Test",
                bundleIdentifier: "me.morie.tests"
            )
            try captures.container.mainContext.save()
        }
        return id
    }

    func learn(
        _ id: UUID,
        suggestion: MemorySuggestion = LearningFixture.suggestion()
    ) throws {
        try memory.enqueueCompletedInput(captureID: id)
        let input = try memory.learningInput(
            for: memory.analysisSource(for: id)
        )
        try memory.apply([suggestion], from: input)
    }

    nonisolated static func suggestion(
        name: String = "Morie",
        text: String = "I work on Morie.",
        notes: String? = nil,
        kind: MemoryKind = .project,
        scope: MemoryScope = .longTerm,
        confidence: Double = 0.95,
        action: MemoryLearningAction = .create,
        existingMemoryID: UUID? = nil
    ) -> MemorySuggestion {
        MemorySuggestion(
            draft: MemoryDraft(
                kind: kind,
                name: name,
                notes: notes ?? text,
                scope: scope
            ),
            evidence: text,
            confidence: confidence,
            action: action,
            existingMemoryID: existingMemoryID
        )
    }
}

private actor PendingLearning {
    private var continuation:
        CheckedContinuation<[MemorySuggestion], Error>?

    var isWaiting: Bool {
        continuation != nil
    }

    func run(
        _ input: MemoryLearningInput
    ) async throws -> [MemorySuggestion] {
        try await withCheckedThrowingContinuation {
            continuation = $0
        }
    }

    func finish(_ suggestions: [MemorySuggestion]) {
        continuation?.resume(returning: suggestions)
        continuation = nil
    }
}
