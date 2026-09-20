# M-037 — No-Speech Fast Exit and Recognition Outcomes

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#77](https://github.com/6spot/Morie/issues/77)  
PR: [#78](https://github.com/6spot/Morie/pull/78)

## Problem

The no-speech fast-exit work added stronger speech activity detection and Apple SpeechDetector participation. On the owner device, Apple Speech later surfaced the internal recognition rejection text `Recog Rejected` during finalization. Morie treated that as a generic operational failure, which allowed the low-level string to reach the modal `Morie 输入失败` alert.

A recognizer rejecting an utterance is not equivalent to a microphone, persistence, or delivery failure.

## Morie policy

Recognition now has two categories at the Speech boundary:

- **recognition outcome** — no accepted transcript / recognizer rejection; settle through the existing empty-recognition path;
- **operational failure** — the Speech pipeline cannot continue for a real runtime reason.

For a recognition outcome:

- confirmed no-speech audio is discarded and the HUD says **未检测到语音**;
- meaningful or uncertain audio is retained for retry and the HUD says **未识别，录音已保留**;
- no modal alert is shown;
- Apple Speech internal error text is diagnostics-only.

Saved-audio re-recognition follows the same rule: a recognizer rejection becomes the existing empty-recognition result rather than exposing framework error text.

Operational failures continue to be logged with NSError domain/code/description. User-facing live Speech failure text is intentionally generic rather than forwarding Apple's internal localized description.

## Acceptance criteria

- [x] `Recog Rejected` is classified as a recognition outcome.
- [x] finalization rejection returns the captured result instead of entering generic Capture failure.
- [x] startup/boundary rejection settles through no-speech / retained-for-retry behavior without a modal alert.
- [x] saved-audio rejection becomes empty recognition.
- [x] operational failure remains distinguishable from rejection.
- [x] diagnostics retain NSError domain/code/description.
- [x] regression tests cover direct, nested, and non-rejection errors.
- [ ] macOS 27 CI compile/test passes.
- [ ] owner-device reproduction confirms no `Morie 输入失败 / Recog Rejected` alert.

## Implementation notes

The rejection classifier is deliberately centralized at the Speech boundary. Apple does not expose the observed `Recog Rejected` state as a stable Morie-facing semantic type, so the compatibility recognition is isolated in one helper rather than scattered through UI/controller code.

The UI never branches on the framework string. Controllers only receive the semantic rejection outcome or a sanitized operational failure.

## Validation

Pending CI and owner-device validation.
