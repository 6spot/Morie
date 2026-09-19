# M-028 — Capture Feedback

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#37](https://github.com/6spot/Morie/issues/37)

## Goal

Make Morie's global capture state obvious even when the user is not looking directly at the bottom-center HUD.

## Inspiration

Two useful implementation lessons were taken from current Type4Me/OpenLess code without importing their UI systems:

- Type4Me prebuilds short start/stop `AVAudioPlayer` cues instead of creating audio state on every hotkey press.
- OpenLess treats sound as capture-state-edge feedback and makes the cue optional.

Morie keeps the slice smaller: two synthesized in-memory tones, one boolean setting, and no bundled sound pack or output-device picker.

## Audio semantics

- **Start**: play only after `SpeechPipeline.start` succeeds and the session is truly recording.
- **Finish**: `SpeechPipeline.stop` closes `CaptureAudioSource` first, then emits a capture-stopped callback; the stop cue plays from that edge while analyzer finalization continues.
- **Cancel**: no normal stop cue.
- **Startup failure**: no start cue.

This means the normal stop tone is not captured in the retained audio tail.

Settings adds **录音开始和结束提示音**, default on.

## Capsule motion

The existing fixed-size native panel remains; only its visible content root morphs:

```text
hidden
  ↓
tiny center point (~6%)
  ↓ 180 ms ease-out
full capsule
  ↓ lifecycle states stay full size
success / saved / failure timeout
  ↓ 140 ms ease-in
tiny center point
  ↓
release NSHostingView + panel
```

Keeping the panel geometry fixed avoids monitor repositioning or layout jumps. Releasing the host after collapse preserves the existing idle-performance rule that the waveform TimelineView must not survive while hidden.

Reduce Motion skips the scale animation.

## Processing state

The old indeterminate `ProgressView` is removed. Processing uses a compact `Thinking` + sparkles label. This avoids suggesting that Morie is waiting on a network request.

## Acceptance criteria

- [x] default-on setting exists;
- [x] start cue is tied to successful capture startup;
- [x] stop cue occurs after microphone capture closes;
- [x] cancel does not use the stop cue;
- [x] no bundled/external audio dependency;
- [x] capsule opens/closes from center;
- [x] Reduce Motion bypasses the morph;
- [x] processing state contains no spinner;
- [ ] Xcode 27 / macOS 27 Release compile passes;
- [ ] owner verifies cue volume/tone and capsule motion on-device.
