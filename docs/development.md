# Development Guide

## Requirements

Current Phase 0 development baseline:

- Apple Intelligence-capable Mac
- macOS 27+
- latest Xcode compatible with the macOS 27 SDK
- Swift toolchain shipped with that Xcode
- Apple Developer signing identity/team for normal local signing where required

Morie intentionally does not support older Macs by adding alternate ASR/LLM runtimes.

## Open and build

1. Clone `https://github.com/6spot/Morie.git`.
2. Check out the active task branch, currently `phase0/input-foundation`.
3. Open `Morie.xcodeproj` in Xcode.
4. Select the `Morie` target.
5. Configure your Development Team if Xcode requests signing configuration.
6. Build and run on a supported Mac.

Command-line compile validation can use:

```bash
xcodebuild \
  -project Morie.xcodeproj \
  -target Morie \
  -configuration Debug \
  -sdk macosx27.0 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Disabling signing here is for compile validation only; normal local launch/distribution follows the appropriate signing path.

## CI compile gate

`.github/workflows/macos-27-build.yml` compiles product changes on GitHub's `xcode-27` hosted environment.

The CI gate exists to catch:

- current macOS 27 SDK signature drift;
- Swift 6 strict-concurrency errors;
- Xcode project/build-setting breakage;
- accidental product-source compile failures.

It is intentionally scoped to changes under `Morie/**`, `Morie.xcodeproj/**`, and the workflow itself. Documentation-only changes do not need another expensive macOS compile run.

CI is **not** runtime acceptance. A hosted build cannot prove real microphone/TCC behavior, physical hotkeys, focus restoration, app injection, Liquid Glass rendering, or latency/energy characteristics.

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
8. Repeat several times, including short taps, rapid repeated holds, and Chinese/English mixed content where relevant.
9. Verify the previous clipboard content is restored after clipboard fallback unless another app/user changed the clipboard meanwhile.

Also validate release during startup/session setup: releasing the shortcut must not allow a late microphone session to start afterward.

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

Default: no external product dependency.

A new dependency requires a written justification per `AGENTS.md` and the product baseline. Avoid packages merely for convenience when the system framework is adequate.

The GitHub-hosted CI workflow and official checkout action are development infrastructure, not Morie runtime/product dependencies.

### API selection

Use current Apple platform APIs. Do not introduce compatibility fallback merely to compile on older deployment targets.

For current Speech work, the intended path is:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- `CaptureInputSequenceProvider`

Do not implement recognition using `SFSpeechRecognizer` as a fallback. Its presence is currently limited to authorization where the current SDK exposes that permission path.

### Type4Me reference use

For every subsystem:

`Morie requirement → Type4Me code/tests → ADAPT / DROP / VERIFY → smallest macOS 27-native implementation`

Do not import generalized compatibility machinery merely because it exists upstream.

## Concurrency

Prefer structured Swift Concurrency:

- `@MainActor` for UI/application state;
- actors for mutable pipeline state that should be isolated;
- `Task` only where lifecycle/ownership is explicit;
- use explicit capture/session identity when async work can outlive the interaction that started it;
- cancellation must release resources and leave state recoverable.

Avoid arbitrary dispatch queues unless a platform API requires them.

Native C frameworks that lack Swift 6 concurrency annotations may use an explicit `@preconcurrency import` boundary when justified. Do not disable strict concurrency globally to silence such errors.

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

Phase 0 should establish a baseline for:

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

- ensure the macOS 27 compile gate passes for product changes;
- run relevant manual tests on supported hardware;
- check that no accidental external product dependency was added;
- update `docs/tasks.md` if overall task status changed;
- update the task detail document with implementation and validation evidence;
- update architecture/deployment/validation docs if procedures or behavior changed;
- explicitly list tests that could not be run.

## Review principle

Prefer the smallest implementation that satisfies the active acceptance criteria. Morie should not accumulate provider routers, generalized plugin systems, cross-platform layers, cloud abstractions, or compatibility frameworks before there is a real requirement.
