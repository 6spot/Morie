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

Morie includes a native `Morie Debug` window for Phase 0 runtime diagnosis.

Open the Morie management window from the menu-bar panel, then choose **Diagnostics** in its sidebar. The diagnostics surface uses only system SwiftUI/macOS controls and records the current process lifetime in memory.

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

Diagnostics are also persisted for the current app launch at `~/Library/Logs/Morie/morie-debug.log`. The file is recreated at launch, **Clear** truncates both the window and file, and **Show Log File** reveals it in Finder. This runtime file is outside the repository and must not be committed.

The window provides:

- **Copy All** — copy the complete current in-memory diagnostic log for issue/debug sharing;
- **Clear** — reset the current log before reproducing a defect.

Recommended defect reproduction flow:

1. launch Morie;
2. open **Morie Debug**;
3. press **Clear** if necessary;
4. focus the target text field in another app;
5. activate the configured shortcut (solo Fn release by default), speak, then activate it again to finish;
6. return to Morie → **Diagnostics** and use **Copy All**;
7. attach/paste the log with the observed behavior.

If no accepted Hotkey entry appears after the configured shortcut, diagnose the event-tap/shortcut path before investigating Speech or text injection. For Fn, distinguish `press began`, `solo release accepted`, and `candidate cancelled` entries. If Speech entries appear but no Delivery entries do, diagnose finalization/session lifecycle.

## Current manual smoke test

1. Launch Morie.
2. Confirm the menu bar item reaches `Ready` on a supported system.
3. Open `Morie Debug` and confirm bootstrap/capability/hotkey-install entries are present.
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
