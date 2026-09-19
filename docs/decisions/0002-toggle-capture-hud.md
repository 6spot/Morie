# ADR 0002 — Toggle capture and native HUD

- **Status:** Accepted
- **Date:** 2026-09-17
- **Task:** M-002 — macOS Input Foundation

## Context

Real-device Phase 0 testing showed that a menu-bar status alone does not provide enough feedback during voice capture. A hold-to-talk interaction also forces the user to keep a shortcut physically pressed during longer expression, which does not fit Morie's intended capture experience.

## Decision

The project owner confirms toggle capture as Morie's formal V0 interaction on macOS. This decision supersedes earlier hold-to-talk wording in the product baseline, architecture, task, development, and validation documents:

1. first activation of the configured shortcut starts a Capture; the default is a solo `Fn / Globe` press confirmed on release;
2. releasing the keys does not stop recording;
3. a second activation finishes the active Capture;
4. `Escape` cancels only while recording;
5. the HUD cancel button is equivalent to `Escape`;
6. the HUD confirm button is equivalent to the second shortcut activation;
7. using Fn with any other key/modifier cancels the solo candidate and must not toggle Capture;
8. native Settings provides approved alternate keyboard combinations.

While recording, Morie displays a native non-activating floating HUD near the bottom-center of the active screen. It must not become the target application or steal text-input focus. The reference layout is a compact cancel / waveform / confirm control group; its visual treatment uses macOS 27 system Liquid Glass rather than a custom opaque imitation.

The recording HUD uses Apple-native UI primitives and displays:

- a cancel control;
- a live microphone level visualization;
- a confirm control.

The HUD uses one AppKit `NSGlassEffectView` as the native capsule surface inside the transparent non-activating panel, with standard bordered system buttons embedded in that single material layer. This avoids stacking several independent glass effects and ensures the glass samples behind the window. Only the live microphone waveform is custom-drawn because macOS has no equivalent system control. System accessibility settings govern glass contrast/transparency, and Reduce Motion replaces the traveling waveform with a stationary level visualization.

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
- waveform threshold and gain adapt Type4Me's proven compact indicator behavior, while Morie uses a smaller always-present center-weighted envelope instead of a waveform that begins empty or scrolls in from one edge.
