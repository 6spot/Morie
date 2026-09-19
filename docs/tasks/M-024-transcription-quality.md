# M-024 — Transcription Readability and Native Speech Quality

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#24](https://github.com/6spot/Morie/issues/24)

## Goal

Improve how History explains recognition versus cleanup, then diagnose actual native recognition quality using evidence instead of assuming the speaker's accent is the problem.

## Current baseline

Live input already uses Apple's `DictationTranscriber(.progressiveLongDictation)`, preserves Apple's segment punctuation/spacing, and supplies bounded Dictionary hints through `AnalysisContext`.

History already stores raw `recognizedText` separately from `finalText` and refinement provenance. The remaining problem is both presentation density and uncertainty about whether a bad-looking result came from ASR, terminology, punctuation/segmentation, or conservative cleanup.

## Planned work

- Keep **最终文字** as the primary reading surface.
- Rename/clarify secondary raw content as **原始语音识别**.
- Keep the History detail intentionally compact: raw ASR once, then only cleanup result/status and duration.
- Remove edit-by-edit diff, pre-cleanup text, dictionary snapshot and memory-context snapshot from the normal History UI. These snapshots remain persisted for diagnostics and later internal use.
- Improve visual paragraph spacing without mutating persisted text.
- Make refinement outcome and raw recognition clearly distinct.
- Reproduce controlled Mandarin, Chinese/English mixed and dictionary-term samples.
- Compare source audio → raw recognition → final refinement and classify failure source.
- Only change Speech configuration/assembly with repeatable before/after evidence.

## Acceptance criteria

- [x] **最终文字** remains the only primary text surface.
- [x] Raw ASR is labeled **原始语音识别** and shown once.
- [x] Cleanup UI shows only result/status, duration and an optional reason.
- [x] Edit diff, pre-cleanup text, dictionary snapshot and referenced-memory snapshot are hidden from normal History presentation.
- [x] Hidden provenance remains persisted; this is presentation-only.
- Presentation changes never rewrite saved `recognizedText` or `finalText`.
- At least three representative quality samples are recorded.
- Dictionary hints are verified for terminology cases.
- Any Speech-layer change preserves Apple's punctuation and segment ownership.
- No cloud ASR or third-party dependency is introduced speculatively.
- [x] macOS 27 compile gate passes.


## 2026-09-19 History simplification

Owner review found the previous refinement detail redundant: final text already represents the cleanup output, while raw recognition already represents the pre-cleanup speech text. Repeating edit-by-edit diffs, the full pre-cleanup snapshot and per-input dictionary/context snapshots made the page read like a debug inspector.

The normal History detail now has one user-facing comparison:

```text
最终文字
   ↑ primary result

识别与润色
  ├─ 原始语音识别
  └─ 输入润色
       ├─ 处理结果
       ├─ 耗时
       └─ 可选原因
```

Persisted provenance is intentionally unchanged.


## Observed sample 1 — owner device, 2026-09-19

A real Mandarin input about History timing produced a generally understandable raw transcript, but it inserted sentence-final question particles such as “吗” where the speaker was making statements and introduced an unrelated/noisy tail fragment before the final “我们继续呗”.

The cleanup output removed those artifacts and restored the intended declarative structure.

Current classification:

- core lexical recognition: mostly usable;
- punctuation / sentence-boundary interpretation: imperfect;
- short particle insertion: observable;
- tail-fragment recognition: observable;
- cleanup recovery: useful on this sample.

Do not attribute this sample to accent alone. Keep collecting controlled samples before changing Speech configuration.


## Validation

GitHub Actions `macOS 27 CI` run #75 passed the Release product compile for PR #28 on Xcode 27/macOS 27.

The change is presentation-only: persisted `recognizedText`, `finalText`, refinement edits, dictionary snapshots and memory-context snapshots are unchanged.
