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
│   ├── CaptureRecord.swift
│   ├── CaptureStore.swift
│   ├── CaptureHistoryView.swift
│   ├── CaptureHUD.swift
│   ├── Diagnostics.swift
│   ├── PushToTalkHotkey.swift
│   ├── SpeechPipeline.swift
│   └── TextInjector.swift
├── MorieTests/
│   └── CaptureStoreTests.swift
├── .github/workflows/
│   ├── macos-27-ci.yml
│   └── macos-27-package.yml
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
install minimal global toggle-capture event tap
  ↓
Ready

solo configured shortcut activation (Fn / Globe release by default)
  ↓
create authoritative capture UUID
  ↓
capture original target application
  ↓
start Apple capture + Speech session for that UUID
  ↓
progressive / volatile transcript
  ↓
second configured shortcut activation (or HUD confirm)
  ↓
stop capture input
  ↓
finish Speech analysis for consumed audio
  ↓
final transcript
  ↓
restore original target
  ↓
safe synthetic Cmd+V using temporary clipboard value
  ↓
restore clipboard only if user did not change it
  ↓
clear session identity and return Ready
```

Releasing the shortcut never finishes a toggle capture. If finish or cancel is requested while asynchronous Speech setup is still in flight, that request remains attached to the same capture UUID; late setup cannot create an orphaned recording.

## Phase 0 state ownership

Two levels of state are intentional.

### Visible application state

`AppController` owns the small UI-facing state machine:

`checking → ready → recording → delivering → ready`

`failed` and `blocked` represent recoverable operation failure and unavailable required capability respectively.

### Capture identity

A UUID is created for every intentional toggle capture. It is the authority for setup, transcript callbacks, finish/cancel, and cleanup.

This identity exists because UI state alone is not sufficient to protect against asynchronous setup/results arriving after a newer user interaction. Stale callbacks are ignored rather than being allowed to mutate the next session.

Morie does not introduce a generalized multi-provider session framework to solve this.

## Current component responsibilities

### `MorieApp`

Thin native menu-bar application shell. It owns presentation composition only and uses Apple system components. Its menu-bar item uses one stable product-entry symbol; capture and delivery state belong to the HUD and textual menu content rather than repeatedly changing the persistent system-bar icon.

### `AppController`

Owns Phase 0 orchestration:

- bootstrap/capability flow;
- Speech asset preparation before Ready;
- hotkey installation;
- authoritative capture UUID;
- original target-app capture;
- start/finish/cancel coordination;
- delivery transition;
- terminal success/cancel/failure cleanup.

It specifically prevents finish/cancel-during-setup from becoming a late or orphaned recording session.

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

A **minimal macOS 27 toggle-capture subsystem**, not a Type4Me-style generalized hotkey manager. The type name is retained temporarily to avoid unrelated churn during M-002.

Current behavior:

- session-level `CGEventTap`;
- persisted native shortcut selection, defaulting to solo `Fn / Globe` release;
- Fn chord rejection: any other key/modifier used while Fn is held cancels the solo candidate and passes the chord through;
- exact modifier matching;
- one action per physical press, with autorepeat suppressed;
- key release only resets press ownership and never changes capture state;
- first press starts, second press finishes, and `Escape` cancels only while recording;
- matched shortcut events are consumed;
- Morie-generated synthetic input is excluded;
- Accessibility trust is checked in the event path and loss immediately releases the tap while passing the current event through;
- a system-disabled or timed-out tap is released instead of automatically re-enabled, so a Morie failure cannot repeatedly block the system keyboard event chain;
- recovery after a timeout is explicit through capability recheck.

Not present by design:

- media keys;
- mouse buttons;
- multiple binding/mode routing;
- modifier-prefix gestures;
- old macOS compatibility machinery.

The owner-approved default is solo `Fn / Globe` release. Its interaction with the macOS Globe/Fn system action and external keyboards remains a real-device validation item; Settings provides alternate native keyboard combinations.

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

Speech assets are prepared before Ready so a model download is not started inside an active capture.

A finish action stops capture and lets already-captured analyzer input finish before finalization. Cancellation instead terminates analysis immediately. The most recent volatile segment is preserved because the current Speech result contract does not guarantee that each volatile result will later be emitted again as final.

There is no legacy recognition fallback and no provider abstraction.

### `TextInjector`

Delivery is intentionally generic and macOS 27 evidence-driven:

- rejects missing/terminated/self target;
- captures the original on-screen window identity and refuses delivery if that window closes before paste;
- preserves undelivered transcript on clipboard;
- restores the original app;
- snapshots the clipboard, writes the final transcript, and uses synthetic Cmd+V;
- tags synthetic key events so Morie's own hotkey path ignores them;
- snapshots only safe text-like clipboard representations;
- restores the previous clipboard only when `changeCount` proves no newer user/app clipboard write occurred.

There is no Electron-specific or per-app compatibility branch. Such behavior can be added only after reproduction on macOS 27 and recording the evidence in the active task.

### `CaptureHUD`

Owns a native, non-activating recording surface that does not replace the original target application:

- system `NSPanel` placement and focus behavior;
- one AppKit `NSGlassEffectView` that embeds the complete HUD content and samples behind the transparent panel;
- standard bordered system buttons inside that single glass surface;
- cancel / live microphone level / finish layout;
- processing, success, and failure feedback;
- inline delivery fallback feedback that states when the transcript was copied to the clipboard, without a focus-stealing modal alert;
- animated, labelled successful-input feedback instead of an isolated static status glyph;
- stationary level feedback when Reduce Motion is enabled;
- no custom glass imitation or third-party UI.

The microphone waveform is the only custom-drawn control because macOS does not provide a system live-audio waveform component. It renders a complete center-weighted envelope from the first frame—low at both edges and tallest in the middle—then smoothly changes the middle bars with actual microphone level. Its silence threshold and restrained gain curve retain the relevant proven behavior from Type4Me without importing Type4Me's scrolling-history presentation or UI system.

### `CaptureRecord` / `CaptureStore`

M-003 introduces the first durable product boundary using Apple SwiftData:

- the Phase 0 session UUID is also the Capture identity;
- an intentional voice Capture is saved before Speech startup;
- progressive recognition checkpoints update the same record with a bounded save cadence;
- final recognition, delivery success, clipboard-preserved delivery failure, and operational failure become explicit durable lifecycle states;
- explicit user cancellation discards the in-progress record;
- source application name, bundle identifier and original window identity are the current minimal App Context.

The local `ModelConfiguration` explicitly disables CloudKit until a real container and entitlements are configured. This is an implementation stage, not a Device Only product mode.

### `CaptureHistoryView`

Native SwiftUI/SwiftData History surface using system `Window`, `NavigationStack`, `List`, `ContentUnavailableView`, and `@Query`. It is intentionally a basic inspection surface while M-003 persistence semantics are validated.

### `MorieTests`

The first logic-only XCTest target compiles the Capture persistence sources directly so tests can run without launching the menu-bar app or entering its permission/capability lifecycle. It uses in-memory stores for lifecycle transitions and a unique temporary file URL for store-recreation coverage; it never opens the production Capture database.

## Type4Me extraction boundary

Reference repository: `joewongjc/type4me`.

Phase 0 reviewed the relevant hotkey/session/audio/injection/Speech behavior, but Morie retains behavior rather than Type4Me's architecture.

### ADAPT

- physical key-press ownership and repeat suppression;
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

`.github/workflows/macos-27-ci.yml` compiles product changes on GitHub's hosted macOS 27 / Xcode 27 image with signing disabled. `.github/workflows/macos-27-package.yml` produces the test artifact.

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
