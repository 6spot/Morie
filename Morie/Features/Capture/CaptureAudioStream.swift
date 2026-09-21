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
    private let captureID: UUID?
    private var convert: ((AVAudioPCMBuffer) throws -> [AnalyzerInput])?
    private var flush: (() throws -> [AnalyzerInput])?
    private var onAudioLevel: (@Sendable (Double) -> Void)?
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private var audioFile: AVAudioFile?
    private var writtenFrames: AVAudioFramePosition = 0
    private var callbackCount = 0
    private var speechEvidence = SpeechActivityEvidence()
    private var ended = false
    private var failure: Error?
    private var completion: Completion?

    init(
        destinationURL: URL,
        captureID: UUID? = nil,
        convert: @escaping (AVAudioPCMBuffer) throws -> [AnalyzerInput],
        flush: @escaping () throws -> [AnalyzerInput],
        onAudioLevel: @escaping @Sendable (Double) -> Void
    ) throws {
        (analyzerInputs, continuation) = AsyncThrowingStream.makeStream()
        self.destinationURL = destinationURL
        self.captureID = captureID
        self.convert = convert
        self.flush = flush
        self.onAudioLevel = onAudioLevel
        DevelopmentDiagnostics.record(
            "AudioStream",
            captureID: captureID,
            "init; file=\(destinationURL.lastPathComponent); targetFormat=16000Hz/mono/AAC32kbps"
        )
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
            speechEvidence.observe(buffer)
            guard let convert else { return }
            for input in try convert(buffer) {
                continuation.yield(input)
            }
            callbackCount += 1
            if callbackCount.isMultiple(of: 3) {
                onAudioLevel?(Self.normalizedLevel(decibels))
            }
        } catch {
            fail(error)
        }
    }

    func fail(_ error: Error) {
        guard !ended else { return }
        DevelopmentDiagnostics.record(
            "AudioStream",
            captureID: captureID,
            level: .error,
            "failed; errorType=\(DevelopmentDiagnostics.errorType(error)); callbacks=\(callbackCount); writtenFrames=\(writtenFrames)"
        )
        failure = error
        ended = true
        continuation.finish(throwing: error)
    }

    func finish() -> Completion {
        if let completion { return completion }
        DevelopmentDiagnostics.record(
            "AudioStream",
            captureID: captureID,
            "finishRequested; callbacks=\(callbackCount); writtenFrames=\(writtenFrames)"
        )
        if !ended {
            do {
                if let flush {
                    for input in try flush() {
                        continuation.yield(input)
                    }
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
        DevelopmentDiagnostics.record(
            "AudioStream",
            captureID: captureID,
            level: .warning,
            "stopImmediately; callbacks=\(callbackCount); writtenFrames=\(writtenFrames)"
        )
        ended = true
        continuation.finish(throwing: CancellationError())
        return closeFile().sourceAudio
    }

    private func closeFile() -> Completion {
        // Closing finalizes the AAC container even when Speech conversion failed.
        // Only CaptureStore may delete it after an explicit discard or expiry.
        audioFile = nil
        convert = nil
        flush = nil
        onAudioLevel = nil
        let evidence = speechEvidence.summary
        let hasMeaningfulAudio = evidence.hasMeaningfulSpeech
        DevelopmentDiagnostics.record(
            "AudioEvidence",
            captureID: captureID,
            "closed; meaningful=\(hasMeaningfulAudio); activeMs=\(Int(evidence.bestActiveDuration * 1_000)); voiceLikeMs=\(Int(evidence.bestVoiceLikeDuration * 1_000)); dynamicRangeDb=\(String(format: "%.1f", evidence.bestDynamicRangeDecibels)); noiseFloorDb=\(String(format: "%.1f", evidence.noiseFloorDecibels)); peakDb=\(evidence.peakDecibels.isFinite ? String(format: "%.1f", evidence.peakDecibels) : "-inf"); callbacks=\(callbackCount); writtenFrames=\(writtenFrames)"
        )
        Diagnostics.record(
            "AudioEvidence",
            "Capture audio closed; meaningful=\(hasMeaningfulAudio); "
                + "activeMs=\(Int(evidence.bestActiveDuration * 1_000)); "
                + "voiceLikeMs=\(Int(evidence.bestVoiceLikeDuration * 1_000)); "
                + "dynamicRangeDb=\(String(format: "%.1f", evidence.bestDynamicRangeDecibels)); "
                + "noiseFloorDb=\(String(format: "%.1f", evidence.noiseFloorDecibels)); "
                + "peakDb=\(evidence.peakDecibels.isFinite ? String(format: "%.1f", evidence.peakDecibels) : "-inf")"
        )
        let result = Completion(
            sourceAudio: CapturedSourceAudio(
                url: destinationURL,
                duration: Double(writtenFrames) / 16_000,
                hasMeaningfulAudio: hasMeaningfulAudio
            ),
            error: failure
        )
        completion = result
        return result
    }

    deinit {
        Diagnostics.record("AudioLifetime", "CaptureAudioStream released")
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


private struct SpeechActivityEvidence {
    struct Summary {
        let hasMeaningfulSpeech: Bool
        let bestActiveDuration: Double
        let bestVoiceLikeDuration: Double
        let bestDynamicRangeDecibels: Float
        let noiseFloorDecibels: Float
        let peakDecibels: Float
    }

    private static let windowDurationSeconds = 0.02
    private static let relativeSpeechRiseDecibels: Float = 8
    private static let absoluteSpeechFloorDecibels: Float = -48
    private static let maximumGapDuration: Double = 0.08
    private static let minimumActiveDuration: Double = 0.20
    private static let minimumVoiceLikeDuration: Double = 0.12
    private static let minimumDynamicRangeDecibels: Float = 4.5
    private static let minimumVoiceZeroCrossingRate: Double = 0.008
    private static let maximumVoiceZeroCrossingRate: Double = 0.30

    private var noiseFloorDecibels: Float = -60
    private var peakDecibels: Float = -.infinity
    private var detectedSpeech = false

    private var runActiveDuration: Double = 0
    private var runVoiceLikeDuration: Double = 0
    private var runGapDuration: Double = 0
    private var runMinimumActiveDecibels: Float = .infinity
    private var runMaximumActiveDecibels: Float = -.infinity

    private var bestActiveDuration: Double = 0
    private var bestVoiceLikeDuration: Double = 0
    private var bestDynamicRangeDecibels: Float = 0

    var summary: Summary {
        Summary(
            hasMeaningfulSpeech: detectedSpeech,
            bestActiveDuration: bestActiveDuration,
            bestVoiceLikeDuration: bestVoiceLikeDuration,
            bestDynamicRangeDecibels: bestDynamicRangeDecibels,
            noiseFloorDecibels: noiseFloorDecibels,
            peakDecibels: peakDecibels
        )
    }

    mutating func observe(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0],
              buffer.frameLength > 0,
              buffer.format.sampleRate > 0
        else { return }

        let sampleRate = buffer.format.sampleRate
        let framesPerWindow = max(1, Int(sampleRate * Self.windowDurationSeconds))
        let frameCount = Int(buffer.frameLength)
        var start = 0

        while start < frameCount {
            let end = min(start + framesPerWindow, frameCount)
            let metrics = Self.metrics(channel, start: start, end: end)
            observeWindow(
                decibels: metrics.decibels,
                zeroCrossingRate: metrics.zeroCrossingRate,
                duration: Double(end - start) / sampleRate
            )
            start = end
        }
    }

    private mutating func observeWindow(
        decibels: Float,
        zeroCrossingRate: Double,
        duration: Double
    ) {
        guard decibels.isFinite, duration > 0 else {
            closeRun()
            return
        }

        peakDecibels = max(peakDecibels, decibels)
        let threshold = max(
            Self.absoluteSpeechFloorDecibels,
            noiseFloorDecibels + Self.relativeSpeechRiseDecibels
        )
        let active = decibels >= threshold
        let voiceLike = active
            && zeroCrossingRate >= Self.minimumVoiceZeroCrossingRate
            && zeroCrossingRate <= Self.maximumVoiceZeroCrossingRate

        if active {
            runGapDuration = 0
            runActiveDuration += duration
            if voiceLike {
                runVoiceLikeDuration += duration
            }
            runMinimumActiveDecibels = min(runMinimumActiveDecibels, decibels)
            runMaximumActiveDecibels = max(runMaximumActiveDecibels, decibels)
            updateBestRun()
        } else {
            // Learn the local room floor only from windows that are already
            // below the speech candidate threshold. Loud steady noise therefore
            // cannot teach the detector to call itself speech.
            noiseFloorDecibels = noiseFloorDecibels * 0.92 + decibels * 0.08
            if runActiveDuration > 0,
               runGapDuration + duration <= Self.maximumGapDuration {
                runGapDuration += duration
            } else {
                closeRun()
            }
        }
    }

    private mutating func updateBestRun() {
        let dynamicRange = currentDynamicRange
        bestActiveDuration = max(bestActiveDuration, runActiveDuration)
        bestVoiceLikeDuration = max(bestVoiceLikeDuration, runVoiceLikeDuration)
        bestDynamicRangeDecibels = max(bestDynamicRangeDecibels, dynamicRange)

        if runActiveDuration >= Self.minimumActiveDuration,
           runVoiceLikeDuration >= Self.minimumVoiceLikeDuration,
           dynamicRange >= Self.minimumDynamicRangeDecibels {
            detectedSpeech = true
        }
    }

    private mutating func closeRun() {
        runActiveDuration = 0
        runVoiceLikeDuration = 0
        runGapDuration = 0
        runMinimumActiveDecibels = .infinity
        runMaximumActiveDecibels = -.infinity
    }

    private var currentDynamicRange: Float {
        guard runMinimumActiveDecibels.isFinite,
              runMaximumActiveDecibels.isFinite
        else { return 0 }
        return runMaximumActiveDecibels - runMinimumActiveDecibels
    }

    private static func metrics(
        _ channel: UnsafeMutablePointer<Float>,
        start: Int,
        end: Int
    ) -> (decibels: Float, zeroCrossingRate: Double) {
        guard end > start else { return (.nan, 0) }

        var sumSquares: Float = 0
        var crossings = 0
        var previous = channel[start]

        for index in start..<end {
            let sample = channel[index]
            sumSquares += sample * sample
            if index > start,
               (sample >= 0 && previous < 0) || (sample < 0 && previous >= 0) {
                crossings += 1
            }
            previous = sample
        }

        let count = end - start
        let rms = sqrt(sumSquares / Float(count))
        let decibels = rms == 0 ? -.infinity : 20 * log10(rms)
        let zeroCrossingRate = count > 1
            ? Double(crossings) / Double(count - 1)
            : 0
        return (decibels, zeroCrossingRate)
    }
}
