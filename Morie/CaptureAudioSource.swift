import AVFoundation
import CoreMedia
import Foundation
import Speech

final class CaptureAudioSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum SourceError: LocalizedError {
        case noInput
        case inputUnavailable
        case outputUnavailable
        case invalidAudioBuffer
        case encoderFailed(String)

        var errorDescription: String? {
            switch self {
            case .noInput: "No microphone input is available."
            case .inputUnavailable: "The microphone input cannot be attached to the capture session."
            case .outputUnavailable: "The microphone data output cannot be attached to the capture session."
            case .invalidAudioBuffer: "The microphone returned an unsupported audio buffer."
            case .encoderFailed(let reason): "Source-audio encoding failed: \(reason)"
            }
        }
    }

    let session = AVCaptureSession()
    let analyzerInputs: AsyncThrowingStream<AnalyzerInput, Error>

    private let output = AVCaptureAudioDataOutput()
    private let outputQueue = DispatchQueue(label: "me.morie.capture-audio", qos: .userInitiated)
    private let converter: AnalyzerInputConverter
    private let destinationURL: URL
    private var audioFile: AVAudioFile?
    private let continuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation
    private let onAudioLevel: @Sendable (Double) -> Void
    private var writtenFrames: AVAudioFramePosition = 0
    private var callbackCount = 0
    private var voicedFrameCount = 0
    private var terminal = false

    init(
        device: AVCaptureDevice,
        converter: AnalyzerInputConverter,
        destinationURL: URL,
        onAudioLevel: @escaping @Sendable (Double) -> Void
    ) throws {
        var streamContinuation: AsyncThrowingStream<AnalyzerInput, Error>.Continuation!
        analyzerInputs = AsyncThrowingStream { streamContinuation = $0 }
        continuation = streamContinuation
        self.converter = converter
        self.destinationURL = destinationURL
        self.onAudioLevel = onAudioLevel

        try? FileManager.default.removeItem(at: destinationURL)
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

        super.init()

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw SourceError.inputUnavailable }
        session.addInput(input)

        output.audioSettings = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: true
        ]
        output.setSampleBufferDelegate(self, queue: outputQueue)
        guard session.canAddOutput(output) else { throw SourceError.outputUnavailable }
        session.addOutput(output)
    }

    func start() {
        session.startRunning()
    }

    func finish() throws -> CapturedSourceAudio {
        session.stopRunning()
        outputQueue.sync {}
        guard !terminal else { throw SourceError.encoderFailed("The audio stream ended unexpectedly.") }
        for input in try converter.flush() {
            continuation.yield(input)
        }
        terminal = true
        continuation.finish()
        output.setSampleBufferDelegate(nil, queue: nil)
        audioFile = nil
        let duration = Double(writtenFrames) / 16_000
        return CapturedSourceAudio(
            url: destinationURL,
            duration: duration,
            hasMeaningfulAudio: voicedFrameCount >= 5
        )
    }

    func cancel() {
        session.stopRunning()
        outputQueue.sync {}
        terminal = true
        continuation.finish(throwing: CancellationError())
        output.setSampleBufferDelegate(nil, queue: nil)
        audioFile = nil
        try? FileManager.default.removeItem(at: destinationURL)
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard !terminal else { return }
        do {
            guard let pcmBuffer = sampleBuffer.moriePCMBuffer else {
                throw SourceError.invalidAudioBuffer
            }
            guard let audioFile else { return }
            try audioFile.write(from: pcmBuffer)
            writtenFrames += AVAudioFramePosition(pcmBuffer.frameLength)
            for input in try converter.convert(pcmBuffer, at: nil) {
                continuation.yield(input)
            }
            let decibels = Self.signalDecibels(pcmBuffer)
            let level = Self.normalizedLevel(decibels)
            if decibels > -50 {
                voicedFrameCount += 1
            }
            callbackCount += 1
            if callbackCount.isMultiple(of: 3) {
                onAudioLevel(level)
            }
        } catch {
            terminal = true
            continuation.finish(throwing: error)
        }
    }

    private static func signalDecibels(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -60 }
        var sum: Float = 0
        for index in 0..<Int(buffer.frameLength) {
            let sample = channel[index]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(buffer.frameLength))
        return rms > 0 ? 20 * log10(rms) : -60
    }

    private static func normalizedLevel(_ decibels: Float) -> Double {
        return Double((min(max(decibels, -42), -6) + 42) / 36)
    }
}

private extension CMSampleBuffer {
    var moriePCMBuffer: AVAudioPCMBuffer? {
        guard let description = formatDescription,
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: streamDescription)
        else { return nil }

        let frames = numSamples
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(frames)
              )
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(frames)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}
