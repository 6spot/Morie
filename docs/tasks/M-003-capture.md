# M-003 — Durable Capture

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Phase:** Phase 1
- **Starts after:** M-002 macOS Input Foundation reaches an acceptable stable baseline
- **Owner sequencing decision (2026-09-18):** finish the single-Mac input/dictionary/Memory loop before cross-device work. CloudKit is outside this task and the current milestone, not a local-persistence blocker. No Team ID or container is requested.

## Current UI/setup behavior — M-010, 2026-09-18

[M-010](M-010-macos-native-setup.md) translates History/recovery copy and adds read-only setup inspection. Refresh no longer interrupts a Capture; explicit setup completion is blocked during input. No persisted model, database path or retention rule changes. The completed owner-approved development reset and verified backup below remain unchanged.

## Why

Morie must give every intentional user expression a durable recovery anchor before optional processing. The minimal Capture shell and audio destination are that boundary. Derived recognition/refinement/delivery state should become durable without forcing ordinary current-app input to wait for History I/O.

## Scope

Planned:

- shared `Capture` data model;
- durable local Capture storage;
- raw/recognized/final content states;
- source application/context fields;
- delivery mode (`currentApp` / `captureOnly`);
- basic History UI;
- App Context persistence;
- compressed source-audio preservation and re-recognition, defaulting to 7-day retention with a configurable day-based policy.

Excluded:

- automatic Memory learning (owned by M-004/M-009);
- iCloud/CloudKit provisioning, account gating and sync validation (later cross-device milestone);
- knowledge graph;
- iOS client;
- Morie cloud backend.

## Acceptance criteria

1. The minimal intentional Capture shell and audio destination are durably written before Speech/enrichment starts; later derived History state may persist asynchronously.
2. AI/enrichment failure cannot lose the raw Capture.
3. History can inspect saved captures.
4. Retained source audio can be played and explicitly re-recognized from History using native Apple APIs/UI.
5. Retry failure, empty output, cancellation, and late completion cannot erase saved text/audio or change an original delivery outcome.
6. Starting live capture stops History playback and cancels pending re-recognition before microphone capture begins.
7. Expiry removes the recording while preserving the History row and its metadata, including failed empty captures.
8. The History window can start a `captureOnly` voice recording. Its mode is saved before Speech starts; successful completion saves text/audio without target-app focus restoration, injection or clipboard changes.
9. Both entry points share finish/cancel, empty-result recovery and History preemption. An in-app capture reports “已保存”; a later global-shortcut capture still uses `currentApp` delivery.
10. Capability recheck, shortcut loss, microphone interruption and Speech failure stop native recording and preserve available source audio/text as a failed Capture. Late results must not inject or override capability status.
11. Explicit user cancellation closes native recording and awaits outstanding work before deleting the Capture and its file. New recording cannot begin during teardown.
12. Speech conversion/flush failure still finalizes already-written AAC. Repeated teardown is idempotent, and an already-dispatched delivery keeps its actual outcome.
13. After the initial recovery shell, normal `currentApp` input does not await SwiftData History writes before cleanup, paste dispatch, or success feedback. `captureOnly` waits for its latest final snapshot before reporting “已保存”.

## Progress

| Subtask | Status | Notes |
| --- | --- | --- |
| SwiftData Capture schema | IMPLEMENTED / VERIFY | `CaptureRecord` stores stable identity, timestamps, lifecycle, recognized/final text, delivery mode, source app/bundle, original window identity and delivery error. No uniqueness constraint or non-Apple dependency. |
| Capture-first local store | IMPLEMENTED / VERIFY | A minimal voice Capture shell and audio filename are synchronously saved before Speech starts. Later progressive/final/refinement/delivery snapshots are queued to a separate revisioned persistence writer; progressive checkpoints remain bounded to at most every 500 ms. Explicit cancellation uses a tombstone revision. Empty results preserve uncertain audio, and interrupted audio/text can be recovered on restart. Ambient-noise classification remains open. |
| Input-loop integration | IMPLEMENTED / VERIFY | Capture UUID is shared with the Phase 0 session UUID. Storage initialization failure blocks capture rather than silently running without durability. |
| Interruption versus discard | IMPLEMENTED / VERIFY | One shutdown task closes native recording and joins startup/finalization before disposition. Operational failures preserve text/audio; only explicit cancellation discards. Live Speech/capture-session errors trigger cleanup, and late results cannot deliver. AAC error-path tests pass; real microphone, timing and notification validation remains open. |
| Capture-only voice entry | IMPLEMENTED / VERIFY | History's native **Record Capture** toolbar action starts the shared audio pipeline with a durably stored `captureOnly` destination. Unlike current-app delivery, completion explicitly flushes the newest final snapshot before releasing active ownership and reporting “已保存”. It never enters text delivery. Finish/cancel use the existing HUD or shortcut. Interaction validation remains open. |
| Native management window / History | IMPLEMENTED / VERIFY | Native management window with selectable `List` and a simultaneous reading detail, reorganized by [M-008](./M-008-macos-management-ui.md). Details show recognition/original output, native AVKit playback, Copy actions, explicit failures, and deletion with system confirmation. Device interaction validation remains open. |
| App Context | IN PROGRESS | Source app name, bundle identifier and original window number are stored. Window title collection remains excluded until a minimal privacy-safe requirement is approved. |
| Source audio / retry | IMPLEMENTED / VERIFY | Single-output AAC capture remains in place. File retry uses `SpeechAnalyzer.analyzeSequence(from:)`; results save only on success and original delivered output stays intact. Generated Chinese AAC, silent-file and missing-file native checks passed. Interactive retry/cancel and live-capture preemption still require device validation. |
| Empty-result classification | IN PROGRESS | Removed the amplitude-only “five buffers above −50 dB” speech decision. No input/zero signal can be discarded; nonzero uncertain audio is retained with an explicit failed-recognition state and History recovery actions. Quiet speech versus ambient noise still needs owner-device evidence. |
| Audio retention | IMPLEMENTED / VERIFY | Default 7 days, configurable 1–365 days. Expiry preserves text, failed rows, duration and expiry metadata. Checks run on startup, capture, settings changes and History access, including an open detail's expiry deadline. |
| Tests | IMPLEMENTED / PASS | 31 tests cover native AAC conversion/flush failure and immediate stop, restart preservation, explicit discard, persistence/modes, History retry/cancellation/preemption, expiry/missing files, and scoped deletion. Temporary databases/audio and a test-only diagnostics sink isolate the running app. |

Isolated macOS 27 Debug compilation passed using temporary DerivedData, without overwriting the owner's Xcode-run product. All five CaptureStore tests passed on 2026-09-17.

## Implementation notes

- The persistent entity is `CaptureRecord`; voice is represented as a source of Capture rather than the domain root.
- M-009's current schema adds `DictionaryEntry`, `MemoryRecord`, `MemoryAnalysisRecord` and `MemoryLearningBlock` to the Capture container. Dictionary and personal Memory write through separate contexts and cannot roll back Capture checkpoints. Current implementation is direct, with no migrations from the superseded candidate schema.
- `recognizedText`, final text and exact dictionary/context/cleanup provenance remain separate in the Capture model, but current-app delivery no longer waits for those derived fields to commit. Live state is snapshotted to the ordered background writer; Memory learning waits for a post-delivery flush. `captureOnly` remains save-first. Deleting a Capture removes its analysis source snapshots; separate Memory remains. History retries preserve completed final output and its actual earlier provenance. See [M-009](M-009-macos-input-memory.md) for current evidence and remaining model/device acceptance.
- The authoritative session UUID is also the Capture UUID, avoiding a second identity mapping during the input loop.
- Capture creation requires an explicit delivery mode. The shortcut supplies `currentApp`; History's **Record Capture** supplies `captureOnly` and records Morie as the source without reading another app's window identity. Recognition completion returns the persisted mode, so the controller's delivery decision does not depend on whichever app is frontmost at finish time.
- Capture-only success is terminal at the recognition save. The same record becomes available to History playback/retry without a delivery step, and a late cancellation cannot discard it. The HUD reports saved versus inserted using the corresponding mode.
- Local persistence uses SwiftData with an explicit non-CloudKit configuration throughout this single-Mac milestone.
- The first durable shell write occurs before `SpeechPipeline.start`. After that point `CaptureStore` keeps main-context autosave disabled. Progressive recognized text is snapshotted with a bounded 500 ms cadence and written by `CapturePersistenceWriter`, so Speech callbacks do not perform disk saves.
- Delivery success/failure and operational failure remain terminal History states, but current-app terminal commits are asynchronous after the delivery decision. User cancellation is an explicit discard; its tombstone revision prevents older queued snapshots from restoring the record.
- Capability recheck and hotkey loss previously reused destructive cancellation. They now retain a failed Capture. The controller claims shutdown ownership before awaiting native work, cancels outstanding startup/finalization, closes the writer, accepts any final snapshot, and only then persists failure or explicit discard. Checking/blocked states cannot be replaced by a cancelled task's Ready transition.
- `CaptureAudioStream` owns AAC writing and analyzer inputs behind the source's serial output queue. Conversion and flush errors end analysis but always close the file; repeated completion and immediate stop cannot remove or append to the artifact. Speech teardown returns text/audio without deleting files.
- `SpeechPipeline` observes live analyzer/result failures. AVFoundation runtime-error/interruption notifications fail the input stream and trigger controller cleanup. An ownership check after async converter creation prevents cancelled startup from opening a later source.
- A result arriving during teardown is saved without initiating delivery. `TextInjector` checks cancellation before activation and after focus handoff; paste dispatch has no suspension point. A delivery already dispatched still records `delivered`, and later interruption cannot overwrite that terminal outcome.
- `CaptureStore` accepts an explicit file URL for isolated restart testing; production continues to use SwiftData's default local application store.
- M-010 uses a native menu-bar menu and Chinese management labels. History, Dictionary, Personal Memory and Diagnostics share the management sidebar; Settings and permission setup open their native windows.
- History retry is explicit and cancellable. It reads the saved file without microphone capture, changes the same Capture only after successful recognition, and never injects or changes the clipboard automatically.
- Successful recovery of a failed Capture saves recognized/final text and changes its state to `recognized`. For previously delivered/delivery-failed Captures, only recognized text and retry metadata change; the original output and delivery state remain available.
- Retry errors use the new optional `lastRecognitionAttemptAt` / `lastRecognitionErrorDescription` fields. Failed/empty/cancelled retries leave prior text and source audio intact.
- New live input pauses the History player, cancels file recognition, and awaits its shutdown before Speech startup. A cancelled file task checks cancellation before any persistence mutation, even if a native operation returns a late result.
- AVKit's `AVPlayerView` supplies playback controls. Now Playing metadata is disabled for private recordings; selection/navigation changes release the player.
- Expired audio no longer clears the evidence needed to keep an empty failed History row across subsequent launches. Store startup recovers current-version interrupted audio/checkpoints using the filename saved before capture.
- Owner clarification: this is a development-stage product with no legacy compatibility requirement. This slice does not add old-schema migration or reconstruct missing metadata from earlier implementations.
- Type4Me #311 (`cc56207b`) confirms the useful distinction between cancellation, earlier transcript evidence, and a normal empty result. Morie adapts those invariants and drops Type4Me's provider retry machinery. Apple's `SpeechDetector` documentation warns that it gates transcription and can drop speech, so it is not inserted into the established live path merely to classify silence.

## Validation evidence

- `xcodebuild -scheme MorieTests ... test`: 5 tests passed on macOS 27 / Xcode 27 using `/tmp/morie-derived-data.o30wQv`.
- `xcodebuild -scheme Morie ... build`: succeeded with signing disabled using `/tmp/morie-derived-data.0FA3Lq`.
- Management-window restructuring compiled successfully with signing disabled using `/tmp/morie-derived-data.2ZXLp8`.
- Runtime History and capture-first behavior still require owner validation from the normal Xcode-signed launch.
- 2026-09-18 real-device crash evidence: incident `F160F627-871F-4F35-A880-74BAFBE55D67` terminates in `AVCaptureAudioFileOutput.startRecording` immediately after `CaptureInputSequenceProvider` creation. The unsafe implementation was reverted in commits `37c7877` and `dd7c782`; strict Swift 6 type-check passes after restoration.
- The replacement single-output implementation passes Swift 6 complete-concurrency type checking and 8 logic tests.
- Owner hardware confirmed on 2026-09-18 that normal Chinese voice input still works and M4A source files are created after the single-output replacement.
- Owner hardware also reproduced two empty transcripts retained as `failed` (`CBCA4A24`, `5B073CAE`) because the current signal threshold classified their audio as meaningful. Empty-record classification is explicitly deferred rather than accepted as complete.
- 2026-09-18 History recovery implementation: final isolated Debug app build passed with Xcode 27.0 / SDK 27.0. Build log: `/tmp/morie-history-build.uRUQIr/final-build.log`. The build did not replace or launch the owner's signed app.
- Final logic suite passed **20 tests, 0 failures, 0 skipped** on macOS 27.0 (`26A428`), arm64 MacBook Pro. Result bundle: `/tmp/morie-history-tests.IqCV2m/HistoryTestsFinal.xcresult`, confirmed with `xcresulttool get test-results summary`. Tests do not launch Morie or touch its production database, audio directory, clipboard, or log.
- Native file-recognition smoke passed with generated Chinese speech encoded by Apple's tools as mono AAC at 16 kHz / 32 kbps. `CaptureFileTranscriber` returned the spoken Chinese sentence; a silent M4A produced an explicit empty-recognition error, and a missing file was rejected. Harness and log: `/tmp/morie-history-native.rn38T5/HistoryAudioSmoke.swift` and `/tmp/morie-history-native.rn38T5/smoke.log`. This checks file analysis, not microphone input or recognition accuracy across real recordings.
- Offscreen `NSHostingView` rendering exercised the native Capture detail using synthetic data and a temporary store: `/tmp/morie-history-native.rn38T5/HistoryCaptureDetail.png`. The product retains AVKit's inline controls; offscreen rendering does not establish Liquid Glass compositing, interactive playback or accessibility acceptance.
- `git diff --check` passed. No external dependency, legacy format migration or old-platform fallback was introduced.
- 2026-09-18 capture-only follow-up: isolated Debug app build passed (`/tmp/morie-history-build.uRUQIr/capture-only-build.log`). All **24 tests passed, 0 failed, 0 skipped**; result bundle `/tmp/morie-history-tests.IqCV2m/CaptureOnlyTests.xcresult` was confirmed with `xcresulttool`. New coverage checks durable mode before recognition, terminal capture-only completion/restart, current-app ownership until delivery, capture-only cancellation and retry destination preservation.
- The capture-only History toolbar and detail were rendered offscreen with synthetic data at `/tmp/morie-history-native.rn38T5/CaptureOnlyHistory.png` and `CaptureOnlyDetail.png`. The native toolbar exposes **Record Capture**, and the completed detail shows **Destination: History / Saved**. This is layout evidence; microphone, clipboard/focus and interactive accessibility acceptance remain open.
- 2026-09-18 interruption preservation: isolated Debug app compilation passed with Xcode 27 / SDK 27 (`/tmp/morie-interruption-build.NcWvBS/final-build.log`). All **31 tests passed, 0 failed, 0 skipped**, confirmed with `xcresulttool get test-results summary` for `/tmp/morie-interruption-tests.UkSTyr/FinalInterruptionTests.xcresult`; test log `/tmp/morie-interruption-tests.UkSTyr/final-tests.log`. Seven new tests use real native AAC encoding/decoding to cover conversion failure, flush failure, immediate stop, repeated finalization, injected runtime interruption, text/audio/mode survival across store recreation, and explicit discard. Delivery storage coverage also verifies that a late interruption does not overwrite a completed dispatch.
- Interruption validation used only synthetic PCM and temporary stores/files, without launching Morie, opening a microphone, or touching production Captures/clipboard/logs. `git diff --check` passed. Real capture-session notifications, controller timing and cross-app interruption behavior remain in the device matrix.

## Known issues / follow-up

- Quiet-room silence versus audible recognition failure remains unvalidated. Current automatic discard only covers no input/zero signal without prior transcript evidence. Uncertain recordings stay available for playback, re-recognition or explicit deletion; do not claim the ambient-noise false-positive cases are fixed.
- Validate the History playback/seek, native retry/cancel, live-capture preemption, navigation/window cleanup, expiry and deletion flows from the normal Xcode-signed app. Logic tests are not device UI/ASR acceptance.
- Validate **Record Capture** with both HUD and shortcut finish, Escape cancellation, switching apps before finishing, repeated `captureOnly`/`currentApp` captures, and an unchanged clipboard/focus for capture-only completion.
- Validate read-only setup refresh during startup, recording and finalization: it must leave input intact. Separately validate shortcut loss/microphone interruption, rapid restart and focus-handoff interruption. M-010 removes the former recheck-driven interruption; native AAC tests do not establish controller scheduling or device-notification behavior. See the updated [M-003 matrix](../validation.md#m-003-interruption-and-discard).
- Unexpected process termination or storage failure may leave incomplete M4A files; History preserves them and reports playback/recognition errors rather than claiming every interrupted recording is decodable.
- App Context remains partial. CloudKit is deferred to a separately scheduled cross-device milestone after the Mac loop works; enrollment/container setup and sync acceptance are not requirements for completing local Capture work.

## Known design constraints

- Private Mode is not Device Only; iCloud/CloudKit is part of the intended long-term data path.
- CloudKit will use each user's own iCloud private database within Morie's app container. Developer provisioning identifies and authorizes the app; it does not create a shared Morie user-data service or require end users to hold developer accounts.
- Capture is the core model; Voice is only one source.
- Window title/context collection must remain minimal and intentional rather than expanding into passive surveillance.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- [`../architecture.md`](../architecture.md)
- predecessor: [`M-002-macos-input-foundation.md`](./M-002-macos-input-foundation.md)
