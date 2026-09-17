# AGENTS.md

This file defines the working rules for humans and coding agents contributing to Morie.

## Source of truth

Read these before changing code:

1. `README.md` — project direction and current status.
2. `docs/product-architecture-baseline.md` — approved product/architecture constraints.
3. `docs/architecture.md` — current code/module architecture.
4. `docs/tasks.md` — master task plan and overall progress.
5. `docs/tasks/M-xxx-*.md` — detailed execution record for the active task.
6. `docs/development.md` — local development workflow.
7. `docs/deployment.md` — build, signing, packaging, and release workflow.
8. `docs/validation.md` — Phase 0 real-device validation matrix.

When implementation changes behavior, update the relevant documentation in the same pull request.

## Non-negotiable product constraints

- **macOS First**: finish the macOS input loop before building iOS.
- **Latest Apple Only**: target macOS 27+ and Apple Intelligence-capable Macs. Do not add legacy-platform compatibility layers.
- **Apple Native First**: use Swift, SwiftUI/AppKit, AVFoundation, Speech, FoundationModels, NaturalLanguage, Accessibility, iCloud/CloudKit, and other Apple system frameworks before considering external dependencies.
- **Private Mode first**: V0 has no Morie cloud backend.
- **No Device Only mode**: Private Mode is Apple-native local intelligence plus iCloud/CloudKit once persistence ships.
- **Capture First**: intentional user input must be durably saved before AI enrichment once Phase 1 persistence exists.
- **Expression First**: personalization must not make ordinary voice input slow or unreliable.

## Dependency policy

Do not add a third-party package, runtime, model, SDK, C/C++ bridge, Python component, or network service unless all of the following are documented in the PR:

- the Apple-native option is insufficient;
- the benefit is measurable;
- binary size/startup/memory/energy impact is understood;
- removal is feasible if Apple later provides the capability.

For Phase 0, the expected third-party dependency count is **zero**.

## Platform/API policy

- Prefer the newest stable Apple APIs available to the deployment target.
- Speech recognition uses the modern Speech stack (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, related capture APIs).
- Do not introduce `SFSpeechRecognizer` as a recognition fallback. It may only be used where Apple still requires it for authorization until a newer authorization API replaces it.
- Foundation Models capability checks use `SystemLanguageModel`.
- Do not add compatibility routing for unsupported Macs. Unsupported required capabilities block Private Mode.

## Architecture boundaries

Keep platform-specific macOS integration separate from reusable product logic.

Current Phase 0 responsibilities:

- app shell / menu bar;
- capability gate;
- global push-to-talk;
- audio capture and Speech transcription;
- frontmost-app capture;
- focus restore;
- text injection and clipboard fallback.

Do not pull Phase 1+ persistence, Memory, iOS, provider abstractions, MCP, or Morie Cloud into a Phase 0 change unless the task explicitly requires it.

## Task workflow

Morie uses two documentation levels for tasks:

- `docs/tasks.md` is the **master task overview and progress index**.
- `docs/tasks/M-xxx-*.md` is the **detailed record for one task**.

Rules:

1. Every implementation task gets a stable `M-xxx` ID and a row in `docs/tasks.md`.
2. As soon as a task becomes `IN PROGRESS`, create its dedicated file under `docs/tasks/`.
3. The detail file records: why, scope, exclusions, acceptance criteria, subtasks/progress, implementation notes, validation evidence, blockers/known issues, follow-up, and Issue/PR references.
4. `docs/tasks.md` must remain concise; do not turn it into an implementation log.
5. Update the task detail file in the same PR as meaningful implementation progress.
6. If task-level status changes, update `docs/tasks.md` in the same PR.
7. Keep GitHub Issue/PR and repository task docs linked, but GitHub metadata does not replace the repository task record.
8. Use one of the task states: `TODO`, `IN PROGRESS`, `BLOCKED`, `DONE`.
9. Do not mark device-dependent work `DONE` until it has actually been validated on supported hardware.

## Pull request workflow

- Work on feature branches; do not develop directly on `main`.
- Keep acceptance criteria explicit.
- Update docs with code.
- Run all checks available in the current environment.
- If a check cannot be run because it needs macOS/Xcode/Apple Intelligence hardware, state that clearly in the PR and leave the relevant validation item open.
- Do not merge Phase 0 until the required real-device compatibility matrix is completed or the project owner explicitly narrows the acceptance criteria.

## Code quality

- Use Swift Concurrency rather than ad-hoc thread management.
- Keep state transitions explicit for recording/delivery flows.
- Failure and cancellation paths must release microphone/capture resources.
- Never lose the user's intentional capture because AI processing failed once persistence is introduced.
- Prefer small, testable types over provider-style abstraction layers that are not yet needed.
- Avoid speculative architecture.

## Documentation rule

A task is not complete if code changed but any of the following are stale:

- `docs/tasks.md` task-level progress;
- the task's `docs/tasks/M-xxx-*.md` execution record;
- architecture/development/deployment/validation documentation affected by the change.

Documentation is part of the implementation, not post-task cleanup.