import AVFoundation
import Foundation

struct CapturedSourceAudio: Sendable {
    let url: URL
    let duration: TimeInterval
}

final class CaptureAudioArchive: NSObject, AVCaptureFileOutputRecordingDelegate, @unchecked Sendable {
    enum ArchiveError: LocalizedError {
        case outputUnavailable

        var errorDescription: String? { "The microphone session cannot create a source-audio recording." }
    }

    private let output = AVCaptureAudioFileOutput()
    private var continuation: CheckedContinuation<CapturedSourceAudio, Error>?
    private var destinationURL: URL?

    func attach(to session: AVCaptureSession, destinationURL: URL) throws {
        guard session.canAddOutput(output) else { throw ArchiveError.outputUnavailable }
        output.audioSettings = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000
        ]
        session.addOutput(output)
        self.destinationURL = destinationURL
        try? FileManager.default.removeItem(at: destinationURL)
        output.startRecording(to: destinationURL, outputFileType: .m4a, recordingDelegate: self)
    }

    func finish(stopping session: AVCaptureSession) async throws -> CapturedSourceAudio {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.stopRecording()
            session.stopRunning()
        }
    }

    func cancel() {
        if output.isRecording { output.stopRecording() }
        if let destinationURL { try? FileManager.default.removeItem(at: destinationURL) }
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }

    func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        guard let continuation else { return }
        self.continuation = nil
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: CapturedSourceAudio(
                url: outputFileURL,
                duration: max(0, output.recordedDuration.seconds)
            ))
        }
    }
}
