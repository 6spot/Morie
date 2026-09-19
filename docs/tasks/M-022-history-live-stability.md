# M-022 — History Live Stability

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#22](https://github.com/6spot/Morie/issues/22)

## Goal

Keep the History list and selected detail stable while Morie continues to durably checkpoint the currently active Capture. Also make row metadata easier to scan by trailing-aligning the timestamp.

## Design decision

Do **not** stop progressive persistence. A live Capture must still be created before Speech starts and checkpoint recognized text at the existing cadence for recovery.

Instead, the normal History query excludes records whose lifecycle is `.capturing`. The active record stays in SwiftData for crash/interruption recovery but is not presented as an ordinary historical item. Once it becomes recognized/delivered/deliveryFailed/failed, it enters History normally.

This keeps recovery durability and UI presentation as separate concerns.

## Acceptance criteria

- [x] The normal History query excludes `.capturing` records.
- [x] Progressive live text saves continue without adding the active row to the visible History result.
- [x] A retained terminal Capture becomes visible after its lifecycle leaves `.capturing`.
- [x] Existing selected historical rows remain eligible and are not replaced by the live record.
- [x] Row timestamp is on the trailing edge and stays fully visible before long app text.
- [x] Search/filter/load-more continue to operate over stable historical rows.
- [ ] Capture/History tests pass.
- [ ] macOS 27 Release compile gate passes.
- [ ] Owner interaction check: leave an older detail open, start/finish another recording, and confirm list/detail do not jump.

## Implementation

- Centralize the stable-history `FetchDescriptor` in `CaptureHistoryQuery`.
- Use a raw lifecycle predicate at the SwiftData query boundary rather than filtering after `@Query` delivery.
- Keep the existing `CaptureStore.updateRecognizedText` persistence cadence unchanged.
- Reorder the History row metadata HStack so app/status are leading and date/time is fixed-width trailing content.

## Validation

Automated coverage includes a live and terminal Capture in the same store:

1. terminal record is visible;
2. newly created live Capture is absent;
3. progressive recognized-text save remains absent from History;
4. converting the live Capture to a terminal failed state makes it visible.

The real-window selection/jump behavior still requires owner interaction because hosted CI does not exercise SwiftUI navigation state with a real recording session.
