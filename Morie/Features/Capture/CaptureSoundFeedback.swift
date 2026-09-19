import AVFoundation
import Foundation

@MainActor
final class CaptureSoundFeedback {
    static let enabledDefaultsKey = "capture.soundFeedback.enabled"

    private struct Tone {
        let frequency: Double
        let duration: Double
        let gain: Double
        let brightness: Double
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
                    // Reference clip: ~130 ms G4 followed immediately by a
                    // longer ~200 ms C5 tail.
                    Tone(frequency: 392.0, duration: 0.132, gain: 0.96, brightness: 0.026),
                    Tone(frequency: 523.25, duration: 0.205, gain: 1.00, brightness: 0.022),
                ]
            case .stop:
                [
                    // Reference clip: the finish cue is not a tiny tick; its
                    // first G4 is comparable in level to Start and resolves
                    // into a soft, longer D4.
                    Tone(frequency: 392.0, duration: 0.134, gain: 0.92, brightness: 0.030),
                    Tone(frequency: 293.66, duration: 0.225, gain: 0.96, brightness: 0.024),
                ]
            }
        }

        var volume: Float {
            switch self {
            case .start: 0.105
            case .stop: 0.095
            }
        }
    }

    private let sampleRate: Double = 48_000
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
        let attack = 0.0024
        let release = 0.026
        // The reference changes pitch directly rather than inserting an
        // audible pause between notes.
        let interToneGapFrames = 0
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
                let decay = exp(-2.65 * progress)
                let phase = 2 * .pi * tone.frequency * t

                // The reference is much closer to a clean sine than the
                // previous brighter synthesized cue. Its tiny third harmonic
                // is more audible than the second, so keep the timbre clear
                // without turning the cue into a dull pure sine.
                let fundamental = sin(phase)
                let second = sin(phase * 2.0) * tone.brightness * 0.25
                let third = sin(phase * 3.0) * tone.brightness
                let fourth = sin(phase * 4.0) * tone.brightness * 0.12 * (1 - progress)
                let normalization = 1 + tone.brightness * 1.37
                let timbre = (fundamental + second + third + fourth) / normalization

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
