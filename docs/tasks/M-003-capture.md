# M-003 — Durable Capture

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-18
- **Phase:** Phase 1
- **Starts after:** M-002 macOS Input Foundation reaches an acceptable stable baseline
- **Owner sequencing decision (2026-09-18):** defer iCloud/CloudKit sync to the final integration stage. The owner has not enrolled in an Apple Developer account/program. Continue local development without waiting for a Team ID or container.

## Why

Morie must make every intentional user expression durable before optional AI processing. Phase 1 establishes the persistence boundary that later Memory and personalization depend on.

## Scope

Planned:

- shared `Capture` data model;
- durable local Capture storage;
- raw/recognized/final content states;
- source application/context fields;
- delivery mode (`currentApp` / `captureOnly`);
- basic History UI;
- App Context persistence;
- real iCloud/CloudKit container and entitlements;
- CloudKit sync semantics;
- iCloud/CloudKit capability check as part of full Private Mode readiness.
- compressed source-audio preservation and re-recognition, defaulting to 7-day retention with a configurable day-based policy.

Excluded:

- full Memory extraction;
- knowledge graph;
- iOS client;
- Morie cloud backend.

## Acceptance criteria

1. Intentional Capture is durably written before optional enrichment.
2. AI/enrichment failure cannot lose the raw Capture.
3. History can inspect saved captures.
4. iCloud/CloudKit is configured against a real container, not a placeholder.
5. Private Mode readiness includes the required iCloud/CloudKit availability state.
6. Sync semantics are documented and tested for the macOS client.
7. Retained source audio can be played and explicitly re-recognized from History using native Apple APIs/UI.
8. Retry failure, empty output, cancellation, and late completion cannot erase saved text/audio or change an original delivery outcome.
9. Starting live capture stops History playback and cancels pending re-recognition before microphone capture begins.
10. Expiry removes the recording while preserving the History row and its metadata, including failed empty captures.
11. The History window can start a `captureOnly` voice recording. Its mode is saved before Speech starts; successful completion saves text/audio without target-app focus restoration, injection or clipboard changes.
12. Both entry points share finish/cancel, empty-result recovery and History preemption. An in-app capture reports “已保存”; a later global-shortcut capture still uses `currentApp` delivery.
13. Capability recheck, shortcut loss, microphone interruption and Speech failure stop native recording and preserve available source audio/text as a failed Capture. Late results must not inject or override capability status.
14. Explicit user cancellation closes native recording and awaits outstanding work before deleting the Capture and its file. New recording cannot begin during teardown.
15. Speech conversion/flush failure still finalizes already-written AAC. Repeated teardown is idempotent, and an already-dispatched delivery keeps its actual durable outcome.

## Progress

| Subtask | Status | Notes |
| --- | --- | --- |
| SwiftData Capture schema | IMPLEMENTED / VERIFY | `CaptureRecord` stores stable identity, timestamps, lifecycle, recognized/final text, delivery mode, source app/bundle, original window identity and delivery error. No uniqueness constraint or non-Apple dependency. |
| Capture-first local store | IMPLEMENTED / VERIFY | A voice Capture and audio filename are saved before Speech starts; progressive text is checkpointed at most every 500 ms. Explicit cancellation discards the record. Empty results preserve uncertain audio, and interrupted audio/text can be recovered on restart. Ambient-noise classification remains open. |
| Input-loop integration | IMPLEMENTED / VERIFY | Capture UUID is shared with the Phase 0 session UUID. Storage initialization failure blocks capture rather than silently running without durability. |
| Interruption versus discard | IMPLEMENTED / VERIFY | One shutdown task closes native recording and joins startup/finalization before disposition. Operational failures preserve text/audio; only explicit cancellation discards. Live Speech/capture-session errors trigger cleanup, and late results cannot deliver. AAC error-path tests pass; real microphone, timing and notification validation remains open. |
| Capture-only voice entry | IMPLEMENTED / VERIFY | History's native **Record Capture** toolbar action starts the shared audio pipeline with a durably stored `captureOnly` destination. Completion saves a terminal `recognized` record, releases active ownership and reports “已保存”, without entering text delivery. Finish/cancel use the existing HUD or shortcut. Interaction validation remains open. |
| Native management window / History | IMPLEMENTED / VERIFY | Native management window plus `List`/`NavigationStack`/`Form` Capture details. Details show recognition/original output, native AVKit playback, Copy actions, explicit failures, and deletion with system confirmation. Device interaction validation remains open. |
| App Context | IN PROGRESS | Source app name, bundle identifier and original window number are stored. Window title collection remains excluded until a minimal privacy-safe requirement is approved. |
| Source audio / retry | IMPLEMENTED / VERIFY | Single-output AAC capture remains in place. File retry uses `SpeechAnalyzer.analyzeSequence(from:)`; results save only on success and original delivered output stays intact. Generated Chinese AAC, silent-file and missing-file native checks passed. Interactive retry/cancel and live-capture preemption still require device validation. |
| Empty-result classification | IN PROGRESS | Removed the amplitude-only “five buffers above −50 dB” speech decision. No input/zero signal can be discarded; nonzero uncertain audio is retained with an explicit failed-recognition state and History recovery actions. Quiet speech versus ambient noise still needs owner-device evidence. |
| Audio retention | IMPLEMENTED / VERIFY | Default 7 days, configurable 1–365 days. Expiry preserves text, failed rows, duration and expiry metadata. Checks run on startup, capture, settings changes and History access, including an open detail's expiry deadline. |
| Tests | IMPLEMENTED / PASS | 31 tests cover native AAC conversion/flush failure and immediate stop, restart preservation, explicit discard, persistence/modes, History retry/cancellation/preemption, expiry/missing files, and scoped deletion. Temporary databases/audio and a test-only diagnostics sink isolate the running app. |
| iCloud/CloudKit | TODO | Owner explicitly deferred sync to the final integration stage on 2026-09-18 because the Apple Developer account/program is not yet set up. It does not block current local work. Later integration requires a real Development Team and container, entitlements, account/capability handling and sync validation. Local configuration remains `.none`. |

Isolated macOS 27 Debug compilation passed using temporary DerivedData, without overwriting the owner's Xcode-run product. All five CaptureStore tests passed on 2026-09-17.

## Implementation notes

- The persistent entity is `CaptureRecord`; voice is represented as a source of Capture rather than the domain root.
- The authoritative session UUID is also the Capture UUID, avoiding a second identity mapping during the input loop.
- Capture creation requires an explicit delivery mode. The shortcut supplies `currentApp`; History's **Record Capture** supplies `captureOnly` and records Morie as the source without reading another app's window identity. Recognition completion returns the persisted mode, so the controller's delivery decision does not depend on whichever app is frontmost at finish time.
- Capture-only success is terminal at the recognition save. The same record becomes available to History playback/retry without a delivery step, and a late cancellation cannot discard it. The HUD reports saved versus inserted using the corresponding mode.
- Local persistence uses SwiftData with an explicit non-CloudKit configuration until the real iCloud container exists.
- The first durable write occurs before `SpeechPipeline.start`. Progressive recognized text is checkpointed with a bounded 500 ms cadence to avoid a disk save for every character callback.
- Delivery success/failure and operational failure are durable terminal states. User cancellation is an explicit discard and removes the active record.
- Capability recheck and hotkey loss previously reused destructive cancellation. They now retain a failed Capture. The controller claims shutdown ownership before awaiting native work, cancels outstanding startup/finalization, closes the writer, accepts any final snapshot, and only then persists failure or explicit discard. Checking/blocked states cannot be replaced by a cancelled task's Ready transition.
- `CaptureAudioStream` owns AAC writing and analyzer inputs behind the source's serial output queue. Conversion and flush errors end analysis but always close the file; repeated completion and immediate stop cannot remove or append to the artifact. Speech teardown returns text/audio without deleting files.
- `SpeechPipeline` observes live analyzer/result failures. AVFoundation runtime-error/interruption notifications fail the input stream and trigger controller cleanup. An ownership check after async converter creation prevents cancelled startup from opening a later source.
- A result arriving during teardown is saved without initiating delivery. `TextInjector` checks cancellation before activation and after focus handoff; paste dispatch has no suspension point. A delivery already dispatched still records `delivered`, and later interruption cannot overwrite that terminal outcome.
- `CaptureStore` accepts an explicit file URL for isolated restart testing; production continues to use SwiftData's default local application store.
- The menu-bar panel remains compact. History, Settings, Diagnostics, and future management destinations are organized in the standard sidebar of one Morie window.
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
- Validate capability recheck/shortcut loss/microphone interruption during startup, recording and finalization, including rapid restart and interruption during focus handoff. Native AAC tests do not establish controller scheduling or device-notification behavior.
- Unexpected process termination or storage failure may leave incomplete M4A files; History preserves them and reports playback/recognition errors rather than claiming every interrupted recording is decodable.
- App Context remains partial. Per the owner's sequencing decision, resume CloudKit only at the final integration stage after Apple Developer enrollment and container setup. Do not request configuration IDs during the current local-development work.

## Known design constraints

- Private Mode is not Device Only; iCloud/CloudKit is part of the intended long-term data path.
- CloudKit will use each user's own iCloud private database within Morie's app container. Developer provisioning identifies and authorizes the app; it does not create a shared Morie user-data service or require end users to hold developer accounts.
- Capture is the core model; Voice is only one source.
- Window title/context collection must remain minimal and intentional rather than expanding into passive surveillance.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- [`../architecture.md`](../architecture.md)
- predecessor: [`M-002-macos-input-foundation.md`](./M-002-macos-input-foundation.md)
