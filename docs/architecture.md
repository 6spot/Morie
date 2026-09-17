# Architecture

## Current stage

Morie is in **Phase 0 — macOS Input Foundation**. The architecture is intentionally narrow: establish a reliable Apple-native input loop before persistence, Memory, iOS, or cloud complexity is introduced.

## Architectural principles

- macOS First
- Latest Apple Only
- Apple Native First
- Capture First
- Expression First
- Private by Design
- Minimal Dependencies
- Progressive Intelligence

See [`product-architecture-baseline.md`](./product-architecture-baseline.md) for the product-level constraints.

## Current repository shape

```text
Morie/
├── AGENTS.md
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
    ├── tasks.md
    ├── validation.md
    └── tasks/
```

This is not the final package layout. Shared Swift Packages should only be extracted once there is real shared business logic to justify them.

## Phase 0 runtime flow

```text
Global shortcut press
        ↓
Capture original frontmost app
        ↓
Start audio capture
        ↓
SpeechAnalyzer / SpeechTranscriber
        ↓
Partial transcript
        ↓
Global shortcut release
        ↓
Finalize Speech analysis
        ↓
Final transcript
        ↓
Restore original app focus
        ↓
AX selected-text insertion
        ↓ fallback
Clipboard + Cmd+V
```

## Component responsibilities

### `MorieApp`

Application shell and menu-bar UI. It should remain thin and should not own capture/business logic.

### `AppController`

Phase 0 orchestration and visible application state. The initial state machine is intentionally explicit rather than abstracted:

`checking → ready → recording → delivering → ready`

Error/blocked paths remain recoverable and user-visible.

### `CapabilityGate`

Checks whether the current machine can enter the currently implemented portion of Private Mode.

Phase 0 checks currently cover:

- `SystemLanguageModel` availability;
- model locale support;
- modern Speech API availability/locale;
- microphone permission;
- Speech authorization;
- Accessibility trust.

CloudKit/iCloud gating belongs with Phase 1, because it should be implemented against a real container and entitlements rather than a placeholder check.

### `PushToTalkHotkey`

Owns global/local keyboard monitoring and converts shortcut press/release into intentional capture events. It must not become a general keyboard listener or capture ordinary user typing.

### `SpeechPipeline`

Owns the current Apple-native speech path:

- microphone capture;
- `SpeechTranscriber`;
- `SpeechAnalyzer`;
- required Speech assets;
- partial/final result accumulation;
- capture lifecycle cleanup.

There is no legacy recognition fallback.

### `TextInjector`

Owns delivery back to the app that was frontmost before recording:

1. reactivate the original app;
2. attempt focused-element Accessibility insertion;
3. use clipboard + Cmd+V fallback if direct AX insertion is unsupported;
4. restore previous representable clipboard content.

Application-specific differences are validated through the compatibility matrix rather than hidden behind premature provider abstractions.

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
└── SharedUI/

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

## Boundary against future Cloud

A future Morie Cloud may use Rust and expose APIs/MCP, but the Apple client remains Swift-native. Client and server may share protocol/data semantics, not runtime implementation.

Do not add server-oriented architecture to the client before the Private product loop is validated.