import AVFoundation
import Foundation
import Speech

actor AppleSpeechSession {
    typealias UpdateHandler = @Sendable (_ text: String, _ isFinal: Bool) -> Void

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputProvider: CaptureInputSequenceProvider?
    private var resultTask: Task<Void, Never>?
    private var finalizedText = ""
    private var volatileText = ""

    func start(locale requestedLocale: Locale, onUpdate: @escaping UpdateHandler) async throws {
        guard analyzer == nil else { throw SpeechSessionError.alreadyRunning }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw SpeechSessionError.microphonePermissionMissing
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: requestedLocale) else {
            throw SpeechSessionError.unsupportedLocale(requestedLocale.identifier)
        }

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }

        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            throw SpeechSessionError.noMicrophone
        }

        let provider = try await CaptureInputSequenceProvider.providerWithSession(
            from: microphone,
            compatibleWith: [transcriber]
        )
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        try await analyzer.prepareToAnalyze(in: nil)

        finalizedText = ""
        volatileText = ""
        self.transcriber = transcriber
        self.inputProvider = provider
        self.analyzer = analyzer

        resultTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    if result.isFinal {
                        await self.acceptFinal(text)
                    } else {
                        await self.acceptVolatile(text)
                    }
                    let current = await self.currentText
                    onUpdate(current, result.isFinal)
                }
            } catch {
                // The owning session surfaces start/stop errors. Result-stream termination is expected on stop.
            }
        }

        try await analyzer.start(inputSequence: provider.analyzerInputs)
        provider.captureSession.startRunning()
    }

    func stop() async throws -> String {
        guard let analyzer, let provider = inputProvider else {
            throw SpeechSessionError.notRunning
        }

        provider.captureSession.stopRunning()
        try await analyzer.finalize(through: nil)
        await analyzer.cancelAndFinishNow()
        _ = await resultTask?.value

        let result = currentText
        reset()
        return result
    }

    func cancel() async {
        inputProvider?.captureSession.stopRunning()
        await analyzer?.cancelAndFinishNow()
        resultTask?.cancel()
        reset()
    }

    private var currentText: String {
        Self.join(finalizedText, volatileText)
    }

    private func acceptFinal(_ text: String) {
        finalizedText = Self.join(finalizedText, text)
        volatileText = ""
    }

    private func acceptVolatile(_ text: String) {
        volatileText = text
    }

    private func reset() {
        resultTask = nil
        inputProvider = nil
        analyzer = nil
        transcriber = nil
        finalizedText = ""
        volatileText = ""
    }

    private static func join(_ left: String, _ right: String) -> String {
        guard !left.isEmpty else { return right }
        guard !right.isEmpty else { return left }
        guard let last = left.last, let first = right.first else { return left + right }

        let needsSpace = !last.isWhitespace
            && !first.isWhitespace
            && last.isASCII
            && first.isASCII
            && (last.isLetter || last.isNumber)
            && (first.isLetter || first.isNumber)
        return needsSpace ? left + " " + right : left + right
    }
}

enum SpeechSessionError: LocalizedError {
    case alreadyRunning
    case notRunning
    case microphonePermissionMissing
    case noMicrophone
    case unsupportedLocale(String)

    var errorDescription: String? {
        switch self {
        case .alreadyRunning: "A speech session is already running."
        case .notRunning: "No speech session is running."
        case .microphonePermissionMissing: "Microphone permission is required."
        case .noMicrophone: "No audio capture device is available."
        case .unsupportedLocale(let locale): "Apple Speech does not support locale \(locale)."
        }
    }
}
