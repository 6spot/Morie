# Type4Me Reference Implementation

## Purpose

Morie's macOS voice-input foundation is **not** a greenfield implementation, but Type4Me is also **not** a migration template.

Type4Me is a reference implementation and experience archive for input infrastructure that has already accumulated real-world behavior, edge cases, fixes, tests, packaging knowledge, and application compatibility lessons.

Reference repository:

- `https://github.com/joewongjc/type4me`
- branch: `main`

Morie only adopts Type4Me behavior **after it passes Morie's own product/architecture/design constraints**.

## Mandatory migration order

Before taking anything from Type4Me, use this order:

1. Read the current Morie product baseline.
2. Read the current Morie architecture.
3. Read the current Morie native UI/dependency rules when relevant.
4. Define the exact Morie requirement for macOS 27+.
5. Inspect the corresponding Type4Me implementation/tests/review history only as reference evidence.
6. Decide the smallest macOS 27-native behavior Morie actually needs.
7. Implement it using current Apple APIs and Morie's architecture.

Type4Me must never drive Morie's architecture in the opposite direction.

Primary Morie sources of truth:

- `docs/design/apple-native-first-v0-baseline-v2.md`
- `docs/product-architecture-baseline.md`
- `docs/architecture.md`
- `docs/ui-design.md`
- active `docs/tasks/M-xxx-*.md`

## Migration principle

> Morie architecture first. Type4Me experience second.

> Reuse proven lessons, not compatibility baggage.

The desired result is a significantly smaller Morie-native implementation for macOS 27+, not a compatibility-preserving extraction of Type4Me.

## Approved extraction strategy

Morie uses **extractive migration by subsystem**.

This deliberately rejects both extremes:

- **Do not copy the complete Type4Me repository into Morie and delete features afterward.** That would import provider abstractions, compatibility layers, settings assumptions, dependencies, and coupling before Morie has justified them.
- **Do not ignore Type4Me and independently rediscover solved failure modes.** Its mature implementation/tests remain valuable evidence for lifecycle and reliability behavior.

For every subsystem, use this workflow:

1. Start from the active Morie task and architecture.
2. State the smallest current macOS 27 requirement.
3. Inspect only the corresponding Type4Me implementation, tests, and relevant review/history.
4. Classify discovered behavior as `ADAPT`, `DROP`, or `VERIFY`.
5. Reimplement the retained behavior as the smallest Morie-native solution using current Apple APIs.
6. Copy Type4Me source code directly only when there is a concrete reason that reimplementation would be worse; preserve applicable MIT attribution when substantial code is transferred.
7. Validate against the current supported macOS 27 environment before adding compatibility branches.

The optimization target is **completion of the active Morie task**, not percentage of Type4Me migrated.

Expected reuse varies by subsystem. For example, Hotkey may reuse mostly state-machine lessons while little source structure survives; Injection may retain more concrete safety behavior; Apple Speech should use Type4Me mostly as behavioral evidence because Morie targets the current Apple Speech stack.

## Platform boundary

Morie starts at **macOS 27+** and does not preserve Type4Me behavior merely because it was needed for earlier macOS releases, older Apple APIs, broader hardware support, or historical implementation constraints.

When Type4Me contains multiple compatibility paths, Morie chooses only the path that matches the current macOS 27 Apple-native architecture.

Do not migrate:

- old macOS workarounds that current macOS 27 APIs make unnecessary;
- legacy Speech compatibility paths;
- provider/runtime abstractions created to support multiple engines;
- old permission/UI compatibility layers that are not required on the current platform baseline;
- generalized hotkey features that Morie's actual V0 interaction does not need;
- broad input-device compatibility features unless Morie's current requirement justifies them;
- fallback technology intended to extend support to machines outside Morie's supported baseline.

## Priority reference areas

### 1. Hotkey lifecycle

Primary reference:

- `Type4Me/Input/HotkeyManager.swift`
- `Type4MeTests/HotkeyStateMachineTests.swift`
- relevant review/development reports

Morie requirement is currently a focused push-to-talk interaction, not Type4Me's generalized hotkey subsystem.

Potentially reusable lessons:

- repeat suppression;
- explicit press/hold/release ownership;
- stale state cleanup;
- stop/abort/reset idempotency;
- synthetic-event exclusion where Morie's own injected events can feed the same event path.

Do **not** automatically migrate:

- mouse-button bindings;
- media-key bindings;
- multiple processing modes;
- arbitrary modifier-only combo machinery;
- cross-mode switching;
- historical compatibility handling that is irrelevant to the selected macOS 27 interaction.

Every retained behavior must be justified by Morie's actual V0 shortcut design.

### 2. Audio capture / recording session

Primary reference:

- `Type4Me/Audio/AudioCaptureEngine.swift`
- `Type4Me/Session/RecognitionSession.swift`

Potentially reusable lessons:

- deterministic start/stop lifecycle;
- release of microphone/capture resources on every terminal path;
- late/stale async-result protection;
- recoverability after failure;
- relevant device/session edge cases that still reproduce on macOS 27.

Do **not** preserve Type4Me audio formats, conversion pipelines, device rules, or warm-up behavior simply because its external ASR engines required them. Morie should use the simplest current Apple-native audio/Speech path that satisfies its architecture.

### 3. Target app, focus and text delivery

Primary reference:

- `Type4Me/Injection/TextInjectionEngine.swift`
- current-focus-injection design/review documents

Potentially reusable lessons:

- avoid delivering into Morie itself;
- preserve user text if the target disappears;
- change-count-aware clipboard restore;
- synthetic Cmd+V event marking if required by Morie's chosen event mechanism;
- bounded Accessibility access;
- real compatibility testing across representative apps.

Compatibility handling must remain proportional to Morie's macOS 27 target. We do not inherit a growing per-app compatibility framework unless actual validation demonstrates a current need.

### 4. Recognition session orchestration

Primary reference:

- `Type4Me/Session/RecognitionSession.swift`
- `Type4MeTests/RecognitionSessionTests.swift`

Potentially reusable lessons:

- one authoritative active session;
- stale asynchronous events must not mutate a newer session;
- deterministic stop/finalization ordering;
- cleanup on all terminal paths.

Morie should implement these concepts in the smallest architecture that fits its single Apple-native Speech path, not reproduce Type4Me's multi-provider orchestration.

### 5. Apple Speech

Type4Me can be inspected for user-facing behavior and lifecycle lessons such as partial/final handling, cancellation, locale behavior, and session integration.

The implementation itself must be based on the **current macOS 27 Speech APIs** (`SpeechAnalyzer`, `SpeechTranscriber`, current asset/input APIs). Old Apple Speech code is not migrated for compatibility.

### 6. Permissions and onboarding

Type4Me can provide evidence about practical macOS permission flows, but Morie must use current macOS 27 behavior and Apple system UI.

Only current requirements for Microphone, Speech Recognition, Accessibility/event handling, and recovery after Settings changes should be retained.

### 7. Later-phase reusable lessons

When later phases start, inspect Type4Me only after reading that phase's Morie design/task document. Potential reference areas include:

- vocabulary/hotword behavior;
- correction learning;
- History persistence semantics;
- personalized revision logic;
- signing/packaging edge cases.

Do not import these early merely because they exist.

## Explicitly do not inherit

Morie does not inherit these Type4Me architecture choices by default:

- large ASR provider enum/registry/factory system;
- large LLM provider matrix;
- cloud-provider settings UI;
- SenseVoice / sherpa-onnx runtime;
- Silero VAD when Apple capability satisfies the requirement;
- Qwen3-ASR Python/MLX server;
- CppJieba when NaturalLanguage is sufficient;
- pricing registry/subscription variants;
- support for old macOS versions or old platform APIs;
- generalized compatibility frameworks that solve requirements outside Morie's macOS 27 baseline;
- provider credentials/account surfaces irrelevant to Private V0.

Any external dependency proposed from Type4Me remains subject to Morie's explicit owner-approval gate. Existing use in Type4Me is not permission to introduce it in Morie.

## Decision labels

For each reference area, use one of these labels in the active task document:

- `ADAPT` — retain a proven concept/behavior, reimplement it in Morie's macOS 27 architecture.
- `DROP` — not required by Morie's current architecture/design/platform baseline.
- `VERIFY` — suspected current macOS 27 issue that must be reproduced before any compatibility code is added.

Avoid `ADOPT` for large Type4Me implementation blocks. Direct code transfer should be exceptional; Morie should normally reimplement the small required behavior against current Apple APIs.

## Phase 0 audit checklist

Before M-002 is implementation-complete, inspect only the relevant portions of:

- [ ] `HotkeyManager.swift` + relevant state-machine tests
- [ ] `AudioCaptureEngine.swift`
- [ ] `RecognitionSession.swift` + relevant tests
- [ ] `TextInjectionEngine.swift`
- [ ] current-focus-injection decisions
- [ ] current permission/onboarding behavior
- [ ] Apple Speech behavior and current-API migration gaps

For each, record:

- the Morie requirement first;
- whether the Type4Me issue still exists on macOS 27;
- `ADAPT`, `DROP`, or `VERIFY`;
- the smallest Morie-native implementation needed.

## Current assessment

The first Morie Phase 0 skeleton is still provisional, but the goal is **not** to replace it with Type4Me's full mature machinery. The goal is to use Type4Me to identify which failure modes are worth protecting against, then implement only the macOS 27-native subset that Morie's design actually requires.