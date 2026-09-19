import Foundation
import XCTest

@MainActor
final class DictionaryTests: XCTestCase {
    func testSpeechSegmentsPreserveNativeSpacingWithoutInventingSeparators() {
        XCTAssertEqual(SpeechTranscriptAssembler.join("常", "蚊"), "常蚊")
        XCTAssertEqual(SpeechTranscriptAssembler.join("常蚊", "子"), "常蚊子")
        XCTAssertEqual(SpeechTranscriptAssembler.join("hello ", "world"), "hello world")
    }

    func testWordsSurviveRestartSeparatelyFromMemory() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MorieDictionary-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "store")
        let captures = try CaptureStore(storageURL: url)
        let dictionary = DictionaryStore(container: captures.container)
        let id = try dictionary.create(DictionaryDraft(name: " ProjectMorie "))
        let snapshot = try XCTUnwrap(dictionary.entries.first?.snapshot)
        let reopened = try CaptureStore(storageURL: url)
        let loaded = DictionaryStore(container: reopened.container)
        try loaded.load()
        let entry = try XCTUnwrap(loaded.entries.first)
        XCTAssertEqual(entry.id, id)
        XCTAssertEqual(entry.name, "ProjectMorie")
        XCTAssertEqual(entry.snapshot, snapshot)
        let memory = MemoryStore(container: reopened.container)
        try memory.load()
        XCTAssertTrue(memory.entries.isEmpty)
    }

    func testDuplicateWordsAreRejectedWithoutOverwritingSavedEntries() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        let first = try store.create(DictionaryDraft(name: "Morie"))
        XCTAssertThrowsError(try store.create(DictionaryDraft(name: " morie ")))
        let fullWidth = try store.create(DictionaryDraft(name: "ＭＯＲＩＥ"))
        let second = try store.create(DictionaryDraft(name: "Second"))
        XCTAssertThrowsError(try store.update(second, draft: DictionaryDraft(name: "MORIE")))
        XCTAssertEqual(store.entries.count, 3)
        XCTAssertEqual(store.entries.first(where: { $0.id == fullWidth })?.name, "ＭＯＲＩＥ")
        XCTAssertEqual(store.entries.first(where: { $0.id == second })?.name, "Second")
        try store.update(first, draft: DictionaryDraft(name: "MORIE"))
        XCTAssertEqual(store.entries.first(where: { $0.id == first })?.name, "MORIE")
        try store.update(first, draft: DictionaryDraft(name: "Morie Pro"))
        XCTAssertNoThrow(try store.create(DictionaryDraft(name: "Morie")))
    }

    func testInvalidWordsDoNotOverwriteSavedEntries() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        let id = try store.create(DictionaryDraft(name: "Kept"))
        for word in ["", " \n ", "two\nlines", "two\u{2028}lines", "two\u{2029}lines", "a\tb", String(repeating: "x", count: 121)] {
            XCTAssertThrowsError(try store.update(id, draft: DictionaryDraft(name: word)))
        }
        XCTAssertEqual(store.entries.first?.name, "Kept")
    }

    func testWordsOnlyNormalizeTheirOwnSpellingAndPreserveOtherText() {
        let entries = [snapshot("Morie"), snapshot("Git"), snapshot("项目")]
        let input = "不要发布 morie 2.0，用ＭＯＲＩＥ记录项目。GitHub more e 莫里。`morie` https://morie.app /morie/run morie_name"
        let result = DictionarySpelling.normalize(input, using: entries)
        XCTAssertEqual(result.text, "不要发布 Morie 2.0，用ＭＯＲＩＥ记录项目。GitHub more e 莫里。`morie` https://morie.app /morie/run morie_name")
        XCTAssertEqual(result.edits.count, 1)
        XCTAssertEqual(result.edits.map(\.dictionaryEntryID), [entries[0].id])
        XCTAssertTrue(DictionarySpelling.normalize("Morie more e 莫里 GitHub", using: entries).edits.isEmpty)
    }

    func testLongestWordWinsEvenWhenItsSpellingAlreadyMatches() {
        let entries = [snapshot("Morie"), snapshot("MORIE Pro")]
        for words in [entries, entries.reversed()] {
            XCTAssertEqual(DictionarySpelling.normalize("use morie pro", using: words).text, "use MORIE Pro")
            XCTAssertTrue(DictionarySpelling.normalize("use MORIE Pro", using: words).edits.isEmpty)
        }
    }

    func testSavedWordSuppliesHintsAndCleanupContextEvenWhenRecognitionMisspellsIt() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        let id = try store.create(DictionaryDraft(name: "UserSpecificTerm"))
        XCTAssertTrue(try store.speechHints().contains("UserSpecificTerm"))
        XCTAssertTrue(try store.relevantEntries(for: "use user specific term").map(\.id).contains(id))
        try store.delete(id)
        XCTAssertFalse(try store.speechHints().contains("UserSpecificTerm"))
        XCTAssertFalse(try store.relevantEntries(for: "UserSpecificTerm").map(\.id).contains(id))
        XCTAssertTrue(try store.speechHints().contains("GitHub"))
    }

    func testBuiltInWordsAreReadOnlyAndUserEntriesOverrideTheirDisplaySource() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        try store.load()
        let builtIn = try XCTUnwrap(store.displayEntries.first(where: { $0.name == "GitHub" }))
        XCTAssertEqual(builtIn.source, .builtIn)
        XCTAssertFalse(builtIn.isEditable)

        let id = try store.create(DictionaryDraft(name: "github"))
        let overridden = try XCTUnwrap(store.displayEntries.first(where: {
            $0.name.caseInsensitiveCompare("github") == .orderedSame
        }))
        XCTAssertEqual(overridden.id, id)
        XCTAssertEqual(overridden.source, .manual)
        XCTAssertEqual(store.displayEntries.filter {
            $0.name.caseInsensitiveCompare("github") == .orderedSame
        }.count, 1)
    }

    func testManualAndCorrectionSourcesPersistSeparately() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "MorieDictionarySource-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "store")
        let captures = try CaptureStore(storageURL: url)
        let dictionary = DictionaryStore(container: captures.container)
        let manualID = try dictionary.create(DictionaryDraft(name: "ManualTerm"))
        let correctionID = try dictionary.create(DictionaryDraft(name: "CorrectedTerm"), source: .correction)

        let reopened = try CaptureStore(storageURL: url)
        let loaded = DictionaryStore(container: reopened.container)
        try loaded.load()
        XCTAssertEqual(loaded.entries.first(where: { $0.id == manualID })?.source, .manual)
        XCTAssertEqual(loaded.entries.first(where: { $0.id == correctionID })?.source, .correction)
    }

    func testSpeechHintsRespectWordAndCharacterBudgets() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = DictionaryStore(container: captures.container)
        var ids: [UUID] = []
        for index in 0..<105 { ids.append(try store.create(DictionaryDraft(name: "Term \(index)"))) }
        XCTAssertEqual(try store.speechHints().count, 100)
        for (index, id) in ids.enumerated() {
            try store.update(id, draft: DictionaryDraft(name: "\(index) " + String(repeating: "x", count: 110)))
        }
        let hints = try store.speechHints()
        XCTAssertFalse(hints.isEmpty)
        XCTAssertLessThanOrEqual(hints.reduce(0) { $0 + $1.count }, 2_000)
        XCTAssertLessThan(hints.count, 100)
    }

    private func snapshot(_ name: String) -> DictionarySnapshot {
        DictionarySnapshot(id: UUID(), name: name, updatedAt: Date())
    }
}
