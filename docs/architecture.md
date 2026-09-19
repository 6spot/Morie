# Architecture

## Current stage

[M-009](tasks/M-009-macos-input-memory.md) integrates a useful single-Mac input loop: durable recovery capture, a separate custom dictionary, independent cleanup, low-latency final output, ordered asynchronous History persistence, reliable insertion and automatic personal Memory during idle time. There is no required Memory candidate-review inbox. iOS, mobile inspiration/follow-up and cross-device sync are outside this milestone; interactive validation remains deferred, not waived.

Type4Me and the owner-supplied [OpenLess reference](reference/openless.md) supply bounded behavior lessons, not Morie's architecture or dependencies. Implement the current design directly without legacy schemas or compatibility adapters.

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

The app and tests remain single Xcode targets. Directories express ownership and navigation boundaries; they are not separate Swift modules or packages.

```text
Morie/
├── AGENTS.md
├── CONTRIBUTING.md
├── README.md
├── Morie.xcodeproj/
├── Morie/
│   ├── App/
│   │   ├── MorieApp.swift
│   │   ├── AppController.swift
│   │   └── MorieControlCenter.swift
│   ├── Features/
│   │   ├── Overview/
│   │   │   └── OverviewView.swift
│   │   ├── Capture/
│   │   │   ├── CaptureRecord.swift
│   │   │   ├── CaptureStore.swift
│   │   │   ├── CapturePersistenceWriter.swift
│   │   │   ├── CaptureAudioSource.swift
│   │   │   ├── CaptureAudioStream.swift
│   │   │   ├── CaptureFileTranscriber.swift
│   │   │   ├── SpeechPipeline.swift
│   │   │   ├── SpeechRecognitionBackend.swift
│   │   │   ├── CaptureRefinement.swift
│   │   │   ├── InputRefiner.swift
│   │   │   ├── CaptureHUD.swift
│   │   │   ├── CaptureSoundFeedback.swift
│   │   │   ├── CaptureSessionController.swift
│   │   │   └── History/
│   │   │       ├── CaptureHistoryController.swift
│   │   │       └── CaptureHistoryView.swift
│   │   ├── Memory/
│   │   │   ├── MemoryRecord.swift
│   │   │   ├── MemoryAnalysisRecord.swift
│   │   │   ├── MemoryStore.swift
│   │   │   ├── MemoryContextRetriever.swift
│   │   │   ├── MemoryLearner.swift
│   │   │   ├── MemoryLearningController.swift
│   │   │   ├── MemoryLearningView.swift
│   │   │   └── MemoryView.swift
│   │   ├── Dictionary/
│   │   │   ├── DictionaryStore.swift
│   │   │   ├── DictionaryCorrection.swift
│   │   │   └── DictionaryView.swift
│   │   ├── Personalization/
│   │   │   ├── CapturePersonalizer.swift
│   │   │   ├── ExpressionProfile.swift
│   │   │   └── PostInsertionLearningController.swift
│   │   └── Setup/
│   │       ├── PermissionSetupController.swift
│   │       └── MorieSetupView.swift
│   ├── Platform/
│   │   ├── Capabilities/CapabilityGate.swift
│   │   ├── Input/PushToTalkHotkey.swift
│   │   ├── TextDelivery/TextInjector.swift
│   │   └── Cloud/ICloudSyncSettings.swift
│   ├── Support/
│   │   └── Diagnostics.swift
│   ├── Resources/
│   │   └── zh-Hans.lproj/InfoPlist.strings
│   └── Morie.entitlements
├── MorieTests/
│   ├── Capture/
│   ├── Memory/
│   ├── Dictionary/
│   ├── Personalization/
│   ├── Setup/
│   └── Support/
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

The feature-first layout keeps files that change together near each other. `Platform/` owns macOS/Apple integration that is not itself a product feature, `Support/` holds cross-cutting diagnostics, and `App/` remains the composition/orchestration shell. Tests mirror the same feature boundaries. This is organizational only: target membership, runtime ownership and visibility do not change.

Do not extract shared packages merely to match a future diagram. New modules need real ownership/reuse pressure first.

## Current input runtime flow

\`\`\`text
bootstrap
  ↓
read-only capability/permission inspection
  ↓
first use or unmet requirement → native setup guide / explicit authorization
  ↓
all required checks pass + setup completion
  ↓
prepare required Apple Speech assets
  ↓
recheck requirements after asset preparation
  ↓
install minimal global toggle-capture event tap
  ↓
Ready

solo configured shortcut activation (Fn / Globe release by default)
  ↓
create authoritative capture UUID; cancel optional learning/word observation
  ↓
snapshot immutable per-Capture runtime context
(locale + Speech dictionary hints + cleanup/correction/expression/sound preferences)
  ↓
durably save the minimal Capture shell + audio destination
(the only required synchronous History write on the live-input path)
  ↓
start Apple capture + Speech with bounded dictionary hints
  ↓
play optional native start cue immediately when the start action is accepted
  ↓
progressive / volatile transcript
  ├─ update live Capture state immediately
  └─ enqueue bounded History checkpoints on CapturePersistenceWriter
  ↓
second configured shortcut activation (or HUD confirm)
  ↓
accepted finish action
  ├─ play optional finish cue immediately
  ↓
stop capture input and enter Thinking
  ↓
finish Speech analysis for consumed audio
  ↓
recognized text in live state
  ├─ enqueue recognized/audio snapshot
  ↓
confirmed user correction mappings
  ↓
canonical dictionary spelling + bounded optional AI cleanup
  ↓
final text + refinement provenance in live state
  ├─ enqueue final snapshot
  ↓
currentApp:
resolve the external app that currently owns keyboard focus
  ↓
safe synthetic Cmd+V using temporary clipboard value; macOS first-responder routing chooses the field
  ↓
restore clipboard only if user did not change it
  ↓
return Ready / success feedback without waiting for History I/O
  ├─ enqueue delivery outcome
  └─ after background flush, allow dependent Memory learning

captureOnly:
await the latest History snapshot
  ↓
release active ownership and report “已保存”
\`\`\`

The first Capture shell remains a synchronous durability boundary because it is the recovery anchor for an intentional expression. After that point, current-app recognition, cleanup and delivery use live in-memory state. History is eventually consistent through a dedicated writer; it is not allowed to add database latency to the normal finish-to-paste path.

Each queued snapshot carries a monotonically increasing per-Capture revision. The writer owns a separate SwiftData context and rejects stale revisions, so scheduling order cannot let an older progressive transcript overwrite a newer refined or delivered state. Explicit cancellation claims a higher tombstone revision before deletion I/O, preventing already-queued snapshots from resurrecting the Capture.

Releasing the shortcut never finishes a toggle capture. If finish or cancel is requested while asynchronous Speech setup is still in flight, that request remains attached to the same capture UUID; late setup cannot create an orphaned recording.

## Phase 0 state ownership

Two levels of state are intentional.

### Visible application state

`AppController` owns the small UI-facing state machine:

`checking → ready → recording → finalizing → refining → delivering → ready`

`captureOnly` retains its existing completion path after refinement without delivery or automatic personal learning. Refinement can be skipped or end with saved dictionary-corrected/original text; it does not change the required capability gate or introduce another product mode.

`failed` and `blocked` represent recoverable operation failure and unavailable required capability respectively.
Explicit cancellation uses `stopping` until native teardown and discard complete. Capability recheck enters `checking`, and shortcut loss enters `blocked`, before awaiting teardown; late capture work cannot replace these states with Ready.

### Capture identity

A UUID is created for every intentional toggle capture. It is the authority for setup, transcript callbacks, finish/cancel, and cleanup.

This identity exists because UI state alone is not sufficient to protect against asynchronous setup/results arriving after a newer user interaction. Stale callbacks are ignored rather than being allowed to mutate the next session.

Morie does not introduce a generalized multi-provider session framework to solve this.

## Current component responsibilities

### `MorieApp`

Thin native menu-bar shell with a system `.menu` MenuBarExtra, a management Window, a dedicated setup Window and the native Settings scene. SettingsLink entries in the sidebar/menu and Command-comma share that Settings scene. SidebarCommands supplies the system visibility command; no new global shortcut tap is added. The menu-bar symbol stays stable while textual status changes.

The primary bundle language and localized privacy descriptions are `zh-Hans`. App-owned UI/error/accessibility copy is Chinese; user input, dictionary spellings, prompts, technical log identifiers and persisted raw values remain unchanged. SwiftUI surfaces and formatted dates use a Chinese locale.

### `AppController`

Owns application-level orchestration and the UI-facing state surface:

- bootstrap/capability flow;
- global hotkey installation and shortcut preference changes;
- setup/permission gating;
- mapping live Capture phases into the existing visible state machine;
- top-level Settings/iCloud state;
- idle Memory learner startup outside an active capture;
- application-level failure presentation and scheduled audio maintenance.

It no longer owns the authoritative capture UUID/task bookkeeping, Speech lifecycle, HUD state or text delivery. Those belong to the Capture feature.

### `DictionaryStore` / confirmed corrections

The visible Dictionary continues to own **canonical words**, not a list of noisy ASR misspellings. Canonical user/system words are passed to Apple Speech as bounded contextual hints.

M-027 adds a separate internal `DictionaryCorrectionRule` model for user-confirmed observed-ASR → canonical-word relations. The normal Dictionary UI does not render these aliases.

Processing order is:

```text
Apple Speech + canonical hotwords
        ↓
raw transcript
        ↓
exact confirmed correction mappings
        ↓
canonical spelling normalization
        ↓
optional Foundation Models cleanup
```

Exact confirmed mappings are deterministic even when AI cleanup is disabled or unavailable. Latin/technical mappings use token boundaries; CJK mappings may replace an exact confirmed substring inside a longer phrase such as `总版页面 → 总览页面`. Code/URL/path/identifier protected ranges are excluded.

`RefinementInput` snapshots the bounded correction set together with dictionary/context provenance. If Dictionary or correction rules change during cleanup, the result is treated as stale rather than applying against a different knowledge snapshot.

`PostInsertionLearningController` still observes only the already-verified Morie insertion and still requires a stable bounded word-level user edit. Confirmation now saves the full relation (`Athers → Issues`) rather than discarding the observed wrong form after adding only `Issues`. Existing canonical words—including system built-ins—do not suppress learning. If the canonical word does not yet exist, the confirmation adds it as a user correction word first.

One normalized observed form owns one current canonical replacement. A later explicit confirmation may update it. Deleting a user canonical word removes internal mappings that target it. Morie does not ship a large hard-coded alias list copied from a different ASR engine.

Cleanup context is narrower than Speech hints. `speechHints()` still returns the full bounded canonical set because ASR needs candidates before the correct spelling appears. `relevantEntries(for:)` is intentionally transcript-scoped for Foundation Models: exact terms plus a small set of close Latin spelling neighbors, capped at 16. Confirmed correction rules are loaded only when the observed form exists, applied deterministically before cleanup and retained as provenance/staleness data; they are not serialized into the model prompt. This prevents historical correction vocabulary from becoming generation material.

### `CaptureSessionController`

Owns the authoritative live Capture lifecycle:

- capture UUID and source-audio destination;
- one immutable per-Capture runtime context containing delivery mode, locale, Speech dictionary hints and the cleanup/correction/expression/sound preferences accepted at Start;
- Speech asset preparation, start/finalization and live transcript state;
- enqueueing bounded persistence snapshots without awaiting them on the current-app delivery path;
- finish-during-Speech-startup coordination;
- explicit cancel and interruption shutdown;
- HUD recording/processing/success/failure state;
- dictionary hints, independent cleanup and low-latency final text;
- current-keyboard-focus delivery and bounded post-insertion observation;
- terminal success/failure cleanup and preservation of interrupted text/audio.

One shared shutdown task owns each interruption/discard. It cancels startup/finalization, closes native capture, preserves the latest text/audio, and awaits outstanding work before committing the disposition. User cancellation discards; shortcut failure, microphone interruption and Speech errors retain a failed Capture. A result that arrives during shutdown is saved without delivery; a paste already dispatched retains its actual delivery outcome.

`AppController` receives phase/transcript/failure callbacks and keeps the app/setup state machine authoritative. Returning a Capture session to idle only returns the visible app state to Ready when the current state is capture-owned; a concurrent blocked/checking state is not overwritten.

Settings remain mutable application preferences, but they are sampled only when a new Capture is accepted. The active Capture never rereads those preference properties during asynchronous Speech startup, finalization, cleanup or post-insertion observation. Dictionary Speech hints are likewise resolved once for that Capture. This keeps one interaction deterministic without introducing a generalized provider/session abstraction.

### \`CapturePersistenceWriter\`

Owns post-shell History persistence for live input:

- a SwiftData \`ModelContext\` separate from the main/live Capture context;
- full value snapshots rather than cross-actor model objects;
- monotonically increasing per-Capture revisions;
- stale-write rejection when async tasks arrive out of scheduling order;
- cancellation tombstones that block older queued snapshots even if deletion I/O fails;
- queue/write latency diagnostics.

\`CaptureStore\` keeps autosave disabled on its main context so mutating live Capture state cannot trigger an implicit disk write on the input actor. It performs the initial shell save explicitly, then snapshots live state and hands it to this writer.

For \`currentApp\`, persistence failure is diagnostic/recoverable and does not turn a successful paste into an input failure. For \`captureOnly\`, the session explicitly flushes the newest revision before reporting success because saving is the user's requested destination.

### `CapabilityGate` / `PermissionSetupController`

Inspects all mandatory requirements without authorization side effects:

- `SystemLanguageModel` availability and locale;
- modern Speech availability and locale;
- Microphone permission;
- Speech authorization;
- Accessibility trust.

Checks use the actual Chinese Speech locale, rather than the UI/system locale. Microphone and Speech requests occur only after an explicit setup action and only for undetermined TCC status. Denied access opens the corresponding System Settings pane. Accessibility registration and its native settings link also require an explicit action; restricted and unsupported states remain blocked.

`PermissionSetupController` owns immutable check snapshots, coalesces overlapping refreshes, serializes requests and rereads the current state before acting. Native-dialog activation cannot race a request's final inspection. Empty/partial snapshots cannot pass the gate. Its injected closures let logic tests exercise these transitions without touching TCC.

An explicit permission action remembers its originating Morie window. Native Microphone/Speech completion restores that window immediately. A jump to a Privacy pane uses a bounded 500 ms status wait owned only by that action; granting restores the originating window, returning without granting/cancellation/timeout ends the wait. Accessibility first calls the public prompting `AXIsProcessTrustedWithOptions` route so a newly signed Morie is registered, then opens the Accessibility pane from that same Morie action after a short handoff. The required macOS confirmation may still appear. No permission watcher runs while the app is idle.

Speech authorization's Objective-C callback has no main-queue guarantee. `CapabilityGate.requestSpeechAuthorization` uses an explicitly `@Sendable` completion that only resumes a checked continuation, so it does not inherit the gate's `MainActor` isolation. The awaiting setup flow returns to the main actor before inspecting permissions or updating UI state.

`MorieSetupView` refreshes on presentation and app activation. It uses a grouped Form with device/permission rows, status labels, native buttons and preparation feedback. The first launch shows setup even if permissions already exist; `setup.completed` is saved only after asset preparation and hotkey installation succeed. Every launch rechecks actual requirements. Missing requirements and preparation errors reopen the guide instead of stacking startup alerts. Completing setup is disabled during active input; refreshing never calls bootstrap, prepares models or resets a capture. Requirements are rechecked after potentially lengthy Speech preparation.

The setup Window uses the system `.hiddenTitleBar` style. Permission rows show an available authorization/settings action until authorized, then **已授权**, with no redundant ungranted label; restricted/unavailable states without an action retain their explanation. The native footer places **稍后设置** on the left and **重新检查 / 开始使用** on the right, retaining existing keyboard actions and request/preparation disabling.

ApplicationServices is imported through a Swift `@preconcurrency` boundary because its native C accessibility option-key global is not annotated for Swift 6 concurrency. This is an Apple-framework interop boundary, not a replacement dependency.

Optional CloudKit/iCloud sync/backup is separate from the local-input capability gate. The current capability gate has no iCloud account/container dependency; local capture remains usable with sync disabled or unavailable.

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
- recovery after a timeout is explicit through **使用引导与权限 → 重新检查 → 开始使用**.

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
- runtime preference for Apple's newer `SpeechTranscriber` with `.progressiveTranscription`; `DictationTranscriber(.progressiveLongDictation)` is the Apple-native fallback only when the requested locale/device cannot use the newer model or its preparation fails;
- `AssetInventory` preparation;
- one `CaptureAudioSource` owning an AVFoundation data output and `AnalyzerInputConverter`;
- `SpeechAnalyzer`;
- final + volatile transcript accumulation;
- normal finalization versus cancellation;
- stale-session rejection;
- resource cleanup.

Speech assets for both the live progressive preset and the final accurate preset are prepared before Ready so a model download is not started inside an active capture or finish path. `SpeechPipeline.start` receives up to 100 dictionary spellings / 2,000 characters and applies `AnalysisContext.contextualStrings[.general]` through `SpeechAnalyzer.setContext`. Hint failure does not prevent capture; session ownership is rechecked after that await.

Result passages are concatenated exactly as Apple emits them; Morie does not insert spaces or guessed punctuation between native segments. A finish action stops capture and lets already-captured analyzer input finish before finalization. Cancellation instead terminates analysis immediately. The most recent volatile segment is preserved because the current Speech result contract does not guarantee that each volatile result will later be emitted again as final.

For a normal finish, that progressive snapshot is the live-feedback/fallback transcript rather than the authoritative final ASR result. After the source audio is closed, `CaptureSessionController` re-reads the same file through `CaptureFileTranscriber` using `SpeechTranscriber(.transcription)` (or the native Dictation fallback) and the Capture's frozen Dictionary hints. A successful non-empty accurate pass replaces the progressive transcript before cleanup; a non-cancellation failure falls back to the progressive transcript. Audio already confirmed as no speech skips the second pass.

Native teardown always preserves the audio file and returns the best available text/audio snapshot. The snapshot remains available while normal finalization awaits Speech. Analyzer/result errors report to the controller during recording, so the microphone can stop without waiting for another user finish action. Capture-session runtime-error/interruption notifications end the input stream with an error. Session ownership is checked again after asynchronous converter creation, before constructing a microphone source.

There is no third-party/provider abstraction or legacy `SFSpeechRecognizer` path. The only fallback is between Apple's current native transcribers: `SpeechTranscriber` first, then `DictationTranscriber` when necessary.

### `CaptureAudioSource` / `CaptureAudioStream`

`CaptureAudioSource` owns the microphone session, native notifications and serial sample queue. `CaptureAudioStream` writes AAC before Speech conversion, owns the analyzer input stream, and finalizes the file even if conversion or flushing fails. Immediate stop skips converter flushing. Repeated stop/finish returns the same closed artifact; late buffers cannot append to it. Only the store applies explicit discard, empty no-input removal, expiry or History deletion. The stream boundary allows real Apple AAC encoding/error-path tests with synthetic PCM and no microphone/model access.

No-speech retention policy is evidence-based rather than `any non-zero microphone sample == meaningful`. `CaptureAudioStream` tracks the longest continuous run above a speech-like RMS threshold. SpeechPipeline independently upgrades `hasMeaningfulAudio` to true whenever Apple Speech emitted transcript evidence.

Terminal empty-transcript policy:

```text
no final transcript
  ├─ no Speech evidence + no sustained speech-like audio → discard Capture + audio
  └─ Speech evidence or sustained speech-like audio       → retain failed Capture for History retry
```

This combines Type4Me's no-speech fast exit with OpenLess's recoverable empty-transcript history behavior: normal room noise does not pollute History, but recordings likely containing actual speech are not destroyed merely because ASR returned no final text.

### `ExpressionProfileStore` / `PostInsertionLearningController`

Expression Profile is separate from personal Memory. Memory stores semantic facts/preferences/projects; Expression Profile stores only aggregate formatting/style tendencies learned from the user's edits to text Morie just inserted.

The first slice is deliberately narrow:

- learning is opt-in and local;
- the observer anchors only the verified recently inserted range in the focused non-secure text field;
- it stops on a new recording, field ownership loss, unsupported/sensitive targets or after 30 seconds;
- raw edited text is never persisted as profile data;
- only style-only edits whose lexical content is unchanged are admitted;
- current features are sentence length, line-break density, list usage, terminal punctuation, exclamation usage and Chinese/English spacing;
- at least 10 accepted style edits spanning at least 3 days are required before a feature can become stable;
- cleanup receives at most four stable style directives and persists those directives in `RefinementInput` provenance;
- disabling Expression Profile stops observation and stops applying learned directives; clearing deletes the aggregate profile without touching History, Dictionary or Memory.

The same bounded observer also powers explicit dictionary suggestions, avoiding two competing Accessibility polling loops. Dictionary spelling corrections remain separate user-owned dictionary data and are not counted as style evidence.


### `ICloudSyncSettings` / managed SwiftData CloudKit

iCloud is optional and explicitly user-controlled. Morie does not add a local automatic-backup subsystem.

The production SwiftData store is configured at launch with `ModelConfiguration.CloudKitDatabase`:

- toggle off: `.none`, local SwiftData only;
- toggle on: `.automatic`, allowing SwiftData to use the primary CloudKit container from the app's signed iCloud entitlements;
- in-memory tests and explicit storage URLs always force `.none` so development/test fixtures never contact CloudKit.

The setting is applied on the next launch because the `ModelContainer` owns its CloudKit configuration for its lifetime. Enabling first checks `CKContainer.default().accountStatus()`. If a requested CloudKit-backed store cannot open, Morie retries the current schema locally and reports the iCloud failure instead of blocking voice input.

Managed CloudKit uses the user's private database; there is no Morie data backend. The SwiftData records cover History text and processing provenance, user Dictionary, Personal Memory and Expression Profile. Source-audio files remain in Morie's local `CaptureAudio` directory and are not uploaded by this managed store.

The repository intentionally does not invent an iCloud container identifier. The actual Apple Developer/Xcode CloudKit capability and primary container must be configured before runtime synchronization can be accepted.


### `TextInjector`

Delivery is intentionally generic and follows the system-input model:

- resolves the external frontmost application only when final text is ready;
- never activates or restores the application/window that was frontmost at recording start;
- rejects missing/terminated/self current targets and preserves undelivered text on the ordinary clipboard;
- snapshots the clipboard, writes the final transcript, and posts one synthetic Cmd+V;
- lets macOS and the receiving application's first-responder chain choose the actual field;
- tags synthetic key events so Morie's own hotkey path ignores them;
- snapshots only safe text-like clipboard representations;
- restores the previous clipboard only when `changeCount` proves no newer user/app clipboard write occurred.

Accessibility is not an editability gate for ordinary delivery. There is no Electron-specific or per-app compatibility branch. Such behavior can be added only after reproduction on macOS 27 and recording the evidence in the active task.

Target resolution, clipboard staging and paste dispatch run synchronously on the main actor once delivery starts. There is no focus-handoff sleep or delayed app activation. Successful dispatch records the actual frontmost app/bundle and supplies that same application to the bounded correction observer.

### `CaptureHUD` / `CaptureSoundFeedback`

Owns a native, non-activating recording surface that does not become the keyboard target:

- system `NSPanel` placement and focus behavior;
- one AppKit `NSGlassEffectView` that embeds the complete HUD content and samples behind the transparent panel;
- standard bordered system buttons inside that single glass surface;
- cancel / live microphone level / finish layout;
- processing, success, and failure feedback;
- inline delivery fallback feedback that states when the transcript was copied to the clipboard, without a focus-stealing modal alert;
- animated, labelled successful-input feedback instead of an isolated static status glyph;
- stationary level feedback when Reduce Motion is enabled;
- no custom glass imitation or third-party UI.

The visible capsule now morphs from a tiny center point into the full pill on first presentation and collapses back to the center before its hosting tree is released. The AppKit panel geometry itself stays fixed, so there is no monitor re-position or layout jump. Reduce Motion bypasses this scale animation.

The processing state intentionally uses a larger plain `Thinking` label plus a visible accent-color border flow rather than an indeterminate spinner, avoiding network-loading semantics for local Speech/foundation-model work.

`CaptureSoundFeedback` owns short synthesized in-memory start/finish tones through pre-prepared `AVAudioPlayer` instances. No bundled sound file or third-party dependency is required. The cues acknowledge accepted global actions rather than backend completion: start plays immediately after a new Capture/session/HUD is established; finish plays immediately when a valid finish action is accepted, before `Thinking`. Duplicate/ignored finish requests and cancellation do not replay the normal finish cue.

The microphone waveform is the only custom-drawn control because macOS does not provide a system live-audio waveform component. It renders a complete center-weighted envelope from the first frame—low at both edges and tallest in the middle—then smoothly changes the middle bars with actual microphone level. Its silence threshold and restrained gain curve retain the relevant proven behavior from Type4Me without importing Type4Me's scrolling-history presentation or UI system.

The waveform's display-driven view tree exists only while the HUD is visible. Hiding the HUD releases its hosting view and panel rather than merely ordering the window out, so the 60 Hz `TimelineView` cannot continue rendering during app idle and its render resources do not remain resident unnecessarily.

### `CaptureRecord` / `CaptureStore`

M-003 introduces the first durable product boundary using Apple SwiftData:

- the Phase 0 session UUID is also the Capture identity;
- an intentional voice Capture is saved before Speech startup;
- progressive recognition checkpoints update the same record with a bounded save cadence;
- final recognition, delivery success, clipboard-preserved delivery failure, and operational failure become explicit durable lifecycle states;
- explicit user cancellation discards the in-progress record; an empty transcript only discards audio confirmed to contain no signal/no input, while uncertain audio remains retryable;
- source-audio filenames are saved before recording, and interrupted records with audio or checkpointed text become recoverable failures when the store opens;
- the actual successful delivery application name and bundle identifier are the current minimal App Context; capture-only records retain Morie as their source context.

Every new voice Capture has an explicit, durably saved delivery mode. The global shortcut creates `currentApp`; History's **Record Capture** action creates `captureOnly`. Both use the same capture UUID, microphone session, Speech pipeline, cancellation and History preemption. An in-app capture records Morie as the source and never enters external delivery. Recognition completion returns the saved mode: capture-only completion ends as `recognized` and releases recording/discard ownership; a running refinement separately blocks History mutation and extraction. Current-app completion retains ownership through delivery. Both modes refine the saved text before success. Capture-only success never enters `TextInjector` or the clipboard/focus path and reports “已保存” in the shared HUD.

The local `ModelConfiguration` explicitly disables CloudKit. The single-Mac milestone does not depend on sync, enrollment or a container. A later scheduled cross-device milestone uses each user's own iCloud private database within Morie's app container; this is not a separate Device Only product mode. The current schema contains `CaptureRecord`, `DictionaryEntry`, `MemoryRecord`, `MemoryAnalysisRecord` and `MemoryLearningBlock`, with no old-schema migration.

M-003's approved persistence direction is audio-first: the durable raw Capture is compressed source audio, recognized text is the Speech result, and final text is the later post-processing result. Source audio defaults to 7-day retention, Settings exposes a 1–365 day policy, and expiry removes audio without deleting text/history metadata. Encoding streams to disk rather than retaining a complete PCM recording in memory.

The first attempted implementation using `AVCaptureAudioFileOutput` beside `CaptureInputSequenceProvider.captureAudioDataOutput` is rejected. On the owner's macOS 27 hardware, `canAddOutput` succeeded but `startRecording(to:outputFileType:recordingDelegate:)` raised an Objective-C exception inside AVFoundation and terminated Morie with `SIGABRT` (incident `F160F627-871F-4F35-A880-74BAFBE55D67`). Because this exception cannot be handled by Swift `throws`, that output must not be reintroduced without a proven Apple-supported configuration and real-device validation. The replacement must follow the proven single-`AVCaptureAudioDataOutput` ownership/lifecycle pattern and stream encoded samples without duplicating the microphone session.

The replacement now owns one `AVCaptureSession` and one `AVCaptureAudioDataOutput`. Each 16 kHz mono PCM buffer is passed through Apple's `AnalyzerInputConverter` to `SpeechAnalyzer` and streamed into an Apple `AVAudioFile` AAC encoder targeting 32 kbps. This adapts Type4Me's proven single-output ownership and deterministic queue drain while dropping its complete in-memory PCM accumulation. Runtime acceptance remains open until owner-hardware validation confirms recognition, waveform response, playable M4A output, cancellation and repeated start/stop.

Source-audio evidence is conservative: `true` means Speech previously returned text, `false` means the captured PCM contained no signal, and `nil` means nonzero signal has not been established as speech or silence. Empty results with unknown audio stay as failed Captures. The former “five buffers above −50 dB” heuristic could mistake ambient noise for speech and is removed. Apple documents that `SpeechDetector` gates transcription and may drop speech; it is not added to the live path without validating that trade-off on owner hardware.

Expiry clears the audio path but retains duration, expiry, recognition errors, and the History row, including failed captures with no text. Cleanup runs once on startup, immediately after an explicit retention-policy change, and from a once-per-day background maintenance loop while Morie is ready. Capture start and History playback/re-recognition never scan the Capture table for expired audio; direct audio access still checks the selected record's expiry before opening the file. Interrupted-capture recovery uses the filename saved by the current implementation; it does not reconstruct legacy metadata or migrate old formats.

Re-recognition updates `recognizedText` only after successful file analysis. Delivered/delivery-failed output and output from a completed refinement (including unchanged/capture-only output) retain `finalText` and their actual refinement input/context. Other successful recoveries become `recognized` and receive the recovered final text. Retry errors use separate optional metadata; failure, empty retry results, and cancellation never erase prior text or audio. Retry never injects into the original app or changes the clipboard; copying is an explicit History action.

### `CaptureFileTranscriber` / `CaptureHistoryController`

`CaptureFileTranscriber` uses the same native backend preference as live input: `SpeechTranscriber(.transcription)` when the locale/device supports it, otherwise `DictationTranscriber(.longDictation)`. It reads an existing `AVAudioFile` with `SpeechAnalyzer.analyzeSequence(from:)`, finalizes through the consumed audio, and closes native analysis on cancellation or failure. Normal Capture completion calls this path once after live finalization and supplies the session-frozen Dictionary hints through `AnalysisContext`; explicit History re-recognition does not reconstruct historical hint state. A SpeechTranscriber asset-preparation failure can fall back to DictationTranscriber; recognition failure after analysis begins is not silently retried through another engine.

`CaptureHistoryController` owns one selected recording's `AVPlayer` and one cancellable file-recognition task. Selection changes or leaving the detail cancel that task and release playback. Starting a live Capture pauses playback, cancels the retry, and awaits its termination before starting Speech. Every result checks task cancellation before persistence so a late retry cannot overwrite a newer interaction.

### `CaptureHistoryView`

`CaptureHistoryView` receives records from a History-only SwiftData query and a Capture-ID selection binding. The Control Center root does not keep the full Capture query alive while the user is on Dictionary, Memory, Settings, Permissions or Diagnostics. The selected detail uses a separate UUID-filtered query so only the chosen Capture is observed there. A native selectable `List` supports text/app search and All / History Only / Needs Attention filters. Filtering or deletion clears a selection that is no longer visible. `CaptureDetailView` presents saved final text on a reading surface; native disclosures retain recognition/refinement provenance and recording/retry details. Copy Final Text is a toolbar action; secondary copy/deletion actions use a system menu and deletion confirmation.

Audio playback uses AVKit's standard `AVPlayerView` controls. Open/close, expiry and refinement-state hooks preserve the controller's existing cancellation/player ownership. No replacement media controls are drawn, and recordings do not populate Now Playing metadata.


### `OverviewView`

The Control Center landing page is a local-only summary, not an analytics subsystem. It queries completed Capture records only while the page is visible and derives a small first-slice set of metrics:

- cumulative recognized characters;
- successful current-app deliveries;
- operational input failure rate over terminal current-app attempts;
- average cleanup duration where a refinement duration exists.

The operational failure rate is deliberately not labelled as ASR accuracy/WER. Morie does not yet have enough ground-truth user corrections to distinguish recognition errors from spoken restarts, cleanup changes or later user edits reliably.

The same page exposes actual runtime model state. `AppController` publishes the backend that `SpeechPipeline.prepare` really prepared, so a `DictationTranscriber` fallback is shown as fallback rather than pretending the preferred `SpeechTranscriber` is active. Cleanup identifies Apple's public `SystemLanguageModel.default` / Foundation Models surface and its current availability; Morie does not invent an Apple model/version string that the API does not expose.

### `MorieControlCenter`

The primary management surface is one native SwiftUI `Window`, defaulting to 1120 × 720 with a 960 × 600 minimum. The sidebar opens on **总览**, then groups **历史记录 / 字典 / 个人记忆** under **资料库**, and **设置 / 权限 / 诊断** under **应用**. History and Personal Memory use three-column `NavigationSplitView` layouts; Dictionary and application pages use two columns. Both map a shared sidebar-visibility choice to their native column states (`doubleColumn` versus `detailOnly` when hidden). Native expandable Section controls persist group expansion. Settings and routine permission management are embedded pages. The separate welcome guide has no permanent navigation entry. A one-time read-only launch inspection opens it automatically when setup is incomplete; the explicit **打开 Morie** action applies the same gate.

The root owns independent Capture, Dictionary and Personal Memory UUID selections. Capture and Personal Memory details get a `NavigationStack` whose identity changes with that selection, so source/related links cannot leak navigation from another record. Dictionary selection drives edit/delete actions directly on its single content page. The SwiftData container is attached at the window root. Capture `@Query` instances are created only by the visible History panes or the visible Overview page; neither keeps the full Capture history subscribed while the user is elsewhere. The native menu retains one icon-free **打开 Morie** action, status/shortcut guidance and **退出 Morie**; it does not duplicate Settings or setup destinations.

`ManagementDetailContent` is a small composition of native ScrollView/VStack with 28-point padding and a readable maximum width of 760 points. It is shared by Capture and Personal Memory reading surfaces. Settings and Permissions use grouped Forms; the single-word dictionary sheet uses a compact native columns Form. There is no custom navigation, control library, material or persistence layer.

`MorieSettingsView` and routine permission management use flexible grouped Forms in Control Center. Command-comma opens that window and selects Settings. The first-use setup window defaults to 700 × 740 and permits native resizing down to 640 × 680; long permission descriptions scroll inside the grouped Form. `DiagnosticLogView` uses a native Table with search/direct level filtering, selection and a resizable event-detail area for complete messages. In-memory events remain immediate, while disk writes are coalesced over a short interval, errors flush immediately, and the debug file is bounded to avoid unbounded long-running I/O/storage growth. Copy All Events, reveal-file and confirmed clear actions preserve the existing logger behavior.

### `DictionaryEntry` / `DictionaryStore`

The dictionary remains separate from personal Memory and saves one word per user entry. The owner's M-011 amendment removes alias fields from drafts, records and processing snapshots. A very small code-owned built-in baseline is kept outside SwiftData; user words persist in `DictionaryEntry` with provenance that distinguishes manual entry from explicit correction confirmation. Existing rows without provenance read as manual. User entries override matching built-in spellings in the effective view/hint set, so one case-insensitive term appears once.

The non-autosaving write context shares the Capture container without touching Capture checkpoints. Duplicate user words are rejected; a word is trimmed, 1–120 characters long and contains no internal control characters or line breaks. Effective words supply up to 100 native Speech hints within a 2,000-character budget, with user entries taking priority and built-ins filling remaining capacity. Speech result segments retain Apple's own whitespace and punctuation and are concatenated without an invented separator. `DictionarySpelling` then normalizes only letter-case variants of the same whole word using native `NLTokenizer` boundaries. It prefers longer terms even when already correctly spelled, avoids overlaps and protects code/URLs/paths/technical spans. It does not normalize full-/half-width forms or invent a homophone substitution based on a previous recognition error.

`DictionaryView` uses one searchable content page with an adaptive grid of native bordered buttons so short words pack across each row. Built-in/manual/correction-confirmed words may appear together; built-ins are read-only while user entries retain edit/delete actions. The editor remains a content-sized system sheet with one **词语** field. History retains just the words used by each refinement, alongside the actual edits.

### `CapturePersonalizer` / `InputRefiner`

`Speech → durable recognized text → dictionary corrections → optional cleanup with related personal context → validation → durable final text → delivery`

Basic cleanup runs with an empty or unavailable Memory store. `InputRefiner` creates a fresh Apple `LanguageModelSession`, supplies transcript/dictionary/context as JSON data under the [approved cleanup instructions](input-cleanup.md), and requests complete final text through greedy `@Generable` output. Native token accounting bounds the full prompt, instructions, schema and a response budget of 256–1,536 tokens. Oversized input is declined without truncating the saved text.

Foundation Models owns light cleanup and contextual correction through the approved instructions and `@Generable` structured result, but it receives a narrower vocabulary surface than Speech. Speech keeps the full bounded hint set; cleanup receives only transcript-relevant canonical candidates (including close Latin neighbors such as **Coldex → Codex**). Confirmed mappings are deterministic pre-model edits rather than prompt material. The save boundary still rejects empty/control-character payloads and now adds a conservative grounding check for longer generated clauses; clearly unsupported new sentences are rejected and the prepared transcript is used instead. Snapshot freshness, dictionary/Memory changes and durable-save failure remain separate consistency checks.

`InputRefinementRunner` owns one model task and one continuation. It has no elapsed-time deadline: completion is determined by Foundation Models success/failure or explicit caller cancellation, so input length and actual model work—not an arbitrary number of seconds—determine duration. Cancellation resolves the caller without joining model teardown; late results are ignored and optional model work skips while an old cancelled session drains. Idle learning and cleanup consult each other's activity. Historical `.timeLimit` records remain readable but production no longer creates them.

`CaptureRefinement` retains the exact input, dictionary/personal-context snapshots, accepted edits, status, fixed reason and duration. Current and separately committed source text must agree before inference and save. Source, dictionary and relevant Memory are rechecked after inference; stale model output cannot be delivered. Disabling/failing/timing out cleanup can still durably apply dictionary corrections. A changed dictionary or failed final save retains the verified durable original. No unsaved model result is returned for insertion.

Running refinement blocks History mutations/playback/re-recognition. Speech retries preserve completed final output and its earlier processing provenance. Restart clears current-version interrupted refinement without replaying delivery or restarting that model. Existing capture-only processing remains but is excluded from automatic personal learning.

The local Foundation Models prompt follows a **closed-world cleanup contract**: transcript is the only source of facts/topics; spelling candidates, Memory context and expression style may only disambiguate or repair content already expressed. The instructions are deliberately shorter than cloud-oriented reference prompts to reduce competing instruction/vocabulary priming on the on-device model. A final grounding validator rejects clearly unsupported longer clauses before they can become deliverable text.

### `MemoryRecord` / `MemoryStore`

Personal Memory kinds are `project`, `person`, `preference`, `fact` and `decision`. Records hold topic/name, personal information, source Capture IDs, automatic/user origin, optional confidence, last evidence date, timestamps, lifecycle and predecessor identity. There are no vocabulary aliases or required confirmation fields.

A separate non-autosaving Memory context protects active Capture checkpoints. Only MemoryRecord objects are kept in the long-lived published collection; MemoryAnalysisRecord history is fetched by capture/state on demand, UI receives lightweight value snapshots, and the mutation context is recreated after each save so analysis faults do not accumulate for the app lifetime. Active normalized topics are unique within their kind. User editing keeps identity/provenance, marks user origin and clears model confidence. Replacement creates a successor and supersedes the prior record atomically; archive/restore respect active-topic conflicts. Automatic updates never overwrite user-edited records.

`MemoryLearningBlock` retains a SHA-256 hash of kind + normalized topic when a memory is deleted (or renamed through editing). Automatic learning skips that topic; explicit manual creation removes its block. Deletion removes matching observation payloads while retaining the user's source Captures. This key is lexical, not a guarantee against a model inventing a different semantic label for the same fact; validate topic consistency on actual model output. Deleting a Capture removes its analysis snapshots while separate Memory retains its source ID and shows an unavailable source.

### `MemoryContextRetriever`

Pure Swift retrieval consumes immutable active Memory snapshots from either origin. Native lexical name/content overlap ranks deterministic results capped at eight. History distinguishes source-linked Memory from related context. Retrieval is local, bounded and independent of a model call; it is not semantic recall or dictionary replacement. Context helps understand what was said and cannot insert unspoken background or rewrite the user's current preferences.

### `MemoryAnalysisRecord` / `MemoryLearner` / `MemoryLearningController`

Completed `currentApp` Captures (`delivered` or `deliveryFailed`) with committed final text are queue sources. Active, cancelled, capture-only, running-refinement and raw-only inputs do not enter learning. Normal completion enqueues only that Capture through `enqueueCompletedInput`; a single startup `reconcileCompletedInputs` pass discovers work saved immediately before a crash/relaunch. The steady-state learner never rescans all Capture history to discover work. Each analysis retains exact final text/date/ID, context snapshots, observations, attempts, retry time and pending/completed/skipped status. No recognized-text fallback or historical reconstruction is used.

`MemoryLearner` uses a fresh Apple Foundation Models session and native full-request context accounting to propose at most three personal observations. Learning context combines up to eight related memories with up to four recent fact/preference records, capped at twelve. Source text is data; fixed failure categories prevent raw framework/model text from entering logs.

Admission requires literal supporting evidence, notes contained in that evidence, an explicit personal connection and finite confidence. Temporary/uncertain/quoted suggestions are rejected, with additional quote/hypothetical checks. Person/project names require literal evidence unless updating identified context. Strong explicit personal evidence (at least 0.9) may create Memory automatically; weaker recurring evidence (at least 0.8) needs two distinct source Captures. These thresholds are engineering filters, not calibrated confidence guarantees.

Repeated evidence merges idempotently. Explicit later updates require a current context ID/snapshot, an automatic record, newer evidence and an update marker before superseding it. Ambiguous, older or user-owned conflicts do not overwrite current information. Analysis completion and Memory mutations share one save; failures roll back the entire mutation, including intermediate fetch failures. The source is rechecked before commit so deleted/changed input cannot produce a late result.

The controller is event-driven: after startup reconciliation or a newly completed Capture it waits 30 seconds of input idle time, then processes at most three sources per batch. When no pending source exists, no worker/timer remains scheduled. Retryable work schedules one wake for its earliest `nextAttemptAt` instead of polling every 30 seconds. One owned worker/model runs at a time. New input cancels it immediately without awaiting an uncooperative model; unfinished work stays pending and late results cannot commit. Retryable unavailability/generation/invalid-result failures back off from 30 seconds to one hour. Nonretryable language/context/refusal/source-change outcomes are visible in History with an optional retry. A background model has no independent deadline in this slice; it retains ownership until it drains, while new input continues and cleanup can skip it.

### Native Memory management

`MemoryView` shows personal information directly in the shared searchable list/detail UI, with status filtering and optional native create/edit/archive/restore/replace/delete actions. There is no candidate inbox or review sheet. `MemoryLearningView` shows per-Capture learning progress/outcomes, linked memories and **用于学习的文字**. Sources remain exact and inspectable; opening/closing a page does not start or cancel background learning.

### `DictionaryCorrectionController`

The independent **修改输入后建议加入字典** setting defaults off. After current-app paste dispatch, a short actor task verifies the exact inserted text at the caret; unsupported/secure fields and selected terminal/password-manager apps are excluded. No clipboard fallback or capture-only input starts observation.

Accessibility IPC stays off the main actor with 50 ms native message timeouts. `AXStringForRange` reads a bounded insertion (at most 1,200 UTF-16 units, at most 64 units of length change); it never requests the whole document. PID, field identity, secure-input state and selection bounds are checked. Observation ends on departure, new capture, disabling the setting or 30 seconds. Character-count delta infers range length, so concurrent edits elsewhere and host range implementations remain device-validation risks.

The pure detector aligns native word boundaries across both texts and waits two seconds for a stable small correction. The per-process suggested-word suppression cache is bounded to 256 normalized words instead of growing without limit. It handles shared letters, added/deleted letters and word joins, while rejecting appended/deleted phrases, punctuation/numbers/technical edits and broad rewrites. A native nonactivating `NSPanel` offers **加入字典 / 暂不添加** for the correction. Explicit confirmation keeps/adds the canonical spelling and may persist the detected observed-ASR → canonical-word mapping in the internal `DictionaryCorrectionRule` store; the wrong form never becomes a normal Dictionary row. Not Now/expiry saves nothing. The prompt expires after 20 seconds, dismisses on further edits/departure, and offers each normalized word at most once per process. External text is never sent to AI, logged or saved into Capture. See the [OpenLess audit](reference/openless.md).

### `MorieTests`

The logic-only target compiles core persistence, audio, dictionary, cleanup and learning sources directly without launching Morie or entering TCC. In-memory/unique temporary stores and synthetic audio isolate production data; `TestDiagnostics.swift` isolates the running app's log. Native AAC encoding/decoding is exercised without opening a microphone.

Permission setup tests cover mandatory complete snapshots, read-only revocation/recovery, explicit authorization, denied/restricted/unsupported states, stale buttons, coalesced refresh and duplicate/dialog-activation races. They also compile the real capability gate's Speech authorization bridge with injected `SFSpeechRecognizer` subclasses, exercising the native Objective-C callback boundary on a background queue and synchronously. Status inspections and system actions remain injected; no test queries or requests real TCC.

Dictionary tests cover word-only persistence, normalized duplicates, invalid-input protection, bounded hints, native word boundaries, overlapping names and technical-content protection. Correction tests cover Chinese/mixed words, added/deleted/joined letters, excluded edits, settling and undo without reading Accessibility data or displaying a panel.

Memory tests cover provenance, lifecycle and retrieval. Learning tests inject evidence/models to verify exact final-text snapshots, restart discovery, automatic admission/accumulation, deduplication, conflicts/updates, user changes, scoped deletion, atomic failure/retry, source validation and immediate input preemption. Personalization tests inject model output, including tasks that ignore cancellation, to establish durable ordering, dictionary fallback, cleanup guards, stale-context rejection, deadline/cancellation and recovery. Actual model fidelity, AX/cross-app behavior, UI interaction and latency remain device acceptance.

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
- real current-focus routing;
- target-app injection;
- Liquid Glass visual behavior;
- latency/energy use.

Those remain real-device acceptance work.

## Future package direction

Extract shared Swift packages only when a real second consumer requires them. The current macOS target keeps platform integration separate from testable product logic without creating an iOS shell, empty provider layers or speculative CloudKit packages. Any future shared UI must remain compositions of Apple system components.

## Data architecture direction

The central durable object is `Capture`; voice is one source.

```text
Capture
├── identity / timestamps
├── type: voice | text
├── content: raw / recognized / final
├── source: app / bundle / optional context
├── delivery: currentApp | captureOnly
├── context: project / topic / people / entities
└── personal analysis: separate source snapshot / pending / completed / skipped

DictionaryEntry → one saved word / spelling hint
MemoryRecord → personal information and source provenance
```

Voice is an input source, not the core domain object.

## Persistence boundary

M-003 introduces the reliability boundary:

1. intentional Capture is durably saved;
2. only then may AI correction/classification/Memory extraction run;
3. enriched/final state updates the saved Capture;
4. failures never delete the original intentional capture.

Private Mode eventual cross-device sync uses iCloud/CloudKit. It is outside the single-Mac milestone; local development is not a separate Device Only product mode.

## External dependency boundary

There is no architecture layer called “third-party fallback”.

If Apple-native capabilities cannot satisfy a concrete requirement, document the gap and request explicit owner approval. Existing use of a dependency in Type4Me is not permission to introduce it in Morie.

## Boundary against future Cloud

A future Morie Cloud may use Rust and expose APIs/MCP, but the Apple client remains Swift-native. Client and server may share protocol/data semantics, not runtime implementation.

Do not add server-oriented architecture to the client before the Private product loop is validated.
