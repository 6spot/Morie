# Phase 0 Validation

This document defines the real-device acceptance checks for **M-002 — macOS Input Foundation**.

Phase 0 cannot be marked `DONE` solely from static review or compilation. Global keyboard capture, microphone behavior, permission lifecycle, focus restoration, Accessibility APIs, and editor insertion must be exercised on a supported Mac.

Owner scheduling decision, 2026-09-18: defer interactive device validation until the evening and continue independent development now. Keep the checklist open; no device result is inferred from this deferral.

## Compile gate

Product/Xcode-project changes must first pass `.github/workflows/macos-27-ci.yml` on the hosted macOS 27 / Xcode 27 environment.

This proves current SDK/Swift compilation only. It does not replace any runtime check below.

## Test environment

Record for each validation run:

- macOS version/build;
- Mac model / chip;
- Apple Intelligence state;
- primary locale(s);
- Xcode/build version;
- Morie commit SHA/build number;
- relevant app versions.

## Capability gate

Verify:

- supported Mac + Apple Intelligence available → passes model capability check;
- unavailable model state → Morie remains blocked with a useful reason;
- unsupported Speech locale → blocked rather than silently falling back;
- denied microphone permission → blocked/recoverable;
- denied Speech permission → blocked/recoverable;
- missing Accessibility trust → blocked/recoverable;
- rechecking after permission changes can reach Ready without adding a fallback implementation;
- revoking Accessibility after startup does not leave a broken/stuck global shortcut session.
- a system event-tap timeout disables Morie's shortcut and leaves ordinary keyboard input immediately usable; Morie must not automatically re-enable a repeatedly failing tap;

CloudKit/iCloud is intentionally not part of the Phase 0 gate; M-003 adds it with the real container/entitlements.

The initial `AVCaptureAudioFileOutput` integration caused a confirmed AVFoundation `SIGABRT` on macOS 27 and was removed. Its single-data-output replacement is implemented but must prove start, stop, cancellation, recognition failure, repeated capture, M4A playback, size, CPU and memory behavior on owner hardware before acceptance.

Verify the empty-result split explicitly: a silent start/stop must create neither a History row nor a retained M4A, while audible speech that produces no transcript must retain both the failed Capture and its retryable source audio.

2026-09-18 owner validation confirmed normal Chinese input and M4A creation, but the empty-result split did not pass: captures `CBCA4A24` and `5B073CAE` produced empty transcripts and were retained because ambient/input energy crossed the former meaningful-audio threshold. The History follow-up removes that amplitude-only decision and retains uncertain audio with explicit recovery actions. Automatic discard currently covers no input/zero signal only. **The quiet-room silence versus audible recognition failure acceptance item remains open.**

## M-003 History playback and recovery

Run from the owner's normal Xcode-signed build using disposable test Captures:

- [ ] Open a Capture and play, pause and seek using the native audio controls; opening alone must not play it.
- [ ] Leave the detail, switch sections, close the window, or start Fn recording while playback is active; playback must stop.
- [ ] Re-recognize a completed Capture; recovered text is saved to the same record and survives relaunch.
- [ ] Original delivered text/outcome remain visible when new recognition differs; retry itself must not paste or change the clipboard.
- [ ] Cancel retry during file analysis/finalization; prior text and audio remain intact, including when a late result arrives.
- [ ] Start live Fn capture during retry; the retry stops, the new microphone session starts once, and ordinary input remains usable.
- [ ] Repeatedly retry, cancel, navigate away and retry another Capture without a stuck progress indicator or incorrect-row update.
- [ ] Empty or failed re-recognition has readable recovery feedback and keeps the prior content. A later successful retry clears the retry error.
- [ ] An expired, missing or unplayable recording has useful feedback, with saved text still available.
- [ ] Let an open detail's recording expire and change retention while a recording is selected; playback/retry must not keep an expired recording usable.
- [ ] Relaunch with an empty failed Capture whose audio expired; the History row/error/duration remain.
- [ ] Delete one disposable Capture through confirmation; its row and audio disappear, and other Captures remain.
- [ ] Confirm native player/Copy/retry/cancel/delete controls with keyboard and VoiceOver, long text, and light/dark appearance.

Automated persistence/History tests cover success, empty results, failure, cancellation, input preemption, missing/expired audio, interrupted recovery and scoped deletion. These tests use temporary storage and injected file recognition, so they do not establish native playback, ASR accuracy, microphone behavior or visual acceptance.

2026-09-18: the final isolated app build and all **20 logic tests** passed on macOS 27 / Xcode 27, with no failures or skipped tests. A separate native `CaptureFileTranscriber` check recognized generated Chinese AAC audio, reported empty recognition for a silent M4A, and rejected a missing file. Offscreen rendering checked the Capture detail layout only. Evidence paths are recorded in [`M-003-capture.md`](./tasks/M-003-capture.md); the interactive checks above remain open.

## M-003 capture-only voice entry

- [ ] Choose **History → Record Capture**, speak and finish with the HUD; text/audio are saved with **Destination: History**, and feedback says “已保存”.
- [ ] Finish another capture-only recording with the configured shortcut; the entry's saved destination remains authoritative.
- [ ] Switch to another app before finishing; no paste, clipboard mutation or target-app activation occurs.
- [ ] Cancel with Escape/HUD; the unfinished row and audio are removed, and a new capture starts normally.
- [ ] Alternate capture-only and global-shortcut captures; current-app input still restores/delivers to the correct target and reports “已输入”.
- [ ] Retry an empty/failed capture-only recording; recovery retains its History destination and does not trigger delivery.
- [ ] Start capture-only during History playback/retry; preemption works and capture startup remains responsive.
- [ ] The native toolbar action is accessible by keyboard/VoiceOver and cannot start duplicate recordings during startup/finalization.

2026-09-18: isolated Debug compilation and all **24 logic tests** passed (0 failed/skipped). Offscreen native rendering confirms the History toolbar action and the completed capture-only destination/status. These checks do not establish microphone, clipboard/focus or live interaction acceptance; the checklist remains open.

## M-003 interruption and discard

Use disposable captures from the normal Xcode-signed app. Repeat the relevant cases for both the shortcut and History's **Record Capture** entry:

- [ ] Start recording, speak, then choose **Recheck Capabilities**. The microphone stops, text/audio remain in a failed History record, and the capability flow completes without a late paste.
- [ ] Recheck during Speech startup and normal finalization. No orphan microphone session, duplicate teardown, stale Ready transition, or late delivery occurs.
- [ ] Reproduce shortcut unavailability/Accessibility revocation while recording. Ordinary keyboard input remains usable; the Capture is retained and status stays blocked until explicit recheck.
- [ ] Exercise a real microphone/capture-session interruption where practical. Failure ends capture without requiring the user to press Finish; retained audio can be played or shows an accurate native error.
- [ ] Interrupt during focus handoff before paste. Saved text stays in History and no delayed clipboard staging/paste occurs. A paste already dispatched retains its actual delivery outcome.
- [ ] Cancel with Escape/HUD during startup and recording. Native recording closes before the row/file disappear; a subsequent capture starts normally.
- [ ] Repeat interruption/recheck/cancel followed by another capture. No stale text, stuck progress, duplicate recording or retained microphone indicator remains.

Automated AAC tests establish finalization and data preservation for controlled conversion/flush errors, immediate stop and repeated completion. They do not establish real session-notification timing, controller scheduling, microphone release, or decodability after a force quit/storage failure. Those checks remain open.

2026-09-18: final isolated Debug compilation and all **31 tests** passed on macOS 27 / Xcode 27 (0 failed/skipped). The seven new tests use real Apple AAC encoding/decoding plus temporary storage, without opening a microphone or launching Morie. Paths and limits are recorded in [M-003](./tasks/M-003-capture.md#validation-evidence).

## M-004 Memory foundation

Use disposable Capture/Memory entries when interactive validation resumes tonight:

- [ ] Create vocabulary and projects from **Memory → New Memory** with Chinese/English names, multiline aliases and notes; relaunch and inspect the saved entries.
- [ ] Save a selective memory from History, link another Capture to it, and inspect both sources without changing the original transcript or delivery outcome.
- [ ] Cancel a new/edit sheet; saved data remains unchanged. Invalid input and duplicate active names keep the sheet open with a readable error.
- [ ] Edit a memory and inspect updated matching context in History. Canonical names and aliases work without partial Latin-word matches.
- [ ] Archive/restore a matching entry; it disappears/reappears in related context. Restoring a conflicting active name is refused.
- [ ] Replace a memory; the new entry links to the old one, old status becomes **Superseded**, and old content no longer appears as relevant context.
- [ ] Delete a disposable source Capture; separately confirmed Memory remains and the source is labelled deleted. Delete one memory; its sources and other memories remain.
- [ ] Verify list/search/filter, source navigation, editor/save/cancel, lifecycle and delete controls with keyboard/VoiceOver and long text.
- [ ] Open History/Memory while using voice capture; no automatic memory save, new model task, paste, or clipboard change occurs.

2026-09-18: all **47 isolated tests** passed, including 16 Memory tests and the 31 Capture/History/audio regression tests. Offscreen native rendering checked list/detail/editor/context layout with synthetic data. Evidence is in [M-004](./tasks/M-004-memory.md#validation-evidence); interactive acceptance remains open.

## M-004 Memory Candidates

- [ ] In a disposable saved Capture, choose **Find Memory Candidates**; verify zero to three selective Vocabulary/Project suggestions with grounded Chinese/English names, aliases, notes and literal evidence.
- [ ] Inspect **Text Used for Extraction**. It must match saved final text, or recognized text only when no final exists. Current final text is not described as AI-polished; M-005 must save and retain polished output here later.
- [ ] Edit/save, link to an existing active memory, dismiss and cancel review. Confirmed Memory and review states survive relaunch; pending suggestions never participate in related context.
- [ ] Inspect the source snapshot from saved AI-derived Memory. The exact extraction text remains available even after a later source-text change, until that source Capture is deleted.
- [ ] Change the source during extraction or before review confirmation. Stale results must not save; re-extraction uses the updated text. Repeating an already analyzed text preserves decisions and does not rerun inference.
- [ ] Cancel inference, leave the detail and begin live capture. Verify no late candidates, blocked voice startup or unnecessary model work after cancellation.
- [ ] Exercise empty suggestions, oversized input, model unavailability/refusal and unsupported language; Captures and existing Memory remain, with readable recovery.
- [ ] Delete a disposable source Capture during/after extraction; its snapshots disappear, no late result recreates them, and separately confirmed Memory remains.
- [ ] Verify Memory inbox/review/source disclosure/progress controls with keyboard, VoiceOver and long text; measure model latency/energy and live-input preemption.

2026-09-18: all **65 isolated tests** pass, including 18 candidate tests with injected inference. The real macOS 27 Foundation Models path compiles. These results establish persistence and concurrency behavior, not AI quality; the real-model and interaction checks remain open for tonight. Evidence is in [M-004](./tasks/M-004-memory.md#candidate-slice-validation).

## Toggle-capture lifecycle

Verify repeated sequences:

1. place caret in target app;
2. press and release the configured shortcut once (solo `Fn / Globe` by default);
3. confirm recording begins once;
4. speak;
5. confirm that releasing the shortcut did not stop recording;
6. activate the configured shortcut again;
7. confirm capture stops/finalizes once;
8. verify Morie returns to Ready;
9. immediately repeat.

Also test:

- second press while Speech session setup is still starting — it must finish the same Capture without a late/orphaned recording;
- `Escape` while setup is still starting — it must cancel without a late/orphaned recording;
- rapid repeated toggles;
- long utterance;
- key autorepeat while physically held — each physical press toggles at most once;
- key-up events do not start, finish, or cancel capture;
- `Escape` is consumed only while recording and behaves normally otherwise;
- HUD cancel matches `Escape`; HUD confirm matches the second shortcut press;
- switching/closing target app during recording;
- closing the original target window while its app remains running preserves the transcript on the ordinary clipboard instead of reporting a false successful paste;
- Accessibility revocation after Morie has reached Ready;
- microphone interruption where practical;
- capture/transcription error followed by another successful attempt.

Record any stuck hotkey, duplicate start/stop, orphan microphone indicator, or event that leaks unexpectedly into the target application.

Safety invariant: a hotkey failure may disable Morie, but must never leave normal system keyboard input blocked. Recovery after a timeout is explicit through **Recheck Capabilities**.

## Session identity / stale result checks

Exercise timing-sensitive transitions deliberately:

- start → immediate finish → new start;
- start → immediate cancel → new start;
- start → error/cancel → immediate new start;
- finalize one utterance while rapidly beginning the next after Ready returns;
- repeat short sessions around Speech asset/session initialization.

Expected behavior:

- a previous session's partial/final callback never changes the visible transcript of a newer session;
- a cancelled setup never starts recording later;
- only the active session can finalize/deliver;
- every terminal path releases recording resources.

## Transcription

Test at least:

- English;
- Simplified Chinese where supported/configured;
- Chinese + English mixed sentence;
- common punctuation behavior;
- project/product names to establish a Phase 0 baseline before Vocabulary learning exists;
- quiet and normal office acoustic conditions.

Record whether partial/volatile text is sensible, whether finalization changes it materially, and whether the end of a short utterance is ever lost after the finish action.

## Capture HUD and Liquid Glass

Validate the HUD over light, dark, detailed, and full-screen backgrounds:

- the HUD renders as one continuous system Liquid Glass capsule that visibly samples the content behind its window, rather than an opaque black surface or three separate glass islands;
- the cancel, waveform, and finish grouping matches the approved compact reference hierarchy;
- the panel appears on the screen containing the pointer and near the bottom-center of its visible frame;
- it never activates itself, steals text focus, or replaces the original target application;
- cancel and finish buttons have correct pointer-down feedback, hit targets, tooltips, and accessibility labels;
- the waveform is present on the first frame, stays low at both edges and tallest in the middle, and changes its center with real microphone level without opening a second capture path;
- normal speech produces clearly visible changes; the Debug log reports a nonzero audio-channel count and changing average/peak/normalized meter values rather than a missing-channel or floor-pinned warning;
- processing, success, and failure states are distinguishable and do not block immediate subsequent input;
- successful delivery shows an animated, labelled “已输入” result rather than an isolated static checkmark;
- when delivery cannot reach the original input location but preserves the transcript, the same HUD reports “已复制到剪贴板” and does not steal focus with a modal alert;
- Reduce Motion keeps stationary level feedback and avoids unnecessary panel animation;
- Reduce Transparency and Increase Contrast produce a legible system-controlled material;
- VoiceOver announces cancel, microphone input level, finish, processing, success, and failure meaningfully;
- light/dark appearance changes do not rely on a forced color scheme or hard-coded foreground/background colors.

## Menu bar shell

Verify that the menu-bar waveform icon remains visually stable through checking, ready, recording, processing, successful delivery, clipboard fallback, and recoverable failure. Runtime status should remain available in the HUD and menu text without making the persistent menu-bar item flicker between symbols.

## Delivery behavior

For every target app, validate:

- correct original app is restored;
- intended text field/editor receives focus again;
- insertion occurs at the intended selection/caret;
- existing selected text replacement behaves predictably;
- multiline text works where appropriate;
- Chinese/English mixed text survives insertion;
- repeated captures do not progressively lose focus;
- undo behavior is acceptable;
- clipboard fallback does not overwrite a newer clipboard change;
- ordinary fallback restores the previous text-like clipboard value after delivery;
- if the clipboard was empty before successful delivery, Morie's temporary transcript is removed and the clipboard becomes empty again;
- clipboard-history tools that honor `org.nspasteboard.TransientType` (including the tested Raycast setup) do not retain Morie's temporary injection or automatic restoration entries;
- Morie's synthetic Cmd+V never triggers the toggle-capture shortcut path;
- no unexpected keystrokes are delivered to the target.

Do not add an app-specific workaround merely because an app fails once. Reproduce on macOS 27, record the exact failure here/M-002, then implement the smallest native fix.

## Compatibility matrix

Use the following as the first representative matrix. The purpose is to validate Morie's generic path across common native/web/electron/editor surfaces, not to create a permanent per-app compatibility subsystem.

| App | App/version | Focus restore | Paste delivery | Clipboard restore | Mixed text | Multiline | Repeat input | Undo | Result / notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Safari | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☐ | ☐ | One logged Fn capture completed; broader field/format coverage remains |
| Chrome | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| WeChat | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☑ | ☐ | Repeated short/normal captures plus ~85-second, 371-character capture completed |
| Slack | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Telegram | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Mail | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Notes | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☑ | ☐ | Two consecutive logged captures completed |
| Xcode | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☑ | ☐ | Two logged Fn captures completed; mixed text/multiline/undo remain |
| VS Code | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Cursor | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Terminal | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☐ | ☐ | One logged Fn capture completed |
| Pages | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Microsoft Word | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |

Morie intentionally validates one generic clipboard + synthetic paste delivery path. Do not add AX mutation or app-specific branches without a new evidence-backed decision.

## Shortcut conflict check

Solo `Fn / Globe` release is the approved default Phase 0 binding. Alternate combinations are available in native Settings.

On the validation Mac, record:

- configured Globe/Fn system action and input-source shortcuts;
- whether solo Fn release both toggles Morie and accidentally opens a system surface;
- whether Fn combined with another key passes through without toggling Morie;
- alternate shortcut selection, persistence across relaunch, and absence of unacceptable side effects;
- built-in and external-keyboard behavior.

If a conflict is material, record the exact macOS 27 behavior and use the approved alternate binding rather than building broad compatibility machinery.

## Reliability run

After individual app checks, perform repeated use rather than only one-shot tests.

Suggested initial baseline:

- at least 50 consecutive captures across several target apps;
- include rapid back-to-back captures, immediate finish, immediate cancel, and long captures;
- record any lost capture, stuck recording state, duplicate delivery, wrong target, failed focus restore, orphan microphone session, or paste failure.

The objective is to discover lifecycle defects before Memory work starts.

## Performance baseline

Record observations for the same tested build:

| Metric | Measurement | Environment / notes |
| --- | --- | --- |
| App bundle / executable size | 1,060,864-byte app bundle / 1,050,744-byte executable | Local unsigned arm64 Release build, Xcode 27 / macOS 27 SDK; establish signed-package size separately |
| Cold launch time | TBD | |
| Idle RSS | TBD | |
| Recording RSS | TBD | |
| ASR final latency | TBD | finish action → final transcript |
| Final → delivery latency | TBD | final transcript → inserted text |
| CPU / Energy Impact | TBD | Activity Monitor / Instruments as appropriate |
| Capture loss rate | TBD | from reliability run |

The first goal is a trustworthy baseline. Numeric regression budgets can be established after real measurements exist.

## Completion record

When validation is complete, update:

- this matrix;
- [`tasks/M-002-macos-input-foundation.md`](./tasks/M-002-macos-input-foundation.md) with evidence and remaining issues;
- [`tasks.md`](./tasks.md) task state;
- the current task branch/PR with the tested environment and results (PR #3 remains the merged implementation-baseline reference).

Do not replace device/runtime evidence with assumptions, Type4Me history, or compile success.
