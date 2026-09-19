# M-029 — No-Speech Retention

## Status

**DONE** — 2026-09-19

Issue: [#44](https://github.com/6spot/Morie/issues/44)

## Problem

Morie's previous `CaptureAudioStream` set `hasMeaningfulAudio=nil` whenever any captured PCM buffer had finite/non-zero RMS energy. A real microphone almost always has a noise floor, so ordinary silence frequently became a retryable failed Capture and showed:

`未识别，录音已保存`

This was too conservative for normal use and cluttered History.

## Reference behavior

Type4Me has an explicit `speechDetected` gate. If the mic level never crosses its speech threshold, stop takes a fast no-speech exit and does not run the normal result/history path. For short streaming sessions with no transcript it also waits briefly and then exits when no text appears.

OpenLess keeps `emptyTranscript` as an explicit failed-history/error state. That is useful when a recording may contain real speech but the ASR provider failed.

Morie adopts a hybrid policy.

## Morie policy

`CaptureAudioStream` now tracks the **longest continuous speech-like energy run** rather than merely checking whether samples are non-zero:

- RMS threshold: `-36 dBFS`;
- minimum continuous run: `160 ms`;
- a short click/transient does not qualify;
- quiet room noise below threshold does not qualify.

Apple Speech transcript evidence still overrides the raw-audio classifier to `true`. Therefore a quiet recording that produced any partial/final transcript is never discarded by the energy gate.

Empty final transcript handling:

- `hasMeaningfulAudio == false` → explicit `CaptureStore.cancel`: delete row + audio; HUD briefly says **未检测到语音**;
- `hasMeaningfulAudio == true` → preserve failed Capture + audio for History re-recognition; HUD says **未识别，录音已保留**.

Operational microphone/Speech failures keep their existing recovery behavior.

## Acceptance criteria

- [x] quiet room noise is classified non-meaningful;
- [x] a brief loud transient is classified non-meaningful;
- [x] sustained speech-like signal remains meaningful;
- [x] discarded no-speech Capture does not remain in History;
- [x] user feedback no longer says `录音已保存` for confirmed no-speech;
- [x] Xcode 27 / macOS 27 Release compile passes;
- [ ] test-capable run executes audio/store tests;
- [x] owner device confirms normal silent/accidental capture no longer creates History.

## Validation / closure

GitHub Actions `macOS 27 CI` run #119 passed the Release product compile. Repository CI does not execute `MorieTests`, so the test-capable-run checkbox above remains intentionally unchecked rather than being claimed as run.

Owner-device validation on 2026-09-19 confirmed that a no-speech attempt no longer creates the previous `未识别，录音已保存` History entry and requested closure.

M-029 is complete. Issue #44 may be closed as completed.
