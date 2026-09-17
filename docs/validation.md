# Phase 0 Validation

This document defines the real-device acceptance checks for **M-002 — macOS Input Foundation**.

Phase 0 cannot be marked `DONE` solely from static review or compilation. Global keyboard capture, microphone behavior, permission lifecycle, focus restoration, Accessibility APIs, and editor insertion must be exercised on a supported Mac.

## Compile gate

Product/Xcode-project changes must first pass `.github/workflows/macos-27-build.yml` on the hosted macOS 27 / Xcode 27 environment.

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

CloudKit/iCloud is intentionally not part of the Phase 0 gate; M-003 adds it with the real container/entitlements.

## Push-to-talk lifecycle

Verify repeated sequences:

1. place caret in target app;
2. hold `Control + Space`;
3. confirm recording begins once;
4. speak;
5. release;
6. confirm capture stops/finalizes once;
7. verify Morie returns to Ready;
8. immediately repeat.

Also test:

- very short press/release while Speech session setup is still starting — no late/orphaned recording may appear afterward;
- rapid repeated holds;
- long utterance;
- key autorepeat while held — recording starts only once;
- release Space after releasing Control first — the active hold still ends once;
- press additional modifiers while held;
- switching/closing target app during recording;
- Accessibility revocation after Morie has reached Ready;
- microphone interruption where practical;
- capture/transcription error followed by another successful attempt.

Record any stuck hotkey, duplicate start/stop, orphan microphone indicator, or event that leaks unexpectedly into the target application.

## Session identity / stale result checks

Exercise timing-sensitive transitions deliberately:

- start → immediate release → new start;
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

Record whether partial/volatile text is sensible, whether finalization changes it materially, and whether the end of a short utterance is ever lost on release.

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
- Morie's synthetic Cmd+V never triggers the push-to-talk shortcut path;
- no unexpected keystrokes are delivered to the target.

Do not add an app-specific workaround merely because an app fails once. Reproduce on macOS 27, record the exact failure here/M-002, then implement the smallest native fix.

## Compatibility matrix

Use the following as the first representative matrix. The purpose is to validate Morie's generic path across common native/web/electron/editor surfaces, not to create a permanent per-app compatibility subsystem.

| App | App/version | Focus restore | AX insert | Clipboard fallback | Mixed text | Multiline | Repeat input | Undo | Result / notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Safari | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Chrome | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| WeChat | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Slack | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Telegram | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Mail | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Notes | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Xcode | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| VS Code | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Cursor | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Terminal | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Pages | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Microsoft Word | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |

When AX insertion is unsupported but the generic clipboard fallback works reliably, record that explicitly; it can still be an acceptable compatibility result.

## Shortcut conflict check

`Control + Space` is the current Phase 0 binding, not yet a frozen product default.

On the validation Mac, record:

- configured input-source shortcuts;
- whether `Control + Space` conflicts with system/user input switching;
- whether Morie consuming the shortcut causes unacceptable side effects.

If a conflict is material, resolve the product shortcut decision directly rather than building broad hotkey compatibility machinery.

## Reliability run

After individual app checks, perform repeated use rather than only one-shot tests.

Suggested initial baseline:

- at least 50 consecutive captures across several target apps;
- include rapid back-to-back captures and very short holds;
- record any lost capture, stuck recording state, duplicate delivery, wrong target, failed focus restore, orphan microphone session, or paste failure.

The objective is to discover lifecycle defects before Memory work starts.

## Performance baseline

Record observations for the same tested build:

| Metric | Measurement | Environment / notes |
| --- | --- | --- |
| App binary size | TBD | |
| Cold launch time | TBD | |
| Idle RSS | TBD | |
| Recording RSS | TBD | |
| ASR final latency | TBD | release → final transcript |
| Final → delivery latency | TBD | final transcript → inserted text |
| CPU / Energy Impact | TBD | Activity Monitor / Instruments as appropriate |
| Capture loss rate | TBD | from reliability run |

The first goal is a trustworthy baseline. Numeric regression budgets can be established after real measurements exist.

## Completion record

When validation is complete, update:

- this matrix;
- [`tasks/M-002-macos-input-foundation.md`](./tasks/M-002-macos-input-foundation.md) with evidence and remaining issues;
- [`tasks.md`](./tasks.md) task state;
- PR #3 with the tested environment/results.

Do not replace device/runtime evidence with assumptions, Type4Me history, or compile success.
