import AVFoundation
import Foundation

@MainActor
final class CaptureSoundFeedback {
    static let enabledDefaultsKey = "capture.soundFeedback.enabled"

    private struct Tone {
        let frequency: Double
        let duration: Double
        let gain: Double
    }

    private enum Cue {
        case start
        case stop

        // Tuned from the owner's reference recording: a quiet rising two-note
        // start chime and an even softer falling two-note finish chime.
        var tones: [Tone] {
            switch self {
            case .start:
                [
                    Tone(frequency: 392.0, duration: 0.055, gain: 0.82),
                    Tone(frequency: 523.25, duration: 0.082, gain: 1.0),
                ]
            case .stop:
                [
                    Tone(frequency: 392.0, duration: 0.045, gain: 0.66),
                    Tone(frequency: 293.66, duration: 0.064, gain: 0.72),
                ]
            }
        }

        var volume: Float {
            switch self {
            case .start: 0.14
            case .stop: 0.085
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
        play(startPlayer, cue: .start, label: "start")
    }

    func playStop() {
        play(stopPlayer, cue: .stop, label: "stop")
    }

    private func play(_ player: AVAudioPlayer?, cue: Cue, label: String) {
        guard let player else {
            Diagnostics.record("CaptureSound", "Cue unavailable: \(label)", level: .warning)
            return
        }
        startPlayer?.stop()
        stopPlayer?.stop()
        player.currentTime = 0
        player.volume = cue.volume
        player.play()
        Diagnostics.record("CaptureSound", "Played \(label) cue")
    }

    private func makePlayer(for cue: Cue) -> AVAudioPlayer? {
        guard let data = wavData(for: cue.tones) else { return nil }
        return try? AVAudioPlayer(data: data)
    }

    private func wavData(
        for tones: [Tone]
    ) -> Data? {
        let attack = 0.0015
        let release = 0.010
        let interToneGapFrames = Int(0.007 * sampleRate)
        var samples: [Int16] = []

        for (toneIndex, tone) in tones.enumerated() {
            if toneIndex > 0 {
                samples.append(contentsOf: repeatElement(0, count: interToneGapFrames))
            }

            let frameCount = max(1, Int(tone.duration * sampleRate))
            for index in 0..<frameCount {
                let t = Double(index) / sampleRate
                let progress = Double(index) / Double(max(frameCount - 1, 1))
                let remaining = tone.duration - t

                let attackEnvelope = min(1, t / attack)
                let releaseEnvelope = min(1, max(0, remaining / release))
                let decay = exp(-3.2 * progress)
                let phase = 2 * .pi * tone.frequency * t

                // Mostly a clean musical tone with just enough upper harmonic
                // energy to feel crisp on laptop speakers at low volume.
                let fundamental = sin(phase)
                let second = sin(phase * 2.0) * 0.12
                let third = sin(phase * 3.0) * 0.025
                let timbre = (fundamental + second + third) / 1.145

                let value = timbre
                    * attackEnvelope
                    * releaseEnvelope
                    * decay
                    * tone.gain

                samples.append(
                    Int16(max(-1, min(1, value)) * Double(Int16.max))
                )
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
