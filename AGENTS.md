# AGENTS.md

This file defines the working rules for humans and coding agents contributing to Morie.

## Source of truth

Read these before changing code, in this order:

1. `README.md` — project direction and current status.
2. `docs/design/apple-native-first-v0-baseline-v2.md` — repository copy of the approved design baseline and owner-approved amendments.
3. `docs/product-architecture-baseline.md` — approved product/architecture constraints.
4. `docs/architecture.md` — current code/module architecture.
5. `docs/ui-design.md` — macOS 27 native UI / Liquid Glass rules.
6. `docs/tasks.md` — master task plan and overall progress.
7. `docs/tasks/M-xxx-*.md` — detailed execution record for the active task.
8. `docs/reference/type4me.md` — Type4Me reference/migration boundary, consulted only after the Morie requirement is understood.
9. `docs/development.md` — local development workflow.
10. `docs/deployment.md` — build, signing, packaging, and release workflow.
11. `docs/validation.md` — Phase 0 real-device validation matrix.

When implementation changes behavior, update the relevant documentation in the same pull request.

## Non-negotiable product constraints

- **macOS First**: finish the macOS input loop before building iOS.
- **Latest Apple Only**: start at macOS 27+ and Apple Intelligence-capable Macs. Do not add old-platform or old-API compatibility layers.
- **Development Stage, No Legacy Contract**: implement the current design directly. Do not add old-schema migrations, legacy data reconstruction, version routing, compatibility shims, or speculative upgrade paths. Current-version crash recovery and Capture-first data protection remain required.
- **Apple Native First**: the Apple system implementation is the default and required implementation path.
- **Native UI Only**: product UI must use Apple system UI components and the native macOS 27 Liquid Glass design language. Do not replace a system component with a custom imitation.
- **Private Mode first**: V0 has no Morie cloud backend.
- **Single Mac first**: Private Mode currently uses Apple-native local intelligence and storage. iCloud/CloudKit belongs to a later, actual cross-device milestone; it is not a dependency of local persistence or this milestone. No separate Device Only product mode is introduced.
- **Dictionary and Memory are different**: user-maintained dictionary entries specify spelling/explicit aliases; automatic personal Memory records durable information from daily communication. Ordinary input never requires candidate approval.
- **Current scope**: finish Mac input, independent basic cleanup, custom dictionary and automatic local Memory. Inspiration capture/follow-up primarily belongs to the future mobile product and is not active work.
- **Capture First**: intentional user input must be durably saved before AI enrichment once Phase 1 persistence exists.
- **Expression First**: personalization must not make ordinary voice input slow or unreliable.
- **Morie Architecture First**: architecture/design/task requirements are decided from Morie's documents first. Type4Me never overrides them.
- **Reuse Proven Lessons, Not Compatibility Baggage**: Type4Me is an experience/reference source for solved input problems, not a compatibility target or migration template.

## Native UI policy — hard approval gate

Morie's UI baseline is **Apple system UI, not merely Apple-looking UI**.

Required rules:

1. Use standard SwiftUI/AppKit components whenever Apple provides the interaction or presentation primitive.
2. Build and design for macOS 27 so standard controls, menus, toolbars, windows, sheets, popovers, sidebars, navigation and other system surfaces adopt current Liquid Glass behavior automatically.
3. For a genuinely custom control that has no system equivalent, use Apple's own current Liquid Glass APIs (`glassEffect`, `GlassEffectContainer`, glass button styles, `NSGlassEffectView`, etc.) and Apple layout/interaction conventions.
4. Do not hand-draw, shader-simulate, blur-stack, overlay-stack, or otherwise imitate Liquid Glass when a system component/effect exists.
5. Do not introduce a third-party UI framework, component library, design system, rendering runtime, or replacement control library.
6. Do not replace a native control because a custom version is easier to style.
7. If Apple system UI cannot satisfy a product requirement, **stop before implementing a substitute**. Document the exact gap, native options considered, UX/technical trade-offs, and proposed exception, then obtain explicit project-owner approval.
8. No agent or contributor may approve that exception on the owner's behalf.

This approval gate applies even when a custom/third-party approach would be faster to implement.

## External dependency policy — hard approval gate

The default allowed dependency set is Apple system frameworks plus repository-owned Swift code.

Do **not** add a third-party package, runtime, model, SDK, binary framework, C/C++ bridge, Python component, JavaScript runtime, network service, UI library, analytics SDK, updater, database abstraction, or other external dependency without explicit project-owner approval.

Before requesting approval, document:

- the exact requirement Apple-native APIs cannot satisfy;
- Apple-native alternatives considered and why they fail;
- measurable benefit of the proposed dependency;
- binary size, startup, memory, CPU/energy, privacy, signing, packaging and maintenance impact;
- new runtime/model/network requirements;
- security/update ownership;
- removal/migration path if Apple later provides the capability.

If approval has not been explicitly granted, the dependency must not be introduced.

For Phase 0, the expected third-party dependency count is **zero**.

## Platform/API policy

- Use the newest stable Apple APIs available to the macOS 27 deployment target.
- Do not preserve or recreate old-macOS compatibility behavior without reproducing a current macOS 27 requirement.
- Speech recognition uses the modern Speech stack (`SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, related capture APIs).
- Do not introduce `SFSpeechRecognizer` as a recognition fallback. It may only be used where Apple still requires it for authorization until a newer authorization API replaces it.
- Foundation Models capability checks use `SystemLanguageModel`.
- Do not add compatibility routing for unsupported Macs. Unsupported required capabilities block Private Mode.

## Type4Me reference policy

Reference repository: `joewongjc/type4me`.

The mandatory order is:

`Morie design → Morie architecture → active Morie task → exact macOS 27 requirement → Type4Me reference → smallest Apple-native implementation`

Never start from Type4Me code and then bend Morie around it.

Before implementing or redesigning a Phase 0 input behavior, inspect only the relevant Type4Me path and tests/review history to learn which failure modes were real. Then determine whether those failure modes still apply to macOS 27.

Important reference areas include:

- `Type4Me/Audio/AudioCaptureEngine.swift`
- `Type4Me/Session/RecognitionSession.swift`
- `Type4Me/Input/HotkeyManager.swift`
- `Type4Me/Injection/TextInjectionEngine.swift`
- Apple Speech behavior under `Type4Me/ASR/`
- permission/onboarding handling
- focus/target capture logic
- hotword/vocabulary and correction-learning paths when those phases begin

Use these decision labels:

- `ADAPT` — proven concept still matters; reimplement the smallest macOS 27-native version.
- `DROP` — unnecessary under Morie's architecture/platform baseline.
- `VERIFY` — only add compatibility logic after reproducing the issue on current macOS 27.

Do not migrate Type4Me's generalized compatibility surface merely because it exists. In particular, Morie does not automatically inherit multi-hotkey/media/mouse behavior, broad device compatibility, old-system workarounds, old Speech paths, provider routers, Python, sherpa-onnx, C/C++ bridges, subscription/build variants, or external runtimes.

Any code copied substantially from Type4Me must also preserve applicable MIT attribution/license requirements. Prefer concept-level adaptation against current Apple APIs.

## Architecture boundaries

Keep platform-specific macOS integration separate from reusable product logic.

Current Phase 0 responsibilities:

- native macOS 27 app shell and Liquid Glass UI;
- capability gate;
- focused global toggle-capture interaction;
- audio capture/session lifecycle;
- latest Apple Speech transcription;
- frontmost-app/target capture;
- focus restore;
- text injection and clipboard fallback;
- Type4Me reference audit only for currently relevant failure modes.

Do not pull Phase 1+ persistence, Memory, iOS, provider abstractions, MCP, Morie Cloud, or generalized backward-compatibility systems into a Phase 0 change unless the task explicitly requires it.

## Task workflow

Morie uses two documentation levels for tasks:

- `docs/tasks.md` is the **master task overview and progress index**.
- `docs/tasks/M-xxx-*.md` is the **detailed record for one task**.

Rules:

1. Every implementation task gets a stable `M-xxx` ID and a row in `docs/tasks.md`.
2. Every formal task has a dedicated file under `docs/tasks/`; active tasks keep detailed progress there.
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
- A PR introducing any external dependency or non-system UI substitute must include the owner's explicit approval; otherwise it must not be implemented.
- Do not merge Phase 0 until the required real-device compatibility matrix is completed or the project owner explicitly narrows the acceptance criteria.

## Code quality

- Use Swift Concurrency rather than ad-hoc thread management where it fits the current Apple API.
- Keep state transitions explicit for recording/delivery flows.
- Failure and cancellation paths must release microphone/capture resources.
- Never lose the user's intentional capture because AI processing failed once persistence is introduced.
- Prefer small, testable types over provider-style abstraction layers that are not yet needed.
- Avoid speculative architecture and speculative compatibility code.
- Use Type4Me to identify proven failure modes, then implement only the current macOS 27-native protection Morie actually needs.

## Documentation rule

A task is not complete if code changed but any of the following are stale:

- `docs/tasks.md` task-level progress;
- the task's `docs/tasks/M-xxx-*.md` execution record;
- architecture/development/deployment/validation documentation affected by the change;
- UI/design documentation for user-visible changes;
- Type4Me reference/migration notes when input infrastructure changes.

Documentation is part of the implementation, not post-task cleanup.
