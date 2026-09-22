import AVFoundation
import AVKit
import Combine
import Foundation

@MainActor
final class CaptureHistoryController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var audioMessage: String?
    @Published private(set) var recognizingCaptureID: UUID?
    @Published private(set) var recognitionMessage: String?
    @Published private(set) var isInputActive = false
    @Published private(set) var captures: [MorieCaptureDTO] = []
    @Published private(set) var listError: String?

    private let client: MorieRuntimeClient
    private let runtimeState: () -> Bool
    private var selectedCaptureID: UUID?
    private var playbackObservation: NSKeyValueObservation?
    private var recognitionTask: Task<Void, Never>?
    private var listLimit = 0
    private var totalCount = 0
    private var isListVisible = false
    private static let pageSize = 50

    init(client: MorieRuntimeClient, runtimeState: @escaping () -> Bool) {
        self.client = client
        self.runtimeState = runtimeState
    }

    var canLoadMoreCaptures: Bool { captures.count < totalCount }

    func setListVisible(_ visible: Bool) {
        isListVisible = visible
        if visible {
            Task { await reload(limit: max(listLimit, Self.pageSize)) }
        } else {
            releasePresentationResources()
        }
    }

    func loadMoreCaptures() {
        guard isListVisible else { return }
        Task {
            await reload(limit: max(listLimit + Self.pageSize, Self.pageSize))
        }
    }

    func releasePresentationResources() {
        isListVisible = false
        recognitionTask?.cancel()
        recognitionTask = nil
        releasePlayer()
        selectedCaptureID = nil
        recognitionMessage = nil
        audioMessage = nil
        captures.removeAll(keepingCapacity: false)
        listError = nil
        listLimit = 0
        totalCount = 0
    }

    func captureListDidChange() {
        guard isListVisible else { return }
        Task { await reload(limit: max(listLimit, Self.pageSize)) }
    }

    func open(_ id: UUID) {
        selectedCaptureID = id
        Task { await refreshDetail(for: id) }
    }

    func close(_ id: UUID) {
        guard selectedCaptureID == id else { return }
        selectedCaptureID = nil
        releasePlayer()
    }

    func refreshAudio(for id: UUID) {
        guard selectedCaptureID == id else { return }
        Task { await refreshDetail(for: id) }
    }

    func setInputActive(_ active: Bool) {
        isInputActive = active
        if let id = selectedCaptureID {
            Task { await refreshDetail(for: id) }
        }
    }

    func pausePlayback() { player?.pause() }

    func recognizeAgain(_ id: UUID) {
        guard recognizingCaptureID == nil, !runtimeState() else { return }
        recognizingCaptureID = id
        recognitionMessage = nil
        pausePlayback()

        recognitionTask = Task {
            defer {
                recognizingCaptureID = nil
                recognitionTask = nil
            }
            do {
                let updated = try await client.rerecognizeHistory(id)
                try Task.checkCancellation()
                replace(updated)
                recognitionMessage =
                    updated.lastRecognitionErrorDescription
                    ?? "识别结果已保存，可复制文字到其他应用使用。"
                configurePlayer(for: updated)
            } catch is CancellationError {
                recognitionMessage = nil
            } catch {
                recognitionMessage = error.localizedDescription
            }
        }
    }

    func cancelRecognition() {
        guard let id = recognizingCaptureID else { return }
        recognitionTask?.cancel()
        Task {
            try? await client.cancelRerecognition(id)
        }
    }

    func deleteCapture(_ id: UUID) async throws {
        releasePlayer()
        try await client.deleteHistory(id)
        await reload(limit: max(listLimit, Self.pageSize))
    }

    private func reload(limit: Int) async {
        do {
            let page = try await client.historyPage(limit: limit)
            captures = page.captures
            totalCount = page.totalCount
            listLimit = limit
            listError = nil
        } catch {
            listError = "无法加载历史记录。"
        }
    }

    private func refreshDetail(for id: UUID) async {
        do {
            let detail = try await client.historyDetail(id)
            replace(detail)
            if selectedCaptureID == id {
                configurePlayer(for: detail)
            }
        } catch {
            audioMessage = error.localizedDescription
        }
    }

    private func replace(_ item: MorieCaptureDTO) {
        if let index = captures.firstIndex(where: { $0.id == item.id }) {
            captures[index] = item
        } else {
            captures.insert(item, at: 0)
        }
    }

    private func configurePlayer(for item: MorieCaptureDTO) {
        releasePlayer()
        guard !runtimeState() else {
            audioMessage = "本次录音结束后即可播放。"
            return
        }
        guard let url = item.sourceAudioURL else {
            audioMessage = "原始录音不可用或已过期。"
            return
        }

        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        audioMessage = nil
        playbackObservation = playerItem.observe(
            \.status,
            options: [.initial, .new]
        ) { [weak self, weak playerItem] item, _ in
            Task { @MainActor [weak self, weak playerItem] in
                guard let self,
                      let playerItem,
                      item.status == .failed,
                      self.player?.currentItem === playerItem
                else { return }
                self.audioMessage =
                    "无法播放这段录音。\(item.error?.localizedDescription ?? "")"
            }
        }
    }

    private func releasePlayer() {
        playbackObservation = nil
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}
