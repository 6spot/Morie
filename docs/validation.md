# Phase 0 Validation

This document defines the real-device acceptance checks for **M-002 — macOS Input Foundation**.

Phase 0 cannot be marked `DONE` solely from static review or compilation. Global keyboard capture, microphone behavior, permission lifecycle, focus restoration, Accessibility APIs, and editor insertion must be exercised on a supported Mac.

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
