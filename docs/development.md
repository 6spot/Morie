# Development Guide

## Requirements

Current Phase 0 development baseline:

- Apple Intelligence-capable Mac
- macOS 27+
- latest stable Xcode compatible with macOS 27 SDK
- Swift toolchain shipped with that Xcode
- Apple Developer signing identity/team for normal local signing where required

Morie intentionally does not support older Macs by adding alternate ASR/LLM runtimes.

## Open and build

1. Clone `https://github.com/6spot/Morie.git`.
2. Check out the active task branch, currently `phase0/input-foundation`.
3. Open `Morie.xcodeproj` in Xcode.
4. Select the `Morie` scheme/target.
5. Configure your Development Team if Xcode requests signing configuration.
6. Build and run on the local Mac.

## Required permissions

Phase 0 may require:

- Microphone
- Speech Recognition
- Accessibility

The app should surface capability failures rather than silently degrading to a third-party or legacy implementation.

If permissions were denied during development, use macOS System Settings to restore access before retesting. When testing permission onboarding behavior itself, reset the relevant app permission state using normal macOS developer/test procedures.

## Current manual smoke test

1. Launch Morie.
2. Confirm the menu bar item reaches `Ready` on a supported system.
3. Place the caret in another application.
4. Hold `Control + Space`.
5. Speak a short phrase.
6. Release `Control + Space`.
7. Verify the original app regains focus and receives the final text.
8. Repeat several times, including Chinese/English mixed content where relevant.

A successful smoke test is not the full acceptance test. Complete [`validation.md`](./validation.md) before Phase 0 is considered done.

## Development rules

### Work from tasks

Before implementation:

- confirm the task exists in [`tasks.md`](./tasks.md);
- create/update the corresponding detailed file in [`tasks/`](./tasks/README.md);
- connect the task to a GitHub Issue/PR when applicable.

After implementation, update code and task documentation together.

### Branching

Use feature/task branches. Do not implement directly on `main`.

Current convention can remain simple:

- `phase0/input-foundation`
- future examples: `phase1/capture-store`, `phase2/relevant-context`

Task IDs remain stable in docs even if branch naming evolves.

### Dependencies

Default: no external dependency.

A new dependency requires a written justification per `AGENTS.md` and the product baseline. Avoid packages merely for convenience when the system framework is adequate.

### API selection

Use current Apple platform APIs. Do not introduce compatibility fallback merely to compile on older deployment targets.

For current Speech work, the intended path is:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- current capture-input APIs

Do not implement recognition using `SFSpeechRecognizer` as a fallback.

## Concurrency

Prefer structured Swift Concurrency:

- `@MainActor` for UI/application state that must stay on the main actor;
- actors for mutable pipeline state that should be isolated;
- `Task` only where lifecycle/ownership is explicit;
- cancellation should release resources and leave state recoverable.

Avoid arbitrary dispatch queues unless a platform API requires them.

## Logging and diagnostics

As Phase 0 hardens, diagnostics should make the following distinguishable without logging private transcript content unnecessarily:

- capability failure;
- permission state;
- recording/session transition;
- Speech asset availability/download failure;
- transcription finalization failure;
- focus restore failure;
- AX insertion failure and clipboard fallback;
- delivery success/failure;
- latency checkpoints.

Do not log full user Capture content by default.

## Performance measurements

Phase 0 should establish, not prematurely optimize against, a baseline for:

- app binary size;
- cold launch time;
- idle RSS;
- recording RSS;
- ASR final latency;
- final transcript → delivery latency;
- CPU / Energy Impact;
- capture-loss/failure rate during repeated testing.

Record actual measurements in the active task document or a linked validation artifact.

## Before opening/updating a PR

- ensure the project builds in the available supported environment;
- run relevant manual tests;
- check that no accidental external dependency was added;
- update `docs/tasks.md` if overall task status changed;
- update the task detail document with implementation and validation evidence;
- update architecture/deployment/validation docs if procedures or behavior changed;
- explicitly list tests that could not be run.

## Review principle

Prefer the smallest implementation that satisfies the active acceptance criteria. Morie should not accumulate provider routers, generalized plugin systems, cross-platform layers, or cloud abstractions before there is a real requirement.