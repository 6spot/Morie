import Foundation
import SwiftData
import XCTest

@MainActor
final class MemoryStoreTests: XCTestCase {
    func testConfirmedMemoryAndProvenanceSurviveRestartWithoutChangingCapture() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "captures.store")
        let captures = try CaptureStore(storageURL: url)
        let sourceID = try completedCapture(in: captures)
        let memory = MemoryStore(container: captures.container)
        try memory.load()
        XCTAssertTrue(memory.entries.isEmpty, "Saving a Capture must not automatically create Memory")

        let id = try memory.create(MemoryDraft(kind: .project, name: "Morie", aliases: ["莫里"], notes: "个人输入项目"), sourceCaptureID: sourceID)
        let reopened = try CaptureStore(storageURL: url)
        let reloadedMemory = MemoryStore(container: reopened.container)
        let record = try reloadedMemory.memory(id)

        XCTAssertEqual(record.kind, .project)
        XCTAssertEqual(record.status, .active)
        XCTAssertEqual(record.name, "Morie")
        XCTAssertEqual(record.aliases, ["莫里"])
        XCTAssertEqual(record.notes, "个人输入项目")
        XCTAssertEqual(record.sourceCaptureIDs, [sourceID])
        XCTAssertTrue(record.userConfirmed)
        XCTAssertNil(record.confidence, "Manual confirmation must not invent model confidence")
        let source = try reopened.capture(sourceID)
        XCTAssertEqual(source.recognizedText, "Morie source text")
        XCTAssertEqual(source.finalText, "Morie source text")
        XCTAssertEqual(source.lifecycle, .delivered)
    }

    func testManualMemoryNormalizesAliasesWithoutInventingProvenance() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try memory.create(MemoryDraft(name: " Morie ", aliases: ["ＭＯＲＩＥ", "莫里", " 莫里 ", "More E"], notes: " project notes "))
        let record = try memory.memory(id)
        XCTAssertEqual(record.name, "Morie")
        XCTAssertEqual(record.aliases, ["莫里", "More E"])
        XCTAssertEqual(record.notes, "project notes")
        XCTAssertTrue(record.sourceCaptureIDs.isEmpty)
    }

    func testDuplicateActiveNamesAreRejectedWithinKind() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try memory.create(MemoryDraft(name: "Morie"))
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "  ＭＯＲＩＥ  ")))
        let projectID = try memory.create(MemoryDraft(kind: .project, name: "Morie"))
        XCTAssertNotEqual(projectID, id)
        XCTAssertEqual(memory.entries.count, 2)
    }

    func testInvalidDraftsDoNotCreateOrOverwriteMemory() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try memory.create(MemoryDraft(name: "Kept", notes: "original"))
        for draft in [
            MemoryDraft(name: " \n "),
            MemoryDraft(name: "two\nlines"),
            MemoryDraft(name: String(repeating: "x", count: 121)),
            MemoryDraft(name: "name", aliases: ["invalid\nalias"]),
            MemoryDraft(name: "name", aliases: Array(repeating: "alias", count: 21)),
            MemoryDraft(name: "name", notes: String(repeating: "x", count: 2_001))
        ] {
            XCTAssertThrowsError(try memory.update(id, draft: draft))
            XCTAssertThrowsError(try memory.create(draft))
        }
        XCTAssertEqual(memory.entries.count, 1)
        XCTAssertEqual(try memory.memory(id).name, "Kept")
        XCTAssertEqual(try memory.memory(id).notes, "original")
    }

    func testSourceMustExistAndHaveCompletedText() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let sourceID = UUID()
        _ = try captures.beginVoiceCapture(id: sourceID, deliveryMode: .captureOnly, applicationName: nil, bundleIdentifier: nil, windowNumber: nil)
        try captures.updateRecognizedText("in progress", for: sourceID)
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "Morie"), sourceCaptureID: sourceID))
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "Morie"), sourceCaptureID: UUID()))
        try captures.updateRecognizedText("", for: sourceID)
        try captures.markFailed(sourceID, error: "no text")
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "Morie"), sourceCaptureID: sourceID))
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testEditingKeepsIdentityAndSourceWhileChangingCurrentContext() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try completedCapture(in: captures)
        let id = try memory.create(MemoryDraft(name: "Before"), sourceCaptureID: source)
        let createdAt = try memory.memory(id).createdAt

        try memory.update(id, draft: MemoryDraft(name: "After", aliases: ["New name"], notes: "updated"))

        let entry = try memory.memory(id)
        XCTAssertEqual(entry.createdAt, createdAt)
        XCTAssertEqual(entry.sourceCaptureIDs, [source])
        XCTAssertEqual(entry.name, "After")
        XCTAssertTrue(try memory.relevantContext(for: "Before").isEmpty)
        XCTAssertEqual(try memory.relevantContext(for: "New name").map(\.id), [id])
        XCTAssertEqual(try captures.capture(source).finalText, "Morie source text")
    }

    func testLinkingSourcesIsIdempotentAndSurvivesSourceDeletion() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let first = try completedCapture(in: captures)
        let second = try completedCapture(in: captures)
        let id = try memory.create(MemoryDraft(name: "Morie", notes: "confirmed"), sourceCaptureID: first)
        try memory.addSource(second, to: id)
        try memory.addSource(second, to: id)
        try captures.deleteCapture(first)

        XCTAssertEqual(try memory.memory(id).sourceCaptureIDs, [first, second])
        XCTAssertEqual(try memory.memory(id).notes, "confirmed")
        XCTAssertEqual(try memory.relevantContext(for: "Morie").map(\.id), [id])
        XCTAssertThrowsError(try memory.addSource(first, to: id))
    }

    func testArchiveRemovesContextAndRestoreRejectsAnActiveNameCollision() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try memory.create(MemoryDraft(name: "Morie"))
        try memory.archive(id)
        XCTAssertTrue(try memory.relevantContext(for: "Morie").isEmpty)
        try memory.restore(id)
        XCTAssertEqual(try memory.relevantContext(for: "Morie").map(\.id), [id])
        try memory.archive(id)
        let newID = try memory.create(MemoryDraft(name: "Morie"))
        XCTAssertThrowsError(try memory.restore(id))
        XCTAssertEqual(try memory.memory(id).status, .archived)
        XCTAssertEqual(try memory.relevantContext(for: "Morie").map(\.id), [newID])
    }

    func testReplacementPreservesProvenanceAndExcludesSupersededMemory() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try completedCapture(in: captures)
        let oldID = try memory.create(MemoryDraft(kind: .project, name: "Old project"), sourceCaptureID: source)
        let newID = try memory.replace(oldID, with: MemoryDraft(kind: .project, name: "New project"))

        XCTAssertEqual(try memory.memory(oldID).status, .superseded)
        XCTAssertEqual(try memory.memory(newID).supersedesID, oldID)
        XCTAssertEqual(try memory.memory(newID).sourceCaptureIDs, [source])
        XCTAssertEqual(try memory.relevantContext(for: "Old project and New project").map(\.id), [newID])
        XCTAssertThrowsError(try memory.restore(oldID))
        XCTAssertThrowsError(try memory.update(oldID, draft: MemoryDraft(name: "stale")))
        XCTAssertThrowsError(try memory.replace(oldID, with: MemoryDraft(name: "another")))
    }

    func testReplacementConflictLeavesOriginalActive() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let oldID = try memory.create(MemoryDraft(name: "Old"))
        _ = try memory.create(MemoryDraft(name: "Existing"))
        XCTAssertThrowsError(try memory.replace(oldID, with: MemoryDraft(name: "Existing")))
        XCTAssertEqual(try memory.memory(oldID).status, .active)
        XCTAssertEqual(memory.entries.count, 2)
    }

    func testMemoryDeletionKeepsCaptureAndOtherMemories() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try completedCapture(in: captures)
        let first = try memory.create(MemoryDraft(name: "First"), sourceCaptureID: source)
        let second = try memory.create(MemoryDraft(name: "Second"), sourceCaptureID: source)
        try memory.delete(first)
        XCTAssertThrowsError(try memory.memory(first))
        XCTAssertEqual(try memory.memory(second).sourceCaptureIDs, [source])
        XCTAssertEqual(try captures.capture(source).lifecycle, .delivered)
    }

    private func temporaryStore() throws -> (CaptureStore, MemoryStore) {
        let captures = try CaptureStore(inMemory: true)
        return (captures, MemoryStore(container: captures.container))
    }

    private func completedCapture(in store: CaptureStore) throws -> UUID {
        let id = UUID()
        _ = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: "Test", bundleIdentifier: "me.morie.tests", windowNumber: nil)
        try store.completeRecognition("Morie source text", for: id)
        try store.markDelivered(id)
        return id
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "MorieMemoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

final class MemoryContextRetrieverTests: XCTestCase {
    func testChineseEnglishAndAliasesMatchWithoutPartialLatinWords() {
        let morie = memory("Morie", aliases: ["莫里"])
        let project = memory("北极星计划", kind: .project)
        let git = memory("Git")
        let cpp = memory("C++")
        let entries = [morie, project, git, cpp]

        XCTAssertEqual(Set(retrieve("讨论北极星计划，以及ＭＯＲＩＥ。", entries).map(\.id)), Set([morie.id, project.id]))
        XCTAssertEqual(retrieve("用莫里记录想法", entries).map(\.id), [morie.id])
        XCTAssertTrue(retrieve("GitHub and C language", entries).isEmpty)
        XCTAssertEqual(retrieve("Write C++ code", entries).map(\.id), [cpp.id])
        XCTAssertEqual(retrieve("Git and git", entries).map(\.id), [git.id])
    }

    func testOnlyActiveConfirmedMemoryParticipates() {
        let active = memory("Morie")
        let entries = [active, memory("Morie", status: .archived), memory("Morie", status: .superseded), memory("Morie", confirmed: false)]
        XCTAssertEqual(retrieve("Morie", entries).map(\.id), [active.id])
    }

    func testCanonicalAndSpecificMatchesHaveDeterministicPriority() {
        let general = memory("Morie")
        let specific = memory("Morie Project")
        let alias = memory("Other name", aliases: ["Morie Project"])
        let expected = [specific.id, general.id, alias.id]
        XCTAssertEqual(retrieve("Morie Project", [general, alias, specific]).map(\.id), expected)
        XCTAssertEqual(retrieve("Morie Project", [specific, general, alias]).map(\.id), expected)
    }

    func testEmptyInputAndResultLimitsAreBounded() {
        let entries = (0..<12).map { memory("Term\($0)") }
        let query = entries.map(\.name).joined(separator: " ")
        XCTAssertEqual(MemoryContextRetriever.retrieve(for: query, from: entries, limit: 100).count, 8)
        XCTAssertEqual(MemoryContextRetriever.retrieve(for: query, from: entries, limit: 2).count, 2)
        XCTAssertTrue(MemoryContextRetriever.retrieve(for: query, from: entries, limit: 0).isEmpty)
        XCTAssertTrue(retrieve(" \n ... ", entries).isEmpty)
        XCTAssertTrue(retrieve("Unrelated content", entries).isEmpty)
    }

    func testMostSpecificMatchingAliasDeterminesRanking() {
        let specific = memory("First", aliases: ["Morie", "Morie Project"])
        let general = memory("Second", aliases: ["Morie"])
        let result = retrieve("Morie Project", [general, specific])
        XCTAssertEqual(result.map(\.id), [specific.id, general.id])
        XCTAssertEqual(result.first?.matchedTerm, "Morie Project")
    }

    private func memory(
        _ name: String, aliases: [String] = [], kind: MemoryKind = .vocabulary,
        status: MemoryStatus = .active, confirmed: Bool = true
    ) -> MemorySnapshot {
        MemorySnapshot(id: UUID(), kind: kind, status: status, name: name, aliases: aliases,
                       notes: "notes", userConfirmed: confirmed, updatedAt: Date(timeIntervalSince1970: 1))
    }

    private func retrieve(_ text: String, _ entries: [MemorySnapshot]) -> [MemoryContextMatch] {
        MemoryContextRetriever.retrieve(for: text, from: entries)
    }
}
