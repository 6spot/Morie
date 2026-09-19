# M-032 — Per-Capture Runtime Context

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#50](https://github.com/6spot/Morie/issues/50)

## Goal

Treat one accepted Capture as a deterministic transaction. Settings and Speech dictionary hints are snapshotted once when the Capture is accepted and cannot change the behavior of that in-flight session.

## Design

`CaptureSessionController` owns one immutable `CaptureSessionContext` for the active UUID:

```text
accepted Start
  ↓
snapshot
  ├─ capture id / delivery mode
  ├─ locale
  ├─ Speech dictionary hints
  ├─ input-cleanup enabled
  ├─ correction-suggestion enabled
  ├─ expression-learning enabled
  ├─ sound-feedback enabled
  └─ accepted timestamp
  ↓
durable Capture shell
  ↓
Speech → cleanup → delivery → post-insertion learning
       all read the same snapshot
```

The editable Settings values remain application preferences for the **next** Capture. They are not a live control channel into an already accepted recording.

## Runtime boundaries

- Speech receives the snapshotted locale and dictionary hints, even when Dictionary changes while startup is still asynchronous.
- Optional cleanup uses the snapshotted cleanup/expression preferences.
- Post-insertion observation uses the snapshotted correction/expression preferences.
- The accepted Start and Finish actions use the same snapshotted sound preference.
- Existing UUID stale-callback checks remain authoritative.
- Session reset clears the context together with the active UUID.

## Excluded

- ASR/LLM provider routers;
- generalized EventBus/replay;
- cloud/provider configuration;
- changing current-focus clipboard delivery;
- persisting this ephemeral runtime context as a new Capture schema.

## Acceptance criteria

- [x] Start creates one immutable context before asynchronous Speech startup.
- [x] Speech hints are read once per accepted Capture.
- [x] Settings changes during a Capture affect only the next Capture.
- [x] Accepted Start/Finish sound behavior is consistent within the same Capture.
- [x] Context is cleared on terminal/reset paths.
- [x] Existing session UUID/stale callback protection remains unchanged.
- [ ] macOS 27 Release product compile passes.
- [ ] Deterministic logic-test gate passes on the M-032 head.

## Validation

No provider abstraction or new persistence schema is introduced. Direct session-setting behavior still benefits from a small owner-device check: begin a recording, change one relevant setting before finishing, and confirm the current Capture keeps its start-time behavior while the next Capture uses the new preference.
