import AVFoundation
import Combine
import Foundation
import SwiftData

@MainActor
final class CaptureHistoryController: ObservableObject {
    typealias RecognizeFile = @Sendable (URL, Locale) async throws -> String

    @Published private(set) var player: AVPlayer?
    @Published private(set) var audioMessage: String?
    @Published private(set) var recognizingCaptureID: UUID?
    @Published private(set) var recognitionMessage: String?
    @Published private(set) var isInputActive = false
    @Published private(set) var captures: [CaptureRecord] = []
    @Published private(set) var listError: String?

    private let store: CaptureStore
    private let locale: Locale
    private let recognizeFile: RecognizeFile
    private var selectedCaptureID: UUID?
    private var recognitionTask: Task<Void, Never>?
    private var playbackObservation: NSKeyValueObservation?
    private var historyRevisionObservation: AnyCancellable?
    private var listLimit = 0
    private var listSignature: CaptureHistorySignature?
    private var listNeedsRefresh = false
    private var isListVisible = false
    private var presentationContext: ModelContext?

    private static let pageSize = 50

    init(
        store: CaptureStore,
        locale: Locale,
        recognizeFile: @escaping RecognizeFile = CaptureFileTranscriber.recognize
    ) {
        self.store = store
        self.locale = locale
        self.recognizeFile = recognizeFile

        historyRevisionObservation = store.$historyRevision
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.captureListDidChange()
                }
            }
    }

    deinit {
        Diagnostics.record("History", "Control Center History controller deinitialized")
        Diagnostics.recordMemory("control-center-history-deinit")
    }

    var canLoadMoreCaptures: Bool {
        guard let total = listSignature?.count else { return false }
        return captures.count < total
    }

    func setListVisible(_ visible: Bool) {
        isListVisible = visible

        if visible {
            if presentationContext == nil {
                let context = ModelContext(store.container)
                context.autosaveEnabled = false
                presentationContext = context
            }
            refreshListIfNeeded()
        } else {
            releasePresentationResources()
        }
    }

    func loadMoreCaptures() {
        guard isListVisible else { return }
        let nextLimit = max(
            listLimit + Self.pageSize,
            Self.pageSize
        )
        reloadList(limit: nextLimit)
    }

    func releasePresentationResources() {
        isListVisible = false
        cancelRecognition()
        releasePlayer()

        selectedCaptureID = nil
        recognitionMessage = nil
        audioMessage = nil
        captures.removeAll(keepingCapacity: false)
        listError = nil
        listLimit = 0
        listSignature = nil
        listNeedsRefresh = false
        presentationContext = nil
    }

    func captureListDidChange() {
        guard listLimit > 0 else { return }
        listNeedsRefresh = true
        guard isListVisible else { return }
        reloadList(limit: listLimit)
    }

    private func refreshListIfNeeded() {
        guard listLimit > 0 else {
            reloadList(limit: Self.pageSize)
            return
        }

        do {
            guard let context = presentationContext else { return }
            let signature = try CaptureHistoryQuery.signature(in: context)
            guard listNeedsRefresh || signature != listSignature else {
                listError = nil
                return
            }
            reloadList(limit: listLimit, signature: signature)
        } catch {
            listError = "无法加载历史记录。"
            Diagnostics.record(
                "History",
                "History signature refresh failed: \(error.localizedDescription)",
                level: .warning
            )
        }
    }

    private func reloadList(
        limit: Int,
        signature prefetchedSignature: CaptureHistorySignature? = nil
    ) {
        do {
            guard let context = presentationContext else { return }
            let records = try context.fetch(
                CaptureHistoryQuery.descriptor(limit: limit)
            )
            let signature: CaptureHistorySignature
            if let prefetchedSignature {
                signature = prefetchedSignature
            } else {
                signature = try CaptureHistoryQuery.signature(in: context)
            }
            captures = records
            listLimit = limit
            listSignature = signature
            listNeedsRefresh = false
            listError = nil
        } catch {
            listError = "无法加载历史记录。"
            Diagnostics.record(
                "History",
                "History list refresh failed: \(error.localizedDescription)",
                level: .warning
            )
        }
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
                // A terminal Capture may become visible from the live/main context before
                // its last active-session snapshot reaches the background writer. Drain
                // that revision first so an older queued snapshot cannot overwrite a
                // subsequent History retry result.
                try await self.store.flushPersistence(for: id)
                try Task.checkCancellation()
                guard !self.isInputActive else { throw CancellationError() }

                let text = try await recognizeFile(url, locale)
                try Task.checkCancellation()
                guard !self.isInputActive else { throw CancellationError() }
                try self.store.saveReRecognition(text, for: id)
                self.captureListDidChange()
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
                    self.captureListDidChange()
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
        // Serialize deletion after any queued active-session snapshots for the
        // same Capture so a late writer cannot race this History mutation.
        try await store.flushPersistence(for: id)
        try store.deleteCapture(id)
        captureListDidChange()
    }

    private func releasePlayer() {
        playbackObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}
