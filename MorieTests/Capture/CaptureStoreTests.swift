import Foundation
import SwiftData
import XCTest

@MainActor
final class CaptureStoreTests: XCTestCase {
    func testIsolatedStoresNeverEnableManagedCloudSync() throws {
        let inMemory = try CaptureStore(inMemory: true, cloudSyncEnabled: true)
        defer { try? FileManager.default.removeItem(at: inMemory.audioDirectory) }
        XCTAssertFalse(inMemory.cloudSyncEnabled)

        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieCloudIsolation-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let explicit = try CaptureStore(
            storageURL: directory.appending(path: "captures.store"),
            cloudSyncEnabled: true
        )
        XCTAssertFalse(explicit.cloudSyncEnabled)
    }

    func testCaptureOnlyModeIsSavedBeforeRecognitionAndCompletesWithoutDelivery() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieCaptureOnlyTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "captures.store")
        let store = try CaptureStore(storageURL: storeURL)
        let id = UUID()
        let audioURL = try store.beginVoiceCapture(
            id: id, deliveryMode: .captureOnly,
            applicationName: "Morie", bundleIdentifier: "me.morie.mac"
        )

        let persisted = try XCTUnwrap(ModelContext(store.container).fetch(FetchDescriptor<CaptureRecord>()).first)
        XCTAssertEqual(persisted.deliveryModeRawValue, CaptureDeliveryMode.captureOnly.rawValue)
        XCTAssertEqual(persisted.lifecycle, .capturing)

        let audio = Data("saved idea audio".utf8)
        try audio.write(to: audioURL)
        try store.attachSourceAudio(CapturedSourceAudio(url: audioURL, duration: 2, hasMeaningfulAudio: true), for: id)
        let destination = try store.completeRecognition("remember this idea", for: id)

        XCTAssertEqual(destination, .captureOnly)
        XCTAssertEqual(try store.sourceAudioURL(for: id), audioURL,
                       "Capture-only completion must release active-record ownership without a delivery step")
        try store.cancel(id)
        XCTAssertEqual(try store.capture(id).lifecycle, .recognized,
                       "Late cancellation must not discard a completed Capture")

        let reopened = try CaptureStore(storageURL: storeURL)
        let capture = try reopened.capture(id)
        XCTAssertEqual(capture.deliveryModeRawValue, CaptureDeliveryMode.captureOnly.rawValue)
        XCTAssertEqual(capture.lifecycle, .recognized)
        XCTAssertEqual(capture.recognizedText, "remember this idea")
        XCTAssertEqual(capture.finalText, "remember this idea")
        XCTAssertEqual(capture.sourceBundleIdentifier, "me.morie.mac")
        XCTAssertNil(capture.deliveryErrorDescription)
        XCTAssertEqual(try Data(contentsOf: reopened.sourceAudioURL(for: id)), audio)
    }

    func testCurrentAppRecognitionKeepsOwnershipUntilDeliveryFinishes() throws {
        let store = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.audioDirectory) }
        let id = UUID()
        let audioURL = try store.beginVoiceCapture(
            id: id, deliveryMode: .currentApp,
            applicationName: "Notes", bundleIdentifier: "com.apple.Notes"
        )
        try Data("input audio".utf8).write(to: audioURL)
        try store.attachSourceAudio(CapturedSourceAudio(url: audioURL, duration: 2), for: id)

        let destination = try store.completeRecognition("insert this text", for: id)

        XCTAssertEqual(destination, .currentApp)
        XCTAssertThrowsError(try store.sourceAudioURL(for: id)) { error in
            guard case CaptureStore.StoreError.captureInProgress = error else {
                return XCTFail("Expected captureInProgress, got \(error)")
            }
        }
        try store.markDelivered(
            id,
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes"
        )
        try store.markFailed(id, error: "A late interruption arrived after paste dispatch")
        XCTAssertEqual(try store.capture(id).lifecycle, .delivered)
        XCTAssertNil(try store.capture(id).deliveryErrorDescription)
        XCTAssertEqual(try store.sourceAudioURL(for: id), audioURL)
    }

    func testCaptureOnlyCancellationRemovesUnfinishedTextAndAudio() throws {
        let store = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.audioDirectory) }
        let id = UUID()
        let audioURL = try store.beginVoiceCapture(
            id: id, deliveryMode: .captureOnly,
            applicationName: "Morie", bundleIdentifier: "me.morie.mac"
        )
        try Data("discarded idea audio".utf8).write(to: audioURL)
        try store.updateRecognizedText("unfinished idea", for: id)

        try store.cancel(id)

        XCTAssertNil(try fetch(id, from: store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testDeliveredLifecyclePreservesRecognitionAndActualDeliveryContext() throws {
        let store = try CaptureStore(inMemory: true)
        let id = UUID()

        _ = try store.beginVoiceCapture(
            id: id,
            deliveryMode: .currentApp,
            applicationName: nil,
            bundleIdentifier: nil
        )
        try store.updateRecognizedText("partial", for: id)
        try store.completeRecognition("final text", for: id)
        try store.markDelivered(
            id,
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes"
        )

        let record = try XCTUnwrap(fetch(id, from: store))
        XCTAssertEqual(record.lifecycle, .delivered)
        XCTAssertEqual(record.recognizedText, "final text")
        XCTAssertEqual(record.finalText, "final text")
        XCTAssertEqual(record.sourceApplicationName, "Notes")
        XCTAssertEqual(record.sourceBundleIdentifier, "com.apple.Notes")
        XCTAssertNil(record.deliveryErrorDescription)
    }

    func testDeliveryFailurePreservesFinalTextAndError() throws {
        let store = try CaptureStore(inMemory: true)
        let id = UUID()

        _ = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        try store.completeRecognition("keep this", for: id)
        try store.markDeliveryFailed(id, error: "Target window closed")

        let record = try XCTUnwrap(fetch(id, from: store))
        XCTAssertEqual(record.lifecycle, .deliveryFailed)
        XCTAssertEqual(record.finalText, "keep this")
        XCTAssertEqual(record.deliveryErrorDescription, "Target window closed")
    }

    func testOperationalFailureIsDurable() throws {
        let store = try CaptureStore(inMemory: true)
        let id = UUID()

        _ = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        try store.updateRecognizedText("recoverable partial", for: id)
        try store.markFailed(id, error: "Speech stopped")

        let record = try XCTUnwrap(fetch(id, from: store))
        XCTAssertEqual(record.lifecycle, .failed)
        XCTAssertEqual(record.recognizedText, "recoverable partial")
        XCTAssertEqual(record.deliveryErrorDescription, "Speech stopped")
    }

    func testExplicitCancellationRemovesCapture() throws {
        let store = try CaptureStore(inMemory: true)
        let id = UUID()

        _ = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        try store.cancel(id)

        XCTAssertNil(try fetch(id, from: store))
    }

    func testCaptureSurvivesStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieCaptureStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "captures.store")
        let id = UUID()

        do {
            let store = try CaptureStore(storageURL: storeURL)
            _ = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
            try store.completeRecognition("persisted", for: id)
            try store.markDelivered(
                id,
                applicationName: "Xcode",
                bundleIdentifier: "com.apple.dt.Xcode"
            )
        }

        let reopenedStore = try CaptureStore(storageURL: storeURL)
        let record = try XCTUnwrap(fetch(id, from: reopenedStore))
        XCTAssertEqual(record.lifecycle, .delivered)
        XCTAssertEqual(record.finalText, "persisted")
        XCTAssertEqual(record.sourceBundleIdentifier, "com.apple.dt.Xcode")
    }

    func testStoreRecreationRemovesEmptyCaptureWithoutMeaningfulAudio() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieEmptyCaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "captures.store")
        let id = UUID()

        do {
            let store = try CaptureStore(storageURL: storeURL)
            _ = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        }

        let reopenedStore = try CaptureStore(storageURL: storeURL)
        XCTAssertNil(try fetch(id, from: reopenedStore))
    }

    func testExpiredAudioIsRemovedWithoutDeletingCapture() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieAudioExpiryTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try CaptureStore(inMemory: true, audioDirectory: directory)
        let id = UUID()
        let audioURL = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        try Data("audio".utf8).write(to: audioURL)
        try store.attachSourceAudio(CapturedSourceAudio(url: audioURL, duration: 1), for: id)
        try store.markFailed(id, error: "No text recognized")

        let record = try XCTUnwrap(fetch(id, from: store))
        record.sourceAudioExpiresAt = .distantPast
        try store.container.mainContext.save()
        try store.pruneExpiredAudio()

        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
        XCTAssertNil(try XCTUnwrap(fetch(id, from: store)).sourceAudioRelativePath)
    }

    func testStartingCaptureDoesNotRunExpiredAudioMaintenance() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieAudioHotPathTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try CaptureStore(inMemory: true, audioDirectory: directory)
        let expiredID = UUID()
        let expiredURL = try store.beginVoiceCapture(
            id: expiredID,
            deliveryMode: .currentApp,
            applicationName: nil,
            bundleIdentifier: nil
        )
        try Data("audio".utf8).write(to: expiredURL)
        try store.attachSourceAudio(CapturedSourceAudio(url: expiredURL, duration: 1), for: expiredID)
        try store.markFailed(expiredID, error: "No text recognized")
        let expiredRecord = try XCTUnwrap(fetch(expiredID, from: store))
        expiredRecord.sourceAudioExpiresAt = .distantPast
        try store.container.mainContext.save()

        let activeID = UUID()
        _ = try store.beginVoiceCapture(
            id: activeID,
            deliveryMode: .currentApp,
            applicationName: nil,
            bundleIdentifier: nil
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: expiredURL.path))
        XCTAssertNotNil(try XCTUnwrap(fetch(expiredID, from: store)).sourceAudioRelativePath)

        try store.cancel(activeID)
        try store.pruneExpiredAudio()
        XCTAssertFalse(FileManager.default.fileExists(atPath: expiredURL.path))
    }

    func testMeaningfulAudioPreservesEmptyFailedCaptureAcrossRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieMeaningfulAudioTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "captures.store")
        let audioDirectory = directory.appending(path: "audio", directoryHint: .isDirectory)
        let id = UUID()
        do {
            let store = try CaptureStore(storageURL: storeURL, audioDirectory: audioDirectory)
            let audioURL = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
            try Data("audio".utf8).write(to: audioURL)
            try store.attachSourceAudio(
                CapturedSourceAudio(url: audioURL, duration: 1, hasMeaningfulAudio: true),
                for: id
            )
            try store.markFailed(id, error: "Recognition returned no text")
        }

        let reopened = try CaptureStore(storageURL: storeURL, audioDirectory: audioDirectory)
        XCTAssertEqual(try XCTUnwrap(fetch(id, from: reopened)).sourceAudioHasMeaningfulContent, true)
    }

    func testOnlyConfirmedSilenceOrNoInputDiscardsEmptyCapture() throws {
        for (duration, meaningful) in [(2.0, false as Bool?), (0.0, nil)] {
            let store = try CaptureStore(inMemory: true)
            defer { try? FileManager.default.removeItem(at: store.audioDirectory) }
            let id = UUID()
            let url = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
            try Data("audio".utf8).write(to: url)
            let source = CapturedSourceAudio(url: url, duration: duration, hasMeaningfulAudio: meaningful)
            try store.attachSourceAudio(source, for: id)

            let outcome = try store.finishEmptyRecognition(for: id, sourceAudio: source)

            XCTAssertEqual(outcome, .discarded)
            XCTAssertNil(try fetch(id, from: store))
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testUncertainSignalAndPreviouslyRecognizedSpeechRemainRetryable() throws {
        for (duration, meaningful) in [(2.0, nil as Bool?), (2.0, true), (0.0, true)] {
            let store = try CaptureStore(inMemory: true)
            defer { try? FileManager.default.removeItem(at: store.audioDirectory) }
            let id = UUID()
            let url = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
            try Data("audio".utf8).write(to: url)
            let source = CapturedSourceAudio(url: url, duration: duration, hasMeaningfulAudio: meaningful)
            try store.attachSourceAudio(source, for: id)

            let outcome = try store.finishEmptyRecognition(for: id, sourceAudio: source)

            XCTAssertEqual(outcome, .retainedForRetry)
            XCTAssertEqual(try store.capture(id).lifecycle, .failed)
            XCTAssertEqual(try store.sourceAudioURL(for: id), url)
        }
    }

    func testExpiredEmptyFailureSurvivesRepeatedStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieExpiredFailureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "captures.store")
        let id = UUID()
        let store = try CaptureStore(storageURL: storeURL)
        let audioURL = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        try Data("audio".utf8).write(to: audioURL)
        let source = CapturedSourceAudio(url: audioURL, duration: 2)
        try store.attachSourceAudio(source, for: id)
        _ = try store.finishEmptyRecognition(for: id, sourceAudio: source)
        try store.capture(id).sourceAudioExpiresAt = .distantPast
        try store.container.mainContext.save()

        for _ in 0..<2 {
            let reopened = try CaptureStore(storageURL: storeURL)
            let capture = try reopened.capture(id)
            XCTAssertEqual(capture.lifecycle, .failed)
            XCTAssertNil(capture.sourceAudioRelativePath)
            XCTAssertEqual(capture.sourceAudioDurationSeconds, 2)
            XCTAssertEqual(capture.sourceAudioExpiresAt, .distantPast)
            XCTAssertThrowsError(try reopened.sourceAudioURL(for: id))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: audioURL.path))
    }

    func testInterruptedCaptureRecoversUnfinishedAudio() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieInterruptedCaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "captures.store")
        let id = UUID()
        let store = try CaptureStore(storageURL: storeURL)
        let url = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
        try Data("interrupted audio".utf8).write(to: url)

        let reopened = try CaptureStore(storageURL: storeURL)
        let capture = try reopened.capture(id)
        XCTAssertEqual(capture.lifecycle, .failed)
        XCTAssertNil(capture.sourceAudioHasMeaningfulContent)
        XCTAssertEqual(try reopened.sourceAudioURL(for: id), url)
    }

    func testHistoryDeletionRemovesOnlySelectedCaptureAndAudio() throws {
        let store = try CaptureStore(inMemory: true)
        defer { try? FileManager.default.removeItem(at: store.audioDirectory) }
        var captured: [(UUID, URL)] = []
        for _ in 0..<2 {
            let id = UUID()
            let url = try store.beginVoiceCapture(id: id, deliveryMode: .currentApp, applicationName: nil, bundleIdentifier: nil)
            try Data("audio".utf8).write(to: url)
            try store.attachSourceAudio(CapturedSourceAudio(url: url, duration: 2), for: id)
            try store.markFailed(id, error: "No text recognized")
            captured.append((id, url))
        }

        try store.deleteCapture(captured[0].0)

        XCTAssertNil(try fetch(captured[0].0, from: store))
        XCTAssertFalse(FileManager.default.fileExists(atPath: captured[0].1.path))
        XCTAssertEqual(try store.sourceAudioURL(for: captured[1].0), captured[1].1)
    }

    private func fetch(_ id: UUID, from store: CaptureStore) throws -> CaptureRecord? {
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try store.container.mainContext.fetch(descriptor).first
    }
}
