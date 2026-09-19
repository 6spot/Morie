# M-026 — Control Center Overview

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#31](https://github.com/6spot/Morie/issues/31)

## Goal

Make the Control Center immediately answer two questions:

1. how Morie has been used locally;
2. which Apple-native recognition and cleanup models are actually active right now.

The page must be useful without inventing analytics Morie cannot measure truthfully.

## UX

**总览** is the first sidebar destination and the default Control Center landing page.

The first slice uses native SwiftUI GroupBox/Grid presentation and shows:

- **累计识别字符** — sum of persisted raw recognition text across completed Captures;
- **成功输入** — current-app Captures with terminal `delivered` lifecycle;
- **输入失败率** — `failed + deliveryFailed` divided by terminal current-app attempts;
- **平均润色耗时** — mean persisted refinement duration when samples exist.

A note explicitly states that **输入失败率 is not ASR error rate**.

Morie does not currently display a recognition WER/error percentage because post-insertion edits do not yet provide enough reliable ground truth to separate ASR mistakes from spoken self-correction, cleanup changes and later content edits.

## Current model status

### Speech

`SpeechPipeline.prepare` exposes the backend it actually prepared:

- `SpeechTranscriber` → **首选**;
- `DictationTranscriber` → **回退**;
- locale is shown beside the backend.

This means asset/preparation fallback is visible to the user.

### Cleanup

Overview shows:

- **Apple Foundation Models**;
- `SystemLanguageModel.default · 本机`;
- available / model preparing / Apple Intelligence disabled / unsupported / unavailable;
- **已关闭** when Morie's input-cleanup preference is off.

Apple does not expose a public user-facing Foundation Models version identifier here, so Morie does not fabricate one.

## Performance

Overview owns its Capture query only while Overview is visible. It does not move the full History query into `AppController` or keep a global Capture subscription alive.

No telemetry service, analytics SDK, schema migration or remote backend is added.

## Acceptance criteria

- [x] Overview is the default Control Center page.
- [x] Local usage cards use persisted Capture data.
- [x] Input failure rate has an honest denominator and is not called recognition error rate.
- [x] Actual prepared Speech backend and locale are shown.
- [x] Dictation fallback is visibly labelled **回退**.
- [x] Foundation Models cleanup surface and availability are shown.
- [x] Overview query exists only in the visible feature view.
- [ ] Xcode 27 / macOS 27 Release compile passes.
- [ ] Owner visual check confirms the dashboard is readable at the 960 × 600 minimum window size.

## Follow-up

A future real **识别纠错率 / WER-like** metric requires a trustworthy correction signal with enough observations. Do not derive it from `finalText != recognizedText`; that would incorrectly count filler removal, punctuation, paragraphing and other intended cleanup as recognition mistakes.
