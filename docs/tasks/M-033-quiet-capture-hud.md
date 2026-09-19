# M-033 — Quiet Capture HUD Feedback

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#54](https://github.com/6spot/Morie/issues/54)

## Goal

Make the compact Capture capsule visually quieter and more internally consistent without changing its interaction model.

## Owner decisions

- Cancel and Finish controls use one neutral low-contrast color treatment.
- The capsule uses macOS 27's native `NSGlassEffectView.Style.clear` with no custom tint, so the HUD reads as transparent Liquid Glass rather than a gray-white frosted chip.
- The `Thinking` label uses secondary text contrast so the black text does not dominate the capsule.
- The earlier fill-style Thinking sweep is replaced by a single soft highlight band that travels left → right. It is intentionally not a filling progress bar and leaves the native glass untouched after it passes.
- Normal successful completion has **no separate success node**.
- When processing finishes successfully, the `Thinking` capsule closes immediately using its existing collapse/fade-out animation.
- This applies to both current-app delivery and capture-only completion: no `SUCCESS`, **已输入**, **已保存**, checkmark or green flash remains.
- Result messages are reserved for exceptional/actionable outcomes such as clipboard fallback or recognition failure, and remain text-only.
- Chinese accessibility labels remain descriptive even where the visible completion word is English.

## Implementation

`CaptureHUDView` now treats controls and state feedback separately:

```text
recording
[ x ]      waveform      [ ✓ ]
 dynamic secondary gray

processing
          Thinking
   secondary text +
   one slow glass shimmer

successful completion
          Thinking
             ↓
      collapse / fade out
       no success dwell
```

The native `NSGlassEffectView` remains the surface and now uses Apple's clear glass style with no custom tint. Recording glyphs and waveform use dynamic secondary-gray contrast instead of bright white / near-black extremes. No custom blur/material or third-party UI dependency is introduced.

## Acceptance criteria

- [x] Cancel/Finish symbols have the same neutral foreground treatment.
- [x] Cancel/Finish buttons have the same low-contrast bordered treatment.
- [x] Capsule uses native clear Liquid Glass with no custom tint.
- [x] Thinking text uses secondary contrast instead of primary black.
- [x] Thinking uses a single left-to-right glass highlight instead of a rotating border or fill-progress animation.
- [x] Current-app success has no separate HUD state or dwell.
- [x] Capture-only success has no separate HUD state or dwell.
- [x] Clipboard/recognition status messages have no leading decorative icon.
- [x] macOS 27 Release compile passes (CI #143).
- [x] MorieTests pass (CI #143).
- [ ] Owner-device visual/audio check confirms clear Liquid Glass is visually present, waveform/control contrast is calm, the first cue no longer crackles, and the slower Thinking shimmer no longer implies false progress.

## Reference motion/sound refinement — 2026-09-20

The owner supplied a 5.2-second reference capture and asked Morie to adopt its calmer transition rhythm and cue character without undoing the already-approved neutral control colors.

Frame/audio inspection found:

- the recording capsule contracts around the waveform before `Thinking` replaces it;
- the processing capsule is materially narrower than the recording capsule;
- successful completion fades the compact processing capsule rather than collapsing it into a tiny dot or showing a success badge;
- the reference Start cue is approximately G4 (392 Hz) → C5 (523 Hz);
- the reference Finish cue is approximately G4 (392 Hz) → D4 (294 Hz);
- the pitches already matched Morie, but the reference notes are substantially longer, nearly gapless, cleaner in harmonic content, and much closer in Start/Finish loudness.

Morie therefore keeps the approved neutral controls and secondary `Thinking` text while changing motion/audio:

- recording glass remains 142 pt wide; processing contracts to 94 pt over ~160 ms;
- the wide recording content stays visible during that contraction, so the side controls are naturally clipped/retracted and the waveform remains briefly before a 90 ms fade to `Thinking`;
- successful processing now fades at ~94% scale over 200 ms instead of shrinking to 10%;
- Start tone durations are 132 ms + 205 ms; Finish is 134 ms + 225 ms, with no audible inter-note gap;
- generated cue sample rate is 48 kHz, harmonic energy is reduced toward the reference's near-sine timbre, and Finish volume is brought closer to Start.

These changes remain synthesized/prepared once at `CaptureSoundFeedback` initialization; no sound asset or dependency is added.

The Thinking animation was then refined again after owner-device review. A 1.05 s fill still read like a progress bar that reached 100% before local-model cleanup finished. The final direction is a **single ~2.20 s shimmer band**, not a fill: a soft highlight traverses the clear-glass capsule once, then disappears while `Thinking` remains static until processing really finishes. Reduced Motion skips the shimmer entirely.

macOS 27 CI #149 passed both the Release product compile and the full MorieTests gate for the reference-motion/sound implementation. The initial looping left-to-right Thinking sweep passed CI #152; the owner then reported three real-device issues: first-cue cold-start distortion, weakened Liquid Glass from custom tinting, and repeated Thinking sweeps. This follow-up removes the custom glass tint, makes the sweep single-run, and adds an 18 ms silent pre-roll plus a slightly softer attack before each synthesized cue. macOS 27 CI #155 passed both the Release product compile and the full MorieTests gate for these fixes.

## Validation boundary

The earlier visual refinement passed CI #143. The follow-up that removes the success dwell passed macOS 27 CI #146: Release compile and the full MorieTests gate both succeeded. Final owner-device acceptance should confirm that `Thinking → collapse` feels faster and clearer than a separate success message.
