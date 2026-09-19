# M-012 — Idle CPU and HUD lifecycle

- **Status:** IN PROGRESS
- **Owner:** macOS input foundation
- **Depends on:** M-002 capture HUD

## Goal

Morie must stop capture-only rendering when the HUD is hidden, avoid periodic
data-layer work when there is nothing to process, and prevent persistent object
graphs from growing with every completed Capture. Establish the real-device
idle CPU/RSS baseline and repeated-use memory plateau.

## Observed problem

The owner observed roughly 20% CPU while Morie was otherwise unused, together
with unexpectedly high memory use. Code inspection found that the capture HUD
kept its `NSHostingView` after `NSPanel.orderOut`. Its recording phase contained
a 60 Hz SwiftUI `TimelineView`, so after the first capture the invisible
waveform could continue rendering indefinitely.

## Type4Me boundary

- **ADAPT:** bind metering/render work to the visible capture-session lifetime.
- **DROP:** Type4Me UI/runtime architecture and compatibility machinery.
- **VERIFY:** measure CPU, Energy Impact and RSS in the signed app on the owner’s
  Mac before and after at least one capture; investigate further only if the
  hidden-HUD fix does not return the app to a low idle baseline.

No Type4Me source or external dependency is copied.

## Implementation

- The HUD model now has an explicit hidden phase.
- Hiding orders out the panel, detaches its content view and releases the panel,
  ending the waveform `TimelineView` and freeing its render resources.
- Showing a later HUD creates a fresh native panel/view tree.
- A focused regression test covers the hidden → recording → hidden lifecycle
  and audio-level reset.
- Personal Memory learning no longer polls every 30 seconds. Normal Capture
  completion enqueues one source, startup performs one crash-recovery
  reconciliation, and retryable work schedules only its earliest retry time.
- Source-audio expiry cleanup runs at startup, after retention-policy changes
  and from a daily ready-state maintenance loop. Capture start and History
  playback/re-recognition no longer trigger full-table cleanup scans.
- Control Center creates the full Capture query only while History is visible;
  selected details use a UUID-filtered query.
- Diagnostic file output is coalesced into short batches and bounded to 5 MiB;
  error entries still flush immediately.
- Dictionary and Memory literal matching reuse precomputed word boundaries
  instead of tokenizing the same input once per candidate.
- Memory Analysis history is no longer retained in a published all-record array.
  Queue/status/detail reads use bounded queries and UI value snapshots, while
  the Memory mutation context is recreated after saves.
- History initially retains at most 200 Capture rows and loads older records
  explicitly in 200-row increments.
- The correction-suggestion suppression cache is capped at 256 words.

## Validation

- 2026-09-19: isolated macOS 27 `MorieTests` run passed all **103 tests**,
  including the new HUD lifecycle regression (0 failures, 0 skipped).
- 2026-09-19: isolated unsigned macOS 27 Debug app build succeeded.
- `git diff --check` passed.
- Event-driven/data-query changes require the branch CI and updated logic tests
  before merge; real-device behavior remains a separate acceptance gate.
- Real-device idle CPU, Energy Impact and RSS measurements: pending.

The task remains **IN PROGRESS** until the signed-app before/after runtime
measurements confirm the regression is resolved and no second idle hotspot is
material.
