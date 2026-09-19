import AVFoundation
import Foundation
import Speech
import XCTest

@MainActor
final class CaptureAudioStreamTests: XCTestCase {
    private enum Failure: Error, Equatable {
        case conversion
        case flush
        case interruption
    }

    func testConversionFailureKeepsWrittenAudioAndEndsAnalyzerInput() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try CaptureAudioStream(
            destinationURL: directory.appending(path: "conversion.m4a"),
            convert: { _ in throw Failure.conversion },
            flush: { XCTFail("Failed conversion must not be flushed"); return [] },
            onAudioLevel: { _ in }
        )

        stream.append(try makeAudio())
        let completion = stream.finish()

        XCTAssertEqual(completion.error as? Failure, .conversion)
        XCTAssertEqual(completion.sourceAudio.duration, 1, accuracy: 0.001)
        XCTAssertNil(completion.sourceAudio.hasMeaningfulAudio,
                     "Signal written before conversion failed must remain retryable")
        try assertReadableSignal(completion.sourceAudio.url)
        do {
            for try await _ in stream.analyzerInputs {}
            XCTFail("The analyzer must receive the conversion error")
        } catch {
            XCTAssertEqual(error as? Failure, .conversion)
        }
    }

    func testFlushFailureStillFinalizesEarlierAACFrames() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try CaptureAudioStream(
            destinationURL: directory.appending(path: "flush.m4a"),
            convert: { _ in [] },
            flush: { throw Failure.flush },
            onAudioLevel: { _ in }
        )
        stream.append(try makeAudio())

        let completion = stream.finish()

        XCTAssertEqual(completion.error as? Failure, .flush)
        XCTAssertEqual(completion.sourceAudio.duration, 1, accuracy: 0.001)
        try assertReadableSignal(completion.sourceAudio.url)
        let bytes = try Data(contentsOf: completion.sourceAudio.url)
        _ = stream.finish()
        _ = stream.stopImmediately()
        XCTAssertEqual(try Data(contentsOf: completion.sourceAudio.url), bytes)
    }

    func testImmediateStopSkipsFlushAndKeepsClosedRecording() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try CaptureAudioStream(
            destinationURL: directory.appending(path: "immediate.m4a"),
            convert: { _ in [] },
            flush: { XCTFail("Immediate stop must not flush Speech conversion"); return [] },
            onAudioLevel: { _ in }
        )
        let buffer = try makeAudio()
        stream.append(buffer)

        let source = stream.stopImmediately()
        let bytes = try Data(contentsOf: source.url)
        stream.append(buffer)
        _ = stream.stopImmediately()
        let completion = stream.finish()

        XCTAssertEqual(completion.sourceAudio.duration, 1, accuracy: 0.001)
        XCTAssertEqual(try Data(contentsOf: source.url), bytes,
                       "Late buffers and repeated teardown cannot change the finalized file")
        try assertReadableSignal(source.url)
    }

    func testRuntimeInterruptionPreservesAudioAndFirstError() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let stream = try makeStream(at: directory.appending(path: "interruption.m4a"))
        stream.append(try makeAudio())

        stream.fail(Failure.interruption)
        stream.fail(Failure.conversion)
        let completion = stream.finish()

        XCTAssertEqual(completion.error as? Failure, .interruption)
        try assertReadableSignal(completion.sourceAudio.url)
    }

    func testNormalFinishFlushesOnceAndPreservesAllWrittenAudio() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        var flushCount = 0
        let stream = try CaptureAudioStream(
            destinationURL: directory.appending(path: "normal.m4a"),
            convert: { _ in [] },
            flush: { flushCount += 1; return [] },
            onAudioLevel: { _ in }
        )
        stream.append(try makeAudio())
        stream.append(try makeAudio())

        let completion = stream.finish()
        _ = stream.finish()

        XCTAssertEqual(flushCount, 1)
        XCTAssertNil(completion.error)
        XCTAssertEqual(completion.sourceAudio.duration, 2, accuracy: 0.001)
        try assertReadableSignal(completion.sourceAudio.url)
    }

    func testFinishReleasesConverterAndMeterClosuresBeforeStreamDeinit() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let (stream, probe) = try makeProbeStream(at: directory.appending(path: "release.m4a"))
        XCTAssertNotNil(probe.value)

        stream.append(try makeAudio())
        _ = stream.finish()

        XCTAssertNil(
            probe.value,
            "Native converter/callback captures must be released when a recording finishes, even while the stream object still exists"
        )
    }

    func testInterruptedCaptureKeepsTextAudioAndDestinationAcrossRestart() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appending(path: "captures.store")
        let store = try CaptureStore(storageURL: storeURL)
        for mode in [CaptureDeliveryMode.currentApp, .captureOnly] {
            let id = UUID()
            let url = try store.beginVoiceCapture(
                id: id, deliveryMode: mode,
                applicationName: "Test", bundleIdentifier: nil, windowNumber: nil
            )
            let stream = try makeStream(at: url)
            stream.append(try makeAudio())
            try store.updateRecognizedText("earlier text", for: id)
            try store.updateRecognizedText("latest text before interruption", for: id)
            let source = stream.stopImmediately()
            try store.attachSourceAudio(source, for: id)
            try store.markFailed(id, error: "Microphone interrupted")

            let reopened = try CaptureStore(storageURL: storeURL)
            let record = try reopened.capture(id)
            XCTAssertEqual(record.lifecycle, .failed)
            XCTAssertEqual(record.recognizedText, "latest text before interruption")
            XCTAssertEqual(record.deliveryModeRawValue, mode.rawValue)
            XCTAssertEqual(record.sourceAudioDurationSeconds, 1)
            XCTAssertEqual(record.deliveryErrorDescription, "Microphone interrupted")
            try assertReadableSignal(reopened.sourceAudioURL(for: id))
        }
    }

    func testExplicitDiscardDeletesClosedAudioAndDoesNotRecreateIt() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try CaptureStore(storageURL: directory.appending(path: "captures.store"))
        let id = UUID()
        let url = try store.beginVoiceCapture(
            id: id, deliveryMode: .captureOnly,
            applicationName: "Test", bundleIdentifier: nil, windowNumber: nil
        )
        let stream = try makeStream(at: url)
        stream.append(try makeAudio())
        _ = stream.stopImmediately()
        try assertReadableSignal(url)

        try store.cancel(id)
        _ = stream.finish()

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertThrowsError(try store.capture(id))
    }

    private func makeProbeStream(at url: URL) throws -> (CaptureAudioStream, WeakLifetimeProbe) {
        let probe = LifetimeProbe()
        let weakProbe = WeakLifetimeProbe(probe)
        let stream = try CaptureAudioStream(
            destinationURL: url,
            convert: { [probe] _ in _ = probe; return [] },
            flush: { [probe] in _ = probe; return [] },
            onAudioLevel: { [probe] _ in _ = probe }
        )
        return (stream, weakProbe)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "MorieAudioStreamTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makeStream(at url: URL) throws -> CaptureAudioStream {
        try CaptureAudioStream(
            destinationURL: url,
            convert: { _ in [] },
            flush: { [] },
            onAudioLevel: { _ in }
        )
    }

    private func makeAudio() throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        for index in 0..<Int(buffer.frameLength) {
            channel[index] = 0.25 * sin(2 * .pi * 440 * Float(index) / 16_000)
        }
        return buffer
    }

    private func assertReadableSignal(
        _ url: URL, file: StaticString = #filePath, line: UInt = #line
    ) throws {
        let recording = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(recording.length, 0, file: file, line: line)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: recording.processingFormat, frameCapacity: 16_000))
        try recording.read(into: buffer)
        let channel = try XCTUnwrap(buffer.floatChannelData?[0])
        let energy = (0..<Int(buffer.frameLength)).reduce(Float(0)) { $0 + channel[$1] * channel[$1] }
        XCTAssertGreaterThan(energy, 1, "The preserved AAC must decode to the written signal", file: file, line: line)
    }
}


private final class LifetimeProbe: @unchecked Sendable {}

private final class WeakLifetimeProbe {
    weak var value: LifetimeProbe?
    init(_ value: LifetimeProbe) { self.value = value }
}
