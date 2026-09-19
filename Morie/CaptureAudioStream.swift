import AVFoundation
import Foundation
import Speech

// CaptureAudioSource serializes access on its output queue, including shutdown.
final class CaptureAudioStream {
    struct Completion: Sendable {
        let sourceAudio: CapturedSourceAudio
        let error: Error?
    }

    let analyzerInputs: AsyncThrowingStream<AnalyzerInput, Error>

    private let destinationURL: URL
    private let convert: (AVAudioPCMBuffer) throws -> [AnalyzerInput]
    private let flush: () throws -> [AnalyzerInput]
    private let onAudioLevel: @Sendable (Double) -> Void
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private var audioFile: AVAudioFile?
    private var writtenFrames: AVAudioFramePosition = 0
    private var callbackCount = 0
    private var hasAudioSignal = false
    private var ended = false
    private var failure: Error?
    private var completion: Completion?

    init(
        destinationURL: URL,
        convert: @escaping (AVAudioPCMBuffer) throws -> [AnalyzerInput],
        flush: @escaping () throws -> [AnalyzerInput],
        onAudioLevel: @escaping @Sendable (Double) -> Void
    ) throws {
        (analyzerInputs, continuation) = AsyncThrowingStream.makeStream()
        self.destinationURL = destinationURL
        self.convert = convert
        self.flush = flush
        self.onAudioLevel = onAudioLevel
        audioFile = try AVAudioFile(
            forWriting: destinationURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 32_000
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        guard !ended, let audioFile else { return }
        do {
            try audioFile.write(from: buffer)
            writtenFrames += AVAudioFramePosition(buffer.frameLength)
            let decibels = Self.signalDecibels(buffer)
            // Record signal evidence before Speech conversion, which can fail.
            if decibels != -.infinity { hasAudioSignal = true }
            for input in try convert(buffer) {
                continuation.yield(input)
            }
            callbackCount += 1
            if callbackCount.isMultiple(of: 3) {
                onAudioLevel(Self.normalizedLevel(decibels))
            }
        } catch {
            fail(error)
        }
    }

    func fail(_ error: Error) {
        guard !ended else { return }
        failure = error
        ended = true
        continuation.finish(throwing: error)
    }

    func finish() -> Completion {
        if let completion { return completion }
        if !ended {
            do {
                for input in try flush() {
                    continuation.yield(input)
                }
            } catch {
                fail(error)
            }
        }
        ended = true
        continuation.finish()
        return closeFile()
    }

    func stopImmediately() -> CapturedSourceAudio {
        if let completion { return completion.sourceAudio }
        ended = true
        continuation.finish(throwing: CancellationError())
        return closeFile().sourceAudio
    }

    private func closeFile() -> Completion {
        // Closing finalizes the AAC container even when Speech conversion failed.
        // Only CaptureStore may delete it after an explicit discard or expiry.
        audioFile = nil
        let result = Completion(
            sourceAudio: CapturedSourceAudio(
                url: destinationURL,
                duration: Double(writtenFrames) / 16_000,
                hasMeaningfulAudio: hasAudioSignal ? nil : false
            ),
            error: failure
        )
        completion = result
        return result
    }

    private static func signalDecibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return .nan }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        return rms == 0 ? -.infinity : 20 * log10(rms)
    }

    private static func normalizedLevel(_ decibels: Float) -> Double {
        guard decibels.isFinite else { return 0 }
        return Double((min(max(decibels, -42), -6) + 42) / 36)
    }
}
