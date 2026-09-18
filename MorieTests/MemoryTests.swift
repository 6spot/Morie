import Foundation
import SwiftData
import XCTest

@MainActor
final class MemoryStoreTests: XCTestCase {
    func testUserMemoryAndProvenanceSurviveRestartWithoutChangingCapture() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "captures.store")
        let captures = try CaptureStore(storageURL: url)
        let sourceID = try completedCapture(in: captures)
        let memory = MemoryStore(container: captures.container)
        try memory.load()
        XCTAssertTrue(memory.entries.isEmpty, "Saving input alone must not invent a personal fact before analysis")

        let id = try memory.create(MemoryDraft(kind: .project, name: "Morie", notes: "个人输入项目"), sourceCaptureID: sourceID)
        let reopened = try CaptureStore(storageURL: url)
        let reloadedMemory = MemoryStore(container: reopened.container)
        let record = try reloadedMemory.memory(id)

        XCTAssertEqual(record.kind, .project)
        XCTAssertEqual(record.status, .active)
        XCTAssertEqual(record.name, "Morie")
        XCTAssertEqual(record.notes, "个人输入项目")
        XCTAssertEqual(record.sourceCaptureIDs, [sourceID])
        XCTAssertEqual(record.origin, .user)
        XCTAssertNil(record.confidence, "Manual editing must not invent model confidence")
        let source = try reopened.capture(sourceID)
        XCTAssertEqual(source.recognizedText, "Morie source text")
        XCTAssertEqual(source.finalText, "Morie source text")
        XCTAssertEqual(source.lifecycle, .delivered)
    }

    func testManualMemoryNormalizesTextWithoutInventingProvenance() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try memory.create(MemoryDraft(name: " 工作项目 ", notes: " 我在开发 Morie。 "))
        let record = try memory.memory(id)
        XCTAssertEqual(record.name, "工作项目")
        XCTAssertEqual(record.notes, "我在开发 Morie。")
        XCTAssertEqual(record.origin, .user)
        XCTAssertTrue(record.sourceCaptureIDs.isEmpty)
    }

    func testDuplicateActiveNamesAreRejectedWithinKind() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try memory.create(MemoryDraft(name: "Morie", notes: "personal information"))
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "  ＭＯＲＩＥ  ", notes: "personal information")))
        let projectID = try memory.create(MemoryDraft(kind: .project, name: "Morie", notes: "personal project"))
        XCTAssertNotEqual(projectID, id)
        XCTAssertEqual(memory.entries.count, 2)
    }

    func testInvalidDraftsDoNotCreateOrOverwriteMemory() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let id = try memory.create(MemoryDraft(name: "Kept", notes: "original"))
        for draft in [
            MemoryDraft(name: " \n ", notes: "personal information"),
            MemoryDraft(name: "two\nlines", notes: "personal information"),
            MemoryDraft(name: String(repeating: "x", count: 121)),
            MemoryDraft(name: "name", notes: ""),
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
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "Morie", notes: "personal information"), sourceCaptureID: sourceID))
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "Morie", notes: "personal information"), sourceCaptureID: UUID()))
        try captures.updateRecognizedText("", for: sourceID)
        try captures.markFailed(sourceID, error: "no text")
        XCTAssertThrowsError(try memory.create(MemoryDraft(name: "Morie", notes: "personal information"), sourceCaptureID: sourceID))
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testEditingKeepsIdentityAndSourceWhileChangingCurrentContext() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try completedCapture(in: captures)
        let id = try memory.create(MemoryDraft(name: "Before", notes: "personal information"), sourceCaptureID: source)
        let createdAt = try memory.memory(id).createdAt

        try memory.update(id, draft: MemoryDraft(name: "After", notes: "updated"))

        let entry = try memory.memory(id)
        XCTAssertEqual(entry.createdAt, createdAt)
        XCTAssertEqual(entry.sourceCaptureIDs, [source])
        XCTAssertEqual(entry.name, "After")
        XCTAssertTrue(try memory.relevantContext(for: "Before").isEmpty)
        XCTAssertEqual(try memory.relevantContext(for: "After").map(\.id), [id])
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
        let id = try memory.create(MemoryDraft(name: "Morie", notes: "personal information"))
        try memory.archive(id)
        XCTAssertTrue(try memory.relevantContext(for: "Morie").isEmpty)
        try memory.restore(id)
        XCTAssertEqual(try memory.relevantContext(for: "Morie").map(\.id), [id])
        try memory.archive(id)
        let newID = try memory.create(MemoryDraft(name: "Morie", notes: "personal information"))
        XCTAssertThrowsError(try memory.restore(id))
        XCTAssertEqual(try memory.memory(id).status, .archived)
        XCTAssertEqual(try memory.relevantContext(for: "Morie").map(\.id), [newID])
    }

    func testReplacementPreservesProvenanceAndExcludesSupersededMemory() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try completedCapture(in: captures)
        let oldID = try memory.create(MemoryDraft(kind: .project, name: "Old project", notes: "personal project"), sourceCaptureID: source)
        let newID = try memory.replace(oldID, with: MemoryDraft(kind: .project, name: "New project", notes: "personal project"))

        XCTAssertEqual(try memory.memory(oldID).status, .superseded)
        XCTAssertEqual(try memory.memory(newID).supersedesID, oldID)
        XCTAssertEqual(try memory.memory(newID).sourceCaptureIDs, [source])
        XCTAssertEqual(try memory.relevantContext(for: "Old project and New project").map(\.id), [newID])
        XCTAssertThrowsError(try memory.restore(oldID))
        XCTAssertThrowsError(try memory.update(oldID, draft: MemoryDraft(name: "stale", notes: "personal information")))
        XCTAssertThrowsError(try memory.replace(oldID, with: MemoryDraft(name: "another", notes: "personal information")))
    }

    func testReplacementConflictLeavesOriginalActive() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let oldID = try memory.create(MemoryDraft(name: "Old", notes: "personal information"))
        _ = try memory.create(MemoryDraft(name: "Existing", notes: "personal information"))
        XCTAssertThrowsError(try memory.replace(oldID, with: MemoryDraft(name: "Existing", notes: "personal information")))
        XCTAssertEqual(try memory.memory(oldID).status, .active)
        XCTAssertEqual(memory.entries.count, 2)
    }

    func testMemoryDeletionKeepsCaptureAndOtherMemories() throws {
        let (captures, memory) = try temporaryStore()
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let source = try completedCapture(in: captures)
        let first = try memory.create(MemoryDraft(name: "First", notes: "personal information"), sourceCaptureID: source)
        let second = try memory.create(MemoryDraft(name: "Second", notes: "personal information"), sourceCaptureID: source)
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
    func testAutomaticAndUserMemoryAreAvailableButInactiveEntriesAreExcluded() {
        let learned = memory("Morie", origin: .automatic)
        let manual = memory("Morie team", origin: .user)
        let inactive = [memory("Morie", status: .archived), memory("Morie", status: .superseded)]
        let result = MemoryContextRetriever.retrieve(for: "Morie team", from: inactive + [learned, manual])
        XCTAssertEqual(Set(result.map(\.id)), Set([learned.id, manual.id]))
    }

    func testContentRelevanceAndNativeWordBoundaries() {
        let project = memory("当前项目", notes: "我在开发 Morie。")
        let unrelated = memory("Git", notes: "我维护 Git 工具。")
        XCTAssertEqual(MemoryContextRetriever.retrieve(for: "Morie 的输入体验", from: [unrelated, project]).map(\.id), [project.id])
        XCTAssertTrue(MemoryContextRetriever.retrieve(for: "GitHub", from: [unrelated]).isEmpty)
    }

    func testEmptyContextAndLimitsAreBounded() {
        let records = (0..<12).map { memory("Project\($0)") }
        let query = records.map(\.name).joined(separator: " ")
        XCTAssertEqual(MemoryContextRetriever.retrieve(for: query, from: records, limit: 100).count, 8)
        XCTAssertEqual(MemoryContextRetriever.retrieve(for: query, from: records, limit: 2).count, 2)
        XCTAssertTrue(MemoryContextRetriever.retrieve(for: query, from: records, limit: 0).isEmpty)
        XCTAssertTrue(MemoryContextRetriever.retrieve(for: "", from: records).isEmpty)
        XCTAssertTrue(MemoryContextRetriever.retrieve(for: "我的这个现在可以", from: records).isEmpty)
    }

    private func memory(_ name: String, notes: String = "personal information", status: MemoryStatus = .active, origin: MemoryOrigin = .automatic) -> MemorySnapshot {
        MemorySnapshot(id: UUID(), kind: .project, status: status, name: name, notes: notes, origin: origin, updatedAt: Date(timeIntervalSince1970: 1))
    }
}
