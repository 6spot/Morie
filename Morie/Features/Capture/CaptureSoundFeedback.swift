import AVFoundation
import Foundation

@MainActor
final class CaptureSoundFeedback {
    static let enabledDefaultsKey = "capture.soundFeedback.enabled"

    private enum Cue {
        case start
        case stop

        var tones: [(frequency: Double, duration: Double)] {
            switch self {
            case .start:
                [(660, 0.045), (990, 0.055)]
            case .stop:
                [(880, 0.045), (587, 0.055)]
            }
        }
    }

    private let sampleRate: Double = 44_100
    private var startPlayer: AVAudioPlayer?
    private var stopPlayer: AVAudioPlayer?

    init() {
        startPlayer = makePlayer(for: .start)
        stopPlayer = makePlayer(for: .stop)
        startPlayer?.prepareToPlay()
        stopPlayer?.prepareToPlay()
    }

    func playStart() {
        play(startPlayer, label: "start")
    }

    func playStop() {
        play(stopPlayer, label: "stop")
    }

    private func play(_ player: AVAudioPlayer?, label: String) {
        guard let player else {
            Diagnostics.record("CaptureSound", "Cue unavailable: \(label)", level: .warning)
            return
        }
        startPlayer?.stop()
        stopPlayer?.stop()
        player.currentTime = 0
        player.volume = 0.28
        player.play()
        Diagnostics.record("CaptureSound", "Played \(label) cue")
    }

    private func makePlayer(for cue: Cue) -> AVAudioPlayer? {
        guard let data = wavData(for: cue.tones) else { return nil }
        return try? AVAudioPlayer(data: data)
    }

    private func wavData(
        for tones: [(frequency: Double, duration: Double)]
    ) -> Data? {
        let attack = 0.004
        let release = 0.012
        var samples: [Int16] = []

        for tone in tones {
            let frameCount = max(1, Int(tone.duration * sampleRate))
            for index in 0..<frameCount {
                let t = Double(index) / sampleRate
                let remaining = tone.duration - t
                let envelope = min(
                    1,
                    min(t / attack, max(0, remaining / release))
                )
                let value = sin(2 * .pi * tone.frequency * t) * envelope * 0.42
                samples.append(Int16(max(-1, min(1, value)) * Double(Int16.max)))
            }
        }

        guard !samples.isEmpty else { return nil }

        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let bytesPerSample = Int(bitsPerSample / 8)
        let sampleRate = UInt32(self.sampleRate)
        let dataSize = UInt32(samples.count * bytesPerSample)

        var data = Data(capacity: 44 + Int(dataSize))
        data.append(contentsOf: [0x52, 0x49, 0x46, 0x46])
        appendUInt32(36 + dataSize, to: &data)
        data.append(contentsOf: [0x57, 0x41, 0x56, 0x45])
        data.append(contentsOf: [0x66, 0x6D, 0x74, 0x20])
        appendUInt32(16, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(channels, to: &data)
        appendUInt32(sampleRate, to: &data)
        appendUInt32(sampleRate * UInt32(bytesPerSample), to: &data)
        appendUInt16(UInt16(bytesPerSample), to: &data)
        appendUInt16(bitsPerSample, to: &data)
        data.append(contentsOf: [0x64, 0x61, 0x74, 0x61])
        appendUInt32(dataSize, to: &data)
        for sample in samples {
            appendInt16(sample, to: &data)
        }
        return data
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    private func appendInt16(_ value: Int16, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
