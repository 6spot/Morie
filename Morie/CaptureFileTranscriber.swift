import AVFoundation
import Foundation
import Speech

enum CaptureFileTranscriber {
    enum TranscriptionError: LocalizedError {
        case unsupportedLocale
        case emptyRecognition

        var errorDescription: String? {
            switch self {
            case .unsupportedLocale: "Apple 语音识别暂不支持这段录音的语言。"
            case .emptyRecognition: "未识别到语音，已保存的文字和录音均已保留。"
            }
        }
    }

    static func recognize(_ url: URL, locale requestedLocale: Locale) async throws -> String {
        try Task.checkCancellation()
        let audioFile = try AVAudioFile(forReading: url)
        guard audioFile.length > 0 else { throw TranscriptionError.emptyRecognition }
        guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw TranscriptionError.unsupportedLocale
        }
        try Task.checkCancellation()

        let transcriber = DictationTranscriber(locale: locale, preset: .longDictation)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        return try await withTaskCancellationHandler {
            let results = Task {
                var segments: [String] = []
                for try await result in transcriber.results {
                    try Task.checkCancellation()
                    let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty { segments.append(text) }
                }
                return segments.joined()
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
