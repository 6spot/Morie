# Architecture

## Current stage

Morie is validating **Phase 0 — macOS Input Foundation**, **Phase 1 — Durable Capture**, **Phase 2 — Personal Memory** and the first **Phase 3 — Personalization** slice. The input loop now uses confirmed vocabulary/project context for bounded refinement, saves final text and then attempts candidate extraction with human review. Broader style learning, iOS and Morie Cloud remain subsequent work. The owner has deferred interactive device checks until the evening and sync until final integration.

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
│   ├── CaptureHistoryController.swift
│   ├── CaptureFileTranscriber.swift
│   ├── CaptureAudioSource.swift
│   ├── CaptureAudioStream.swift
│   ├── MemoryRecord.swift
│   ├── MemoryStore.swift
│   ├── MemoryContextRetriever.swift
│   ├── MemoryView.swift
│   ├── MemoryExtractionRecord.swift
│   ├── MemoryCandidateExtractor.swift
│   ├── MemoryCandidateController.swift
│   ├── MemoryCandidatesView.swift
│   ├── CaptureRefinement.swift
│   ├── InputRefiner.swift
│   ├── CapturePersonalizer.swift
│   ├── MorieControlCenter.swift
│   ├── CaptureHUD.swift
│   ├── Diagnostics.swift
│   ├── PushToTalkHotkey.swift
│   ├── SpeechPipeline.swift
│   └── TextInjector.swift
├── MorieTests/
│   ├── CaptureStoreTests.swift
│   ├── CaptureHistoryTests.swift
│   ├── CaptureAudioStreamTests.swift
│   ├── MemoryTests.swift
│   ├── MemoryCandidateTests.swift
│   ├── PersonalizationTests.swift
│   └── TestDiagnostics.swift
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

`checking → ready → recording → finalizing → refining → delivering → ready`

`captureOnly` completes after refinement without entering delivery. Refinement can be skipped or end with the saved original; it does not change the required capability gate or introduce another product mode.

`failed` and `blocked` represent recoverable operation failure and unavailable required capability respectively.
Explicit cancellation uses `stopping` until native teardown and discard complete. Capability recheck enters `checking`, and shortcut loss enters `blocked`, before awaiting teardown; late capture work cannot replace these states with Ready.

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

One shared shutdown task owns each interruption/discard. It cancels startup/finalization, closes native capture, preserves the latest text/audio, and awaits outstanding work before committing the disposition. User cancellation discards; capability recheck, shortcut failure, microphone interruption and Speech errors retain a failed Capture. New input waits until shutdown ends. A result that arrives during shutdown is saved without delivery; a paste already dispatched retains its actual delivery outcome.

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
- one `CaptureAudioSource` owning an AVFoundation data output and `AnalyzerInputConverter`;
- `SpeechAnalyzer`;
- final + volatile transcript accumulation;
- normal finalization versus cancellation;
- stale-session rejection;
- resource cleanup.

Speech assets are prepared before Ready so a model download is not started inside an active capture.

A finish action stops capture and lets already-captured analyzer input finish before finalization. Cancellation instead terminates analysis immediately. The most recent volatile segment is preserved because the current Speech result contract does not guarantee that each volatile result will later be emitted again as final.

Native teardown always preserves the audio file and returns the best available text/audio snapshot. The snapshot remains available while normal finalization awaits Speech. Analyzer/result errors report to the controller during recording, so the microphone can stop without waiting for another user finish action. Capture-session runtime-error/interruption notifications end the input stream with an error. Session ownership is checked again after asynchronous converter creation, before constructing a microphone source.

There is no legacy recognition fallback and no provider abstraction.

### `CaptureAudioSource` / `CaptureAudioStream`

`CaptureAudioSource` owns the microphone session, native notifications and serial sample queue. `CaptureAudioStream` writes AAC before Speech conversion, owns the analyzer input stream, and finalizes the file even if conversion or flushing fails. Immediate stop skips converter flushing. Repeated stop/finish returns the same closed artifact; late buffers cannot append to it. Only the store applies explicit discard, empty no-input removal, expiry or History deletion. The stream boundary allows real Apple AAC encoding/error-path tests with synthetic PCM and no microphone/model access.

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

Delivery checks cancellation before activation and after the asynchronous focus handoff. Clipboard staging and paste dispatch then run synchronously on the main actor, so an interruption cannot resume a pending paste afterward. Successful dispatch is persisted even if cancellation reaches the caller before it resumes.

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
- explicit user cancellation discards the in-progress record; an empty transcript only discards audio confirmed to contain no signal/no input, while uncertain audio remains retryable;
- source-audio filenames are saved before recording, and interrupted records with audio or checkpointed text become recoverable failures when the store opens;
- source application name, bundle identifier and original window identity are the current minimal App Context.

Every new voice Capture has an explicit, durably saved delivery mode. The global shortcut creates `currentApp`; History's **Record Capture** action creates `captureOnly`. Both use the same capture UUID, microphone session, Speech pipeline, cancellation and History preemption. An in-app capture records Morie as the source and has no external target/window. Recognition completion returns the saved mode: capture-only completion ends as `recognized` and releases recording/discard ownership; a running refinement separately blocks History mutation and extraction. Current-app completion retains ownership through delivery. Both modes refine the saved text before success. Capture-only success never enters `TextInjector` or the clipboard/focus path and reports “已保存” in the shared HUD.

The local `ModelConfiguration` explicitly disables CloudKit. On 2026-09-18, the owner deferred synchronization to the final integration stage because Apple Developer enrollment is not yet set up. The intended destination remains each user's own iCloud private database within Morie's app container. This is an implementation stage, not a Device Only product mode.

M-003's approved persistence direction is audio-first: the durable raw Capture is compressed source audio, recognized text is the Speech result, and final text is the later post-processing result. Source audio defaults to 7-day retention, Settings exposes a 1–365 day policy, and expiry removes audio without deleting text/history metadata. Encoding streams to disk rather than retaining a complete PCM recording in memory.

The first attempted implementation using `AVCaptureAudioFileOutput` beside `CaptureInputSequenceProvider.captureAudioDataOutput` is rejected. On the owner's macOS 27 hardware, `canAddOutput` succeeded but `startRecording(to:outputFileType:recordingDelegate:)` raised an Objective-C exception inside AVFoundation and terminated Morie with `SIGABRT` (incident `F160F627-871F-4F35-A880-74BAFBE55D67`). Because this exception cannot be handled by Swift `throws`, that output must not be reintroduced without a proven Apple-supported configuration and real-device validation. The replacement must follow the proven single-`AVCaptureAudioDataOutput` ownership/lifecycle pattern and stream encoded samples without duplicating the microphone session.

The replacement now owns one `AVCaptureSession` and one `AVCaptureAudioDataOutput`. Each 16 kHz mono PCM buffer is passed through Apple's `AnalyzerInputConverter` to `SpeechAnalyzer` and streamed into an Apple `AVAudioFile` AAC encoder targeting 32 kbps. This adapts Type4Me's proven single-output ownership and deterministic queue drain while dropping its complete in-memory PCM accumulation. Runtime acceptance remains open until owner-hardware validation confirms recognition, waveform response, playable M4A output, cancellation and repeated start/stop.

Source-audio evidence is conservative: `true` means Speech previously returned text, `false` means the captured PCM contained no signal, and `nil` means nonzero signal has not been established as speech or silence. Empty results with unknown audio stay as failed Captures. The former “five buffers above −50 dB” heuristic could mistake ambient noise for speech and is removed. Apple documents that `SpeechDetector` gates transcription and may drop speech; it is not added to the live path without validating that trade-off on owner hardware.

Expiry clears the audio path but retains duration, expiry, recognition errors, and the History row, including failed captures with no text. Cleanup runs on startup, retention changes, new capture, and History audio access. An open detail view refreshes when its recording expires. Interrupted-capture recovery uses the filename saved by the current implementation; it does not reconstruct legacy metadata or migrate old formats.

Re-recognition updates `recognizedText` only after successful file analysis. Delivered/delivery-failed output and output from a completed refinement (including unchanged/capture-only output) retain `finalText` and their actual refinement input/context. Other successful recoveries become `recognized` and receive the recovered final text. Retry errors use separate optional metadata; failure, empty retry results, and cancellation never erase prior text or audio. Retry never injects into the original app or changes the clipboard; copying is an explicit History action.

### `CaptureFileTranscriber` / `CaptureHistoryController`

`CaptureFileTranscriber` reads an existing `AVAudioFile` with `SpeechAnalyzer.analyzeSequence(from:)` and a final-result `SpeechTranscriber`, finalizes through the consumed audio, and closes native analysis on cancellation or failure. It creates no microphone session and uses the Speech assets prepared by bootstrap.

`CaptureHistoryController` owns one selected recording's `AVPlayer` and one cancellable file-recognition task. Selection changes or leaving the detail cancel that task and release playback. Starting a live Capture pauses playback, cancels the retry, and awaits its termination before starting Speech. Every result checks task cancellation before persistence so a late retry cannot overwrite a newer interaction.

### `CaptureHistoryView`

Native SwiftUI/SwiftData History uses `List`, `NavigationStack`, `Form`, and `@Query` for a list and Capture detail. Audio playback uses AVKit's standard `AVPlayerView` controls. Details show final text first, original/latest recognition separately, refinement outcome/input/changes/context, explicit Copy buttons, retry progress/cancel, audio expiry/errors and deletion with a system confirmation dialog. No replacement media controls are drawn, and recordings do not populate Now Playing metadata.

### `MorieControlCenter`

The primary management surface is one native SwiftUI `Window` with a standard `NavigationSplitView`. Its sidebar currently routes to History, Memory, Settings, and Diagnostics. The SwiftData container is attached at the window root before `@Query` builds the initial History detail, avoiding a different first-render environment. The panel retains one **Open Morie** action plus capture status and essential recovery/quit actions.

### `MemoryRecord` / `MemoryStore`

The Capture container now includes `MemoryRecord` for vocabulary and projects: name, aliases, notes, source Capture IDs, confirmation, optional model confidence, timestamps, lifecycle, and predecessor identity. New Memory is explicitly saved by the user from History or the Memory section. Manual confirmation leaves model confidence nil. Saving Capture itself does not create Memory.

`MemoryStore` uses its own non-autosaving `ModelContext` in that same container, so rolling back a failed Memory edit cannot roll back a live Capture's checkpoint. It publishes its saved records for native UI and reads source Captures from their authoritative main context. Memory operations never modify source transcript/delivery fields. Names and aliases are validated; active names are unique within their kind after case/width/whitespace normalization, and aliases are deduplicated.

Editing keeps identity/provenance. Replacement atomically creates a new active record with the predecessor ID and source IDs, and marks the previous record superseded. Archived records can be restored if their name is available; superseded records cannot be edited or restored. Explicit deletion removes only that Memory. Deleting a source Capture retains independently confirmed Memory and its source ID, and the UI reports the source as deleted instead of fabricating provenance.

### `MemoryContextRetriever`

This pure Swift boundary consumes immutable snapshots. It selects only confirmed active records by normalized name/alias matching with NaturalLanguage's native word boundaries. Literal matching preserves significant punctuation in identifiers such as `C++`; boundaries prevent a term such as `Git` from matching inside `GitHub`. Canonical-name matches rank ahead of aliases, longer phrases ahead of shorter ones, then recency and UUID provide deterministic ordering. Results are capped at eight.

History exposes related records and separately labels records saved from that Capture, including their lifecycle. The retriever is also used after durable recognition for input refinement. Retrieval itself uses no model/network call. It remains lexical matching, not semantic recall, Speech hotword configuration or a built-in dictionary; a misrecognition must be an explicitly confirmed alias to support correction.

### `CapturePersonalizer` / `InputRefiner`

The current input sequence is:

`Speech → durable recognized text → relevant confirmed Memory → bounded edit proposals → validation → durable final text → delivery/History completion → optional Memory Candidates`

`CapturePersonalizer` owns this persistence boundary for both capture modes. The current source and a separate committed context must agree before inference and final save. `CaptureRefinement` retains the exact input, context snapshots, accepted edits, outcome, fixed reason and elapsed time. Running refinement blocks playback/re-recognition/deletion and Memory extraction. Late Speech partials cannot overwrite a completed recognition. Restart clears interrupted refinement while preserving saved text/audio and any actual delivery outcome; it does not restart a model or deliver text automatically.

`InputRefiner` calls `SystemLanguageModel.default` through a fresh `LanguageModelSession` with greedy `@Generable` output. The full prompt/instructions/schema plus a 768-token response allowance must fit the native context limit. Transcript and context are data, never instructions. Up to eight anchored edits may correct an explicit confirmed name/alias to its exact canonical name, or tidy horizontal spacing/add a missing comma/period. `RefinementValidator` rejects missing/overlapping anchors, partial words, content deletion/expansion, changed existing punctuation, and edits to numeric/technical tokens or backtick code. Word tokens and content characters are retained for cleanup. This first slice does not rewrite style, remove fillers, infer aliases or perform fuzzy term recovery.

`InputRefinementRunner` owns one model task, a deadline task and a single continuation. The provisional model-wait budget is 2 seconds. Timeout/caller cancellation resolves the caller without joining model teardown; a draining task stays owned, its late result is discarded, and new optional model work skips until it ends. Candidate extraction and refinement consult each other's activity so they do not overlap. Storage, validation and main-actor scheduling add overhead beyond the model budget; overall latency/energy remains to be measured on hardware.

After inference, the source and retrieved Memory snapshots are checked again. Changed/archived/deleted Memory or invalid model edits keep the original. A changed/deleted source rejects stale delivery. Save failure rolls back unsaved AI output and returns only the verified durable original. If outcome metadata cannot be saved either, that outcome may be incomplete until a later terminal save/restart; existing text stays durable. Caller cancellation preserves the Capture and cannot resume a pending paste. Diagnostics record status/counts/time, never input/context/model text.

### `MemoryView`

Native `List`, `NavigationStack`, `Form`, `Picker`, `TextField`, `TextEditor`, sheets and confirmation dialogs provide Memory search, detail, editing and lifecycle actions. A History sheet can create a new entry or link its Capture to an existing active entry. Source links show the saved Capture's text and source app/date. The UI distinguishes manual creation, unavailable source Captures, archived records and superseded records.

### Memory Candidates

`MemoryExtractionInput` prefers nonempty saved `finalText`, using `recognizedText` only when no final text exists. `MemoryStore` reads a separate committed context and compares it with the authoritative Capture context before extraction. Unsaved text, recording, running refinement and deleted sources are rejected. M-005 saves refined output before this boundary while preserving recognized text separately, implementing the owner's 2026-09-18 requirement. A skipped/failed refinement is identified as original text kept.

`MemoryCandidateExtractor` uses only `SystemLanguageModel.default`, a fresh `LanguageModelSession`, and `@Generable` output for up to three Vocabulary/Project suggestions. The current SDK's token-count/context-size APIs bound the complete prompt, instructions, schema and response; oversized input is refused rather than truncated. Default Apple guardrails remain enabled. The source is treated as data, not instructions. Each suggestion needs a literal supporting quote containing its name, explicitly present aliases and a finite model confidence estimate of at least 0.8. Invalid/duplicate suggestions are filtered. That estimate is not a calibrated accuracy guarantee; human review is required.

`MemoryExtractionRecord` persists the exact text/type used, including saved refined final text, together with candidates and pending/accepted/dismissed decisions. A successful empty extraction is persisted too. Repeating analysis of the same saved text reuses its result and preserves review decisions. Changed input gets a separate result; stale pending candidates cannot be confirmed. Accepted Memory records retain source Capture IDs, the originating candidate ID and an optional unchanged suggestion confidence. User edits clear that model estimate. Linking to existing active Memory preserves its name/notes and confirmation metadata.

Candidate confirmation and Memory changes share the Memory write context and one save. Source existence and current text are rechecked before committing either extraction or review. Deleting a Capture deletes all its extraction snapshots in the same store save, while independently confirmed Memory remains. Existing Capture/Memory schema is used directly, without migrations or legacy reconstruction.

`MemoryCandidateController` owns one cancellable optional extraction. M-005 requests best-effort analysis after successful delivery/capture-only completion, or after a delivery failure that kept the final text on the clipboard. It never awaits extraction on the delivery path. History's **Find Memory Candidates** remains an explicit recovery action. Leaving that Capture detail or starting live input cancels analysis. Live Speech does not wait for model cancellation, and a late result cannot commit. Busy optional model work causes a skip; there is no durable queue or automatic retry. Foundation Models failure messages are fixed strings so prompts/output are not exposed through debug descriptions or logs. Model quality and cancellation latency remain device acceptance items.

History exposes progress/cancel, review/dismiss and the exact source snapshot using standard SwiftUI controls. The Memory list uses native `@Query` source changes to show only pending candidates whose text still matches; rendering does not issue a database fetch per candidate. Review can edit fields or link to an existing active entry. Confirmed AI-derived Memory also exposes the original extraction snapshot while the source Capture exists.

### `MorieTests`

The logic-only XCTest target compiles persistence, History recovery and the audio stream sources directly, without launching Morie or entering TCC. Tests use in-memory or unique temporary databases/audio directories. An explicit store URL defaults audio storage to the same temporary parent. A test-only diagnostics sink prevents tests from touching the running app's log. File recognition is replaced by an injected async closure for deterministic success/failure/cancellation tests. Audio stream tests write and decode real AAC using synthetic PCM and injected converter failures; native Speech, microphone lifecycle and playback interactions remain separate integration/device checks.

Memory tests use those isolated containers and native NaturalLanguage tokenization. They cover restart durability, explicit provenance, normalization/conflicts, source readiness, lifecycle exclusion, replacement, scoped deletion and deterministic bounded retrieval. No model inference or production data is used.

Candidate tests inject model output and delayed results to cover final-text priority, committed snapshots/restart, explicit confirmation/dismissal, source evidence filtering, conflicts/linking, changed/deleted sources, cancellation, live-input preemption, empty-result reuse and failure privacy. The real Foundation Models implementation is compiled, but these deterministic tests do not establish inference quality or runtime availability.

Personalization tests add grounded edit validation, durable input/final ordering, retained refinement provenance after Speech retry, source/Memory changes during inference, storage failures and interrupted recovery. A model stub that deliberately ignores cancellation proves caller deadlines/cancellation, no overlap and rejection of late results. Automatic candidates are verified to use saved final text and still require review. These tests do not invoke a real model or the target-app delivery path.

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
