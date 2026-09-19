# M-021 — Capture Session Controller

## Status

**IN PROGRESS** — 2026-09-19

Implementation is in [PR #21](https://github.com/6spot/Morie/pull/21) on `m-021/capture-session-controller`. Code and architecture ownership changes are implemented; macOS 27 compile validation remains pending.

## Why

After M-020 made feature ownership visible, `AppController` still owned both application/setup orchestration and the full live Capture state machine. Capture-specific responsibilities included Speech/HUD/delivery services, authoritative UUIDs, startup/finalization/shutdown tasks, interruption preservation, refinement and terminal delivery handling.

That coupling made unrelated application work touch the most concurrency-sensitive input path. M-021 gives the existing Capture lifecycle one owner without introducing another module or generalized provider framework.

## Scope

Included:

- add `CaptureSessionController` under `Features/Capture`;
- move live Capture UUID/task/session ownership into it;
- move Speech lifecycle, HUD lifecycle, current-focus delivery, refinement and terminal cleanup into it;
- preserve existing CaptureStore, Dictionary, Personalization and Memory collaborators;
- leave `AppController.State` as the UI-facing application state and map Capture phases into it;
- keep global hotkey installation and setup handling in `AppController`;
- update architecture/task documentation.

Explicitly excluded:

- package/module/target splitting;
- changing capture semantics, UI, persistence schema or delivery behavior;
- extracting Memory, Dictionary, Setup, iCloud or Settings into new controllers;
- adding a provider abstraction or dependency.

## Acceptance criteria

- [x] `AppController` no longer owns `SpeechPipeline`, `TextInjector`, `CaptureHUDController`, capture UUID bookkeeping or capture start/finish/shutdown tasks.
- [x] `CaptureSessionController` owns live capture start, pending finish, finalization, explicit cancel, interruption preservation and terminal cleanup.
- [x] App-level setup/hotkey/iCloud/Settings ownership stays in `AppController`.
- [x] Existing visible `AppController.State` cases and UI-facing surface remain unchanged.
- [x] No external dependency, package split, schema change or UI redesign is introduced.
- [ ] macOS 27 compile gate passes.

## Subtasks / progress

- [x] Create Issue #20 and task branch.
- [x] Add `CaptureSessionController` to the existing Capture feature/target.
- [x] Move capture lifecycle state and services out of `AppController`.
- [x] Add phase/transcript/failure callbacks back to `AppController`.
- [x] Update architecture/task docs.
- [x] Open PR #21.
- [ ] Run and record CI.

## Implementation notes

`CaptureSessionController` is intentionally not a generalized provider/session framework. It owns the one current Apple-native capture path and its existing collaborators.

The visible application state remains in `AppController`. Capture phases translate into the existing `recording / stopping / finalizing / refining / delivering / failed` cases. An idle Capture phase only returns the app to Ready when the current app state is capture-owned, so an external blocked/checking state is not overwritten.

Hotkey installation remains application-level. The Capture controller only requests whether Escape cancellation should be enabled while a live capture is recording.

Setup-triggered hotkey failure remains application-level: `AppController` enters Blocked, invalidates the hotkey, asks `CaptureSessionController` to preserve/interrupt any active capture, and then refreshes setup state.

The extraction deliberately migrates the existing behavior instead of redesigning it. Finish requested while Speech startup is still in flight remains attached to the same UUID; explicit cancel still discards only after native teardown; interruption/failure preserves available text/audio; current-app delivery still records a paste that was already dispatched.

## Validation

Pending GitHub macOS 27 compile validation.

Structural checks before CI:

- the new controller is included only in the existing Morie app target;
- `AppController` no longer contains the previous Speech/HUD/delivery service fields or capture UUID/task fields;
- no Capture/Memory/Dictionary persistence types or schemas changed;
- no third-party dependency or target was added.

Runtime-sensitive behavior remains governed by the existing validation matrix; this ownership refactor does not waive finish-during-startup, cancellation, interruption, clipboard fallback or microphone-release checks.

## Known issues / blockers

No known product blocker. Compile validation is pending.

## Follow-up

After this boundary is stable, future reductions of `AppController` should be justified independently. Do not automatically create controllers for every feature merely for symmetry.

Do not extract a shared package until iOS or another real consumer creates reuse pressure.

## References

- GitHub Issue: [#20](https://github.com/6spot/Morie/issues/20)
- Pull request: [#21](https://github.com/6spot/Morie/pull/21)
- [Architecture](../architecture.md)
- [M-020 source-tree organization](M-020-source-tree-organization.md)
