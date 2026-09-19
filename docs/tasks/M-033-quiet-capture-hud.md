# M-033 — Quiet Capture HUD Feedback

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#54](https://github.com/6spot/Morie/issues/54)

## Goal

Make the compact Capture capsule visually quieter and more internally consistent without changing its interaction model.

## Owner decisions

- Cancel and Finish controls use one neutral low-contrast color treatment.
- The capsule glass is less black/heavy.
- The existing soft blue/accent processing ring is retained.
- Current-app completion changes from **已输入** to plain `SUCCESS`.
- `SUCCESS` uses the same softened accent-color family as the processing ring; bright green is removed.
- Text feedback inside the capsule does not carry decorative leading icons.
- Capture-only completion remains **已保存**, also text-only.
- Chinese accessibility labels remain descriptive even where the visible completion word is English.

## Implementation

`CaptureHUDView` now treats controls and state feedback separately:

```text
recording
[ x ]      waveform      [ ✓ ]
 neutral                 neutral

processing
          Thinking
   soft accent-color ring

current-app success
          SUCCESS
     soft accent color
     no leading icon
```

The native `NSGlassEffectView` remains the surface; only its tint intensity is reduced. No custom blur/material or third-party UI dependency is introduced.

## Acceptance criteria

- [x] Cancel/Finish symbols have the same neutral foreground treatment.
- [x] Cancel/Finish buttons have the same low-contrast bordered treatment.
- [x] Capsule tint is visibly softer than the previous black-heavy value.
- [x] Thinking ring is unchanged.
- [x] Current-app success is plain `SUCCESS`, no icon, no green.
- [x] Saved/clipboard/recognition status messages have no leading decorative icon.
- [ ] macOS 27 Release compile passes.
- [ ] MorieTests pass.
- [ ] Owner-device visual check confirms contrast feels appropriately quiet.

## Validation boundary

Hosted CI can prove compilation and regression safety, but it cannot establish the final perceived contrast of Liquid Glass on the owner's display. The owner-device visual check remains the final UI acceptance item.
