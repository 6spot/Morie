import AVFoundation
import CoreMedia
import Foundation
import Speech

final class CaptureAudioSource: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    enum SourceError: LocalizedError {
        case inputUnavailable
        case outputUnavailable
        case invalidAudioBuffer
        case interrupted(String)

        var errorDescription: String? {
            switch self {
            case .inputUnavailable: "无法连接麦克风输入。"
            case .outputUnavailable: "无法连接麦克风音频输出。"
            case .invalidAudioBuffer: "麦克风返回了不支持的音频数据。"
            case .interrupted(let reason): "录音已中断：\(reason)"
            }
        }
    }

    let session = AVCaptureSession()
    let analyzerInputs: AsyncThrowingStream<AnalyzerInput, Error>

    private let output = AVCaptureAudioDataOutput()
    private let outputQueue = DispatchQueue(
        label: "me.morie.capture-audio",
        qos: .userInitiated,
        autoreleaseFrequency: .workItem
    )
    private let stream: CaptureAudioStream
    private var notificationObservers: [NSObjectProtocol] = []
    private var stopped = false

    init(
        device: AVCaptureDevice,
        converter: AnalyzerInputConverter,
        destinationURL: URL,
        onAudioLevel: @escaping @Sendable (Double) -> Void
    ) throws {
        stream = try CaptureAudioStream(
            destinationURL: destinationURL,
            convert: { try converter.convert($0, at: nil) },
            flush: { try converter.flush() },
            onAudioLevel: onAudioLevel
        )
        analyzerInputs = stream.analyzerInputs

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

        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
        ) { [weak self] notification in
            let reason = (notification.userInfo?[AVCaptureSessionErrorKey] as? NSError)?.localizedDescription
                ?? "麦克风录音意外停止。"
            self?.reportFailure(SourceError.interrupted(reason))
        })
        notificationObservers.append(NotificationCenter.default.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
        ) { [weak self] _ in
            self?.reportFailure(SourceError.interrupted("麦克风已不可用。"))
        })
    }

    func start() {
        session.startRunning()
    }

    func finish() -> CaptureAudioStream.Completion {
        stopCaptureSession()
        return outputQueue.sync { stream.finish() }
    }

    func stopImmediately() -> CapturedSourceAudio {
        stopCaptureSession()
        return outputQueue.sync { stream.stopImmediately() }
    }

    private func stopCaptureSession() {
        guard !stopped else { return }
        stopped = true

        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        notificationObservers.removeAll()

        output.setSampleBufferDelegate(nil, queue: nil)
        if session.isRunning {
            session.stopRunning()
        }

        // stopRunning() leaves the capture graph configured. Explicitly detach
        // native inputs/outputs so CoreMedia/AudioToolbox resources can be
        // released even if AVFoundation retains the session briefly.
        session.beginConfiguration()
        if session.outputs.contains(where: { $0 === output }) {
            session.removeOutput(output)
        }
        for input in session.inputs {
            session.removeInput(input)
        }
        session.commitConfiguration()
    }

    deinit {
        stopCaptureSession()
    }

    private func reportFailure(_ error: Error) {
        outputQueue.async { [weak self] in self?.stream.fail(error) }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        autoreleasepool {
            guard let pcmBuffer = sampleBuffer.moriePCMBuffer else {
                stream.fail(SourceError.invalidAudioBuffer)
                return
            }
            stream.append(pcmBuffer)
        }
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
