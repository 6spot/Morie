import AVFoundation
import Foundation
import Speech

enum CaptureFileTranscriber {
    enum TranscriptionError: LocalizedError {
        case unsupportedLocale
        case emptyRecognition

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: "The capture language is not supported by Apple Speech."
            case .emptyRecognition: "No speech was recognized. The saved text and recording have been kept."
            }
        }
    }

    static func recognize(_ url: URL, locale requestedLocale: Locale) async throws -> String {
        try Task.checkCancellation()
        let audioFile = try AVAudioFile(forReading: url)
        guard audioFile.length > 0 else { throw TranscriptionError.emptyRecognition }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw TranscriptionError.unsupportedLocale
        }
        try Task.checkCancellation()

        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        return try await withTaskCancellationHandler {
            let results = Task {
                var segments: [String] = []
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { segments.append(text) }
                }
                return segments.joined(separator: " ")
            }
            defer { results.cancel() }

            do {
                try Task.checkCancellation()
                let lastSample = try await analyzer.analyzeSequence(from: audioFile)
                try Task.checkCancellation()
                if let lastSample {
                    try await analyzer.finalizeAndFinish(through: lastSample)
                } else {
                    await analyzer.cancelAndFinishNow()
                }
                let text = try await results.value
                try Task.checkCancellation()
                guard !text.isEmpty else { throw TranscriptionError.emptyRecognition }
                return text
            } catch {
                results.cancel()
                await analyzer.cancelAndFinishNow()
                throw error
            }
        } onCancel: {
            // End the native result stream as well as cancelling the Swift task.
            Task { await analyzer.cancelAndFinishNow() }
        }
    }
}
