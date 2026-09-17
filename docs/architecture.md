# Architecture

## Current stage

Morie is in **Phase 0 — macOS Input Foundation**. The architecture is intentionally narrow: establish a reliable Apple-native input loop before persistence, Memory, iOS, or cloud complexity is introduced.

Phase 0 is not a greenfield rewrite. Type4Me is the reference implementation for already-proven input infrastructure; Morie selectively adapts those lessons to the macOS 27 / latest-Apple-only architecture.

## Architectural principles

- macOS First
- Latest Apple Only
- Apple Native First
- Native UI Only
- Proven Input Reuse
- Capture First
- Expression First
- Private by Design
- Minimal Dependencies
- Progressive Intelligence

See [`product-architecture-baseline.md`](./product-architecture-baseline.md) for the product-level constraints, [`ui-design.md`](./ui-design.md) for the native UI approval gate, and [`reference/type4me.md`](./reference/type4me.md) for the input-foundation migration boundary.

## Native UI architecture

Morie does not own a custom component system.

The presentation stack is:

```text
macOS 27 system design
        ↓
SwiftUI system components
        ↓ when SwiftUI cannot expose required native behavior
AppKit system components
        ↓ only for genuinely custom surfaces with no system control
Apple Liquid Glass APIs
```

There is no automatic next layer containing a third-party design system or homemade glass renderer. If the Apple-native stack cannot meet a requirement, implementation stops until the project owner explicitly approves an exception.

Standard macOS 27 controls should adopt current Liquid Glass behavior from the system. Do not add decorative custom glass on top of surfaces whose material/interaction is already owned by macOS.

## Current repository shape

```text
Morie/
├── AGENTS.md
├── CONTRIBUTING.md
├── README.md
├── Morie.xcodeproj/
├── Morie/
│   ├── MorieApp.swift
│   ├── AppController.swift
│   ├── CapabilityGate.swift
│   ├── PushToTalkHotkey.swift
│   ├── SpeechPipeline.swift
│   └── TextInjector.swift
└── docs/
    ├── README.md
    ├── architecture.md
    ├── development.md
    ├── deployment.md
    ├── product-architecture-baseline.md
    ├── ui-design.md
    ├── validation.md
    ├── tasks.md
    ├── design/
    │   └── apple-native-first-v0-baseline-v2.md
    ├── reference/
    │   └── type4me.md
    └── tasks/
```

This is not the final package layout. Shared Swift Packages should only be extracted once there is real shared business logic to justify them.

## Phase 0 runtime flow

Target flow:

```text
Global shortcut press
        ↓
Capture original target context
        ↓
Start authoritative recording session
        ↓
Apple audio capture
        ↓
SpeechAnalyzer / SpeechTranscriber
        ↓
Partial / volatile transcript
        ↓
Global shortcut release
        ↓
Finalize Speech analysis
        ↓
Final transcript
        ↓
Restore original target/focus
        ↓
Reliable text delivery
        ↓ fallback
Safe clipboard copy/paste path
        ↓
Return to Ready with resources released
```

Type4Me's existing session/hotkey/injection behavior is reviewed before this flow is treated as production-ready.

## Type4Me migration boundary

Reference repository: `joewongjc/type4me`.

Priority reference components:

- `Type4Me/Input/HotkeyManager.swift`
- `Type4MeTests/HotkeyStateMachineTests.swift`
- `Type4Me/Audio/AudioCaptureEngine.swift`
- `Type4Me/Session/RecognitionSession.swift`
- `Type4MeTests/RecognitionSessionTests.swift`
- `Type4Me/Injection/TextInjectionEngine.swift`
- Apple Speech code under `Type4Me/ASR/`
- permission/onboarding implementation and related design/review notes

Morie keeps the behavioral lessons but drops Type4Me's multi-provider/cloud/local-runtime architecture unless a later requirement is separately approved.

See [`reference/type4me.md`](./reference/type4me.md).

## Current component responsibilities

### `MorieApp`

Application shell and menu-bar UI. It should remain thin and should not own capture/business logic.

All visible UI is native macOS 27 UI. `MenuBarExtra` is a system component; later recording/status/permission surfaces must follow the same rule.

### `AppController`

Phase 0 high-level orchestration and visible application state.

Current high-level state:

`checking → ready → recording → delivering → ready`

This is not sufficient by itself to solve all recording-generation/stale-event cases. Those details are being reconciled with Type4Me `RecognitionSession` behavior rather than hidden inside UI state.

### `CapabilityGate`

Checks whether the current machine can enter the currently implemented portion of Private Mode.

Phase 0 checks currently cover:

- `SystemLanguageModel` availability;
- model locale support;
- modern Speech API availability/locale;
- microphone permission;
- Speech authorization;
- Accessibility trust.

CloudKit/iCloud gating belongs with Phase 1 because it should be implemented against a real container and entitlements rather than a placeholder check.

### Hotkey subsystem

The current `PushToTalkHotkey` is an initial scaffold. The final Phase 0 hotkey path must adapt the relevant Type4Me state-machine behavior instead of assuming a pair of global NSEvent callbacks is sufficient.

Required concerns include:

- key repeat;
- modifier transitions;
- explicit hold state;
- stale timers/state;
- active recording ownership;
- abort/reset idempotency;
- synthetic input exclusion.

Morie V0 does not need Type4Me's entire multi-hotkey/media/mouse feature surface.

### Audio / recording session

The recording subsystem must have one authoritative session/generation owner and deterministic terminal cleanup.

Relevant Type4Me lessons include:

- permission/device error behavior;
- graph/resource release on stop;
- stale async result rejection;
- session generation identity;
- Bluetooth/device lifecycle edge cases;
- recoverability after failure.

Morie does not preserve PCM/provider-specific formats unless the latest Apple Speech path requires them.

### `SpeechPipeline`

Owns the current Apple-native speech path:

- current Apple capture/input API;
- `SpeechTranscriber`;
- `SpeechAnalyzer`;
- required Speech assets;
- partial/final result accumulation;
- finalization/cancellation;
- resource lifecycle.

There is no legacy recognition fallback. Type4Me's Apple Speech implementation is a behavioral reference, but Morie uses the current macOS 27 API surface.

### Target / focus / delivery

The current `TextInjector` is provisional until reconciled with Type4Me's mature delivery behavior.

The final subsystem must account for:

- original target validity and self-app exclusion;
- focus restoration;
- bounded Accessibility calls;
- safe no-target fallback;
- synthetic Cmd+V event marking;
- native/Electron paste timing differences;
- change-count-aware clipboard restoration;
- preservation of user content when direct delivery fails.

Application-specific differences are validated through the compatibility matrix rather than hidden behind provider abstractions.

## Future package direction

As Phase 1+ introduces real reusable logic, the intended workspace direction is:

```text
Packages/
├── PersonalCore/
│   ├── Capture
│   ├── Memory
│   ├── Project
│   ├── Person
│   ├── Vocabulary
│   └── Context
├── AppleIntelligence/
│   ├── FoundationModels
│   ├── NaturalLanguage
│   └── Personalization
├── Persistence/
│   ├── LocalStore
│   └── CloudKit
└── SharedUI/              # only shared compositions of native Apple UI

macOSApp/
├── GlobalHotkey
├── AudioSpeech
├── Accessibility
├── AppContext
├── FocusRestore
├── TextInjection
└── MenuBar

# iOSApp is added only in Phase 4.
```

Do not create these modules merely to match the diagram. Extract them when actual code ownership/shared behavior exists.

`SharedUI` must not become a custom design system that replaces native system controls.

## Data architecture direction

The central durable object will be `Capture`, not `Voice`.

Conceptually:

```text
Capture
├── identity / timestamps
├── type: voice | text
├── content: raw / recognized / final
├── source: app / bundle / optional context
├── delivery: currentApp | captureOnly
├── context: project / topic / people / entities
└── memory state: journal / candidate / memory
```

Voice is one input source. This preserves future support for intentional text capture and mobile entry points without redesigning the core model.

## Persistence boundary

Phase 1 introduces the reliability boundary:

1. intentional Capture is durably saved;
2. only then may AI correction/classification/Memory extraction run;
3. enriched/final state updates the saved Capture;
4. failures never delete or invalidate the raw capture.

Private Mode long-term persistence/sync uses iCloud/CloudKit. Morie does not provide Device Only mode.

## Memory direction

V0 does not build a general knowledge graph. Long-term Memory should be selective, provenance-aware, and capable of being superseded or archived.

Likely fields include:

- source Capture IDs;
- confidence;
- user-confirmed state;
- created/updated timestamps;
- active/superseded/archived status;
- supersession relationship.

## External dependency boundary

There is no architecture layer called “third-party fallback”.

If the Apple-native stack cannot meet a concrete requirement, document the gap and request explicit owner approval. Until approval is granted, architecture remains Apple-native and the missing requirement stays open.

Existing use of a dependency in Type4Me does not grant permission to introduce it in Morie.

## Boundary against future Cloud

A future Morie Cloud may use Rust and expose APIs/MCP, but the Apple client remains Swift-native. Client and server may share protocol/data semantics, not runtime implementation.

Do not add server-oriented architecture to the client before the Private product loop is validated.