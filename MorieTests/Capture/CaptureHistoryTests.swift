import Foundation
import SwiftData
import XCTest

@MainActor
final class CaptureHistoryTests: XCTestCase {
    func testFinalRecognitionPrefersAccurateTranscriptWhenAvailable() {
        XCTAssertEqual(
            CaptureFileTranscriber.preferredTranscript(
                live: "实时识别结果",
                accurate: "高精度识别结果"
            ),
            "高精度识别结果"
        )
    }

    func testFinalRecognitionFallsBackToLiveTranscriptWhenAccurateResultIsMissing() {
        XCTAssertEqual(
            CaptureFileTranscriber.preferredTranscript(
                live: "保留实时识别结果",
                accurate: "   \n"
            ),
            "保留实时识别结果"
        )
        XCTAssertEqual(
            CaptureFileTranscriber.preferredTranscript(
                live: "保留实时识别结果",
                accurate: nil
            ),
            "保留实时识别结果"
        )
    }

    func testFinalRecognitionRejectsGrosslyTruncatedAccurateResult() {
        let live = "这是一个比较完整的实时识别结果，里面包含前半段、中间内容和最后的结尾信息。"
        XCTAssertEqual(
            CaptureFileTranscriber.preferredTranscript(
                live: live,
                accurate: "只有前半段"
            ),
            live
        )
    }

    func testFinalRecognitionStillPrefersComparableAccurateResult() {
        XCTAssertEqual(
            CaptureFileTranscriber.preferredTranscript(
                live: "接下来把 Vercowa 模块接进去，然后处理缓存",
                accurate: "接下来把 Vercova 模块接进去，然后处理缓存。"
            ),
            "接下来把 Vercova 模块接进去，然后处理缓存。"
        )
    }

    func testHistoryQueryExcludesLiveCaptureUntilTerminalState() async throws {
        let store = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.audioDirectory) }

        let completedID = UUID()
        _ = try store.beginVoiceCapture(
            id: completedID,
            deliveryMode: .currentApp,
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes"
        )
        try store.markFailed(completedID, error: "saved failure")

        let liveID = UUID()
        _ = try store.beginVoiceCapture(
            id: liveID,
            deliveryMode: .captureOnly,
            applicationName: "Morie",
            bundleIdentifier: "me.morie.mac"
        )

        let reader = ModelContext(store.container)
        var visible = try reader.fetch(CaptureHistoryQuery.descriptor(limit: 200))
        XCTAssertEqual(Set(visible.map(\.id)), [completedID])

        try store.updateRecognizedText("progressively saved text", for: liveID)
        visible = try reader.fetch(CaptureHistoryQuery.descriptor(limit: 200))
        XCTAssertEqual(Set(visible.map(\.id)), [completedID],
                       "Progressive durability must not expose the in-progress row in normal History.")

        try store.markFailed(liveID, error: "recognition stopped")
        try await store.flushPersistence(for: liveID)
        visible = try reader.fetch(CaptureHistoryQuery.descriptor(limit: 200))
        XCTAssertEqual(Set(visible.map(\.id)), [completedID, liveID],
                       "A retained terminal Capture should enter History exactly after it stops being live.")
    }

    func testHistoryControllerReleasesListAcrossPageSwitchAndReloadsOnReturn() async throws {
        let store = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.audioDirectory) }
        let history = CaptureHistoryController(
            store: store,
            locale: Locale(identifier: "zh-CN")
        ) { _, _ in
            throw CaptureStore.StoreError.audioUnavailable
        }

        let firstID = UUID()
        _ = try store.beginVoiceCapture(
            id: firstID,
            deliveryMode: .captureOnly,
            applicationName: "Morie",
            bundleIdentifier: "me.morie.mac"
        )
        try store.markFailed(firstID, error: "first")
        try await store.flushPersistence(for: firstID)

        history.setListVisible(true)
        XCTAssertEqual(history.captures.map(\.id), [firstID])

        history.setListVisible(false)

        let secondID = UUID()
        _ = try store.beginVoiceCapture(
            id: secondID,
            deliveryMode: .captureOnly,
            applicationName: "Morie",
            bundleIdentifier: "me.morie.mac"
        )
        try store.markFailed(secondID, error: "second")
        try await store.flushPersistence(for: secondID)
        history.captureListDidChange()

        XCTAssertTrue(
            history.captures.isEmpty,
            "An off-screen History page should release its presentation records."
        )

        history.setListVisible(true)
        XCTAssertEqual(Set(history.captures.map(\.id)), [firstID, secondID])
    }

    func testRetryRecoversFailedCaptureAndSurvivesRestart() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.removeFiles() }
        let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
            "recovered speech"
        }

        history.recognizeAgain(fixture.id)
        await history.waitForRecognition()

        let reopened = try CaptureStore(storageURL: fixture.storeURL)
        let capture = try reopened.capture(fixture.id)
        XCTAssertEqual(capture.lifecycle, .recognized)
        XCTAssertEqual(capture.recognizedText, "recovered speech")
        XCTAssertEqual(capture.finalText, "recovered speech")
        XCTAssertNotNil(capture.lastRecognitionAttemptAt)
        XCTAssertNil(capture.lastRecognitionErrorDescription)
        XCTAssertNil(capture.deliveryErrorDescription)
        XCTAssertEqual(capture.sourceApplicationName, "Notes")
        XCTAssertEqual(try Data(contentsOf: fixture.audioURL), HistoryFixture.audioData)
        XCTAssertEqual(try reopened.container.mainContext.fetchCount(FetchDescriptor<CaptureRecord>()), 1)
    }

    func testRetryPreservesOriginalDeliveryAndOutput() async throws {
        let fixture = try HistoryFixture(deliveredText: "original output")
        defer { fixture.removeFiles() }
        let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
            "new recognition"
        }

        history.recognizeAgain(fixture.id)
        await history.waitForRecognition()

        let capture = try fixture.store.capture(fixture.id)
        XCTAssertEqual(capture.lifecycle, .delivered)
        XCTAssertEqual(capture.finalText, "original output")
        XCTAssertEqual(capture.recognizedText, "new recognition")
        XCTAssertEqual(capture.deliveryModeRawValue, CaptureDeliveryMode.currentApp.rawValue)
        XCTAssertEqual(try Data(contentsOf: fixture.audioURL), HistoryFixture.audioData)
    }

    func testRetryRecoversCaptureOnlyWithoutChangingItsDestination() async throws {
        let fixture = try HistoryFixture(deliveryMode: .captureOnly)
        defer { fixture.removeFiles() }
        let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
            "recovered idea"
        }

        history.recognizeAgain(fixture.id)
        await history.waitForRecognition()

        let reopened = try CaptureStore(storageURL: fixture.storeURL)
        let capture = try reopened.capture(fixture.id)
        XCTAssertEqual(capture.deliveryModeRawValue, CaptureDeliveryMode.captureOnly.rawValue)
        XCTAssertEqual(capture.lifecycle, .recognized)
        XCTAssertEqual(capture.finalText, "recovered idea")
        XCTAssertEqual(try reopened.sourceAudioURL(for: fixture.id), fixture.audioURL)
    }

    func testEmptyRetryKeepsSavedTextAndAudio() async throws {
        let fixture = try HistoryFixture(deliveredText: "keep this output")
        defer { fixture.removeFiles() }
        let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
            " \n\t "
        }

        history.recognizeAgain(fixture.id)
        await history.waitForRecognition()

        let capture = try fixture.store.capture(fixture.id)
        XCTAssertEqual(capture.lifecycle, .delivered)
        XCTAssertEqual(capture.recognizedText, "keep this output")
        XCTAssertEqual(capture.finalText, "keep this output")
        XCTAssertNotNil(capture.lastRecognitionErrorDescription)
        XCTAssertEqual(try Data(contentsOf: fixture.audioURL), HistoryFixture.audioData)
    }

    func testFailedRetryKeepsOriginalFailureAndRecording() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.removeFiles() }
        let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
            throw CocoaError(.fileReadCorruptFile)
        }

        history.recognizeAgain(fixture.id)
        await history.waitForRecognition()

        let reopened = try CaptureStore(storageURL: fixture.storeURL)
        let capture = try reopened.capture(fixture.id)
        XCTAssertEqual(capture.lifecycle, .failed)
        XCTAssertEqual(capture.deliveryErrorDescription, "Initial recognition failed")
        XCTAssertNotNil(capture.lastRecognitionErrorDescription)
        XCTAssertEqual(try Data(contentsOf: fixture.audioURL), HistoryFixture.audioData)
    }

    func testCancellationIgnoresLateResultWithoutChangingSavedText() async throws {
        let fixture = try HistoryFixture(deliveredText: "original")
        defer { fixture.removeFiles() }
        let pending = PendingFileRecognition()
        let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
            await pending.recognize()
        }

        history.recognizeAgain(fixture.id)
        await pending.waitUntilStarted()
        history.cancelRecognition()
        await pending.finish("late result")
        await history.waitForRecognition()

        let capture = try fixture.store.capture(fixture.id)
        XCTAssertEqual(capture.recognizedText, "original")
        XCTAssertEqual(capture.finalText, "original")
        XCTAssertNil(capture.lastRecognitionAttemptAt)
        XCTAssertNil(history.recognizingCaptureID)
        XCTAssertEqual(try Data(contentsOf: fixture.audioURL), HistoryFixture.audioData)
    }

    func testLiveInputPreemptsRetryAndBlocksAnotherRetry() async throws {
        let fixture = try HistoryFixture()
        defer { fixture.removeFiles() }
        let pending = PendingFileRecognition()
        let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
            await pending.recognize()
        }

        history.recognizeAgain(fixture.id)
        await pending.waitUntilStarted()
        history.setInputActive(true)
        history.recognizeAgain(fixture.id)
        await pending.finish("late result")
        await history.waitForRecognition()

        XCTAssertTrue(history.isInputActive)
        XCTAssertNil(history.recognizingCaptureID)
        XCTAssertNil(try fixture.store.capture(fixture.id).lastRecognitionAttemptAt)
        let calls = await pending.callCount
        XCTAssertEqual(calls, 1)
    }

    func testExpiredAndMissingAudioDoNotStartRecognition() async throws {
        for expired in [true, false] {
            let fixture = try HistoryFixture()
            defer { fixture.removeFiles() }
            if expired {
                try fixture.store.capture(fixture.id).sourceAudioExpiresAt = .distantPast
                try fixture.store.container.mainContext.save()
            } else {
                try FileManager.default.removeItem(at: fixture.audioURL)
            }
            let history = CaptureHistoryController(store: fixture.store, locale: Locale(identifier: "zh-CN")) { _, _ in
                XCTFail("Unavailable source audio must not reach the recognizer")
                return "unexpected"
            }

            history.recognizeAgain(fixture.id)
            await history.waitForRecognition()

            XCTAssertNil(history.recognizingCaptureID)
            XCTAssertNotNil(history.recognitionMessage)
            XCTAssertNil(try fixture.store.capture(fixture.id).lastRecognitionAttemptAt)
        }
    }
}

@MainActor
private struct HistoryFixture {
    static let audioData = Data("isolated source-audio fixture".utf8)

    let directory: URL
    let storeURL: URL
    let store: CaptureStore
    let id = UUID()
    let audioURL: URL

    init(deliveredText: String? = nil, deliveryMode: CaptureDeliveryMode = .currentApp) throws {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieHistoryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appending(path: "captures.store")
        store = try CaptureStore(storageURL: storeURL)
        audioURL = try store.beginVoiceCapture(
            id: id, deliveryMode: deliveryMode,
            applicationName: "Notes", bundleIdentifier: "com.apple.Notes"
        )
        try Self.audioData.write(to: audioURL)
        try store.attachSourceAudio(CapturedSourceAudio(url: audioURL, duration: 2), for: id)
        if let deliveredText {
            try store.completeRecognition(deliveredText, for: id)
            try store.markDelivered(
                id,
                applicationName: "Notes",
                bundleIdentifier: "com.apple.Notes"
            )
        } else {
            try store.markFailed(id, error: "Initial recognition failed")
        }
    }

    func removeFiles() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private actor PendingFileRecognition {
    private var result: CheckedContinuation<String, Never>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var callCount = 0

    func recognize() async -> String {
        callCount += 1
        return await withCheckedContinuation { continuation in
            result = continuation
            started?.resume()
            started = nil
        }
    }

    func waitUntilStarted() async {
        guard result == nil else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finish(_ text: String) {
        result?.resume(returning: text)
        result = nil
    }
}
