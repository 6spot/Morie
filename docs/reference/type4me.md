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

Morie requirement is a focused toggle-capture interaction, not Type4Me's generalized hotkey subsystem.

Potentially reusable lessons:

- repeat suppression;
- explicit key-press ownership and repeat suppression;
- stale state cleanup;
- stop/abort/reset idempotency;
- synthetic-event exclusion where Morie's own injected events can feed the same event path.
- fail-open handling when Accessibility trust disappears: tear down the tap and return the event untouched;
- keep file logging off the event/UI path on a dedicated serial queue.

Current Morie-specific decision after the 2026-09-17 real-device timeout incident:

- **ADAPT:** Type4Me's immediate Accessibility check, tap teardown, state reset, pass-through behavior, and background diagnostic-file queue.
- **DROP:** media/mouse/generalized binding machinery and its broad 0.5-second hotkey watchdog.
- **DO NOT COPY:** Type4Me automatically re-enables a disabled tap while Accessibility remains trusted. Morie observed six disable/re-enable events in one short run together with system-wide keyboard unresponsiveness, so Phase 0 uses the safer policy: release on timeout and require an explicit capability recheck.

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
- transient pasteboard markers so temporary injection/restoration traffic is not captured by clipboard-history apps such as Raycast;
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

M-010 audit, 2026-09-18: inspected `PermissionManager.swift`, `PermissionGuideModel.swift` and `Type4MeTests/PermissionGuideModelTests.swift` at upstream `cc56207b46a30c4c6bf7af0c04b48cc44d06ffc4`. Reviewed permission history `092f71e` (denial/settings return and old signing identity), `5fce88f` (#281: setup bypass, overlay polling CPU and revocation handling) and `bfa487e` (guide/settings consistency).

- **ADAPT:** separate read-only inspection from explicit requests; denied Microphone/Speech access goes to System Settings; refresh on app activation; give setup and recovery one clear native guide.
- **ADAPT:** mandatory completion checks cannot be bypassed. Morie additionally requires Apple Intelligence, modern Chinese Speech availability and Speech authorization, regardless of another product's optional-provider rules. Tests inject all status/actions and never query real TCC.
- **DROP:** custom permission-drag overlays, System Settings window polling, provider selection, optional Apple Speech, signature migration recovery and automatic relaunch/probe systems. These do not follow Morie's current native-only, no-legacy requirement.
- **VERIFY:** any current macOS 27 event-tap/permission restart issue must be reproduced before adding recovery logic. Existing event-tap failure remains explicit and preserves ordinary keyboard input; this UI task does not add a platform workaround.

The implementation is Morie-owned snapshot/controller logic plus native Apple permission APIs and SwiftUI Form/Window controls. No Type4Me implementation or external dependency was imported.

M-010 Speech callback follow-up, 2026-09-18: rechecked the same upstream `PermissionManager.swift`, guide tests and `092f71e` history against the owner's paused-process stack and macOS 27 SDK header. Type4Me's permission manager is nonisolated; Morie's gate is `@MainActor`, so a same-shaped unannotated completion inherits an isolation requirement that the background TCC callback violates.

- **ADAPT:** checked-continuation completion and status reinspection, with an explicit `@Sendable` handler at Morie's native Speech boundary. A regression retaining the Objective-C call boundary reproduces the dispatch assertion without touching TCC and passes with the annotation.
- **DROP:** assuming the authorization callback runs on the main queue, changing global concurrency checks, or introducing signing/relaunch compatibility logic for this failure.
- **VERIFY:** signed-app allow/deny and Settings-return behavior after rebuilding; injected callbacks do not establish actual consent-dialog acceptance.

M-010 permission-window focus follow-up, 2026-09-19: the owner requires the originating Morie window to return after an explicit authorization, and requires Accessibility to open its Settings pane without a redundant system prompt. This narrows the earlier rejection of Type4Me's broad Settings-window polling.

- **ADAPT:** remember and restore the originating native window; after an explicit Privacy-pane action only, use a bounded low-frequency permission-status wait that terminates on grant, return, cancellation or timeout.
- **DROP:** permanent/background System Settings polling and opening the Accessibility pane in parallel with its registration prompt. A later device finding confirmed that `prompt: false` does not add a new app to the list, so Morie must retain `kAXTrustedCheckOptionPrompt: true` as the single public registration/navigation flow.
- **VERIFY:** signed-app TCC registration, focus ordering, allow/deny and return-without-grant behavior on macOS 27. Logic tests do not control System Settings or establish device acceptance.

### M-005 input-cleanup prompt audit, 2026-09-19

Inspected upstream `ProcessingMode.formalWritingPromptTemplate` and the archived voice-polish prompt iteration notes at Type4Me revision `55e8779354cb38a959138ac8fd53a1ce7a75cc4e`.

- **ADAPT:** organize the model instruction by role, task goal, hard boundaries, spoken-language cleanup, formatting, structure/register, context and a small set of generic examples. Retain Type4Me's proven distinction between formal and informal speech so cleanup can improve readability without erasing meaningful conversational tone.
- **DROP:** mandatory Arabic-number conversion for conversational time, forced “总起句 + 编号分点”, generated item titles/subitems, inserted transition phrases, and any rule that changes user-stated counts. Those behaviors belong to Type4Me's stronger Voice Polish mode and exceed Morie's current light-edit contract.
- **ADAPT:** examples should teach behavior classes rather than copy owner-specific UI wording. The prompt explicitly states that example wording, stance and opinions may not leak into unrelated input.
- **VERIFY:** real Apple Foundation Models fidelity for punctuation, repetition, colloquial time and formal/informal register remains a supported-device acceptance item. Prompt shape and unit assertions alone do not prove semantic preservation.

No Type4Me code or external dependency is copied; this is a concept-level prompt-organization adaptation under Morie's existing M-005 contract.

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

M-003 source-audio evidence:

- `ADAPT`: Type4Me's single authoritative `AVCaptureAudioDataOutput`, deterministic stop/drain/detach lifecycle, and streaming sample ownership.
- `DROP`: full uncompressed PCM accumulation in memory and provider/runtime complexity.
- `REJECTED`: adding `AVCaptureAudioFileOutput` beside Apple's `CaptureInputSequenceProvider` data output. Although `canAddOutput` returned true, macOS 27 threw an Objective-C exception from `startRecording` and aborted Morie on owner hardware.
- Morie's replacement must preserve the approved 7-day compressed-audio policy while using one proven data-output path; it must not start a second microphone session.
- `ADAPT` implemented for verification: Morie now owns one data output and drains its callback queue before finishing. Each buffer is forwarded to Apple Speech and streamed to Apple's AAC encoder; unlike Type4Me, the complete PCM recording is never accumulated in memory.

## M-003 History recovery audit — 2026-09-18

Morie requirement: play retained audio and explicitly re-recognize it without losing the original Capture, altering a previous delivery, or delaying a new live input session.

Inspected `Type4Me/UI/Settings/HistoryTab.swift`, the finalization/retry portions of `Type4Me/Session/RecognitionSession.swift`, and `Type4MeTests/RecordingCancellationTests.swift` in fix [#311](https://github.com/joewongjc/type4me/pull/311) (`cc56207b`). The relevant history also includes [#303](https://github.com/joewongjc/type4me/pull/303), which records why recognized and delivered text must remain distinguishable.

- **ADAPT:** preserve earlier nonempty transcript evidence even if a later result becomes empty; distinguish explicit cancellation from failed recognition; reject late results after cancellation; retain original delivered output separately from a new recognition.
- **DROP:** automatic multi-provider/batch retry, network finalization grace periods, full PCM replay buffers, custom History styling, and provider/usage analytics.
- **VERIFY:** quiet speech versus ambient noise and native file-recognition/playback behavior on macOS 27. No new audio threshold is accepted as a proven speech detector.

Apple's current [`SpeechDetector`](https://developer.apple.com/documentation/speech/speechdetector) documentation says it gates transcription and may discard real speech. Morie therefore keeps the live `SpeechTranscriber` path and performs explicit History retry through `SpeechAnalyzer.analyzeSequence(from:)`. Uncertain empty recordings remain recoverable. No Type4Me source was copied.

## M-003 capture-only entry audit — 2026-09-18

The approved Morie baseline requires `captureOnly` as an intentional in-app entry. Inspected the session-start target reset and post-recognition delivery decision in `Type4Me/Session/RecognitionSession.swift`, together with the cancellation tests and #311 history already cited above.

- **ADAPT:** establish a fresh destination for every capture, retain session identity through asynchronous finalization, and keep successful completion distinct from cancellation.
- **DROP:** Type4Me's manual/automation target routing and configurable clipboard output after cancellation. Morie's saved `captureOnly` mode bypasses delivery entirely and uses the existing explicit-discard cancellation behavior.
- **VERIFY:** switching apps before capture-only finish, alternating with normal shortcut input, and live microphone/History preemption on macOS 27.

The implementation adds no provider, legacy format, old API or compatibility route, and copies no Type4Me source.

## M-003 interruption preservation audit — 2026-09-18

Morie requirement: operational interruption must retain intentional audio/text; explicit user cancellation must close native recording before discarding it. Source conversion/finalization failure must not delete earlier AAC frames.

Inspected explicit cancellation and terminal-error handling in `Type4Me/Session/RecognitionSession.swift`, stop/drain/detach in `Type4Me/Audio/AudioCaptureEngine.swift`, synchronous paste dispatch in `Type4Me/Injection/TextInjectionEngine.swift`, and the recording-cancellation tests/history at #311 (`cc56207b`). `AudioCaptureEngineTests.swift` covers format/chunk assumptions and does not prove error-path AAC finalization.

- **ADAPT:** authoritative session identity, deterministic teardown, preservation of prior text/audio after operational error, explicit discard semantics, and recording delivery outcome at paste dispatch.
- **DROP:** provider/network recovery, automatic partial-text injection, broad device workarounds, and complete PCM replay storage. No Type4Me source was copied.
- **VERIFY:** actual macOS 27 microphone interruptions, startup/finalization cancellation timing and immediate subsequent capture. Apple AAC encode/decode tests now prove readable files for controlled converter/flush errors and immediate stop; they do not replace those device checks.

## M-004 explicit Memory foundation audit — 2026-09-18

Morie requirement: selectively save user-confirmed vocabulary/project memory with source IDs and lifecycle, then retrieve active context. Inspected `Services/VocabularyCommands.swift`, `Services/HotwordStorage.swift`, `Type4MeTests/VocabularyCommandsTests.swift`, and the provenance distinction in `UI/Settings/CorrectionProvenance.swift` (#300).

- **ADAPT:** case-insensitive duplicate detection, surfacing save failures, explicit user choice before vocabulary writes, and recording provenance when an action occurs rather than reconstructing it later.
- **DROP:** UserDefaults/file migration, built-in dictionaries, snippet replacement rules, URL/automation commands, cloud hotword tables and external ASR restarts. Morie uses the current SwiftData schema directly and has no compatibility contract.
- **VERIFY:** native editor/navigation/accessibility and the usefulness of real Chinese/English names/aliases. Native NaturalLanguage matching is tested on synthetic examples; no Type4Me source or dictionary is copied.

## M-004 candidate provenance audit — 2026-09-18

Morie requirement: use saved final text for selective candidate extraction, retain the actual input/evidence, and explicitly review before creating Memory. The owner requires future AI-polished output to be saved here while recognized text remains separate. Revisited `UI/Settings/CorrectionProvenance.swift` and `Type4MeTests/CorrectionProvenanceTests.swift` (#300).

- **ADAPT:** record the actual text/provenance at the action boundary; distinguish recognized text from final output and avoid attributing an AI transformation to another operation. Keep explicit review and duplicate/save-error behavior from the vocabulary audit above.
- **DROP:** legacy provenance reconstruction, snippet/provider routing, translation modes and old-build inference. Morie has no released data contract and calls the macOS 27 on-device Foundation Models APIs directly. No Type4Me source was copied.
- **VERIFY:** model selectivity, Chinese/English evidence fidelity, review usability and optional-model cancellation latency on owner hardware. Deterministic tests prove source-state handling, not AI quality.

## M-005 restrained input refinement audit — 2026-09-18

Morie requirement: use confirmed relevant Vocabulary/Project context to improve the next input while preserving the user's own wording and reliable delivery. Inspected `Type4MeTests/IntelliSensePromptAndGuardTests.swift`, `Type4Me/LLM/PromptContext.swift`, and the provenance lessons in `UI/Settings/CorrectionProvenance.swift` / its tests (#300).

- **ADAPT:** treat transcript/context as data rather than instructions; preserve technical tokens, negation, facts and tone; do not answer dictated requests; do not remove acknowledgments such as 嗯/OK/好的 through a filler-word list. Record the actual input and change provenance when refinement happens.
- **DROP:** scene/provider routing, prompt-variable frameworks, clipboard/selection context reads, translation modes, generalized rewriting, old-build inference and Type4Me's lock/detached-AX timeout machinery. Morie uses one current native model session, a native structured result and a Swift-concurrency deadline owner; no source was copied.
- **VERIFY:** real on-device terminology benefit, punctuation quality, mixed-language fidelity and latency versus unrefined input. Morie initially added a provisional two-second deadline, but owner review rejected elapsed time as a correctness condition because work scales with input length. Cleanup now waits for model completion/failure or explicit cancellation; deterministic tests cover cancellation ownership, not a model-duration limit.

## M-009 dictionary and automatic Memory amendment — 2026-09-18

The earlier M-004/M-005 audits record the design at that time. The owner's current requirement separates user-maintained words from automatically learned personal information and removes required Memory candidate confirmation. [M-009](../tasks/M-009-macos-input-memory.md) and [the cleanup contract](../input-cleanup.md) supersede those earlier product rules.

- **ADAPT:** existing prompt/data isolation, technical-content protection, provenance, save-error and duplicate-handling lessons; native Speech contextual strings supply bounded dictionary hints. Meaningful short replies and uncertainty remain content.
- **DROP:** vocabulary stored as personal Memory, a required daily-input review inbox, narrow punctuation-only cleanup, provider-specific hotwords and any old-schema compatibility layer. Personal Memory analyzes committed final text in durable idle batches.
- **ADAPT:** the owner-supplied [OpenLess behavior reference](openless.md) adds an independent opt-in confirmation after a user corrects a word. It creates a spelling hint, not an automatic global replacement or a personal fact. No OpenLess source is copied.
- **VERIFY:** actual native Speech hint benefit, model fidelity and personal-evidence selection, input preemption, bounded AX reads/focus and native correction-prompt usability on macOS 27. Logic tests cannot establish those device results.

## M-011 word-only dictionary amendment — 2026-09-18

The owner clarified that a dictionary entry should save just one word. [M-011](../tasks/M-011-simple-dictionary.md) removes M-009's explicit-alias fields and configuration directly. The vocabulary/save-error and Speech-hint lessons above still apply; no new upstream implementation is needed for this simplification.

- **ADAPT:** normalized duplicate handling, explicit save errors, bounded native Speech hints and immutable word/processing evidence.
- **DROP:** alias editing, alias collision rules, full-/half-width normalization and unconditional substitutions. Same-word letter-case normalization remains, with native word boundaries and technical-content protection.
- **VERIFY:** actual recognition benefit and the compact native editor's focus/keyboard/VoiceOver behavior. The OpenLess-inspired correction confirmation still saves only the corrected word.

### M-011 Apple hotword and segmentation follow-up — 2026-09-19

The owner's **文字 / 蚊子** and **常 蚊 子** results required checking whether Type4Me had a proven Apple-native correction path. Inspected `HotwordStorage.swift`, `SpeechRecognizer.swift`, `AppleASRClient.swift`, `RecognitionSession.swift`, provider protocol builders and relevant history at upstream `cc56207b46a30c4c6bf7af0c04b48cc44d06ffc4`.

- **ADAPT:** Type4Me joins confirmed/partial recognition pieces directly and does not invent whitespace. Morie applies the same behavior to `SpeechTranscriber` results, fixing its own artificial separator that produced **常 蚊 子**. Morie retains macOS 27 `AnalysisContext.contextualStrings`, the current native equivalent of a recognition hint.
- **DROP:** Type4Me's Apple client explicitly ignores shared `ASRRequestOptions.hotwords`; only external providers map them to native keyterm/prompt/boosting APIs. Do not copy provider hotword machinery, cloud tables, ASR restarts, alias tables, candidate heuristics, phonetic rewriting or unconditional **蚊子 → 文字** substitution. Full-/half-width normalization is also removed as unrelated to recognition quality.
- **VERIFY:** signed-device dictation of **再来试一试长文字吧** with **文字** saved and **Codex** when Speech returns **Coldex** must confirm both useful contextual bias, model-assisted correction and absence of artificial inter-segment spaces. Apple `contextualStrings` remains a hint rather than a forced vocabulary. Morie therefore supplies the same bounded dictionary snapshot to cleanup without requiring an exact match in the erroneous transcript. Type4Me does not prove Apple-native hotword effectiveness, and logic tests cannot prove model output.


### M-011 small built-in vocabulary follow-up — 2026-09-19

The owner asked whether Morie should keep a small baseline after reviewing Type4Me's vocabulary history. Rechecked upstream `HotwordStorage.swift` and changelog at revision `55e8779354cb38a959138ac8fd53a1ce7a75cc4e`. Type4Me historically carried 139 code-defined AI/dev hotwords and separate built-in/user files, but later changed `loadEffective()` to return only user-managed words.

- **ADAPT:** the lesson that a small product-owned vocabulary can improve first-run recognition for a few high-value names, and that user words should take precedence over a matching built-in spelling.
- **DROP:** Type4Me's 139-word baseline, dual JSON files, provider-specific hotword/cloud synchronization and built-in snippet replacement machinery. Morie keeps only a tiny code-owned baseline and no replacement rules.
- **ADAPT:** persist provenance for user words created manually versus words accepted from the correction prompt. They remain the same semantic object and therefore share one SwiftData entity rather than separate duplicate tables; provenance keeps the backend distinction explicit.
- **VERIFY:** actual Apple Speech benefit and any unintended bias from the small baseline on signed macOS 27 hardware. The baseline must stay small enough that user-specific words retain priority.

This narrows the earlier M-004 decision that dropped built-in dictionaries entirely; that older decision rejected Type4Me's large file/provider machinery, not a later owner-approved tiny Morie-native baseline.

## M-014 current-keyboard-focus delivery audit — 2026-09-19

Morie requirement: ordinary interactive dictation should behave like a keyboard/input method, not like an asynchronous task that later drags the user back to an app remembered at record start. Inspected Type4Me's implemented current-focus design in `docs/features/current-focus-injection/product-design.md`, `RecognitionSession.swift` and `TextInjectionEngine.swift` on current `main`.

- **ADAPT:** resolve the external frontmost application only when final text is ready, never activate/switch back to the record-start app, and let the target application's normal first-responder path route one standard `Cmd+V`.
- **ADAPT:** treat successful paste-event dispatch as delivery. Accessibility can support bounded post-insertion learning, but it must not block ordinary input merely because an editor exposes an incomplete AX tree.
- **ADAPT:** keep change-count-aware clipboard restoration and clipboard fallback when there is no external target.
- **DROP:** original-app/window pinning, window-existence checks, focus-handoff sleeps, AX editability proof, app-specific target recovery and Type4Me's automation/headless dual target machinery. Morie currently has only ordinary interactive delivery plus capture-only History.
- **VERIFY:** switching apps/fields while Speech or Foundation Models is still processing, custom-rendered editors, terminals, selected-text replacement, clipboard managers and rapid repeated captures on the signed macOS 27 app.

Morie removes its superseded original-window persistence directly. Development data compatibility is not a product requirement at this stage; no compatibility adapter is retained.


## M-017 false-start cleanup follow-up — 2026-09-19

Rechecked Type4Me's current Voice Polish prompt in `Type4Me/UI/AppState.swift`. One useful current rule is to treat a clear mid-sentence restart as self-correction and delete an abandoned fragment, while its broader formatting/number rules remain intentionally more aggressive than Morie.

- **ADAPT:** clear abandoned fragments and sentence restarts can be removed when the later clause fully replaces the same thought.
- **ADAPT:** preserve intentional repetition and keep both clauses when they contain independent information or the replacement relationship is uncertain.
- **DROP:** mandatory Arabic-number conversion, forced total-summary formatting, generated titles/subitems, transition insertion and count rewriting.
- **ADAPT:** avoid defining cleanup as Chinese-only; Morie keeps the same restrained contract for Chinese, English and mixed-language dictation.
- **VERIFY:** real Foundation Models behavior on natural false starts such as partial clause → restart, versus two independent clauses that merely share words.


## M-018 Expression Profile audit — 2026-09-19

Rechecked Type4Me current `ExpressionProfileStore.swift` and `UserEditObservation.swift` on `main`.

Useful lessons for Morie:

- **ADAPT:** Expression Profile is a separate aggregate from semantic Memory. Style features should never be stored as personal facts.
- **ADAPT:** actual edits to recently inserted text are stronger evidence than inferring style from model output.
- **ADAPT:** use explicit `insufficient → learning → stable` states and require repeated multi-day evidence before style changes future output.
- **ADAPT:** sentence length, line breaks, list usage, terminal punctuation, exclamation and Chinese/English spacing are low-risk style dimensions.
- **ADAPT:** offer an explicit reset control.
- **DROP:** Type4Me's global/category/application scope hierarchy for the first Morie slice, accepted-unchanged weak evidence, JSON profile files, rebuild-from-history machinery, schema migration/decay compatibility code and broad runtime-specific sensitivity infrastructure.
- **MORIE-SPECIFIC:** only style-only edits with unchanged lexical content are admitted. Raw edited text is not persisted as Expression Profile data. Stable directives are capped and cannot override the current utterance.

The bounded post-insertion observer is shared with dictionary suggestions so Morie does not run two AX polling loops against the same insertion.
