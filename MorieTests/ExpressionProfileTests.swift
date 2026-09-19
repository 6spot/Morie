import Foundation
import XCTest

@MainActor
final class ExpressionProfileTests: XCTestCase {
    func testExtractorAcceptsStyleOnlyEditsAndRejectsContentChanges() throws {
        let style = try XCTUnwrap(ExpressionStyleExtractor.extract(
            injected: "今天测试Morie然后继续处理这个问题",
            edited: "今天测试 Morie，然后继续处理这个问题。"
        ))
        XCTAssertEqual(style.directions[.terminalPunctuationUsage], 1)
        XCTAssertNotNil(style.values[.chineseEnglishSpacing])

        XCTAssertNil(ExpressionStyleExtractor.extract(
            injected: "今天我们去北京处理这个问题",
            edited: "今天我们去上海处理这个问题。"
        ))
        XCTAssertNil(ExpressionStyleExtractor.extract(
            injected: "版本是 16，今天继续测试",
            edited: "版本是 17，今天继续测试。"
        ))
    }

    func testListAndLineBreakFormattingCanBeLearnedWithoutChangingWords() throws {
        let sample = try XCTUnwrap(ExpressionStyleExtractor.extract(
            injected: "第一件事修登录问题\n第二件事看GitHub issue",
            edited: "- 第一件事修登录问题\n- 第二件事看 GitHub issue"
        ))
        XCTAssertEqual(sample.directions[.listUsage], 1)
        XCTAssertEqual(sample.directions[.chineseEnglishSpacing], 1)
    }

    func testProfileRequiresRepeatedMultiDayEvidenceBeforeProducingDirectives() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = ExpressionProfileStore(container: captures.container)
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        for index in 0..<9 {
            try store.record(
                injected: "今天我们继续测试Morie这个输入功能",
                edited: "今天我们继续测试 Morie 这个输入功能。",
                at: start.addingTimeInterval(Double(index) * 12 * 60 * 60)
            )
        }
        XCTAssertTrue(try store.directives().isEmpty)

        try store.record(
            injected: "今天我们继续测试Morie这个输入功能",
            edited: "今天我们继续测试 Morie 这个输入功能。",
            at: start.addingTimeInterval(4 * 24 * 60 * 60)
        )

        let snapshot = try store.snapshotForTesting()
        XCTAssertEqual(snapshot.sampleCount, 10)
        XCTAssertEqual(
            snapshot.features[ExpressionFeature.terminalPunctuationUsage.rawValue]?.state,
            .stable
        )
        XCTAssertTrue(try store.directives().contains("倾向保留句末标点。"))
        XCTAssertTrue(try store.directives().contains("中文与英文之间倾向保留空格。"))
    }

    func testContentEditsDoNotBecomeExpressionEvidenceAndClearRemovesProfile() throws {
        let captures = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: captures.audioDirectory) }
        let store = ExpressionProfileStore(container: captures.container)

        try store.record(
            injected: "今天我们去北京处理这个问题",
            edited: "今天我们去上海处理这个问题。"
        )
        XCTAssertEqual(try store.snapshotForTesting().sampleCount, 0)

        try store.record(
            injected: "今天我们继续测试这个输入功能",
            edited: "今天我们继续测试这个输入功能。"
        )
        XCTAssertEqual(try store.snapshotForTesting().sampleCount, 1)

        try store.clear()
        XCTAssertEqual(try store.snapshotForTesting().sampleCount, 0)
        XCTAssertTrue(try store.directives().isEmpty)
    }
}
