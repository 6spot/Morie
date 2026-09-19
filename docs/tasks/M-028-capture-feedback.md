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
- **Finish**: the stop cue no longer represents microphone shutdown. It plays only after refinement/delivery has succeeded and Morie is transitioning from `Thinking` to the success/close state.
- **Cancel**: no normal stop cue.
- **Startup failure**: no start cue.

This means the start cue confirms recording readiness, while the much quieter finish cue confirms the **whole input transaction** has completed. The finish cue cannot be captured in the retained audio tail because it happens well after microphone shutdown.

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
- [x] finish cue occurs only after successful capture-only save or successful current-app delivery;
- [x] cancel does not use the stop cue;
- [x] no bundled/external audio dependency;
- [x] capsule opens/closes from center;
- [x] Reduce Motion bypasses the morph;
- [x] processing state contains no spinner;
- [x] Xcode 27 / macOS 27 Release compile passes;
- [ ] owner verifies cue volume/tone and capsule motion on-device.

## Validation

GitHub Actions `macOS 27 CI` run #94 passed the Release product compile on Xcode 27/macOS 27.

Owner-device validation remains open for cue loudness/tone, Bluetooth behavior, and the subjective center-morph feel.

## 2026-09-19 owner-device tuning

Owner validation confirmed that the first M-028 slice works end-to-end, but identified three presentation issues:

- the scale animation visually appeared to grow from the lower-left rather than the capsule center;
- the synthesized two-sine cue sounded too dull;
- `Thinking` was too small and its leading symbol was unnecessary.

Follow-up changes:

- animate the actual `NSGlassEffectView` rather than the whole root content view;
- explicitly set the glass layer anchor point/position to the capsule center before applying scale transforms;
- use a slightly slower 10% → 100% center morph (220 ms open / 160 ms close);
- replace the pure-sine cue with a shorter higher-frequency chime containing restrained second/third harmonics and exponential decay;
- increase `Thinking` to 13 pt semibold and remove the icon;
- add a subtle rotating capsule-border highlight during processing, with a stationary low-opacity border under Reduce Motion.

Owner-device visual/audio feel validation remains open for this tuned version.

## 2026-09-19 second owner-device tuning

Owner feedback clarified that the previous stop cue had the wrong semantic timing: it fired as soon as microphone capture ended, exactly when the HUD entered `Thinking`. That sounded like the whole operation was done even though recognition/cleanup/delivery were still running.

Final cue semantics:

```text
start hotkey
  ↓ Speech capture really ready
bright / quiet start ping

finish hotkey
  ↓ microphone closes
Thinking + flowing border
  ↓ Speech final / cleanup / delivery
text actually delivered (or capture-only state durably saved)
  ↓
subtle finish tick
  ↓ success state / capsule close
```

The completion cue is intentionally much quieter than the start cue.

Sound synthesis is retuned again toward a fast droplet/pluck character: a very short upward high-frequency start chirp at low volume, and a single soft downward finish tick.

`Thinking` is 14 pt semibold. Its border now uses the current macOS accent color plus a bright white highlight and a small accent glow, rather than a near-invisible white-only gradient.

Owner-device validation remains open for the final subjective loudness/tone and border visibility.

## Final tuning compile validation

GitHub Actions `macOS 27 CI` run #113 passed the Release product compile on Xcode 27/macOS 27.

The code slice is mergeable. M-028 remains IN PROGRESS only for owner-device subjective validation of the final cue character/volume and Thinking-border visibility.

## 2026-09-19 third owner-device tuning — cues are action feedback

Owner clarified the desired semantics after using the previous completion-timed version:

- The sounds are not state-completion notifications.
- They are **immediate accepted-action feedback** for the two global capture presses.
- Start cue should play as soon as a new capture has been accepted and its HUD/session state is established; it must not wait for Speech asset/session readiness.
- Finish cue should play as soon as a valid finish press is accepted, immediately before the HUD enters `Thinking`; it must not wait for recognition, cleanup, paste, or success.
- Duplicate/ignored finish presses do not play another cue.
- Cancel remains distinct and does not reuse the normal finish cue.

### Reference sound analysis

The owner supplied a recording of another app's preferred sound character. The audible pair is approximately:

```text
start: ~392 Hz → ~523 Hz   (gentle rising two-note chime)
finish: ~392 Hz → ~294 Hz  (softer falling two-note chime)
```

The recording is a capture of playback rather than the original asset, so these frequencies are treated as tonal guidance rather than source samples.

macOS exposes named Application Kit system sounds through `NSSound`, but the stock Tink/Pop/Ping/Glass family are single system alerts and do not reproduce this exact rising/falling two-note contour. Morie therefore keeps its dependency-free in-memory synthesis and retunes it to the reference character rather than copying/bundling another app's audio asset.

Current generated cues:

- start: 392 Hz then 523.25 Hz, ~144 ms including gap, volume 0.14;
- finish: 392 Hz then 293.66 Hz, ~116 ms including gap, volume 0.085;
- restrained second/third harmonics add laptop-speaker clarity without the previous high-frequency chirp.

### Final interaction timing

```text
accepted Start press
  ↓ cue immediately
  ↓ HUD / Speech startup continues

accepted Finish press
  ↓ cue immediately
  ↓ Thinking
  ↓ Speech final / cleanup / paste
  ↓ success / capsule close
```

Owner-device validation remains open for the new tonal match.

## 2026-09-19 fourth owner-device tuning — crispness

Owner confirmed the reference-like contour is close but the current synthesized tone still lacks a crisp attack; the finish tone also feels too short and dull.

The architecture is already correct for memory/runtime cost: `CaptureSoundFeedback.init()` synthesizes both tiny WAV buffers once, creates two retained `AVAudioPlayer` instances and calls `prepareToPlay()`. Capture presses only rewind/play those players; they do not resynthesize audio.

This tuning keeps the same two-note contour but:

- shortens the attack to ~0.9 ms;
- increases restrained upper harmonics for more laptop-speaker definition;
- lowers overall volume slightly;
- lengthens the finish pair, especially its second note;
- keeps finish quieter than start.
