# Phase 0 Validation

This document defines the real-device acceptance checks for **M-002 — macOS Input Foundation**.

Phase 0 cannot be marked `DONE` solely from static review or compilation. Global keyboard capture, microphone behavior, focus restoration, Accessibility APIs, and editor-specific insertion must be exercised on a supported Mac.

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
- unsupported/unavailable model state → Morie remains blocked with a useful reason;
- unsupported Speech locale → blocked rather than silently falling back;
- denied microphone permission → blocked/recoverable;
- denied Speech permission → blocked/recoverable;
- missing Accessibility trust → blocked/recoverable;
- rechecking after permission changes can reach Ready without relaunch where platform behavior permits.

CloudKit/iCloud is intentionally not part of the Phase 0 gate yet; it will be added with the real Phase 1 container and entitlements.

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

- very short press;
- long utterance;
- key repeat while held;
- release after modifier changes;
- switching/closing target app during recording;
- microphone interruption where practical;
- capture/transcription error followed by another successful attempt.

## Transcription

Test at least:

- English;
- Simplified Chinese where supported/configured;
- Chinese + English mixed sentence;
- common punctuation behavior;
- project/product names to establish a Phase 0 baseline before Vocabulary learning exists;
- quiet and normal office acoustic conditions.

Record whether partial text is sensible and whether finalization changes the text materially.

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
- clipboard fallback does not leave Morie transcript in the clipboard after restoration in ordinary cases;
- no unexpected keystrokes are delivered to the target.

## Compatibility matrix

Use the following as the first mandatory matrix. Add discovered problem cases rather than removing them silently.

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

When AX insertion is unsupported but clipboard fallback works reliably, record that explicitly; it can still be an acceptable compatibility result.

## Reliability run

After individual app checks, perform repeated use rather than only one-shot tests.

Suggested initial baseline:

- at least 50 consecutive captures across several target apps;
- include rapid back-to-back captures;
- record any lost capture, stuck recording state, duplicate delivery, wrong target, failed focus restore, or paste failure.

The objective is to discover state/lifecycle defects before Memory work starts.

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

Do not replace test evidence with assumptions or static code inspection.