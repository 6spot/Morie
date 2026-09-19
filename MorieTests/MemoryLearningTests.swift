import Foundation
import SwiftData
import XCTest

@MainActor
final class MemoryLearningTests: XCTestCase {
    func testSavedFinalTextAutomaticallyCreatesPersonalMemoryAndSurvivesRestart() throws {
        let fixture = try LearningFixture()
        let source = try fixture.capture("I work on Morie.", recognition: "I work on more e.")
        try fixture.learn(source)
        let record = try XCTUnwrap(fixture.memory.entries.first)
        XCTAssertEqual(record.origin, .automatic)
        XCTAssertEqual(record.sourceCaptureIDs, [source])
        XCTAssertEqual(record.notes, "I work on Morie.")
        XCTAssertEqual(try fixture.captures.capture(source).recognizedText, "I work on more e.")
        XCTAssertEqual(try fixture.captures.capture(source).finalText, "I work on Morie.")
        let reopened = try CaptureStore(storageURL: fixture.url)
        let memory = MemoryStore(container: reopened.container)
        try memory.load()
        XCTAssertEqual(memory.entries.first?.id, record.id)
        XCTAssertEqual(memory.analyses.first?.sourceText, "I work on Morie.")
        XCTAssertEqual(memory.analyses.first?.state, .completed)
        XCTAssertEqual(try memory.relevantContext(for: "Morie").map(\.id), [record.id])
        XCTAssertTrue(try DictionaryStore(container: reopened.container).speechHints().isEmpty)
    }

    func testOnlyCompletedCurrentAppInputEntersQueue() throws {
        let fixture = try LearningFixture()
        _ = try fixture.capture("I work on Morie.", mode: .captureOnly)
        let pending = UUID()
        _ = try fixture.captures.beginVoiceCapture(id: pending, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        try fixture.captures.completeRecognition("I work on Morie.", for: pending)
        try fixture.memory.reconcileCompletedInputs()
        XCTAssertTrue(fixture.memory.analyses.isEmpty)
        XCTAssertThrowsError(try fixture.memory.analysisSource(for: pending))
        try fixture.captures.markDeliveryFailed(pending, error: "test clipboard fallback")
        try fixture.memory.reconcileCompletedInputs()
        XCTAssertEqual(fixture.memory.analyses.map(\.sourceCaptureID), [pending])
    }

    func testUnsavedSourceAndStaleModelResultsCannotBecomeMemory() throws {
        let fixture = try LearningFixture()
        let source = try fixture.capture("I work on Morie.")
        try fixture.memory.reconcileCompletedInputs()
        let input = try fixture.memory.learningInput(for: fixture.memory.analysisSource(for: source))
        let capture = try fixture.captures.capture(source)
        capture.finalText = "I work on something else."
        XCTAssertThrowsError(try fixture.memory.analysisSource(for: source))
        XCTAssertThrowsError(try fixture.memory.apply([LearningFixture.suggestion()], from: input))
        try fixture.captures.container.mainContext.save()
        XCTAssertThrowsError(try fixture.memory.apply([LearningFixture.suggestion()], from: input))
        XCTAssertTrue(fixture.memory.entries.isEmpty)
    }

    func testRepeatedAnalysisIsIdempotentAndSourcesMergeWithoutOverwriting() throws {
        let fixture = try LearningFixture()
        let first = try fixture.capture("I work on Morie.")
        try fixture.learn(first)
        try fixture.learn(first)
        let second = try fixture.capture("I work on Morie.")
        try fixture.learn(second)
        XCTAssertEqual(fixture.memory.entries.count, 1)
        XCTAssertEqual(Set(try XCTUnwrap(fixture.memory.entries.first).sourceCaptureIDs), Set([first, second]))
        XCTAssertEqual(fixture.memory.analyses.count, 2)
    }

    func testWeakerPersonalEvidenceAccumulatesAcrossDistinctInputs() throws {
        let fixture = try LearningFixture()
        let suggestion = LearningFixture.suggestion(confidence: 0.85, evidenceKind: .recurringPersonal)
        let first = try fixture.capture("I work on Morie.")
        try fixture.learn(first, suggestion: suggestion)
        try fixture.learn(first, suggestion: suggestion)
        XCTAssertTrue(fixture.memory.entries.isEmpty)
        XCTAssertEqual(fixture.memory.analyses.first?.observations.first?.disposition, .accumulating)
        let second = try fixture.capture("I work on Morie.")
        try fixture.learn(second, suggestion: suggestion)
        XCTAssertEqual(fixture.memory.entries.count, 1)
        XCTAssertEqual(fixture.memory.analyses.flatMap(\.observations).filter { $0.disposition == .learned }.count, 2)
    }

    func testQuotedTemporaryUncertainAndInventedInformationIsNotAdmitted() throws {
        let fixture = try LearningFixture()
        for kind: MemoryEvidenceKind in [.quoted, .temporary, .uncertain] {
            try fixture.learn(fixture.capture("I work on Morie."), suggestion: LearningFixture.suggestion(evidenceKind: kind))
        }
        try fixture.learn(fixture.capture("He said: “I work on Morie.”"))
        let unsupported = MemorySuggestion(draft: MemoryDraft(kind: .project, name: "Morie", notes: "I own Morie."), evidence: "I work on Morie.", confidence: 0.99)
        try fixture.learn(fixture.capture("I work on Morie."), suggestion: unsupported)
        try fixture.learn(fixture.capture("Morie is an application."))
        try fixture.learn(fixture.capture("Maybe I work on Morie."), suggestion: LearningFixture.suggestion(text: "Maybe I work on Morie."))
        XCTAssertTrue(fixture.memory.entries.isEmpty)
    }

    func testExplicitLaterUpdateSupersedesAnAutomaticFact() throws {
        let fixture = try LearningFixture()
        let first = try fixture.capture("我住在北京。", date: Date(timeIntervalSince1970: 10))
        try fixture.learn(first, suggestion: LearningFixture.suggestion(name: "居住城市", text: "我住在北京。", kind: .fact))
        let prior = try XCTUnwrap(fixture.memory.entries.first)
        let second = try fixture.capture("我现在住在上海。", date: Date(timeIntervalSince1970: 20))
        var update = LearningFixture.suggestion(name: "居住城市", text: "我现在住在上海。", kind: .fact)
        update.action = .update
        update.existingMemoryID = prior.id
        try fixture.learn(second, suggestion: update)
        let current = try XCTUnwrap(fixture.memory.entries.first(where: { $0.status == .active }))
        XCTAssertEqual(current.notes, "我现在住在上海。")
        XCTAssertEqual(current.supersedesID, prior.id)
        XCTAssertEqual(try fixture.memory.memory(prior.id).status, .superseded)
        XCTAssertEqual(try fixture.memory.relevantContext(for: "上海").map(\.id), [current.id])
    }

    func testAmbiguousOlderAndUserEditedConflictsDoNotOverwriteMemory() throws {
        let fixture = try LearningFixture()
        try fixture.learn(fixture.capture("我住在北京。", date: Date(timeIntervalSince1970: 20)), suggestion: LearningFixture.suggestion(name: "居住城市", text: "我住在北京。", kind: .fact))
        let memoryID = try XCTUnwrap(fixture.memory.entries.first?.id)
        try fixture.learn(fixture.capture("我住在上海。", date: Date(timeIntervalSince1970: 30)), suggestion: LearningFixture.suggestion(name: "居住城市", text: "我住在上海。", kind: .fact))
        var update = LearningFixture.suggestion(name: "居住城市", text: "我现在住在上海。", kind: .fact)
        update.action = .update
        update.existingMemoryID = memoryID
        try fixture.learn(fixture.capture(update.evidence, date: Date(timeIntervalSince1970: 10)), suggestion: update)
        XCTAssertEqual(try fixture.memory.memory(memoryID).notes, "我住在北京。")
        try fixture.memory.update(memoryID, draft: MemoryDraft(kind: .fact, name: "居住城市", notes: "我住在成都。"))
        try fixture.learn(fixture.capture(update.evidence, date: Date(timeIntervalSince1970: 40)), suggestion: update)
        XCTAssertEqual(try fixture.memory.memory(memoryID).notes, "我住在成都。")
        XCTAssertEqual(fixture.memory.entries.count, 1)
    }

    func testDeletedAndArchivedTopicsAreNotAutomaticallyRelearned() throws {
        let fixture = try LearningFixture()
        try fixture.learn(fixture.capture("I work on Morie."))
        let first = try XCTUnwrap(fixture.memory.entries.first?.id)
        try fixture.memory.archive(first)
        try fixture.learn(fixture.capture("I work on Morie."))
        XCTAssertEqual(fixture.memory.entries.count, 1)
        XCTAssertEqual(try fixture.memory.memory(first).status, .archived)
        try fixture.memory.delete(first)
        try fixture.learn(fixture.capture("I work on Morie."))
        XCTAssertTrue(fixture.memory.entries.isEmpty)
        let manual = try fixture.memory.create(MemoryDraft(kind: .project, name: "Morie", notes: "I work on Morie."))
        try fixture.learn(fixture.capture("I work on Morie."))
        XCTAssertEqual(fixture.memory.entries.map(\.id), [manual])
    }

    func testSourceDeletionRemovesAnalysisSnapshotsButKeepsSeparateMemory() throws {
        let fixture = try LearningFixture()
        let id = try fixture.capture("I work on Morie.")
        try fixture.learn(id)
        let memoryID = try XCTUnwrap(fixture.memory.entries.first?.id)
        try fixture.captures.deleteCapture(id)
        try fixture.memory.load()
        XCTAssertTrue(fixture.memory.analyses.isEmpty)
        XCTAssertEqual(try fixture.memory.memory(memoryID).sourceCaptureIDs, [id])
    }

    func testFailedAtomicSaveKeepsQueuePendingAndDoesNotPartiallyAdmitMemory() throws {
        let fixture = try LearningFixture()
        let id = try fixture.capture("I work on Morie.")
        try fixture.memory.reconcileCompletedInputs()
        let failing = MemoryStore(container: fixture.captures.container, commit: { _ in throw LearningTestError.diskFull })
        let input = try failing.learningInput(for: failing.analysisSource(for: id))
        XCTAssertThrowsError(try failing.apply([LearningFixture.suggestion()], from: input))
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
        XCTAssertEqual(try memory.pendingSources(now: now.addingTimeInterval(31)), [source])
        try memory.recordFailure(.textTooLong, for: source)
        XCTAssertTrue(try memory.pendingSources(now: now.addingTimeInterval(3600)).isEmpty)
        try memory.retry(source)
        XCTAssertEqual(try memory.pendingSources(), [source])
    }

    func testInputPreemptsUncooperativeAnalysisWithoutLosingQueuedWork() async throws {
        let fixture = try LearningFixture()
        _ = try fixture.capture("I work on Morie.")
        let model = PendingLearning()
        let controller = MemoryLearningController(store: fixture.memory, idleDelay: .milliseconds(1), analyze: { try await model.run($0) })
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
        let resumed = MemoryLearningController(store: fixture.memory, idleDelay: .milliseconds(1), analyze: { _ in [LearningFixture.suggestion()] })
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
        let controller = MemoryLearningController(store: fixture.memory, idleDelay: .milliseconds(1), analyze: { try await model.run($0) })
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
        _ = try fixture.capture("I work on Morie.")
        let controller = MemoryLearningController(store: fixture.memory, idleDelay: .milliseconds(1), analyze: { _ in
            throw NSError(domain: "private input text", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATE MODEL CONTENT"])
        })
        controller.setInputActive(false)
        controller.start()
        await controller.waitForCurrentBatch()
        controller.stop()
        XCTAssertFalse(controller.message?.contains("PRIVATE") == true)
        XCTAssertEqual(fixture.memory.analyses.first?.failure, .generationFailed)
        XCTAssertEqual(fixture.memory.analyses.first?.state, .pending)
    }

    func testInvalidAnalysisIsRetryableAndDoesNotMarkTheSourceChanged() async throws {
        let fixture = try LearningFixture()
        _ = try fixture.capture("I work on Morie.")
        let controller = MemoryLearningController(store: fixture.memory, idleDelay: .milliseconds(1), analyze: { _ in
            Array(repeating: LearningFixture.suggestion(), count: 4)
        })
        controller.setInputActive(false)
        controller.start()
        await controller.waitForCurrentBatch()
        controller.stop()
        XCTAssertTrue(fixture.memory.entries.isEmpty)
        XCTAssertEqual(fixture.memory.analyses.first?.failure, .generationFailed)
        XCTAssertEqual(fixture.memory.analyses.first?.state, .pending)
    }

    private func waitUntilStarted(_ model: PendingLearning) async {
        for _ in 0..<500 {
            if await model.isWaiting { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        XCTFail("Analysis did not start")
    }
}

private enum LearningTestError: Error { case diskFull }

@MainActor
private final class LearningFixture {
    let directory: URL
    let url: URL
    let captures: CaptureStore
    let memory: MemoryStore

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "MorieLearning-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        url = directory.appending(path: "store")
        captures = try CaptureStore(storageURL: url)
        memory = MemoryStore(container: captures.container)
    }
    deinit { try? FileManager.default.removeItem(at: directory) }

    func capture(_ text: String, recognition: String? = nil, mode: CaptureDeliveryMode = .currentApp, date: Date = Date()) throws -> UUID {
        let id = UUID()
        _ = try captures.beginVoiceCapture(id: id, deliveryMode: mode, applicationName: "Test", bundleIdentifier: nil)
        try captures.capture(id).createdAt = date
        try captures.completeRecognition(recognition ?? text, for: id)
        try captures.capture(id).finalText = text
        try captures.container.mainContext.save()
        if mode == .currentApp {
            try captures.markDelivered(
                id,
                applicationName: "Test",
                bundleIdentifier: "me.morie.tests"
            )
        }
        return id
    }

    func learn(_ id: UUID, suggestion: MemorySuggestion = LearningFixture.suggestion()) throws {
        try memory.enqueueCompletedInput(captureID: id)
        let input = try memory.learningInput(for: memory.analysisSource(for: id))
        try memory.apply([suggestion], from: input)
    }

    nonisolated static func suggestion(name: String = "Morie", text: String = "I work on Morie.", kind: MemoryKind = .project, confidence: Double = 0.95, evidenceKind: MemoryEvidenceKind = .explicitPersonal) -> MemorySuggestion {
        MemorySuggestion(draft: MemoryDraft(kind: kind, name: name, notes: text), evidence: text, confidence: confidence, evidenceKind: evidenceKind)
    }
}

private actor PendingLearning {
    private var continuation: CheckedContinuation<[MemorySuggestion], Error>?
    var isWaiting: Bool { continuation != nil }
    func run(_ input: MemoryLearningInput) async throws -> [MemorySuggestion] {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func finish(_ suggestions: [MemorySuggestion]) { continuation?.resume(returning: suggestions); continuation = nil }
}
