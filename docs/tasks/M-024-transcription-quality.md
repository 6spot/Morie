# M-024 — Transcription Readability and Native Speech Quality

## Status

**TODO** — 2026-09-19

Issue: [#24](https://github.com/6spot/Morie/issues/24)

## Goal

Improve how History explains recognition versus cleanup, then diagnose actual native recognition quality using evidence instead of assuming the speaker's accent is the problem.

## Current baseline

Live input already uses Apple's `DictationTranscriber(.progressiveLongDictation)`, preserves Apple's segment punctuation/spacing, and supplies bounded Dictionary hints through `AnalysisContext`.

History already stores raw `recognizedText` separately from `finalText` and refinement provenance. The remaining problem is both presentation density and uncertainty about whether a bad-looking result came from ASR, terminology, punctuation/segmentation, or conservative cleanup.

## Planned work

- Keep **最终文字** as the primary reading surface.
- Rename/clarify secondary raw content as **原始语音识别**.
- Improve visual paragraph spacing without mutating persisted text.
- Make refinement outcome and raw recognition clearly distinct.
- Reproduce controlled Mandarin, Chinese/English mixed and dictionary-term samples.
- Compare source audio → raw recognition → final refinement and classify failure source.
- Only change Speech configuration/assembly with repeatable before/after evidence.

## Acceptance criteria

- Presentation changes never rewrite saved `recognizedText` or `finalText`.
- At least three representative quality samples are recorded.
- Dictionary hints are verified for terminology cases.
- Any Speech-layer change preserves Apple's punctuation and segment ownership.
- No cloud ASR or third-party dependency is introduced speculatively.
- macOS 27 compile gate passes.
