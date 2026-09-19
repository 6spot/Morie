import Foundation
import SwiftData
import XCTest

@MainActor
final class CaptureHistoryTests: XCTestCase {
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
