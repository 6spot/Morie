# Development Guide

## Requirements

Current Phase 0 development baseline:

- Apple Intelligence-capable Mac
- macOS 27+
- latest Xcode compatible with the macOS 27 SDK
- Swift toolchain shipped with that Xcode
- Apple Developer signing identity/team for normal local signing where required

Morie intentionally does not support older Macs by adding alternate ASR/LLM runtimes.

## Open and build

1. Clone `https://github.com/6spot/Morie.git`.
2. Create or check out a task branch from current `main`.
3. Open `Morie.xcodeproj` in Xcode.
4. Select the `Morie` target.
5. Configure your Development Team if Xcode requests signing configuration.
6. Build and run on a supported Mac.

The macOS app bundle identifier is `me.morie.mac`. Privacy permissions are associated with this identifier and the current local signing identity.

The target enables Hardened Runtime and signs with `Morie/Morie.entitlements`. The Apple audio-input entitlement is required in addition to `NSMicrophoneUsageDescription`; without it, macOS can reject `AVCaptureDevice.requestAccess(for: .audio)` immediately without presenting consent.

Command-line compile validation must use isolated temporary DerivedData so it cannot overwrite the signed app used by an active Xcode session:

```bash
validation_dir="$(mktemp -d /tmp/morie-derived-data.XXXXXX)"
xcodebuild \
  -project Morie.xcodeproj \
  -scheme Morie \
  -configuration Debug \
  -sdk macosx27.0 \
  -derivedDataPath "$validation_dir" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  build
```

Disabling signing here is for compile validation only; normal local launch/distribution follows the appropriate signing path. Never direct this unsigned build into the repository `build/Debug/Morie.app` while Xcode is running it, because changing the executable's signing identity can invalidate TCC permissions and make microphone behavior impossible to interpret.

iCloud/CloudKit integration is deferred to the final integration stage by the owner's 2026-09-18 decision. Apple Developer enrollment and a real container are not yet set up; do not wait for them to continue local Capture work. The current store explicitly disables sync. The eventual integration uses each user's own iCloud private database and does not change the V0 no-Morie-backend boundary. See [`deployment.md`](./deployment.md#cloudkit-deployment--phase-1).

## Unit tests

Run logic tests with their own temporary DerivedData directory:

```bash
validation_dir="$(mktemp -d /tmp/morie-derived-data.XXXXXX)"
xcodebuild \
  -project Morie.xcodeproj \
  -scheme MorieTests \
  -configuration Debug \
  -sdk macosx27.0 \
  -derivedDataPath "$validation_dir" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

`MorieTests` is a logic-only target: it does not launch the menu-bar app or exercise TCC. Capture persistence tests use in-memory storage or a unique temporary file and audio directory. History tests inject file-recognition results to exercise recovery and cancellation without models or microphone access. The target uses `TestDiagnostics.swift` rather than the product logger, so tests cannot truncate an active Xcode-run app's diagnostic log.

Audio stream tests use synthetic 16 kHz mono PCM and Apple's real AAC writer/decoder. They verify readable audio after conversion/flush failure, immediate stop, repeated finalization, restart preservation and explicit discard. Controller timing, capture-session notifications, microphone release and cross-app delivery still need the signed-app interruption checks in [`validation.md`](./validation.md#m-003-interruption-and-discard).

Memory tests use isolated SwiftData containers and native NaturalLanguage word tokenization to check explicit persistence, provenance, deduplication, lifecycle and bounded retrieval. Memory shares the container schema with Capture but writes through a separate `ModelContext`; there is no migration/legacy-store setup step.

Candidate tests inject structured suggestions or delayed async results. They exercise committed final-text snapshots, review decisions, filtering/conflicts, changed/deleted sources and cancellation without invoking Apple Intelligence. Product compilation includes the real Foundation Models structured-generation path. Model quality, context limits and latency must be exercised separately on disposable data.

Personalization tests inject edit proposals and models that ignore cancellation. They verify grounded corrections, punctuation/content protection, committed original/final ordering, retained context/input snapshots, History retry, source/Memory changes, save failures, restart recovery, deadline/cancellation and no late/overlapping work. They also verify that automatic candidates use the saved final text and require review. No actual model inference or delivery occurs in these tests.

## CI compile gate

`.github/workflows/macos-27-ci.yml` compiles product changes on GitHub's `xcode-27` hosted environment. `.github/workflows/macos-27-package.yml` creates the test artifact.

The CI gate exists to catch:

- current macOS 27 SDK signature drift;
- Swift 6 strict-concurrency errors;
- Xcode project/build-setting breakage;
- accidental product-source compile failures.

It is intentionally scoped to changes under `Morie/**`, `Morie.xcodeproj/**`, and the workflow itself. Documentation-only changes do not need another expensive macOS compile run.

CI is **not** runtime acceptance. A hosted build cannot prove real microphone/TCC behavior, physical hotkeys, focus restoration, app injection, Liquid Glass rendering, or latency/energy characteristics.

## Required permissions

Phase 0 may require:

- Microphone
- Speech Recognition
- Accessibility

The app should surface capability failures rather than silently degrading to a third-party or legacy implementation.

If permissions were denied during development, use macOS System Settings to restore access before retesting. When testing permission onboarding behavior itself, reset the relevant app permission state using normal macOS developer/test procedures.

Accessibility uses the macOS-owned consent prompt only; Morie does not stack a second modal over the system's Device Control and Data Access prompt. Microphone and Speech show native consent prompts while their TCC status is undetermined. If macOS returns denial without presenting consent, Morie shows one recovery alert with **Open System Settings**; after denial, macOS requires the user to re-enable access there. Denied permissions also remain visible in the menu-bar status. After changing a permission, choose **Recheck Capabilities** from the menu-bar panel.

The menu-bar panel also keeps an **Open System Settings** recovery action visible while a permission-backed capability is blocked; **Recheck Capabilities** cannot itself re-prompt a permission whose TCC status is already denied.

## Native diagnostics surface

Morie includes a native **Diagnostics** page in its management window.

Open the Morie management window from the menu-bar panel, then choose **Diagnostics** in its sidebar. The diagnostics surface uses a native Table with search and level filtering. Select an event to read its full message in the resizable detail area. It records the current process lifetime in memory.

It currently traces:

- launch/bootstrap start and Ready/blocked state;
- Apple Intelligence, Speech, microphone, Speech authorization, and Accessibility checks;
- configured global-shortcut event-tap installation, solo Fn candidate/release/chord rejection, accepted key events, repeats, and tap recovery;
- capture session identity and original target app/bundle identifier;
- Speech asset preparation, microphone/provider/analyzer lifecycle, partial/final result lengths, stop/cancel/failure;
- microphone meter channel count, average/peak power, normalized HUD level, and warnings when channels are missing or remain pinned at the floor;
- target activation and Accessibility insertion result;
- clipboard fallback, synthetic Cmd+V dispatch, and clipboard restoration result;
- native alerts and terminal session state.

Privacy rule: diagnostics do **not** record the full transcript by default. They record character counts and lifecycle/error metadata instead.

Diagnostics are also persisted for the current app launch at `~/Library/Logs/Morie/morie-debug.log`. The file is recreated at launch, **Clear Diagnostics…** asks for confirmation before truncating both the table and file, and **Show Log File** reveals it in Finder. This runtime file is outside the repository and must not be committed.

The window provides:

- **Copy All Events** — copy the complete current in-memory diagnostic log, including events outside the current search/filter;
- **Diagnostic Actions → Clear Diagnostics…** — confirm resetting the current log before reproducing a defect;
- **Diagnostic Actions → Show Log File** — reveal the current process log in Finder.

Recommended defect reproduction flow:

1. launch Morie;
2. open **Morie → Diagnostics**;
3. use **Clear Diagnostics…** if necessary;
4. focus the target text field in another app;
5. activate the configured shortcut (solo Fn release by default), speak, then activate it again to finish;
6. return to Morie → **Diagnostics** and use **Copy All Events**;
7. attach/paste the log with the observed behavior.

If no accepted Hotkey entry appears after the configured shortcut, diagnose the event-tap/shortcut path before investigating Speech or text injection. For Fn, distinguish `press began`, `solo release accepted`, and `candidate cancelled` entries. If Speech entries appear but no Delivery entries do, diagnose finalization/session lifecycle.

## Current manual smoke test

1. Launch Morie.
2. Confirm the menu bar item reaches `Ready` on a supported system.
3. Open **Morie → Diagnostics** and confirm bootstrap/capability/hotkey-install entries are present.
4. Place the caret in another application.
5. Press and release `Fn / Globe` once (or use the configured alternate binding).
6. Speak a short phrase.
7. Activate the same shortcut again to finish.
8. Verify the original app regains focus and receives the final text.
9. Verify the debug log contains the corresponding Hotkey → Session → Speech → Delivery path.
10. Repeat several times, including rapid toggles, `Escape` cancellation, HUD cancel/finish, and Chinese/English mixed content where relevant.
11. Verify the previous clipboard content is restored after clipboard fallback unless another app/user changed the clipboard meanwhile.

Also request finish and cancellation during startup/session setup: neither may allow a late orphaned microphone session afterward.

A successful smoke test is not the full acceptance test. Complete [`validation.md`](./validation.md) before Phase 0 is considered done.

## History recovery smoke test

From the normal Xcode-signed app, open **Morie → History** and select a Capture with unexpired audio:

1. Play, pause, and seek with the native recording controls; opening a detail must not autoplay.
2. Choose **Recognize Again**, then verify the saved recognition. Any original delivered output and delivery status remain visible; paste only occurs after an explicit Copy action and the user's paste.
3. Cancel a retry and immediately start a new Fn capture. History playback/retry must stop and the live capture must remain usable.
4. Try a failed/empty Capture. Empty or failed re-recognition preserves its previous text/audio and shows the failure; success makes recovered text available.
5. Switch sections/close the window during playback and retry. Check cleanup, then reopen and retry again.
6. Exercise expired/missing audio, change retention, and confirm that only the audio expires. Delete a disposable test Capture through the native confirmation dialog.

Use generated fixture audio and temporary stores for automated API checks. Never transcribe or delete production History as part of an automated smoke test.

## Capture-only voice smoke test

1. From **Open Morie → History**, choose **Record Capture** and speak an idea. Complete it with the HUD; verify “已保存”, **Destination: History**, saved text and playable audio.
2. Repeat with shortcut finish and Escape cancellation. Cancellation removes the unfinished Capture and audio.
3. Start in History, switch to another app and finish there. The saved idea must not be pasted, focus must not be restored elsewhere, and the clipboard must remain unchanged.
4. Alternate this entry with normal shortcut input into a disposable document. Each new shortcut capture must still deliver to its original app and report “已输入”.
5. Start while a History recording is playing or being re-recognized. The existing live-capture preemption must apply, and no second microphone session may start.

Mode persistence, terminal capture-only storage, cancellation and retry are covered by isolated logic tests. These checks do not replace the interactive clipboard/focus/microphone checks above.

## Memory smoke test

The owner deferred interactive device checks until the evening of 2026-09-18. When resuming validation:

1. Open **Memory → New Memory**, save a vocabulary entry and a project with aliases/notes, then relaunch and inspect them.
2. Open a completed History Capture → **Save Memory…**. Save a selective term/project, then link another Capture to that existing memory and inspect both sources.
3. Inspect History's related context with Chinese/English names and aliases. Archive a matched entry, then restore it; the related result should disappear/reappear.
4. Replace an entry. The new active record links to its predecessor, the old one reads **Superseded**, and stale context is excluded.
5. Confirm that duplicate names and invalid fields keep the editor open with an explanation. Cancel leaves saved records unchanged.
6. Delete a disposable source Capture, then a disposable Memory; independently saved Memory and source Capture data are retained respectively, with missing-source feedback where applicable.

See the full [Memory device checklist](./validation.md#m-004-memory-foundation). Offscreen rendering verifies layout only and does not complete these interaction checks.

## Memory Candidate smoke test

When evening device validation resumes, use a disposable Capture containing an explicitly described vocabulary term or project:

1. After completing a disposable input, inspect its automatically suggested candidates in History/Memory. If optional work was skipped, choose **Find Memory Candidates**. Review each supporting quote/**Text Used for Extraction**; it must match saved final text, including refined text when applied.
2. Edit and Save one suggestion, dismiss another, relaunch, and verify the decisions and source snapshot persist. Pending suggestions also appear in Memory.
3. Try a name already present in active Memory; validation must keep the sheet open so you can choose that existing entry. Linking adds provenance without replacing its notes.
4. Change the saved source through re-recognition where applicable. Old pending suggestions must not save; re-extraction should retain a new snapshot. Already delivered final output remains authoritative when re-recognition changes only recognized text.
5. Cancel during analysis, leave the detail, or begin voice input. A late model result must not create candidates; voice input must remain responsive.
6. Verify an empty result, unsupported/oversized input and model unavailability. The saved Capture remains intact and manual Memory remains available.
7. Delete the disposable Capture; its extraction snapshots disappear while separately confirmed Memory remains.

Do not run these against production History automatically. M-005 saves refined `finalText` before extraction and retains `recognizedText`; this requirement is recorded in its [task criteria](./tasks/M-005-personalization.md).

## Personalization smoke test

When evening validation resumes, use disposable data in the normal Xcode-signed app:

1. Save a project/vocabulary entry with an explicit recognition alias, for example **Morie** / **more e**. Enable **Settings → Use Memory to Refine Input**.
2. Capture a short natural phrase containing that alias. Inspect actual recognition first: correction only has evidence when the saved canonical name or an explicit alias matches. Compare **Final Text**, **Recognition**, **Changes**, **Text Before Refinement** and **Memory Considered**. Preserve wording, negation, tone, numbers and technical content.
3. Confirm the text delivered to a disposable target matches saved final text. Repeat via **Record Capture** and confirm no clipboard/focus/delivery change.
4. Review candidates after input completion. Their extraction snapshot must equal the final text actually saved. No candidate becomes Memory without confirmation.
5. Re-recognize the saved recording. Original refined final output and the refinement-input snapshot remain intact while the latest recognition changes independently.
6. Archive/edit the matching memory and repeat input; stale context must stop applying. Disable refinement and confirm original text is retained/used with a **Skipped** reason.
7. Recheck capabilities during refinement and immediately capture again afterward. There must be no late paste or stuck processing. Exercise timeout/unavailability and inspect the retained original; a draining model must not block a new recording.
8. Compare final-to-delivery latency with refinement enabled/disabled, and record applied/unchanged/skipped/timed-out/failed outcomes on representative Chinese/English samples. The 2-second model-wait budget is provisional and excludes storage/scheduling overhead.

These checks establish whether Memory improves input. Broader rewriting and correction/style learning remain follow-up rather than inferred success from deterministic tests.

## Management UI smoke test

M-008 keeps development on macOS. Use the normal Xcode-signed app and disposable data when the deferred interactive checks resume:

1. Open Morie and switch between History, Memory, Settings and Diagnostics. Resize the window and native split columns; confirm usable content at 960 × 600 and the default 1120 × 720.
2. Select History rows with keyboard and pointer. Search by text/app and change filters; a hidden/deleted record must no longer occupy the detail. Start playback/re-recognition, then change selection or leave History; old work must stop without changing another Capture.
3. Read final text, open recognition/refinement and recording disclosures, use both copy actions, and follow a linked Memory. Selecting a different Capture resets the detail navigation. Long text remains scrollable and selectable.
4. In Memory, review a suggestion and explicitly save/cancel/dismiss it. Check manual creation, validation errors, edit/archive/restore/replace/delete and sources. Pending suggestions are separate from confirmed context; changed/deleted/recording/refining sources cannot remain reviewable.
5. Confirm Settings persistence from both entry points. Filter Diagnostics, select a long event, resize its detail, and check copy-all/reveal/clear actions with disposable logs.
6. Verify keyboard focus, VoiceOver names, light/dark appearance, increased contrast and reduced motion. Native glass, selection colors and toolbar compositing require the real window.

For automated layout work, use temporary NSHostingView/NSWindow fixtures with isolated SwiftData containers, injected controller actions and a memory-only diagnostic logger. Never launch AppController bootstrap or order the fixture window onscreen; use `.prohibited` activation policy. Do not access the microphone, model, clipboard, production History or product log. Keep generated binaries, images and stores under a unique `/tmp` directory. Offscreen bitmap caching can omit native glass/selection layers, so these images establish layout and content only. M-008's local evidence paths are in its [task record](./tasks/M-008-macos-management-ui.md#validation-evidence).

## Development rules

### Work from tasks

Before implementation:

- confirm the task exists in [`tasks.md`](./tasks.md);
- create/update the corresponding detailed file in [`tasks/`](./tasks/README.md);
- connect the task to a GitHub Issue/PR when applicable.

After implementation, update code and task documentation together.

### Development-stage scope

Morie has no released compatibility contract. Implement the current schema and current Apple APIs directly; do not add old-schema migration, legacy metadata reconstruction, version routing or speculative upgrade paths. Current-version crash recovery and protection of intentional captures are still required.

### Branching

Use feature/task branches. Do not implement directly on `main`.

Branch naming can remain simple:

- `phase0/<focused-change>`
- future examples: `phase1/capture-store`, `phase2/relevant-context`

Task IDs remain stable in docs even if branch naming evolves.

### Dependencies

Default: no external product dependency.

A new dependency requires a written justification per `AGENTS.md` and the product baseline. Avoid packages merely for convenience when the system framework is adequate.

The GitHub-hosted CI workflow and official checkout action are development infrastructure, not Morie runtime/product dependencies.

### API selection

Use current Apple platform APIs. Do not introduce compatibility fallback merely to compile on older deployment targets.

For current Speech work, the intended path is:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- one `AVCaptureAudioDataOutput` shared by streamed source-audio encoding and `AnalyzerInputConverter`
- `SpeechAnalyzer.analyzeSequence(from:)` for explicit History file re-recognition

Do not implement recognition using `SFSpeechRecognizer` as a fallback. Its presence is currently limited to authorization where the current SDK exposes that permission path.

### Type4Me reference use

For every subsystem:

`Morie requirement → Type4Me code/tests → ADAPT / DROP / VERIFY → smallest macOS 27-native implementation`

Do not import generalized compatibility machinery merely because it exists upstream.

## Concurrency

Prefer structured Swift Concurrency:

- `@MainActor` for UI/application state;
- actors for mutable pipeline state that should be isolated;
- `Task` only where lifecycle/ownership is explicit;
- use explicit capture/session identity when async work can outlive the interaction that started it;
- cancellation must release resources and leave state recoverable.

Avoid arbitrary dispatch queues unless a platform API requires them.

Native C frameworks that lack Swift 6 concurrency annotations may use an explicit `@preconcurrency import` boundary when justified. Do not disable strict concurrency globally to silence such errors.

## Logging and diagnostics

Phase 0 diagnostics must make the following distinguishable without logging private transcript content unnecessarily:

- capability failure;
- permission state;
- hotkey installation and physical shortcut events;
- recording/session transition;
- Speech asset availability/download failure;
- transcription finalization failure;
- focus restore failure;
- clipboard staging, synthetic paste, and safe restoration;
- delivery success/failure;
- latency checkpoints as they are added.

The in-app Diagnostics section is the primary current runtime diagnostic surface. Do not log full user Capture content by default.

## Performance measurements

Phase 0 should establish a baseline for:

- app binary size;
- cold launch time;
- idle RSS;
- recording RSS;
- ASR final latency;
- final transcript → delivery latency;
- CPU / Energy Impact;
- capture-loss/failure rate during repeated testing.

Record actual measurements in the active task document or a linked validation artifact.

## Before opening/updating a PR

- ensure the macOS 27 compile gate passes for product changes;
- run relevant manual tests on supported hardware;
- check that no accidental external product dependency was added;
- update `docs/tasks.md` if overall task status changed;
- update the task detail document with implementation and validation evidence;
- update architecture/deployment/validation docs if procedures or behavior changed;
- explicitly list tests that could not be run.

## Review principle

Prefer the smallest implementation that satisfies the active acceptance criteria. Morie should not accumulate provider routers, generalized plugin systems, cross-platform layers, cloud abstractions, or compatibility frameworks before there is a real requirement.
