import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class CaptureHUDController {
    private let model = CaptureHUDModel()
    private var panel: NSPanel?
    private weak var animationContainerView: NSView?
    private weak var capsuleView: NSView?
    private var hideTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var processingTransitionTask: Task<Void, Never>?

    private enum Layout {
        static let contentWidth: CGFloat = 142
        static let processingWidth: CGFloat = 94
        static let contentHeight: CGFloat = 34
        static let effectInset: CGFloat = 6
        static let bottomOffset: CGFloat = 48

        static var panelSize: NSSize {
            NSSize(
                width: contentWidth + effectInset * 2,
                height: contentHeight + effectInset * 2
            )
        }
    }

    var onCancel: (() -> Void)? {
        didSet { model.onCancel = onCancel }
    }

    var onConfirm: (() -> Void)? {
        didSet { model.onConfirm = onConfirm }
    }

    func showRecording() {
        hideTask?.cancel()
        hideTask = nil

        processingTransitionTask?.cancel()
        processingTransitionTask = nil
        model.beginRecording()
        showPanel()
        setCapsuleWidth(Layout.contentWidth, animated: false)
        Diagnostics.record("HUD", "Compact capture HUD shown in recording state")
    }

    func updateAudioLevel(_ level: Double) {
        guard model.phase == .recording else { return }
        model.updateAudioLevel(level)
    }

    func showProcessing() {
        hideTask?.cancel()
        hideTask = nil

        if model.phase == .processing || processingTransitionTask != nil {
            return
        }

        showPanel()

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            setCapsuleWidth(Layout.processingWidth, animated: false)
            model.phase = .processing
            Diagnostics.record("HUD", "Compact capture HUD entered processing state")
            return
        }

        // Match the reference rhythm: first let the wide recording capsule
        // close in around the waveform, then replace the waveform with text.
        // Keeping the recording content during the width animation naturally
        // clips the side controls inward instead of hard-cutting them away.
        setCapsuleWidth(Layout.processingWidth, animated: true, duration: 0.16)
        processingTransitionTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(130))
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.09)) {
                self.model.phase = .processing
            }
            self.processingTransitionTask = nil
            Diagnostics.record("HUD", "Compact capture HUD entered processing state")
        }
    }

    func showSuccess(deliveryMode: CaptureDeliveryMode) {
        Diagnostics.record(
            "HUD",
            "Capture completed successfully; closing processing HUD; mode=\(deliveryMode.rawValue)"
        )
        hideSuccessfulProcessing()
    }

    func showClipboardFallback() {
        hideTask?.cancel()
        cancelProcessingTransition()
        model.showFeedback(.clipboardFallback)
        showPanel()
        setCapsuleWidth(Layout.contentWidth, animated: true)
        Diagnostics.record("HUD", "Compact capture HUD showing clipboard fallback", level: .warning)

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showNoSpeech() {
        hideTask?.cancel()
        cancelProcessingTransition()
        model.phase = .noSpeech
        showPanel()
        setCapsuleWidth(Layout.contentWidth, animated: true)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showRecognitionFailure() {
        hideTask?.cancel()
        cancelProcessingTransition()
        model.phase = .recognitionFailure
        showPanel()
        setCapsuleWidth(Layout.contentWidth, animated: true)
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func showFailure() {
        hideTask?.cancel()
        cancelProcessingTransition()
        model.phase = .failure
        showPanel()
        setCapsuleWidth(Layout.contentWidth, animated: true)
        Diagnostics.record("HUD", "Compact capture HUD showing failure", level: .warning)

        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    private func hideSuccessfulProcessing() {
        hideTask?.cancel()
        hideTask = nil
        collapseTask?.cancel()
        cancelProcessingTransition()

        dismissPanel()
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        collapseTask?.cancel()
        cancelProcessingTransition()

        dismissPanel()
    }

    private func showPanel() {
        collapseTask?.cancel()
        collapseTask = nil

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)

        if !panel.isVisible {
            panel.orderFrontRegardless()
            if let animationView = animationContainerView {
                if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                    setPresentation(animationView, scale: 1, opacity: 1)
                } else {
                    animate(
                        animationView,
                        fromScale: 0.82,
                        toScale: 1,
                        fromOpacity: 0,
                        toOpacity: 1,
                        duration: 0.20,
                        timing: .easeOut
                    )
                }
            }
        } else {
            if let animationView = animationContainerView {
                animationView.layer?.removeAllAnimations()
                setPresentation(animationView, scale: 1, opacity: 1)
            }
            panel.orderFrontRegardless()
        }
    }

    private func makePanel() -> NSPanel {
        let size = Layout.panelSize
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Morie owns the capsule motion. AppKit utility-window animation can
        // scale/translate the panel from a lower corner and fights the center morph.
        panel.animationBehavior = .none

        let rootView = NSView(frame: NSRect(origin: .zero, size: size))
        rootView.autoresizingMask = [.width, .height]

        let glassFrame = NSRect(
            x: Layout.effectInset,
            y: Layout.effectInset,
            width: Layout.contentWidth,
            height: Layout.contentHeight
        )
        let glassView = NSGlassEffectView(frame: glassFrame)
        glassView.autoresizingMask = []
        glassView.style = .clear
        glassView.cornerRadius = Layout.contentHeight / 2
        glassView.effectIsInteractive = true
        glassView.wantsLayer = true

        let hostingView = NSHostingView(rootView: CaptureHUDView(model: model))
        hostingView.sizingOptions = []
        hostingView.frame = NSRect(
            origin: .zero,
            size: NSSize(width: Layout.contentWidth, height: Layout.contentHeight)
        )
        hostingView.autoresizingMask = [.width, .height]
        glassView.contentView = hostingView
        rootView.addSubview(glassView)
        rootView.wantsLayer = true
        configureCenterAnchor(for: rootView)
        animationContainerView = rootView
        capsuleView = glassView
        panel.contentView = rootView

        return panel
    }

    private func setCapsuleWidth(
        _ width: CGFloat,
        animated: Bool,
        duration: TimeInterval = 0.16
    ) {
        guard let panel, let view = capsuleView else { return }
        let target = NSRect(
            x: ((panel.contentView?.bounds.width ?? Layout.panelSize.width) - width) / 2,
            y: Layout.effectInset,
            width: width,
            height: Layout.contentHeight
        )

        guard animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            view.frame = target
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.animator().frame = target
        }
    }

    private func cancelProcessingTransition() {
        processingTransitionTask?.cancel()
        processingTransitionTask = nil
    }

    private func releasePanel() {
        collapseTask?.cancel()
        collapseTask = nil
        cancelProcessingTransition()
        panel?.orderOut(nil)
        // Releasing the NSHostingView stops the hidden waveform TimelineView.
        panel?.contentView = nil
        panel = nil
        animationContainerView = nil
        capsuleView = nil
        model.hide()
        Diagnostics.record("HUD", "Capture HUD hidden")
    }

    private func dismissPanel() {
        guard panel != nil, let animationView = animationContainerView else {
            releasePanel()
            return
        }

        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            releasePanel()
            return
        }

        let duration = 0.18
        animate(
            animationView,
            fromScale: currentScale(of: animationView),
            toScale: 0.92,
            fromOpacity: animationView.layer?.presentation()?.opacity ?? 1,
            toOpacity: 0,
            duration: duration,
            timing: .easeOut
        )

        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.releasePanel()
        }
    }

    private func configureCenterAnchor(for view: NSView) {
        guard let layer = view.layer else { return }
        let frame = view.frame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        layer.bounds = CGRect(origin: .zero, size: frame.size)
        layer.position = CGPoint(x: frame.midX, y: frame.midY)
        CATransaction.commit()
    }
    private func animate(
        _ view: NSView,
        fromScale: CGFloat,
        toScale: CGFloat,
        fromOpacity: Float,
        toOpacity: Float,
        duration: TimeInterval,
        timing: CAMediaTimingFunctionName
    ) {
        guard let layer = view.layer else { return }

        layer.removeAllAnimations()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(scaleX: toScale, y: toScale))
        layer.opacity = toOpacity
        CATransaction.commit()

        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = fromScale
        scale.toValue = toScale

        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fromOpacity
        opacity.toValue = toOpacity

        let group = CAAnimationGroup()
        group.animations = [scale, opacity]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(name: timing)
        group.isRemovedOnCompletion = true
        layer.add(group, forKey: "capture-capsule-morph")
    }

    private func setPresentation(_ view: NSView, scale: CGFloat, opacity: Float) {
        guard let layer = view.layer else { return }
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
        layer.opacity = opacity
        CATransaction.commit()
    }

    private func currentScale(of view: NSView) -> CGFloat {
        guard let transform = view.layer?.presentation()?.affineTransform() else { return 1 }
        return max(0.10, sqrt(transform.a * transform.a + transform.c * transform.c))
    }
    private func position(_ panel: NSPanel) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first

        guard let screen else { return }

        let visibleFrame = screen.visibleFrame
        let frame = panel.frame
        let origin = NSPoint(
            x: (visibleFrame.midX - frame.width / 2).rounded(),
            y: (visibleFrame.minY + Layout.bottomOffset - Layout.effectInset).rounded()
        )

        panel.setFrameOrigin(origin)
    }
}

final class CaptureAudioLevelMeter {
    var current: Double = 0
}

@MainActor
final class CaptureHUDModel: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case recording
        case processing
        case clipboardFallback
        case noSpeech
        case recognitionFailure
        case failure
    }

    @Published var phase: Phase = .hidden
    @Published private(set) var recordingGeneration = UUID()
    let audioLevel = CaptureAudioLevelMeter()

    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?

    func beginRecording() {
        audioLevel.current = 0
        recordingGeneration = UUID()
        phase = .recording
    }

    func updateAudioLevel(_ level: Double) {
        audioLevel.current = min(max(level, 0), 1)
    }

    func hide() {
        audioLevel.current = 0
        phase = .hidden
    }

    func showFeedback(_ feedback: Phase) {
        phase = feedback
    }

    func cancel() {
        Diagnostics.record("HUD", "Cancel button pressed")
        onCancel?()
    }

    func confirm() {
        Diagnostics.record("HUD", "Confirm button pressed")
        onConfirm?()
    }
}

@MainActor
private struct CaptureHUDView: View {
    @ObservedObject var model: CaptureHUDModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Layout {
        static let contentWidth: CGFloat = 142
        static let contentHeight: CGFloat = 34
        static let contentInset: CGFloat = 3
        static let controlLaneWidth: CGFloat = 28
        static let controlVisualSize: CGFloat = 20
        static let waveformLaneWidth: CGFloat = 80
        static let waveformWidth: CGFloat = 56
        static let waveformHeight: CGFloat = 20
        static let waveformInset: CGFloat = 2
        static let waveformBarWidth: CGFloat = 2.5
        static let waveformMinHeight: CGFloat = 3
        static let waveformMaxHeight: CGFloat = 16

        static let innerHeight = contentHeight - contentInset * 2
    }

    var body: some View {
        phaseContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: Layout.contentHeight)
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .hidden:
            EmptyView()

        case .recording:
            HStack(spacing: 0) {
                Button(action: model.cancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.88))
                        .frame(width: Layout.controlVisualSize, height: Layout.controlVisualSize)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(Color.secondary.opacity(0.14))
                .frame(width: Layout.controlLaneWidth, height: Layout.innerHeight)
                .accessibilityLabel("取消录音")
                .help("取消录音")

                CompactWaveform(
                    meter: model.audioLevel,
                    reduceMotion: reduceMotion,
                    barWidth: Layout.waveformBarWidth,
                    minHeight: Layout.waveformMinHeight,
                    maxHeight: Layout.waveformMaxHeight
                )
                .id(model.recordingGeneration)
                .frame(
                    width: Layout.waveformWidth - Layout.waveformInset * 2,
                    height: Layout.waveformHeight - Layout.waveformInset * 2
                )
                .padding(Layout.waveformInset)
                .frame(width: Layout.waveformWidth, height: Layout.waveformHeight)
                .frame(width: Layout.waveformLaneWidth, height: Layout.innerHeight)
                .accessibilityLabel("麦克风输入电平")

                Button(action: model.confirm) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary.opacity(0.88))
                        .frame(width: Layout.controlVisualSize, height: Layout.controlVisualSize)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                .controlSize(.small)
                .tint(Color.secondary.opacity(0.14))
                .frame(width: Layout.controlLaneWidth, height: Layout.innerHeight)
                .accessibilityLabel("完成录音")
                .help("完成录音")
            }
            .frame(
                width: Layout.contentWidth - Layout.contentInset * 2,
                height: Layout.innerHeight
            )
            .padding(Layout.contentInset)
            .transition(.opacity)

        case .processing:
            Text("Thinking")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    ProcessingSweep(reduceMotion: reduceMotion)
                        .allowsHitTesting(false)
                }
                .accessibilityLabel("正在整理输入")
                .transition(.opacity)

        case .clipboardFallback:
            Text("已复制到剪贴板")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("输入位置不可用，文字已复制到剪贴板")

        case .noSpeech:
            Text("未检测到语音")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("未检测到语音，本次录音未保存")

        case .recognitionFailure:
            Text("未识别，录音已保留")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("检测到语音但未识别出文字，录音已保留，可在历史记录中重新识别")

        case .failure:
            Image(systemName: "exclamationmark")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.red)
                .frame(width: Layout.waveformWidth, height: Layout.waveformHeight)
                .accessibilityLabel("录音失败")
        }
    }
}

private struct ProcessingSweep: View {
    let reduceMotion: Bool

    @State private var sweepProgress: CGFloat = 0

    private let sweepDuration: TimeInterval = 2.40
    private let pauseDuration: TimeInterval = 0.60

    var body: some View {
        GeometryReader { geometry in
            let bandWidth = max(28, geometry.size.width * 0.44)
            let travel = geometry.size.width + bandWidth
            let offset = -bandWidth + travel * sweepProgress

            if !reduceMotion {
                ZStack(alignment: .leading) {
                    Color.clear

                    LinearGradient(
                        colors: [
                            .clear,
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.26),
                            Color.white.opacity(0.08),
                            .clear,
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: bandWidth, height: geometry.size.height)
                    .offset(x: offset)
                }
                .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .leading
                )
                .clipShape(Capsule())
                .task {
                    while !Task.isCancelled {
                        var reset = Transaction()
                        reset.disablesAnimations = true
                        withTransaction(reset) {
                            sweepProgress = 0
                        }

                        await Task.yield()
                        guard !Task.isCancelled else { return }

                        // The highlight crosses the entire visible capsule.
                        // It is deliberately bright-neutral, not Color.primary,
                        // so light appearance never turns the shimmer black.
                        withAnimation(.linear(duration: sweepDuration)) {
                            sweepProgress = 1
                        }

                        do {
                            try await Task.sleep(
                                for: .seconds(sweepDuration + pauseDuration)
                            )
                        } catch {
                            return
                        }
                    }
                }
            }
        }
    }
}

@MainActor
private final class CompactWaveDynamics {
    private var displayedLevel: CGFloat = 0
    private var previousTarget: CGFloat = 0
    private var lastFrameTime: TimeInterval = 0
    private var lastSampleTime: TimeInterval = 0
    private var recentLevels = Array(repeating: CGFloat.zero, count: 11)

    func update(currentTime: TimeInterval, rawLevel: Double, reduceMotion: Bool) -> [CGFloat] {
        if lastFrameTime == 0 {
            lastFrameTime = currentTime
        }

        let elapsed = min(max(currentTime - lastFrameTime, 0), 0.1)
        lastFrameTime = currentTime
        let normalized = max(0, min(1, CGFloat(rawLevel)))
        // Preserve quiet speech while still mapping normal speech across most
        // of the available height.
        let threshold: CGFloat = 0.10
        let ceiling: CGFloat = 0.88
        let baseTarget = normalized <= threshold
            ? 0
            : pow(min(1, (normalized - threshold) / (ceiling - threshold)), 0.78)
        // Rapid changes are themselves meaningful voice information. A short
        // transient accent makes consonants feel immediate without inventing
        // motion during silence.
        let transient = min(1, abs(baseTarget - previousTarget) * 2.4)
        previousTarget = baseTarget
        let target = min(1, baseTarget + transient * 0.28)

        guard !reduceMotion else {
            displayedLevel = target
            return Array(repeating: displayedLevel, count: recentLevels.count)
        }

        // Preserve continuity between 40 Hz microphone samples, but converge
        // within roughly one rendered frame so consonants do not turn into a
        // slow decorative pulse.
        let response = target > displayedLevel ? 140.0 : 95.0
        let blend = 1 - exp(-response * CGFloat(elapsed))
        displayedLevel += (target - displayedLevel) * blend

        if lastSampleTime == 0 || currentTime - lastSampleTime >= 1.0 / 60.0 {
            recentLevels.insert(displayedLevel, at: 0)
            recentLevels.removeLast()
            lastSampleTime = currentTime
        }

        return recentLevels
    }
}

private struct CompactWaveform: View {
    let meter: CaptureAudioLevelMeter
    let reduceMotion: Bool
    let barWidth: CGFloat
    let minHeight: CGFloat
    let maxHeight: CGFloat

    @State private var dynamics = CompactWaveDynamics()

    // Matches the reference's immediate visual rhythm: quiet edges, an
    // irregular speech-like rise, and one clear center peak. The live meter
    // expands this profile instead of waiting for history to scroll in.
    private let profile: [CGFloat] = [
        0.22, 0.38, 0.55, 0.74, 0.60, 1.00,
        0.68, 0.82, 0.51, 0.34, 0.20,
    ]

    // Center is the newest sample. Moving away from center walks backward
    // through different moments rather than mirroring one shared scalar.
    private let sampleOrder = [10, 8, 6, 4, 2, 0, 1, 3, 5, 7, 9]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            Canvas { context, size in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let levels = dynamics.update(
                    currentTime: time,
                    rawLevel: meter.current,
                    reduceMotion: reduceMotion
                )
                let pitch: CGFloat = 4.95
                guard size.width >= barWidth else { return }

                let totalColumns = profile.count
                let usedWidth = CGFloat(totalColumns - 1) * pitch + barWidth
                let leading = (size.width - usedWidth) / 2

                for index in 0..<totalColumns {
                    let envelope = profile[index]
                    let historicalLevel = levels[sampleOrder[index]]
                    // Keep the recognizable center-weighted resting silhouette,
                    // but reserve most of the available height for live speech.
                    let restingHeight = minHeight + envelope * 1.5
                    // Edge bars remain alive while the center retains the
                    // largest travel. Avoid a symmetric dead-zone at either end.
                    let activityWeight = 0.34 + 0.66 * pow(envelope, 1.55)
                    let barHeight = restingHeight
                        + activityWeight * historicalLevel * (maxHeight - restingHeight)
                    let color = levels[0] > 0.01
                        ? Color.secondary.opacity(0.78)
                        : Color.secondary.opacity(0.45)

                    let rect = CGRect(
                        x: leading + CGFloat(index) * pitch,
                        y: (size.height - barHeight) / 2,
                        width: barWidth,
                        height: barHeight
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(color)
                    )
                }
            }
        }
    }
}
