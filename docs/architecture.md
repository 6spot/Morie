# Architecture

## Current stage

Morie is in **Phase 0 — macOS Input Foundation**. The architecture is intentionally narrow: establish a reliable Apple-native input loop before persistence, Memory, iOS, or cloud complexity is introduced.

Type4Me is an experience/reference archive, not Morie's architecture or migration template. Every retained lesson is filtered through Morie's product design and the macOS 27-only platform boundary.

## Architectural principles

- macOS First
- Latest Apple Only
- Apple Native First
- Native UI Only
- Morie Architecture First
- Reuse Proven Lessons, Not Compatibility Baggage
- Capture First
- Expression First
- Private by Design
- Minimal Dependencies
- Progressive Intelligence

See [`product-architecture-baseline.md`](./product-architecture-baseline.md), [`ui-design.md`](./ui-design.md), and [`reference/type4me.md`](./reference/type4me.md).

## Native UI architecture

Morie does not own a custom component system.

```text
macOS 27 system design
        ↓
SwiftUI system components
        ↓ when SwiftUI cannot expose required native behavior
AppKit system components
        ↓ only for genuinely custom surfaces with no system control
Apple-provided Liquid Glass APIs
```

There is no third-party design-system or homemade-glass fallback. If the Apple-native stack cannot meet a requirement, implementation stops until the project owner explicitly approves an exception.

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
├── .github/workflows/
│   └── macos-27-build.yml
└── docs/
    ├── architecture.md
    ├── development.md
    ├── deployment.md
    ├── product-architecture-baseline.md
    ├── ui-design.md
    ├── validation.md
    ├── tasks.md
    ├── design/
    ├── reference/
    └── tasks/
```

Do not extract shared packages merely to match a future diagram. New modules need real ownership/reuse pressure first.

## Phase 0 runtime flow

```text
bootstrap
  ↓
capability checks
  ↓
prepare required Apple Speech assets
  ↓
install minimal global push-to-talk event tap
  ↓
Ready

Control+Space press
  ↓
create authoritative capture UUID
  ↓
capture original target application
  ↓
start Apple capture + Speech session for that UUID
  ↓
progressive / volatile transcript
  ↓
Control+Space release
  ↓
stop capture input
  ↓
finish Speech analysis for consumed audio
  ↓
final transcript
  ↓
restore original target
  ↓
AX text delivery
  ↓ fallback
safe synthetic Cmd+V using temporary clipboard value
  ↓
restore clipboard only if user did not change it
  ↓
clear session identity and return Ready
```

If release occurs while asynchronous Speech setup is still in flight, that setup is cancelled. A late setup completion must never create an orphaned recording after the user's hold has ended.

## Phase 0 state ownership

Two levels of state are intentional.

### Visible application state

`AppController` owns the small UI-facing state machine:

`checking → ready → recording → delivering → ready`

`failed` and `blocked` represent recoverable operation failure and unavailable required capability respectively.

### Capture identity

A UUID is created for every intentional hold. It is the authority for setup, transcript callbacks, stop/cancel, and cleanup.

This identity exists because UI state alone is not sufficient to protect against asynchronous setup/results arriving after a newer user interaction. Stale callbacks are ignored rather than being allowed to mutate the next session.

Morie does not introduce a generalized multi-provider session framework to solve this.

## Current component responsibilities

### `MorieApp`

Thin native menu-bar application shell. It owns presentation composition only and uses Apple system components.

### `AppController`

Owns Phase 0 orchestration:

- bootstrap/capability flow;
- Speech asset preparation before Ready;
- hotkey installation;
- authoritative capture UUID;
- original target-app capture;
- start/release coordination;
- delivery transition;
- terminal success/cancel/failure cleanup.

It specifically prevents release-during-setup from becoming a late recording session.

### `CapabilityGate`

Checks the capabilities currently owned by Phase 0:

- `SystemLanguageModel` availability and locale;
- modern Speech availability and locale;
- Microphone permission;
- Speech authorization;
- Accessibility trust.

ApplicationServices is imported through a Swift `@preconcurrency` boundary because its native C accessibility option-key global is not annotated for Swift 6 concurrency. This is an Apple-framework interop boundary, not a replacement dependency.

CloudKit/iCloud gating belongs to M-003 where a real container and entitlements exist. Phase 0 therefore describes readiness as device/capability readiness, not full Private Mode readiness.

### `PushToTalkHotkey`

A **minimal macOS 27 push-to-talk subsystem**, not a Type4Me-style generalized hotkey manager.

Current behavior:

- session-level `CGEventTap`;
- current V0 binding `Control + Space`;
- exact modifier matching;
- autorepeat suppression;
- explicit one-hold ownership;
- release terminates the active hold even if Control is released first;
- matched shortcut events are consumed;
- Morie-generated synthetic input is excluded;
- disabled event tap is re-enabled when native permission is still valid;
- Accessibility loss blocks the input path.

Not present by design:

- media keys;
- mouse buttons;
- multiple binding/mode routing;
- modifier-prefix gestures;
- old macOS compatibility machinery.

The default shortcut itself remains a runtime-validation decision because `Control + Space` may conflict with some input-source configurations.

### `SpeechPipeline`

An actor owns the Apple-native speech session state:

- unique active capture UUID;
- `SpeechTranscriber` with progressive transcription;
- `AssetInventory` preparation;
- `CaptureInputSequenceProvider`;
- `SpeechAnalyzer`;
- final + volatile transcript accumulation;
- normal finalization versus cancellation;
- stale-session rejection;
- resource cleanup.

Speech assets are prepared before Ready so a model download is not started inside an active push-to-talk hold.

Normal release stops capture and lets already-captured analyzer input finish before finalization. Cancellation instead terminates analysis immediately. The most recent volatile segment is preserved because the current Speech result contract does not guarantee that each volatile result will later be emitted again as final.

There is no legacy recognition fallback and no provider abstraction.

### `TextInjector`

Delivery is intentionally generic and macOS 27 evidence-driven:

- rejects missing/terminated/self target;
- preserves undelivered transcript on clipboard;
- restores the original app;
- performs bounded AX selected-text insertion first;
- falls back to synthetic Cmd+V;
- tags synthetic key events so Morie's own hotkey path ignores them;
- snapshots only safe text-like clipboard representations;
- restores the previous clipboard only when `changeCount` proves no newer user/app clipboard write occurred.

There is no Electron-specific or per-app compatibility branch. Such behavior can be added only after reproduction on macOS 27 and recording the evidence in the active task.

## Type4Me extraction boundary

Reference repository: `joewongjc/type4me`.

Phase 0 reviewed the relevant hotkey/session/audio/injection/Speech behavior, but Morie retains behavior rather than Type4Me's architecture.

### ADAPT

- hold/release ownership and repeat suppression;
- session-level event handling reliability lessons;
- one authoritative session identity;
- stale async result rejection;
- deterministic terminal cleanup;
- no-loss delivery behavior;
- synthetic-event identity;
- change-count-aware clipboard restoration.

### DROP

- old macOS compatibility;
- legacy Speech paths;
- media/mouse/generalized hotkey features;
- multi-provider ASR/LLM architecture;
- Python/MLX/sherpa/SenseVoice and alternate runtime machinery;
- compatibility code for unsupported machines.

### VERIFY

- device/audio-route workarounds;
- per-app focus/paste timing;
- app-family-specific injection behavior;
- any additional current-platform compatibility branch.

The rule for VERIFY work is:

`reproduce on macOS 27 → document in active task → implement smallest native fix`

## Compile-validation boundary

`.github/workflows/macos-27-build.yml` compiles product changes on GitHub's hosted macOS 27 / Xcode 27 image with signing disabled.

This protects the repository from drifting away from the actual macOS 27 SDK/Swift 6 compiler and has already caught a strict-concurrency issue in the native Accessibility bridge.

CI compilation does **not** validate:

- TCC/permission prompts;
- microphone routing;
- physical keyboard event behavior;
- Apple Intelligence/Speech asset runtime availability;
- real focus restoration;
- target-app injection;
- Liquid Glass visual behavior;
- latency/energy use.

Those remain real-device acceptance work.

## Future package direction

As Phase 1+ introduces genuinely reusable logic, a likely direction is:

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
├── Persistence/
│   ├── LocalStore
│   └── CloudKit
└── SharedUI/   # only shared compositions of native Apple UI

macOSApp/
├── GlobalHotkey
├── AudioSpeech
├── Accessibility
├── AppContext
├── FocusRestore
├── TextInjection
└── MenuBar
```

This is direction, not an instruction to create empty abstractions. `SharedUI` must never become a custom design system replacing Apple controls.

## Data architecture direction

The central durable object will be `Capture`, not `Voice`.

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

Voice is an input source, not the core domain object.

## Persistence boundary

M-003 introduces the reliability boundary:

1. intentional Capture is durably saved;
2. only then may AI correction/classification/Memory extraction run;
3. enriched/final state updates the saved Capture;
4. failures never delete the original intentional capture.

Private Mode long-term persistence/sync uses iCloud/CloudKit. Morie does not provide Device Only mode.

## External dependency boundary

There is no architecture layer called “third-party fallback”.

If Apple-native capabilities cannot satisfy a concrete requirement, document the gap and request explicit owner approval. Existing use of a dependency in Type4Me is not permission to introduce it in Morie.

## Boundary against future Cloud

A future Morie Cloud may use Rust and expose APIs/MCP, but the Apple client remains Swift-native. Client and server may share protocol/data semantics, not runtime implementation.

Do not add server-oriented architecture to the client before the Private product loop is validated.
