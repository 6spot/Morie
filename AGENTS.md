# AGENTS.md

This file defines the working rules for humans and coding agents contributing to Morie.

## Source of truth

Read these before changing code:

1. `README.md` — project direction and current status.
2. `docs/architecture.md` — product/technical architecture constraints.
3. `docs/tasks.md` — task scope and completion state.
4. `docs/development.md` — local development workflow.
5. `docs/deployment.md` — build, signing, packaging, and release workflow.
6. `docs/validation.md` — Phase 0 real-device validation matrix.

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

- Every implementation task must exist in `docs/tasks.md`.
- Update task status in the same PR as the implementation.
- Keep GitHub Issue and `docs/tasks.md` aligned when an Issue exists.
- Use one of: `TODO`, `IN PROGRESS`, `BLOCKED`, `DONE`.
- Do not mark device-dependent work `DONE` until it has actually been validated on supported hardware.

## Pull request workflow

- Work on feature branches; do not develop directly on `main`.
- Keep acceptance criteria explicit.
- Update docs with code.
- Run all checks available in the current environment.
- If a check cannot be run because it needs macOS/Xcode/Apple Intelligence hardware, state that clearly in the PR and leave the relevant validation task open.
- Do not merge Phase 0 until the required real-device compatibility matrix is completed or the project owner explicitly narrows the acceptance criteria.

## Code quality

- Use Swift Concurrency rather than ad-hoc thread management.
- Keep state transitions explicit for recording/delivery flows.
- Failure and cancellation paths must release microphone/capture resources.
- Never lose the user's intentional capture because AI processing failed once persistence is introduced.
- Prefer small, testable types over provider-style abstraction layers that are not yet needed.
- Avoid speculative architecture.

## Documentation rule

A task is not complete if code changed but the affected documentation and `docs/tasks.md` were not updated.