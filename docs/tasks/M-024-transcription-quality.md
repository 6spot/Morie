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

## 2026-09-19 native backend upgrade

Repository review found that live input still selected `DictationTranscriber(.progressiveLongDictation)` unconditionally even on systems where Apple's newer `SpeechTranscriber` is available.

Morie now resolves one Apple-native backend at runtime:

```text
requested locale
    ↓
SpeechTranscriber supported?
    ├─ yes → SpeechTranscriber
    │          live:  .progressiveTranscription
    │          file:  .transcription
    │
    └─ no  → DictationTranscriber
               live:  .progressiveLongDictation
               file:  .longDictation
```

The newer model remains fully on-device. Existing `AnalysisContext.contextualStrings` dictionary hints are still applied to the live `SpeechAnalyzer`. There is no cloud recognizer and no third-party fallback.

Bootstrap prepares the selected backend before Ready. If SpeechTranscriber reports support but its asset preparation fails, bootstrap can prepare DictationTranscriber instead so input remains available. Saved-audio recognition follows the same preference and only falls back during backend/asset setup, not after a recognition run has already begun.

Diagnostics now record the selected backend, normalized locale and dictionary-hint count. This is intentionally left IN PROGRESS until the owner device confirms which backend zh-CN selects and supplies additional before/after samples.

### Validation

- [x] Xcode 27 / macOS 27 Release product compile passes for the new SpeechTranscriber APIs (CI run #81).
- [ ] Owner device confirms `SpeechQuality ... backend=SpeechTranscriber` or records the Dictation fallback reason.
- [ ] Controlled Mandarin sample after backend change.
- [ ] Mixed Chinese/English sample after backend change.
- [ ] Dictionary-term sample after backend change.

## 2026-09-19 owner follow-up — paragraphing and History simplification

The owner-device log confirms the preferred zh-CN backend is now active:

```text
Preferred Speech backend for zh-CN: SpeechTranscriber (zh_CN)
Session 151BA616 backend=SpeechTranscriber; locale=zh_CN; dictionaryHints=13
```

This closes the backend-selection question for the current owner device. The next quality issue is cleanup formatting rather than backend selection: long continuous Chinese speech was semantically cleaned but still returned as one dense paragraph.

Changes in this follow-up:

- long-input paragraphing is now an explicit cleanup requirement, not merely an optional newline hint;
- paragraph boundaries follow semantic/topic transitions rather than fixed character counts;
- 2–4 natural paragraphs are preferred for long multi-topic speech;
- headings/lists are still forbidden unless the speaker actually expressed that structure;
- a long-form Chinese example is included in the system instructions;
- History no longer renders the per-Capture Personal Memory section or memory-analysis source text;
- the underlying Memory feature and stored analysis data are intentionally untouched.

Owner validation still needs to check whether the stronger cleanup instruction produces natural paragraphs on ordinary unscripted speech.

## 2026-09-19 semantic formatting follow-up

Review of current Type4Me/OpenLess behavior changed the paragraphing direction:

- Type4Me's prompt-evaluation notes show that long work reports / technical discussions become more readable when topic blocks are preserved and explicit multi-item speech can become lists, but aggressive headings/lists are not appropriate for every input.
- OpenLess's current prompt language is closer to Morie's default use case: short/single-topic text stays as a coherent paragraph; long speech gets punctuation and sentence boundaries; scattered speech must not be merged back into one large block; event/topic boundaries should be preserved; complex content may use a few natural paragraphs, while short content should not be over-structured.

Morie therefore removes the rigid `2–4 paragraphs` preference and adds a per-input deterministic formatting hint instead of another model call.

### Runtime hint

`InputRefiner.formattingHint(for:)` produces one of:

- `compact` — short/single-topic input; prefer one coherent paragraph;
- `semanticParagraphs` — long input with repeated topic-transition cues / multiple sentence boundaries; separate real topic, event or request blocks with blank lines;
- `explicitList` — the speaker explicitly enumerated multiple items (`第一/第二/第三`, `首先/其次/最后`, `一是/二是/...`).

The hint is serialized with the prompt and reinforced in the Foundation Models `@Guide`. It is only a presentation hint: it cannot add facts, headings, categories or extra list items.

This specifically targets owner samples that contain several independent intentions in one natural spoken turn (for example: project status → new audio-feedback request → discussion of Morie's own paragraphing quality). The user should not need to speak in pre-written paragraphs for Morie to preserve those boundaries.

### Validation

- [x] short single-topic sample classifies as `compact`;
- [x] explicit enumeration classifies as `explicitList`;
- [x] owner-style long multi-topic sample classifies as `semanticParagraphs`;
- [x] macOS 27 Release compile passes;
- [ ] owner-device unscripted speech confirms the hint improves real paragraph output without over-fragmenting short messages.

Semantic-format implementation head `57a0f3d435c855ae03114f5b0efb19d60ee64820` passed GitHub Actions `macOS 27 CI` run #97.

## 2026-09-19 owner sample — cleanup context leakage

Owner-device History exposed a stronger failure than paragraphing alone:

```text
原始语音识别：
这几个分段我也没测试，这是我自己手动分的段嗯。

最终文字：
这几个分段我也没测试，这是我自己手动分的段。

GitHub 里有 issues。
```

The second sentence is not grounded in the displayed raw transcript. This is classified as **cleanup semantic injection**, not ASR or paragraphing error.

Repository review found two concrete priming risks:

1. `DictionaryStore.relevantEntries(for:)` ignored its `text` argument and sent the entire bounded Dictionary to Foundation Models on every cleanup request.
2. `InputRefiner.instructionsText` had grown into a long rule/example document containing real built-in vocabulary such as GitHub / Issues, increasing the chance that the on-device model treats helper context as content.

### Adapted reference lessons

OpenLess's current Light prompt contributes the useful contract **润色，不是重写，更不是扩写**, a small set of allowed edit operations, conservative ASR correction and a strong no-expansion boundary. Type4Me's evaluation material shows that explicit multi-item technical speech benefits from structure, but its richer structured rewrites are not appropriate as Morie's default cleanup mode.

Morie therefore does **not** copy either prompt wholesale. The Apple Foundation Models path gets a shorter closed-world instruction set with fewer competing rules and no vocabulary-bearing examples.

### Runtime changes

- Speech keeps the full bounded canonical hint list; ASR biasing is unchanged.
- Foundation Models cleanup gets at most 16 canonical terms that are actually present or a close Latin spelling neighbor of a transcript token.
- Confirmed correction mappings are loaded only when their observed wrong form is present, applied deterministically before the model, and are **not serialized into the Foundation Models prompt**.
- Prompt field `dictionary` is renamed to `spellingCandidates` to make its role explicit.
- The system prompt states that helper fields may only correct/disambiguate text already expressed and can never create a sentence/topic.
- `@Guide` repeats the same closed-world rule at the generated field boundary.
- `ValidatedRefinement` adds a final grounding check for longer output clauses; a clearly unrelated generated sentence is rejected and the dictionary-prepared original is used instead.

### Regression target

The exact owner sample above is now a regression fixture: appending `GitHub 里有 issues。` to the unrelated source must fail validation.

### Validation

- [x] unrelated dictionary / confirmed-correction context is filtered out in logic tests;
- [x] near Latin spelling `Gethab` still selects `GitHub` as a cleanup candidate;
- [x] unrelated appended sentence is rejected by refinement validation;
- [ ] Xcode 27 / macOS 27 Release compile passes;
- [ ] test-capable run executes Dictionary + Personalization logic tests;
- [ ] owner device confirms the same class of short input no longer gains unrelated dictionary vocabulary.
