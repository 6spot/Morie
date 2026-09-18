import Foundation
import SwiftData
import XCTest

@MainActor
final class MemoryCandidateTests: XCTestCase {
    private let recognized = "more e 是我的个人输入项目"
    private let finalText = "Morie 是我的个人输入项目。"

    func testExtractionPrefersAndRetainsSavedFinalTextAcrossRestart() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MorieCandidates-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "captures.store")
        let captures = try CaptureStore(storageURL: url)
        let memory = MemoryStore(container: captures.container)
        let id = try capture(in: captures)
        let input = try memory.extractionInput(for: id)
        XCTAssertEqual(input.text, finalText)
        XCTAssertEqual(input.textKind, .finalText)
        try memory.saveCandidates([suggestion()], for: input)

        let reopened = try CaptureStore(storageURL: url)
        let reloaded = MemoryStore(container: reopened.container)
        try reloaded.load()
        XCTAssertEqual(reloaded.extractions.first?.input, input)
        XCTAssertEqual(reloaded.pendingCandidates.first?.suggestion.evidence, finalText)
        XCTAssertTrue(reloaded.entries.isEmpty, "Unreviewed suggestions must not enter relevant Memory")
        XCTAssertEqual(try reopened.capture(id).recognizedText, recognized)
        XCTAssertEqual(try reopened.capture(id).finalText, finalText)
    }

    func testSavedRecognitionIsUsedOnlyWhenFinalTextIsEmpty() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try capture(in: captures)
        let record = try captures.capture(id)
        record.finalText = " \n "
        try captures.container.mainContext.save()
        let input = try memory.extractionInput(for: id)
        XCTAssertEqual(input.text, recognized)
        XCTAssertEqual(input.textKind, .recognizedText)
    }

    func testUnsavedFinalTextAndRecordingCannotBecomeExtractionInput() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try capture(in: captures)
        let record = try captures.capture(id)
        record.finalText = "unsaved rewrite"
        XCTAssertThrowsError(try memory.extractionInput(for: id))
        XCTAssertEqual(record.finalText, "unsaved rewrite", "Read rejection must not roll back pending edits")
        captures.container.mainContext.rollback()
        let active = UUID()
        _ = try captures.beginVoiceCapture(id: active, deliveryMode: .captureOnly, applicationName: nil, bundleIdentifier: nil, windowNumber: nil)
        try captures.updateRecognizedText("still recording", for: active)
        XCTAssertThrowsError(try memory.extractionInput(for: active))
    }

    func testConfirmationSavesMemoryAndReviewDecisionTogether() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let candidate = try pendingCandidate(in: memory, source: source)
        XCTAssertTrue(try memory.relevantContext(for: "Morie").isEmpty)
        let id = try memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft)
        let record = try memory.memory(id)
        XCTAssertTrue(record.userConfirmed)
        XCTAssertEqual(record.confidence, 0.95)
        XCTAssertEqual(record.sourceCandidateID, candidate.id)
        XCTAssertEqual(record.sourceCaptureIDs, [source])
        XCTAssertEqual(try memory.candidate(candidate.id).candidate.status, .accepted)
        XCTAssertEqual(try memory.candidate(candidate.id).candidate.memoryID, id)
        XCTAssertEqual(try memory.relevantContext(for: "Morie").map(\.id), [id])
        XCTAssertThrowsError(try memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft))
        XCTAssertEqual(try captures.capture(source).recognizedText, recognized)
        XCTAssertEqual(try captures.capture(source).finalText, finalText)
    }

    func testEditedSuggestionDoesNotReuseConfidenceForDifferentContent() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let candidate = try pendingCandidate(in: memory, source: source)
        var draft = candidate.suggestion.draft
        draft.notes = "User-corrected project context"
        let id = try memory.acceptCandidate(candidate.id, draft: draft)
        XCTAssertNil(try memory.memory(id).confidence)
        XCTAssertEqual(try memory.memory(id).notes, draft.notes)
        XCTAssertEqual(try memory.candidate(candidate.id).extraction.sourceText, finalText)
    }

    func testDuplicateConflictLeavesCandidatePendingForExplicitLinking() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let candidate = try pendingCandidate(in: memory, source: source)
        let existing = try memory.create(MemoryDraft(kind: .project, name: "Morie", notes: "Original notes"))
        XCTAssertThrowsError(try memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft))
        XCTAssertEqual(try memory.candidate(candidate.id).candidate.status, .pending)
        XCTAssertEqual(memory.entries.count, 1)
        let linked = try memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft, existingMemoryID: existing)
        XCTAssertEqual(linked, existing)
        XCTAssertEqual(try memory.memory(existing).notes, "Original notes")
        XCTAssertEqual(try memory.memory(existing).sourceCaptureIDs, [source])
        XCTAssertNil(try memory.memory(existing).confidence)
    }

    func testArchivedMemoryCannotReceiveCandidateConfirmation() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let candidate = try pendingCandidate(in: memory, source: source)
        let existing = try memory.create(MemoryDraft(kind: .project, name: "Morie"))
        try memory.archive(existing)
        XCTAssertThrowsError(try memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft, existingMemoryID: existing))
        XCTAssertEqual(try memory.candidate(candidate.id).candidate.status, .pending)
        XCTAssertTrue(try memory.memory(existing).sourceCaptureIDs.isEmpty)
    }

    func testDismissalAndEmptyAnalysisSurviveRepeatedRequests() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let input = try memory.extractionInput(for: source)
        let candidate = try pendingCandidate(in: memory, source: source)
        try memory.dismissCandidate(candidate.id)
        try memory.saveCandidates([suggestion()], for: input)
        XCTAssertEqual(memory.extractions.count, 1)
        XCTAssertTrue(memory.pendingCandidates.isEmpty)
        XCTAssertEqual(try memory.candidate(candidate.id).candidate.status, .dismissed)

        let otherSource = try capture(in: captures)
        let otherInput = try memory.extractionInput(for: otherSource)
        let emptyID = try memory.saveCandidates([], for: otherInput)
        XCTAssertEqual(try memory.saveCandidates([suggestion()], for: otherInput), emptyID)
        XCTAssertTrue(try XCTUnwrap(memory.extraction(for: otherInput)).candidates.isEmpty)
    }

    func testUngroundedLowConfidenceAndDuplicateSuggestionsAreFiltered() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let invalidSets: [[MemorySuggestion]] = [
            [suggestion(evidence: "This quote was never said"), suggestion(confidence: 0.4), suggestion(confidence: .nan)],
            [suggestion(name: "Invented"), suggestion(aliases: ["Unstated alias"]), suggestion(name: "")],
            [suggestion(), suggestion(name: "ＭＯＲＩＥ")]
        ]
        for (index, suggestions) in invalidSets.enumerated() {
            let input = try memory.extractionInput(for: capture(in: captures))
            try memory.saveCandidates(suggestions, for: input)
            XCTAssertEqual(memory.extraction(for: input)?.candidates.count, index == 2 ? 1 : 0)
        }
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testOversizedCandidateBatchIsRejectedWithoutPartialPersistence() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let input = try memory.extractionInput(for: capture(in: captures))
        XCTAssertThrowsError(try memory.saveCandidates(Array(repeating: suggestion(), count: 4), for: input))
        XCTAssertTrue(memory.extractions.isEmpty)
        XCTAssertEqual(try captures.capture(input.captureID).finalText, finalText)
    }

    func testChangedFinalTextRejectsOldResultsAndOldCandidateReview() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let previousInput = try memory.extractionInput(for: source)
        let candidate = try pendingCandidate(in: memory, source: source)
        let record = try captures.capture(source)
        record.finalText = "Morie 是我新的个人记忆项目。"
        try captures.container.mainContext.save()
        XCTAssertThrowsError(try memory.saveCandidates([suggestion()], for: previousInput))
        XCTAssertThrowsError(try memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft))
        XCTAssertFalse(memory.isCurrent(try memory.candidate(candidate.id).extraction))
        let newInput = try memory.extractionInput(for: source)
        try memory.saveCandidates([suggestion(evidence: newInput.text)], for: newInput)
        XCTAssertEqual(memory.extractions.count, 2)
        XCTAssertEqual(try memory.candidate(candidate.id).extraction.sourceText, finalText)
        XCTAssertEqual(memory.extraction(for: newInput)?.sourceText, record.finalText)
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testSourceDeletionRemovesSnapshotsButKeepsConfirmedMemory() throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let candidate = try pendingCandidate(in: memory, source: source)
        let id = try memory.acceptCandidate(candidate.id, draft: candidate.suggestion.draft)
        try captures.deleteCapture(source)
        let reloaded = MemoryStore(container: captures.container)
        try reloaded.load()
        XCTAssertTrue(reloaded.extractions.isEmpty)
        XCTAssertEqual(try reloaded.memory(id).sourceCaptureIDs, [source])
        XCTAssertThrowsError(try reloaded.candidate(candidate.id))
        XCTAssertThrowsError(try reloaded.extractionInput(for: source))
    }

    func testControllerCancellationRejectsAResultThatIgnoresCancellation() async throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let pending = PendingExtraction()
        let controller = MemoryCandidateController(store: memory, extract: { input in try await pending.run(input) })
        controller.findCandidates(for: source)
        await pending.waitUntilStarted()
        controller.cancelExtraction()
        await pending.finish([suggestion()])
        await controller.waitForExtraction()
        XCTAssertNil(controller.extractingCaptureID)
        XCTAssertTrue(memory.extractions.isEmpty)
        XCTAssertTrue(memory.entries.isEmpty)
        XCTAssertEqual(try captures.capture(source).finalText, finalText)
    }

    func testLiveInputPreemptsExtractionWithoutWaitingForTheModel() async throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let pending = PendingExtraction()
        let controller = MemoryCandidateController(store: memory, extract: { input in try await pending.run(input) })
        controller.findCandidates(for: source)
        await pending.waitUntilStarted()
        controller.setInputActive(true)
        XCTAssertTrue(controller.isInputActive)
        controller.findCandidates(for: source)
        await pending.finish([suggestion()])
        await controller.waitForExtraction()
        XCTAssertTrue(memory.extractions.isEmpty)
        controller.setInputActive(false)
    }

    func testSourceChangeWhileModelRunsDoesNotPersistStaleResults() async throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let pending = PendingExtraction()
        let controller = MemoryCandidateController(store: memory, extract: { input in try await pending.run(input) })
        controller.findCandidates(for: source)
        await pending.waitUntilStarted()
        try captures.saveReRecognition("Updated source text", for: source)
        await pending.finish([suggestion()])
        await controller.waitForExtraction()
        XCTAssertTrue(memory.extractions.isEmpty)
        XCTAssertEqual(try captures.capture(source).finalText, "Updated source text")
    }

    func testSourceDeletionWhileModelRunsDoesNotRecreateCaptureOrSnapshots() async throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let pending = PendingExtraction()
        let controller = MemoryCandidateController(store: memory, extract: { input in try await pending.run(input) })
        controller.findCandidates(for: source)
        await pending.waitUntilStarted()
        try captures.deleteCapture(source)
        await pending.finish([suggestion()])
        await controller.waitForExtraction()
        XCTAssertTrue(memory.extractions.isEmpty)
        XCTAssertThrowsError(try captures.capture(source))
    }

    func testControllerFailureKeepsDataAndDoesNotExposeModelContent() async throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        _ = try memory.create(MemoryDraft(name: "Kept memory"))
        let controller = MemoryCandidateController(store: memory, extract: { _ in
            throw NSError(domain: "Test", code: 1, userInfo: [NSLocalizedDescriptionKey: "private model prompt"])
        })
        controller.findCandidates(for: source)
        await controller.waitForExtraction()
        XCTAssertFalse(controller.message?.contains("private model prompt") ?? true)
        XCTAssertNil(controller.extractingCaptureID)
        XCTAssertTrue(memory.extractions.isEmpty)
        XCTAssertEqual(memory.entries.count, 1)
        XCTAssertEqual(try captures.capture(source).recognizedText, recognized)
    }

    func testControllerReusesEmptyResultWithoutCallingModelAgain() async throws {
        let (captures, memory) = try stores()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try capture(in: captures)
        let pending = PendingExtraction()
        let controller = MemoryCandidateController(store: memory, extract: { input in try await pending.run(input) })
        controller.findCandidates(for: source)
        await pending.waitUntilStarted()
        await pending.finish([])
        await controller.waitForExtraction()
        controller.findCandidates(for: source)
        XCTAssertNil(controller.extractingCaptureID)
        XCTAssertEqual(memory.extractions.count, 1)
    }

    private func stores() throws -> (CaptureStore, MemoryStore) {
        let captures = try CaptureStore(inMemory: true)
        return (captures, MemoryStore(container: captures.container))
    }

    private func capture(in store: CaptureStore) throws -> UUID {
        let id = UUID()
        _ = try store.beginVoiceCapture(id: id, deliveryMode: .captureOnly, applicationName: "Test", bundleIdentifier: nil, windowNumber: nil)
        try store.completeRecognition(recognized, for: id)
        let record = try store.capture(id)
        record.finalText = finalText
        try store.container.mainContext.save()
        return id
    }

    private func pendingCandidate(in memory: MemoryStore, source: UUID) throws -> MemoryCandidate {
        let input = try memory.extractionInput(for: source)
        try memory.saveCandidates([suggestion()], for: input)
        return try XCTUnwrap(memory.extraction(for: input)?.candidates.first)
    }

    private func suggestion(name: String = "Morie", aliases: [String] = [], evidence: String? = nil, confidence: Double = 0.95) -> MemorySuggestion {
        MemorySuggestion(draft: MemoryDraft(kind: .project, name: name, aliases: aliases, notes: "个人输入项目"),
                         evidence: evidence ?? finalText, confidence: confidence)
    }
}

private actor PendingExtraction {
    private var continuation: CheckedContinuation<[MemorySuggestion], Error>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    func run(_ input: MemoryExtractionInput) async throws -> [MemorySuggestion] {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitUntilStarted() async {
        if continuation != nil { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func finish(_ suggestions: [MemorySuggestion]) {
        continuation?.resume(returning: suggestions)
        continuation = nil
    }
}
