# Product & Architecture Baseline

Version: V0 Baseline v2  
Date: 2026-09-17; owner amendments: 2026-09-18

This is the repository-native summary of the approved Morie product baseline. The complete repository transcription of the approved source design is in [`design/apple-native-first-v0-baseline-v2.md`](./design/apple-native-first-v0-baseline-v2.md).

## Product definition

Morie is an Apple-native voice input and intentional capture product that gradually builds Personal Memory from the user's own captures and uses that context to improve future recognition, correction, understanding, and expression.

## V0 hard constraints

1. **macOS First** — finish the macOS end-to-end loop before iOS development.
2. **Latest Apple Only** — target the latest Apple platform capabilities and Apple Intelligence-capable Macs; do not create compatibility layers for old Macs or old APIs.
3. **Private Mode only in V0** — no Morie-hosted cloud backend in V0.
4. **Private Mode = Apple Native + eventual iCloud sync** — there is no separate Device Only product mode. Finish the single-Mac loop first; sync is outside the current milestone.
5. **Apple Native First** — Apple system frameworks are the required default implementation path.
6. **Native UI Only** — all product UI must use Apple system components and the current macOS 27 Liquid Glass design language. Morie does not introduce a parallel/custom UI system.
7. **No unapproved external dependencies** — if Apple-native capabilities cannot meet a requirement, implementation stops until the project owner explicitly approves an exception.
8. **Reuse proven input infrastructure** — Phase 0 is not a from-scratch voice-input rewrite. Type4Me is the reference implementation for mature recording/session/hotkey/focus/injection/Apple Speech behavior; Morie selectively reuses/adapts that behavior while discarding legacy/provider/runtime complexity.
9. **Development stage, no legacy contract** — implement the current design directly; no old-schema migration, legacy data reconstruction, version routing or speculative compatibility layer. Preserve current-version Capture-first and crash-recovery guarantees.

## Native UI boundary

Morie's UI principle is stronger than “looks native”:

> Use Apple system UI itself.

For macOS 27:

- use standard SwiftUI/AppKit windows, menus, controls, sheets, popovers, toolbars, sidebars, navigation, lists and settings surfaces;
- allow standard controls to adopt the current Liquid Glass appearance and behavior from the system;
- use Apple's Liquid Glass APIs only when a genuinely custom surface is necessary and there is no standard system component;
- do not hand-build visual imitations of Liquid Glass;
- do not introduce third-party UI libraries or replacement component systems.

If system UI cannot satisfy a product requirement, the gap must be documented and the owner must explicitly approve any exception before implementation.

See [`ui-design.md`](./ui-design.md).

## External dependency approval boundary

No external package/runtime/model/SDK/binary/UI framework/network service is introduced merely because it is convenient or faster.

Before any exception can be considered, document:

1. the requirement the Apple-native path cannot satisfy;
2. Apple-native alternatives already evaluated;
3. measurable product/technical benefit;
4. binary size, startup, memory, CPU/energy, privacy, signing and packaging impact;
5. runtime/model/network/security maintenance burden;
6. removal path if Apple later provides the capability.

Explicit project-owner approval is required before implementation. For Phase 0, the expected third-party dependency count is **zero**.

## Core loop

`Capture → Understand → Remember → Personalize → Express Better → Capture`

Two intentional Capture modes are planned:

- `currentApp`: transcribe, deliver to the current app, and retain the intentional capture.
- `captureOnly`: record an idea without injecting it into another app.

Normal keyboard input is not monitored. The independent, default-off correction suggestion feature uses bounded Accessibility reads of a verified recent Morie insertion, only while the same text field remains focused. It does not record keystrokes or analyze whole documents. Saving a suggested word requires explicit confirmation and creates a dictionary spelling, not personal Memory or an automatic replacement alias.

## V0 platform boundary

Active implementation scope is macOS only.

Current platform baseline:

- macOS 27+
- Apple Intelligence-capable Mac
- latest stable Xcode / Swift supported by the platform baseline
- Foundation Models / `SystemLanguageModel`
- modern Speech APIs
- native SwiftUI + AppKit
- native Liquid Glass/system control behavior
- AVFoundation
- NaturalLanguage
- Accessibility / AppKit / NSPasteboard for macOS delivery
- iCloud / CloudKit in a later scheduled cross-device milestone, after the single-Mac loop is validated

Unsupported required capabilities block Private Mode. V0 does not add a cloud fallback.

## Type4Me role

Reference repository: `joewongjc/type4me`.

Type4Me is a **Reference Implementation**, not the Morie product architecture.

Morie should first inspect and selectively migrate/rewrite the mature behavior already proven in Type4Me for:

- audio capture and recording-session lifecycle;
- global hotkey state handling;
- frontmost app / target handling;
- focus restore;
- text injection and clipboard fallback;
- Apple Speech behavior;
- permission/signing/packaging edge cases;
- hotword/vocabulary and correction-learning logic when later phases need them;
- Swift Concurrency and error-recovery lessons.

Morie does **not** inherit by default:

- multi-provider ASR architecture;
- multi-provider LLM architecture/settings;
- SenseVoice / sherpa-onnx;
- Qwen3 ASR server / Python / MLX runtime;
- Silero VAD when Apple capabilities suffice;
- CppJieba when NaturalLanguage suffices;
- provider pricing/subscription/build-variant complexity;
- old compatibility/runtime layers.

The migration rule is: **reuse proven behavior, not historical complexity**.

See [`reference/type4me.md`](./reference/type4me.md).

## Delivery order — owner amendment, 2026-09-18

Historical phase numbers identify task areas, not a dependency chain that puts sync before useful local input. The current milestone is [M-009](tasks/M-009-macos-input-memory.md):

1. Reliable macOS recording, durable recognition, final-text save and insertion (M-002/M-003).
2. Independent basic cleanup and a user-maintained dictionary, useful with no personal Memory (M-005/M-009).
3. Periodic idle analysis of completed current-app input into selective personal Memory; future input uses relevant context without adding unspoken information (M-004/M-009).
4. Consistent native management for History, Dictionary, Personal Memory, Settings and Diagnostics (M-008/M-009).
5. Complete device/model/latency and daily-use acceptance. Device checks are deferred, not waived.
6. Only then schedule actual multi-device needs, iOS/mobile inspiration and iCloud/CloudKit sync. Apple Developer enrollment and container configuration are not current blockers or current acceptance criteria.

### Input and Capture foundations

Toggle capture uses a solo shortcut activation to start and the next to finish; Escape cancels. The nonactivating HUD exposes the same finish/cancel actions. Speech uses the modern Apple stack, and generic focus restore/clipboard paste delivers the saved final text.

Persist the Capture and audio destination before recording; checkpoint recognition; save complete recognized text before enrichment. Preserve source audio, final text and recovery metadata through operational failures. Existing `captureOnly` persistence remains, without expanding inspiration recording or follow-up on Mac.

### Independent cleanup and dictionary

Follow [the approved cleanup contract](input-cleanup.md): preserve meaning, tone, terminology, uncertainty and meaningful short replies; remove meaningless fillers and pause redundancy; fix clear self-corrections; add punctuation, paragraphs and lists only for structure already expressed. Do not summarize, expand, translate, answer or execute the input.

Dictionary entries are user-maintained spellings/names/technical terms. Native Speech context uses spelling hints. Only explicit aliases establish deterministic replacements; case/width variants can normalize to the saved spelling. Dictionary corrections remain available if optional AI cleanup is off, busy or fails. Manually correcting recently inserted text can offer an opt-in native confirmation to save its spelling; this never silently makes a common word a global alias.

### Automatic personal Memory

Memory records personal projects, relationships, stable preferences, facts and decisions from daily communication. Routine input must not create a mandatory candidate-review workflow. Saved final text is the analysis source; retain the exact snapshot and source Capture IDs, origin, confidence, evidence date and active/superseded/archived lifecycle.

Use idle batches and durable retry, yielding to new voice input. Admit grounded personal information conservatively, accumulate weaker recurring evidence across distinct inputs, merge repeats and supersede explicit later changes. Quotes, hypothetical/temporary/uncertain statements and unsupported inferences must not be asserted as personal facts. Users may inspect, edit, archive or delete Memory; user changes take priority over automation.

Basic cleanup does not depend on Memory. Retrieved personal context helps interpret this input; it cannot insert background the user did not express or override the user's current view/style. Model estimates and deterministic checks are not evidence of semantic accuracy; evaluate actual outputs on supported hardware.

### iOS, inspiration and cross-device sync — unscheduled

Inspiration recording, follow-up questions and user-led completion belong primarily to the future phone experience. iPhone may later offer Action Button/AppIntent voice/text Capture after the Mac loop works. Do not clone the macOS management UI or start mobile work automatically.

CloudKit synchronizes the user's Capture/Memory across devices using that user's own iCloud private database. The developer provisions the app capability/container once; users do not need developer accounts. Morie does not operate a shared V0 data service. Schedule provisioning and sync semantics when there is a real cross-device milestone, not simply because local persistence exists.

### Later — Optional Morie Cloud

Only after the Private product loop is validated:

- Rust server;
- cloud Memory/retrieval;
- API/MCP/relay;
- optional Cloud mode.

Do not introduce Rust or server-oriented runtime abstractions into the Apple client in anticipation of future cloud work.

## Capture-first reliability rule

Once persistence exists:

> Save the intentional Capture first. AI classification, rewriting, Memory extraction, or retrieval failure must never cause the original Capture to be lost.

## Memory quality rule

Journal may be comprehensive; long-term Memory must be selective. Morie should become more useful with usage, not accumulate indiscriminate context.

## Success criteria

V0 exists to answer three questions:

1. Is Morie stable, fast, and natural enough to become a daily macOS voice-input tool?
2. Do users naturally accumulate meaningful Personal Context through intentional voice/text capture?
3. Does that context measurably improve recognition and expression over time?

Platform expansion comes after these questions are validated.
