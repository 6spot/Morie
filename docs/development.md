# Development Guide

## Requirements

Current single-Mac development baseline:

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

### Development data after schema changes

Only the current data structure is supported. When changing a persisted structure, verify writing and reading a fresh temporary store in separate processes. Recreating a `ModelContainer` in the same test process is useful coverage but does not establish a cold launch. Compilation also cannot establish that an existing development database is readable.

SwiftData can add a column while leaving it null in existing rows. In particular, adding a nonoptional array inside a persisted Codable value can make reading an older value abort inside SwiftData, even though the container opened successfully. Do not add legacy decoding defaults, schema migrations or automatic data deletion to hide this development-data mismatch.

If existing development data needs a reset, make the data change explicit to the owner:

1. Back up the database consistently, including committed WAL contents, and copy the source recordings. Verify database integrity, record counts and recording checksums.
2. Obtain confirmation before clearing the owner's active History. Preserve the verified backup.
3. Stop the app in Xcode, archive the active database and its `-wal` / `-shm` sidecars together, and initialize an empty store using the current model.
4. Verify a cold store open before resuming the owner's signed app. Keep the reset outside product startup; a storage error must never silently erase intentional input.

The current default database is `~/Library/Application Support/MorieCaptures.store`; recordings are under `~/Library/Application Support/Morie/CaptureAudio`. A complete backup is required even when the data was created during development. This is an explicit local development operation, not a compatibility path in Morie.

Optional iCloud/CloudKit sync/backup is separate from the local-input capability gate. Local capture, Speech, cleanup, History and Memory must remain usable without iCloud. When enabled and correctly provisioned, sync uses the user's own private CloudKit database without a Morie backend; original source audio remains local in the current slice. See [deployment.md](deployment.md#cloudkit-deployment--later-cross-device-milestone).

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

Memory tests use isolated SwiftData containers and native NaturalLanguage tokenization to check provenance, lifecycle and bounded personal-context retrieval. Memory and Dictionary write through separate contexts in the same container; development requires no legacy schema or migration setup.

Dictionary tests cover word-only persistence, letter-case duplicates, distinct full-/half-width forms, invalid-input protection, bounded Speech hints, same-word letter-case normalization, overlap and technical-content protection. Correction detector tests cover Chinese/mixed words, shared letters, added/deleted/joined letters, stable-edit timing and undo. They do not observe real Accessibility fields or display prompts.

Learning tests inject structured evidence and delayed models. They verify exact committed final-text sources, idle queue/restart discovery, automatic admission/accumulation, merging/updates, user edits/archive/delete, atomic failure/backoff and input preemption. A cancelled model cannot create late Memory. Personalization tests inject full final text and uncooperative models to check independent cleanup, dictionary fallback, original/final save ordering, provenance, stale source/context, History retry, deadline/cancellation and current-version recovery.

Permission setup tests inject read-only snapshots and authorization/settings actions. They verify complete mandatory checks, explicit actions, denied/restricted/unsupported states, revocation/recovery, stale buttons and concurrent refresh/request behavior. The real Speech authorization bridge is tested with injected `SFSpeechRecognizer` subclasses that return background allow/deny callbacks or a synchronous callback, without querying or requesting real TCC. Preserve this Objective-C call boundary in regression tests: a plain Swift closure fake does not reproduce the SDK callback's runtime isolation check.

The actual Foundation Models and native Speech-hint paths compile. Logic tests never invoke a real model, microphone, clipboard or product app, and cannot establish semantic quality or cross-app acceptance.

## CI compile and logic-test gate

`.github/workflows/macos-27-ci.yml` runs two independent checks on GitHub's `xcode-27` hosted environment:

- **Xcode 27 compile** — Release build of the Morie product target;
- **MorieTests** — Debug execution of the standalone shared `MorieTests` scheme.

`.github/workflows/macos-27-package.yml` remains responsible for creating the test artifact.

The CI gate exists to catch:

- current macOS 27 SDK signature drift;
- Swift 6 strict-concurrency errors;
- Xcode project/build-setting breakage;
- accidental product-source compile failures;
- deterministic regressions already covered by Capture, History, Dictionary, Memory, Personalization, setup and synthetic-audio tests.

It is scoped to changes under `Morie/**`, `MorieTests/**`, `Morie.xcodeproj/**`, and the workflow files. Documentation-only changes do not need another expensive macOS run.

CI is **not** runtime acceptance. Hosted tests intentionally do not request real microphone/TCC access, invoke the user's Apple Intelligence model, exercise physical hotkeys/current-focus paste in third-party apps, judge native rendering/audio feel, or establish latency/energy characteristics.

## Required permissions

The current input loop requires Apple Intelligence, Chinese Speech transcription, Microphone authorization, Speech Recognition authorization and Accessibility trust.

The first launch opens **使用引导与权限** and inspects every requirement without prompting. Use each permission's explicit **授权** action for undetermined Microphone/Speech authorization. Denied access links to its native privacy pane. **辅助功能 → 打开系统设置** registers the signed app with TCC and opens its native pane; Morie does not add a second consent alert. Unauthorized rows show the available action without a duplicate status label; granted rows show **已授权**. Restricted or unavailable capabilities keep input blocked.

Return from System Settings to refresh status automatically, or choose **重新检查**. Refresh never calls bootstrap, stops recording, prepares a model or installs a hotkey. Once all requirements pass, click **开始使用** to prepare Speech assets and enable the shortcut. The completion action is disabled during recording/requests/preparation, and requirements are rechecked after asset preparation. Closing the guide with **稍后设置** does not complete setup. Subsequent launches still inspect actual permissions, regardless of the saved setup-completed preference.

The setup window uses the native hidden-title-bar style. Its footer places **稍后设置** at the far left and **重新检查 / 开始使用** on the right; Escape and Return retain their cancel/default meanings.

Use the normal signed app for TCC validation; compile/test/preview tools must not reset the owner's permissions or replace that app. Intentional permission-reset testing belongs in a separately authorized disposable test setup. CloudKit and Apple Developer enrollment are not part of this guide.

## Chinese UI and native navigation

The app bundle's development language and localized privacy resources are `zh-Hans`. App-owned strings and display dates use Simplified Chinese, including on a Mac with English first in its system language list. User data, prompts, raw enum values and diagnostic identifiers are not translated.

**⌘,**, the sidebar's **设置** entry and the native menu's **设置…** link all open one native Settings scene. The standard sidebar command and toolbar toggle show/hide navigation; **资料库 / 应用** headers use native expansion controls. The menu-bar extra uses a system menu with management, Settings, setup and Quit entries. The recording shortcut is unchanged.

## Native diagnostics surface

Morie includes a native **诊断** page in its management window.

Open the Morie management window from the native menu, then choose **诊断** in its sidebar. The diagnostics surface uses a native Table with search and level filtering. Select an event to read its full message in the resizable detail area. It records the current process lifetime in memory.

It currently traces:

- launch/bootstrap start and Ready/blocked state;
- Apple Intelligence, Speech, microphone, Speech authorization, and Accessibility checks;
- configured global-shortcut event-tap installation, solo Fn candidate/release/chord rejection, accepted key events, repeats, and tap recovery;
- capture session identity plus the actual delivery app/bundle resolved at paste time;
- Speech asset preparation, microphone/provider/analyzer lifecycle, partial/final result lengths, stop/cancel/failure;
- microphone meter channel count, average/peak power, normalized HUD level, and warnings when channels are missing or remain pinned at the floor;
- current-focus delivery target resolution and synthetic paste dispatch result;
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
2. open **Morie → 诊断**;
3. use **Clear Diagnostics…** if necessary;
4. focus the target text field in another app;
5. activate the configured shortcut (solo Fn release by default), speak, then activate it again to finish;
6. return to Morie → **Diagnostics** and use **Copy All Events**;
7. attach/paste the log with the observed behavior.

If no accepted Hotkey entry appears after the configured shortcut, diagnose the event-tap/shortcut path before investigating Speech or text injection. For Fn, distinguish `press began`, `solo release accepted`, and `candidate cancelled` entries. If Speech entries appear but no Delivery entries do, diagnose finalization/session lifecycle.

## Current manual smoke test

1. Launch Morie.
2. Complete **使用引导与权限**, then confirm the native menu reports **可以开始录音**. A later launch with unchanged permissions should become ready without another setup completion.
3. Open **Morie → 诊断** and confirm bootstrap/capability/hotkey-install entries are present.
4. Place the caret in another application.
5. Press and release `Fn / Globe` once (or use the configured alternate binding).
6. Speak a short phrase.
7. Activate the same shortcut again to finish.
8. Verify the app/field that owns keyboard focus when paste is dispatched receives the final text. Switching apps or fields after recording starts must route to the new current focus without Morie activating the record-start app.
9. Verify the debug log contains the corresponding Hotkey → Session → Speech → Delivery path.
10. Repeat several times, including rapid toggles, `Escape` cancellation, HUD cancel/finish, and Chinese/English mixed content where relevant.
11. Verify the previous clipboard content is restored after clipboard fallback unless another app/user changed the clipboard meanwhile.

Also request finish and cancellation during startup/session setup: neither may allow a late orphaned microphone session afterward.

A successful smoke test is not the full acceptance test. Complete [`validation.md`](./validation.md) before Phase 0 is considered done.

## History recovery smoke test

From the normal Xcode-signed app, open **Morie → 历史记录** and select a Capture with unexpired audio:

1. Play, pause, and seek with the native recording controls; opening a detail must not autoplay.
2. Choose **重新识别**, then verify the saved recognition. Any original delivered output and delivery status remain visible; paste only occurs after an explicit Copy action and the user's paste.
3. Cancel a retry and immediately start a new Fn capture. History playback/retry must stop and the live capture must remain usable.
4. Try a failed/empty Capture. Empty or failed re-recognition preserves its previous text/audio and shows the failure; success makes recovered text available.
5. Switch sections/close the window during playback and retry. Check cleanup, then reopen and retry again.
6. Exercise expired/missing audio, change retention, and confirm that only the audio expires. Delete a disposable test Capture through the native confirmation dialog.

Use generated fixture audio and temporary stores for automated API checks. Never transcribe or delete production History as part of an automated smoke test.

## Capture-only voice smoke test

1. From **打开 Morie → 历史记录**, choose **开始录音** and speak an idea. Complete it with the HUD; verify “已保存”, **保存位置：历史记录**, saved text and playable audio.
2. Repeat with shortcut finish and Escape cancellation. Cancellation removes the unfinished Capture and audio.
3. Start in History, switch to another app and finish there. The saved idea must not be pasted, focus must not be restored elsewhere, and the clipboard must remain unchanged.
4. Alternate this entry with normal shortcut input into a disposable document. Each new shortcut capture must deliver to the field that owns keyboard focus at paste time and report “已输入”.
5. Start while a History recording is playing or being re-recognized. The existing live-capture preemption must apply, and no second microphone session may start.

Mode persistence, terminal capture-only storage, cancellation and retry are covered by isolated logic tests. These checks do not replace the interactive clipboard/focus/microphone checks above.

## Dictionary and cleanup smoke test

Interactive checks remain deferred to the evening of 2026-09-18. Use disposable data in the owner's normal signed app when resuming:

1. In **字典 → 添加词语**, enter a word such as **Morie**, **Claude** or a Chinese technical term in the single **词语** field. Relaunch and verify persistence; duplicate/invalid words keep the editor open, and Cancel preserves saved values. Check initial field focus, Return to save and Escape to cancel.
2. Compare Speech recognition with/without a saved word. Check letter-case normalization of the same word (for example, **morie → Morie**) with **自动润色语音输入** off; full-/half-width forms remain untouched. A saved **Morie** must not unconditionally replace **more e**, **莫里**, code or URLs.
3. With an empty Personal Memory profile and cleanup on, test [the cleanup examples](input-cleanup.md): fillers, repeats, clear self-correction, uncertainty, short replies and clear ordered items. No invented content, summary, translation, answer or executed request.
4. Verify the target receives the exact saved **最终文字**. Inspect recognition, dictionary/Memory snapshots and accepted changes in **识别与润色**.
5. Re-recognize the saved audio; the delivered final output and its old processing provenance remain available. Exercise cancellation, unavailable/slow AI and save recovery with disposable captures.
6. Measure actual cleanup fidelity, hint benefit, timeout rate and final-to-delivery latency. The provisional two-second limit bounds model waiting, not storage/scheduling or the full input loop.

## Automatic personal Memory smoke test

1. Dictate a disposable explicit personal fact/project through ordinary current-app input. Let Morie idle, then inspect **个人记忆** and History's learning status. No manual confirmation should be needed.
2. Confirm **用于学习的文字** matches saved final text, including cleanup/dictionary changes. Recognition stays separate. Capture-only/active/cancelled/raw-only input is not automatically learned.
3. Repeat supported information, test weaker evidence across distinct captures, then express a clear later change. Inspect merged sources and superseded history; an ambiguous/older claim must not overwrite current information.
4. Test quotes, third-person/hypothetical/temporary statements and uncertain personal information. Inspect actual evidence rather than assuming model confidence guarantees correctness.
5. Edit/archive/delete personal information. User edits take precedence and the same normalized deleted topic is not immediately relearned. Inspect source links; deleting a source removes analysis snapshots but retains independent Memory.
6. Begin new input during analysis, then relaunch with pending work. New input remains responsive, late cancelled results cannot save, and unfinished work resumes during idle time. Opening/closing History does not govern background learning.

See [the Memory device checklist](validation.md#m-004-memory-foundation). Model selectivity, stable topic identity and energy use require actual evaluation.

## Word-correction suggestion smoke test

1. Verify **修改输入后建议加入字典** defaults off. Enable it explicitly, dictate into a supported disposable text field, correct a word, and pause for two seconds.
2. The native **加入字典 / 暂不添加** prompt should appear without activating Morie or stealing typing focus. Confirmation keeps the canonical spelling in the visible Dictionary and may save the bounded observed-ASR → canonical-word mapping internally; verify that no broad/unconfirmed replacement rule is created.
3. Repeat with Chinese, mixed words, added/deleted letters and joined terms. Appended sentences, numbers, punctuation, URLs/code and broad rewrites should not create word suggestions.
4. Continue editing, undo, move outside the inserted text, change apps/fields, start new input or disable the setting. Observation/pending suggestions should stop. Not Now/expiry saves nothing; the same word should not repeatedly prompt in one process.
5. Verify unsupported/secure fields, capture-only completion and clipboard fallback do not start observation. Check long words, save errors, fullscreen/multiple screens, keyboard/VoiceOver and panel dismissal.

Use the [correction matrix](validation.md#m-009-correction-suggestions). Automated fixtures must never attach an AX watcher to the owner's applications.

## Management UI smoke test

M-008 keeps development on macOS. Use the normal Xcode-signed app and disposable data when the deferred interactive checks resume:

1. Switch between **历史记录 / 字典 / 个人记忆 / 诊断**. Resize the window and native split columns at 960 × 600 and 1120 × 720; use the system sidebar toggle/command and fold **资料库 / 应用**.
2. Select History rows with keyboard and pointer. Search by text/app and change filters; a hidden/deleted record must no longer occupy the detail. Start playback/re-recognition, then change selection or leave History; old work must stop without changing another Capture.
3. Read final text, open recognition/refinement and recording disclosures, use both copy actions, and follow a linked Memory. Selecting a different Capture resets the detail navigation. Long text remains scrollable and selectable.
4. Check dictionary and personal-Memory creation/edit/save/cancel, validation errors, lifecycle/deletion and sources. Personal Memory appears automatically; its editor contains personal information, while Dictionary saves one word per entry. Learning status must not become a required review task.
5. Open **设置** through the sidebar, native menu and **⌘,**; all must reuse the same Settings scene and persist changes. Filter Diagnostics, select a long event, resize its detail, and check copy-all/reveal/clear actions with disposable logs.
6. Verify keyboard focus, VoiceOver names, light/dark appearance, increased contrast and reduced motion. Native glass, selection colors and toolbar compositing require the real window.

Also run the [M-010 native setup checklist](validation.md#m-010-chinese-ui-and-native-setup) for first use, denied permission recovery, setup deferral and app-scoped shortcuts.

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

`SFSpeechRecognizer.requestAuthorization` does not guarantee a main-queue callback. Its completion in the main-actor capability gate must remain explicitly `@Sendable`, capture only the checked continuation and resume it without touching actor-isolated state. The awaiting setup controller then inspects status on the main actor. The background-callback test reproduces the owner's dispatch assertion if that annotation is removed.

## Logging and diagnostics

Phase 0 diagnostics must make the following distinguishable without logging private transcript content unnecessarily:

- capability failure;
- permission state;
- hotkey installation and physical shortcut events;
- recording/session transition;
- Speech asset availability/download failure;
- transcription finalization failure;
- current-focus target resolution / paste dispatch failure;
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
