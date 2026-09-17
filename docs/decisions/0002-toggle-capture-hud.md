# ADR 0002 — Toggle capture and native HUD

- **Status:** Accepted
- **Date:** 2026-09-17
- **Task:** M-002 — macOS Input Foundation

## Context

Real-device Phase 0 testing showed that a menu-bar status alone does not provide enough feedback during voice capture. A hold-to-talk interaction also forces the user to keep a shortcut physically pressed during longer expression, which does not fit Morie's intended capture experience.

## Decision

Morie uses a toggle capture interaction on macOS:

1. first `Control + Space` press starts a Capture;
2. releasing the keys does not stop recording;
3. a second `Control + Space` press finishes the active Capture;
4. `Escape` cancels only while recording;
5. the HUD cancel button is equivalent to `Escape`;
6. the HUD confirm button is equivalent to the second `Control + Space` press.

While recording, Morie displays a native non-activating floating HUD near the bottom-center of the active screen. It must not become the target application or steal text-input focus.

The recording HUD uses Apple-native UI primitives and displays:

- a cancel control;
- a live microphone level visualization;
- a confirm control.

After finish is requested, the HUD transitions to processing, then briefly shows success or failure before disappearing.

## Microphone level source

Morie does not open a second microphone capture path and does not add a third-party waveform dependency.

The existing `CaptureInputSequenceProvider` owns the `AVCaptureSession`. Morie polls the `AVCaptureAudioChannel` objects exposed by the provider's audio-output connections and uses `averagePowerLevel` as the live level source. The value is normalized and lightly smoothed for display.

Morie does not modify `CaptureInputSequenceProvider.captureAudioDataOutput`'s sample-buffer delegate or callback queue.

## Consequences

- capture lifetime is explicit rather than tied to physical key duration;
- keyboard autorepeat cannot repeatedly toggle a session;
- `Escape` remains untouched outside an active recording;
- the HUD provides immediate evidence that capture started and the microphone is receiving sound;
- the panel must remain non-activating so the original target application's focus can be restored reliably;
- live level visualization reuses the existing Apple-native capture session and introduces no external dependency.
