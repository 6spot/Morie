# M-033 — Quiet Capture HUD Feedback

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#54](https://github.com/6spot/Morie/issues/54)

## Goal

Make the compact Capture capsule visually quieter and more internally consistent without changing its interaction model.

## Owner decisions

- Cancel and Finish controls use one neutral low-contrast color treatment.
- The capsule glass is less black/heavy.
- The existing soft blue/accent processing ring is retained unchanged.
- The `Thinking` label uses secondary text contrast so the black text does not dominate the capsule.
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
   existing accent ring

successful completion
          Thinking
             ↓
      collapse / fade out
       no success dwell
```

The native `NSGlassEffectView` remains the surface; only its tint intensity is reduced. No custom blur/material or third-party UI dependency is introduced.

## Acceptance criteria

- [x] Cancel/Finish symbols have the same neutral foreground treatment.
- [x] Cancel/Finish buttons have the same low-contrast bordered treatment.
- [x] Capsule tint is visibly softer than the previous black-heavy value.
- [x] Thinking ring is unchanged.
- [x] Thinking text uses secondary contrast instead of primary black.
- [x] Current-app success has no separate HUD state or dwell.
- [x] Capture-only success has no separate HUD state or dwell.
- [x] Clipboard/recognition status messages have no leading decorative icon.
- [x] macOS 27 Release compile passes (CI #143).
- [x] MorieTests pass (CI #143).
- [ ] Owner-device visual check confirms contrast feels appropriately quiet.

## Validation boundary

The earlier visual refinement passed CI #143. The follow-up that removes the success dwell passed macOS 27 CI #146: Release compile and the full MorieTests gate both succeeded. Final owner-device acceptance should confirm that `Thinking → collapse` feels faster and clearer than a separate success message.
