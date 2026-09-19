import AVFoundation
import Combine
import Foundation

@MainActor
final class CaptureHistoryController: ObservableObject {
    typealias RecognizeFile = @Sendable (URL, Locale) async throws -> String

    @Published private(set) var player: AVPlayer?
    @Published private(set) var audioMessage: String?
    @Published private(set) var recognizingCaptureID: UUID?
    @Published private(set) var recognitionMessage: String?
    @Published private(set) var isInputActive = false

    private let store: CaptureStore
    private let locale: Locale
    private let recognizeFile: RecognizeFile
    private var selectedCaptureID: UUID?
    private var recognitionTask: Task<Void, Never>?
    private var playbackObservation: NSKeyValueObservation?

    init(
        store: CaptureStore,
        locale: Locale,
        recognizeFile: @escaping RecognizeFile = CaptureFileTranscriber.recognize
    ) {
        self.store = store
        self.locale = locale
        self.recognizeFile = recognizeFile
    }

    func open(_ id: UUID) {
        if selectedCaptureID != id {
            cancelRecognition()
            recognitionMessage = nil
        }
        selectedCaptureID = id
        refreshAudio(for: id)
    }

    func close(_ id: UUID) {
        guard selectedCaptureID == id else { return }
        selectedCaptureID = nil
        cancelRecognition()
        releasePlayer()
    }

    func refreshAudio(for id: UUID) {
        guard selectedCaptureID == id else { return }
        releasePlayer()
        guard !isInputActive else {
            audioMessage = "本次录音结束后即可播放。"
            return
        }
        do {
            try store.pruneExpiredAudio()
            let url = try store.sourceAudioURL(for: id)
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            audioMessage = nil
            playbackObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
                Task { @MainActor [weak self, weak item] in
                    guard let self, let item,
                          self.selectedCaptureID == id, self.player?.currentItem === item,
                          item.status == .failed
                    else { return }
                    self.audioMessage = "无法播放这段录音。\(item.error?.localizedDescription ?? "")"
                }
            }
        } catch {
            audioMessage = error.localizedDescription
        }
    }

    func setInputActive(_ active: Bool) {
        isInputActive = active
        if active { cancelRecognition() }
        if let selectedCaptureID { refreshAudio(for: selectedCaptureID) }
    }

    func pausePlayback() {
        player?.pause()
    }

    func recognizeAgain(_ id: UUID) {
        guard !isInputActive, recognitionTask == nil else { return }
        let url: URL
        do {
            try store.pruneExpiredAudio()
            url = try store.sourceAudioURL(for: id)
        } catch {
            recognitionMessage = error.localizedDescription
            return
        }

        pausePlayback()
        recognizingCaptureID = id
        recognitionMessage = nil
        Diagnostics.record("History", "File recognition started for \(id.uuidString.prefix(8))")
        recognitionTask = Task { [weak self, recognizeFile, locale] in
            guard let self else { return }
            defer {
                self.recognizingCaptureID = nil
                self.recognitionTask = nil
            }
            do {
                let text = try await recognizeFile(url, locale)
                try Task.checkCancellation()
                guard !self.isInputActive else { throw CancellationError() }
                try self.store.saveReRecognition(text, for: id)
                if self.selectedCaptureID == id {
                    self.recognitionMessage = "识别结果已保存，可复制文字到其他应用使用。"
                }
            } catch {
                // Native cancellation can arrive as a framework error, not just CancellationError.
                if Task.isCancelled || error is CancellationError {
                    Diagnostics.record("History", "File recognition cancelled for \(id.uuidString.prefix(8))")
                    return
                }
                var message = error.localizedDescription
                do {
                    try self.store.recordReRecognitionFailure(message, for: id)
                } catch {
                    message += " The retry status could not be saved: \(error.localizedDescription)"
                }
                if self.selectedCaptureID == id { self.recognitionMessage = message }
                Diagnostics.record("History", "File recognition failed for \(id.uuidString.prefix(8)): \(message)", level: .warning)
            }
        }
    }

    func cancelRecognition() {
        recognitionTask?.cancel()
    }

    func cancelRecognitionAndWait() async {
        let task = recognitionTask
        task?.cancel()
        await task?.value
    }

    func waitForRecognition() async {
        await recognitionTask?.value
    }

    func deleteCapture(_ id: UUID) async throws {
        if recognizingCaptureID == id { await cancelRecognitionAndWait() }
        if selectedCaptureID == id { releasePlayer() }
        try store.deleteCapture(id)
    }

    private func releasePlayer() {
        playbackObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}
