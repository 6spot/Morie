import Foundation
import XCTest

final class DictionaryCorrectionTests: XCTestCase {
    func testChangedLettersExpandToWholeWord() throws {
        let correction = try XCTUnwrap(DictionaryCorrectionDetector.detect(original: "I use Cloud for this", edited: "I use Claude for this"))
        XCTAssertEqual(correction.original, "Cloud")
        XCTAssertEqual(correction.replacement, "Claude")
    }

    func testChineseTermAndMixedLanguageCorrection() throws {
        let chinese = try XCTUnwrap(DictionaryCorrectionDetector.detect(original: "这个借口需要更新", edited: "这个接口需要更新"))
        XCTAssertEqual(chinese.replacement, "接口")
        let mixed = try XCTUnwrap(DictionaryCorrectionDetector.detect(original: "I work on more e today", edited: "I work on Morie today"))
        XCTAssertEqual(mixed.original, "more e")
        XCTAssertEqual(mixed.replacement, "Morie")
    }

    func testAddedDeletedAndJoinedLettersRemainWholeWordCorrections() throws {
        for (before, after) in [("Claud", "Claude"), ("Microssoft", "Microsoft"), ("Open AI", "OpenAI"), ("Gramerly", "Grammarly")] {
            let correction = try XCTUnwrap(DictionaryCorrectionDetector.detect(original: "Use \(before) today", edited: "Use \(after) today"), before)
            XCTAssertEqual(correction.original, before)
            XCTAssertEqual(correction.replacement, after)
        }
    }

    func testAppendsDeletionPunctuationNumbersCodeAndSentenceRewriteAreNotWords() {
        let pairs = [
            ("hello", "hello there"), ("hello there", "hello"), ("hello", "hello!"),
            ("send 15 items", "send 16 items"), ("use `Cloud`", "use `Claude`"),
            ("use https://morie.app", "use https://moria.app"),
            ("I want to ship this today", "We should completely change the entire plan"),
            ("hello", "Hello"), ("hello", "hello")
        ]
        for (before, after) in pairs { XCTAssertNil(DictionaryCorrectionDetector.detect(original: before, edited: after), before) }
    }

    func testIntermediateTypingWaitsForStableCorrectionAndUndoResetsIt() throws {
        let start = Date(timeIntervalSince1970: 0)
        var tracker = DictionaryCorrectionTracker(original: "I use Cloud")
        XCTAssertNil(tracker.observe("I use Cl", at: start))
        XCTAssertNil(tracker.observe("I use Clau", at: start.addingTimeInterval(1)))
        XCTAssertNil(tracker.observe("I use Claude", at: start.addingTimeInterval(2)))
        XCTAssertNil(tracker.observe("I use Claude", at: start.addingTimeInterval(3)))
        XCTAssertEqual(tracker.observe("I use Claude", at: start.addingTimeInterval(4))?.replacement, "Claude")
        XCTAssertNil(tracker.observe("I use Cloud", at: start.addingTimeInterval(5)))
        XCTAssertNil(tracker.observe("I use Claude", at: start.addingTimeInterval(6)))
    }

    func testOversizedInputIsNotObserved() {
        XCTAssertNil(DictionaryCorrectionDetector.detect(original: String(repeating: "x", count: 1_201), edited: "word"))
    }
}
