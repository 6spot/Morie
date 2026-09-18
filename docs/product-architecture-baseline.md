# Product & Architecture Baseline

Version: V0 Baseline v2  
Date: 2026-09-17

This is the repository-native summary of the approved Morie product baseline. The complete repository transcription of the approved source design is in [`design/apple-native-first-v0-baseline-v2.md`](./design/apple-native-first-v0-baseline-v2.md).

## Product definition

Morie is an Apple-native voice input and intentional capture product that gradually builds Personal Memory from the user's own captures and uses that context to improve future recognition, correction, understanding, and expression.

## V0 hard constraints

1. **macOS First** — finish the macOS end-to-end loop before iOS development.
2. **Latest Apple Only** — target the latest Apple platform capabilities and Apple Intelligence-capable Macs; do not create compatibility layers for old Macs or old APIs.
3. **Private Mode only in V0** — no Morie-hosted cloud backend in V0.
4. **Private Mode = Apple Native + iCloud** — there is no Device Only product mode.
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

Normal keyboard input is not monitored and Morie is not a global keylogger.

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
- iCloud / CloudKit once Capture persistence ships

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

## Phase plan

### Phase 0 — Input Foundation

Validate the core daily input loop:

`press → speak → press again → transcript → restore focus → inject text`

Toggle capture is the approved V0 interaction: releasing the shortcut does not stop recording, a second press finishes, and `Escape` cancels an active recording. The non-activating capture HUD exposes the same cancel/finish actions without stealing focus.

Scope includes:

- Type4Me reference audit and selective migration of proven input behavior;
- audio/session lifecycle;
- global shortcut;
- modern Speech APIs;
- capability gate;
- target-app capture;
- focus restoration;
- Accessibility/text-injection delivery;
- clipboard fallback;
- native macOS 27 UI / Liquid Glass behavior;
- compatibility testing;
- performance baseline.

### Phase 1 — Capture

Add Capture-first persistence:

- durable Capture model/store;
- History;
- App Context persistence;
- iCloud/CloudKit sync;
- iCloud capability gate.

Raw intentional Capture must be durable before optional AI enrichment.

### Phase 2 — Memory

Start with restrained high-value context rather than a knowledge graph:

- Vocabulary;
- Project;
- Relevant Context retrieval;
- data-model support for Person, Topic, Decision, Preference, Fact, Open Thread, and Writing Style.

Memory must retain provenance and lifecycle information such as source captures, confidence, confirmation state, timestamps, and active/superseded/archived status.

### Phase 3 — Personalization

Use relevant historical context to improve current input:

- context-aware correction;
- terminology recovery;
- style-aware rewrite;
- learning from user corrections.

The goal is increasingly user-like output, not generic AI prose.

### Phase 4 — iOS

iPhone becomes an instant Capture surface after the macOS loop works:

- Action Button;
- AppIntent;
- voice/text Capture;
- shared iCloud data semantics.

Do not copy the entire macOS UI to iPhone.

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
