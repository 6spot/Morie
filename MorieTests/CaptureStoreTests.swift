import CoreGraphics
import Foundation
import SwiftData
import XCTest

@MainActor
final class CaptureStoreTests: XCTestCase {
    func testDeliveredLifecyclePreservesRecognitionAndContext() throws {
        let store = try CaptureStore(inMemory: true)
        let id = UUID()

        try store.beginVoiceCapture(
            id: id,
            applicationName: "Notes",
            bundleIdentifier: "com.apple.Notes",
            windowNumber: CGWindowID(42)
        )
        try store.updateRecognizedText("partial", for: id)
        try store.completeRecognition("final text", for: id)
        try store.markDelivered(id)

        let record = try XCTUnwrap(fetch(id, from: store))
        XCTAssertEqual(record.lifecycle, .delivered)
        XCTAssertEqual(record.recognizedText, "final text")
        XCTAssertEqual(record.finalText, "final text")
        XCTAssertEqual(record.sourceApplicationName, "Notes")
        XCTAssertEqual(record.sourceBundleIdentifier, "com.apple.Notes")
        XCTAssertEqual(record.originalWindowNumber, 42)
        XCTAssertNil(record.deliveryErrorDescription)
    }

    func testDeliveryFailurePreservesFinalTextAndError() throws {
        let store = try CaptureStore(inMemory: true)
        let id = UUID()

        try store.beginVoiceCapture(id: id, applicationName: nil, bundleIdentifier: nil, windowNumber: nil)
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

        try store.beginVoiceCapture(id: id, applicationName: nil, bundleIdentifier: nil, windowNumber: nil)
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

        try store.beginVoiceCapture(id: id, applicationName: nil, bundleIdentifier: nil, windowNumber: nil)
        try store.cancel(id)

        XCTAssertNil(try fetch(id, from: store))
    }

    func testCaptureSurvivesStoreRecreation() throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieCaptureStoreTests-(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storeURL = directory.appending(path: "captures.store")
        let id = UUID()

        do {
            let store = try CaptureStore(storageURL: storeURL)
            try store.beginVoiceCapture(id: id, applicationName: "Xcode", bundleIdentifier: "com.apple.dt.Xcode", windowNumber: nil)
            try store.completeRecognition("persisted", for: id)
            try store.markDelivered(id)
        }

        let reopenedStore = try CaptureStore(storageURL: storeURL)
        let record = try XCTUnwrap(fetch(id, from: reopenedStore))
        XCTAssertEqual(record.lifecycle, .delivered)
        XCTAssertEqual(record.finalText, "persisted")
        XCTAssertEqual(record.sourceBundleIdentifier, "com.apple.dt.Xcode")
    }

    private func fetch(_ id: UUID, from store: CaptureStore) throws -> CaptureRecord? {
        var descriptor = FetchDescriptor<CaptureRecord>(
            predicate: #Predicate { $0.id == id }
        )
        descriptor.fetchLimit = 1
        return try store.container.mainContext.fetch(descriptor).first
    }
}
