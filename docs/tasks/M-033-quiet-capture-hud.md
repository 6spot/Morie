# M-033 — Quiet Capture HUD Feedback

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#54](https://github.com/6spot/Morie/issues/54)

## Goal

Make the compact Capture capsule visually quieter and more internally consistent without changing its interaction model.

## Owner decisions

- Cancel and Finish controls use one neutral low-contrast color treatment.
- The capsule uses macOS 27's native `NSGlassEffectView` appearance without a custom black tint, so Liquid Glass retains its own translucency/refraction.
- The `Thinking` label uses secondary text contrast so the black text does not dominate the capsule.
- The earlier rotating accent border is replaced by the reference-style left-to-right fill sweep: a subtle neutral overlay grows across the compact capsule **once per Thinking entry**, then settles into a faint static state while processing continues.
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
 neutral                 neutral

processing
          Thinking
   secondary text +
   left → right soft sweep

successful completion
          Thinking
             ↓
      collapse / fade out
       no success dwell
```

The native `NSGlassEffectView` remains the surface and now uses its system-owned appearance with no custom black tint. No custom blur/material or third-party UI dependency is introduced.

## Acceptance criteria

- [x] Cancel/Finish symbols have the same neutral foreground treatment.
- [x] Cancel/Finish buttons have the same low-contrast bordered treatment.
- [x] Capsule no longer applies a custom black tint; macOS owns the Liquid Glass rendering.
- [x] Thinking text uses secondary contrast instead of primary black.
- [x] Thinking uses a left-to-right reference-style sweep instead of a rotating border highlight.
- [x] Current-app success has no separate HUD state or dwell.
- [x] Capture-only success has no separate HUD state or dwell.
- [x] Clipboard/recognition status messages have no leading decorative icon.
- [x] macOS 27 Release compile passes (CI #143).
- [x] MorieTests pass (CI #143).
- [ ] Owner-device visual/audio check confirms native Liquid Glass is restored, the first cue no longer crackles, and Thinking sweeps only once.

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

The Thinking animation was then refined to match the reference more closely: instead of an angular highlight orbiting the capsule border, a low-contrast fill advances from left to right over ~1.05 s. Owner testing showed that repeated sweeps were distracting, so the final contract is **one sweep per Thinking entry**; after reaching the right edge it settles to a faint static overlay until processing ends. Reduced Motion shows only the static treatment.

macOS 27 CI #149 passed both the Release product compile and the full MorieTests gate for the reference-motion/sound implementation. The initial looping left-to-right Thinking sweep passed CI #152; the owner then reported three real-device issues: first-cue cold-start distortion, weakened Liquid Glass from custom tinting, and repeated Thinking sweeps. This follow-up removes the custom glass tint, makes the sweep single-run, and adds an 18 ms silent pre-roll plus a slightly softer attack before each synthesized cue. macOS 27 CI #155 passed both the Release product compile and the full MorieTests gate for these fixes.

## Validation boundary

The earlier visual refinement passed CI #143. The follow-up that removes the success dwell passed macOS 27 CI #146: Release compile and the full MorieTests gate both succeeded. Final owner-device acceptance should confirm that `Thinking → collapse` feels faster and clearer than a separate success message.
