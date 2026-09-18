# M-003 — Durable Capture

## Status

- **State:** IN PROGRESS
- **Phase:** Phase 1
- **Starts after:** M-002 macOS Input Foundation reaches an acceptable stable baseline

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

## Progress

| Subtask | Status | Notes |
| --- | --- | --- |
| SwiftData Capture schema | IMPLEMENTED / VERIFY | `CaptureRecord` stores stable identity, timestamps, lifecycle, recognized/final text, delivery mode, source app/bundle, original window identity and delivery error. No uniqueness constraint or non-Apple dependency. |
| Capture-first local store | IMPLEMENTED / VERIFY | A voice Capture is synchronously saved before Speech starts; progressive text is checkpointed at most every 500 ms, then final recognition and delivery state update the same record. Explicit cancellation and an empty final transcript remove the in-progress record; empty persisted leftovers are pruned when the store opens. |
| Input-loop integration | IMPLEMENTED / VERIFY | Capture UUID is shared with the Phase 0 session UUID. Storage initialization failure blocks capture rather than silently running without durability. |
| Native management window / History | IMPLEMENTED / VERIFY | One native `Window` + `NavigationSplitView` contains History, Settings, and Diagnostics. The SwiftData container is attached at the window root before History's `@Query` is constructed, keeping the initial History layout consistent; the menu-bar panel has one `Open Morie` entry instead of separate management destinations. |
| App Context | IN PROGRESS | Source app name, bundle identifier and original window number are stored. Window title collection remains excluded until a minimal privacy-safe requirement is approved. |
| Source audio / retry | IMPLEMENTED / VERIFY | Replacement owns one `AVCaptureAudioDataOutput`; the same PCM buffers feed `AnalyzerInputConverter` and streamed `AVAudioFile` AAC encoding. Empty/failed recognition retains finalized audio. Owner-hardware start/stop, playback and repeated-capture validation remains open. |
| Audio retention | IMPLEMENTED / VERIFY | Default 7 days with a 1–365 day Settings control. Expiry removes the M4A asset without deleting Capture text/history metadata. |
| Tests | IMPLEMENTED / PASS | Logic-only XCTest target covers delivered, delivery-failed, operational-failed and explicit-cancel paths plus persistence across store recreation. Tests use in-memory or unique temporary stores and do not launch Morie. |
| iCloud/CloudKit | TODO | Requires the real container, entitlements, account/capability handling and sync validation. Local configuration explicitly uses `.none`; it does not pretend CloudKit is active. |

Isolated macOS 27 Debug compilation passed using temporary DerivedData, without overwriting the owner's Xcode-run product. All five CaptureStore tests passed on 2026-09-17.

## Implementation notes

- The persistent entity is `CaptureRecord`; voice is represented as a source of Capture rather than the domain root.
- The authoritative session UUID is also the Capture UUID, avoiding a second identity mapping during the input loop.
- Local persistence uses SwiftData with an explicit non-CloudKit configuration until the real iCloud container exists.
- The first durable write occurs before `SpeechPipeline.start`. Progressive recognized text is checkpointed with a bounded 500 ms cadence to avoid a disk save for every character callback.
- Delivery success/failure and operational failure are durable terminal states. User cancellation is an explicit discard and removes the active record.
- `CaptureStore` accepts an explicit file URL for isolated restart testing; production continues to use SwiftData's default local application store.
- The menu-bar panel remains compact. History, Settings, Diagnostics, and future management destinations are organized in the standard sidebar of one Morie window.

## Validation evidence

- `xcodebuild -scheme MorieTests ... test`: 5 tests passed on macOS 27 / Xcode 27 using `/tmp/morie-derived-data.o30wQv`.
- `xcodebuild -scheme Morie ... build`: succeeded with signing disabled using `/tmp/morie-derived-data.0FA3Lq`.
- Management-window restructuring compiled successfully with signing disabled using `/tmp/morie-derived-data.2ZXLp8`.
- Runtime History and capture-first behavior still require owner validation from the normal Xcode-signed launch.
- 2026-09-18 real-device crash evidence: incident `F160F627-871F-4F35-A880-74BAFBE55D67` terminates in `AVCaptureAudioFileOutput.startRecording` immediately after `CaptureInputSequenceProvider` creation. The unsafe implementation was reverted in commits `37c7877` and `dd7c782`; strict Swift 6 type-check passes after restoration.
- The replacement single-output implementation passes Swift 6 complete-concurrency type checking and 7 logic tests. Microphone/Speech/AAC behavior still requires the normal Xcode-launched real-device run.

## Known design constraints

- Private Mode is not Device Only; iCloud/CloudKit is part of the intended long-term data path.
- Capture is the core model; Voice is only one source.
- Window title/context collection must remain minimal and intentional rather than expanding into passive surveillance.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- [`../architecture.md`](../architecture.md)
- predecessor: [`M-002-macos-input-foundation.md`](./M-002-macos-input-foundation.md)
