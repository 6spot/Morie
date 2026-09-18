import Foundation
import XCTest

@MainActor
final class DictionaryTests: XCTestCase {
    func testWordsAndExplicitAliasesSurviveRestartSeparatelyFromMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MorieDictionary-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "store")
        let captures = try CaptureStore(storageURL: url)
        let dictionary = DictionaryStore(container: captures.container)
        let id = try dictionary.create(DictionaryDraft(name: " Morie ", aliases: ["ＭＯＲＩＥ", "more e", " more e ", "莫里"]))
        let reopened = try CaptureStore(storageURL: url)
        let loaded = DictionaryStore(container: reopened.container)
        try loaded.load()
        let entry = try XCTUnwrap(loaded.entries.first)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.name, "Morie")
        XCTAssertEqual(entry.aliases, ["more e", "莫里"])
        let memory = MemoryStore(container: reopened.container)
        try memory.load()
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testConflictingAliasesAndCanonicalNamesCannotCreateAmbiguousRules() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        let first = try store.create(DictionaryDraft(name: "Morie", aliases: ["more e"]))
        XCTAssertThrowsError(try store.create(DictionaryDraft(name: "MORE E")))
        XCTAssertThrowsError(try store.create(DictionaryDraft(name: "Another", aliases: ["ＭＯＲＩＥ"])))
        let second = try store.create(DictionaryDraft(name: "Second"))
        XCTAssertThrowsError(try store.update(second, draft: DictionaryDraft(name: "Second", aliases: ["more e"])))
        XCTAssertEqual(store.entries.count, 2)
        try store.update(first, draft: DictionaryDraft(name: "Morie", aliases: ["莫里"]))
        XCTAssertNoThrow(try store.create(DictionaryDraft(name: "More E")))
    }

    func testInvalidWordsDoNotOverwriteSavedEntries() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        let id = try store.create(DictionaryDraft(name: "Kept"))
        for draft in [DictionaryDraft(name: ""), DictionaryDraft(name: "two\nlines"),
                      DictionaryDraft(name: String(repeating: "x", count: 121)),
                      DictionaryDraft(name: "Word", aliases: ["bad\nalias"]),
                      DictionaryDraft(name: "Word", aliases: Array(repeating: "alias", count: 21))] {
            XCTAssertThrowsError(try store.update(id, draft: draft))
        }
        XCTAssertEqual(store.entries.first?.name, "Kept")
    }

    func testExplicitAliasesUseWholeWordsAndDoNotCascadeOrEditTechnicalContent() throws {
        let entries = [snapshot("Morie", aliases: ["more e", "莫里"]), snapshot("Git", aliases: ["git"]), snapshot("Second", aliases: ["Morie"])]
        let result = DictionaryReplacer.replace("不要发布 more e 2.0，用莫里记录 GitHub。`more e` https://more.e", using: entries)
        XCTAssertEqual(result.text, "不要发布 Morie 2.0，用Morie记录 GitHub。`more e` https://more.e")
        XCTAssertEqual(result.edits.count, 2)
        XCTAssertTrue(DictionaryReplacer.replace("more extra", using: entries).edits.isEmpty)
    }

    func testLongestOverlappingAliasWinsDeterministically() {
        let entries = [snapshot("Morie", aliases: ["more"]), snapshot("Morie Pro", aliases: ["more pro"])]
        XCTAssertEqual(DictionaryReplacer.replace("use more pro", using: entries).text, "use Morie Pro")
        XCTAssertEqual(DictionaryReplacer.replace("use more pro", using: entries.reversed()).text, "use Morie Pro")
    }

    func testSpellingHintsNeedNoReplacementAliasAndAreBounded() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        let id = try store.create(DictionaryDraft(name: "Morie"))
        XCTAssertEqual(try store.speechHints(), ["Morie"])
        XCTAssertTrue(DictionaryReplacer.replace("more e", using: store.entries.map(\.snapshot)).edits.isEmpty)
        try store.delete(id)
        XCTAssertTrue(try store.speechHints().isEmpty)
    }

    private func snapshot(_ name: String, aliases: [String]) -> DictionarySnapshot {
        DictionarySnapshot(id: UUID(), name: name, aliases: aliases, updatedAt: Date())
    }
}
