# M-042 — Ephemeral Application Context

Status: **IN PROGRESS**

GitHub: [#97](https://github.com/6spot/Morie/issues/97)

## Why

Typeless-style context-aware dictation shows that transcription quality depends on more than a cleanup prompt. Morie already feeds user Dictionary terms into Apple Speech through `AnalysisContext.contextualStrings`, but it has no separate representation of the application/text environment present when a Capture begins.

Application Context must remain distinct from Dictionary, Personal Memory and Expression Profile:

- **Dictionary** owns durable canonical spellings.
- **Application Context** describes the immediate app/editing environment for one Capture.
- **Personal Memory** owns durable semantic user context.
- **Expression Profile** owns aggregate presentation preferences.

## Current slice

Implement the capture foundation plus bounded Speech vocabulary injection:

- capture the frontmost application identity at voice-input start;
- read bounded selected/focused/nearby text through Apple Accessibility when available;
- pin the target application/PID at Capture Start, resolve bounded AX context asynchronously, and retain the resulting snapshot only for that active Capture;
- keep all raw application text in process memory only;
- log metadata/counts only, never raw application text;
- use no app-specific adapters, screen recording or OCR;
- extract at most 32 high-signal transient terms, prioritizing selected → focused → nearby text;
- merge transient terms after durable Dictionary hints, with a total Speech context cap of 48;
- apply the same merged hints to live Speech and saved-audio high-accuracy re-recognition;
- allow late Application Context to update the active Speech analyzer without delaying capture startup.

## Explicit exclusions

This slice does **not**:

- add raw Application Context text to the cleanup/model prompt;
- use Application Context as a source of final-text facts or requests;
- persist Application Context in Capture/History/Memory;
- add Chrome/Xcode/WeChat-specific behavior;
- add sensitive-app profiles or generalized privacy modes.

## Privacy boundary

`ApplicationContextSnapshot` is intentionally not `Codable`. It must never be attached to `RefinementInput`, `CaptureRefinement`, SwiftData records, History, Memory evidence, or diagnostic message bodies.

Secure text fields contribute no selected/focused/nearby text.

## Acceptance criteria

- [x] Dedicated Application Context value and collector exist.
- [x] Collector uses only Apple Accessibility/AppKit APIs and runs blocking AX IPC on its own actor with native message timeouts.
- [x] Selected/focused/nearby reads have explicit character/node/depth bounds.
- [x] Capture Start pins app/PID without blocking the main actor; the resulting snapshot is accepted only while that Capture remains active.
- [x] Diagnostics contain only app identity and counts, never raw context.
- [x] Snapshot is released when Capture session identity resets.
- [x] High-signal Application Context vocabulary is bounded and never logged verbatim.
- [x] Dictionary hints retain priority when transient Application Context hints are merged.
- [x] Live Speech and saved-audio re-recognition receive the same ephemeral vocabulary.
- [x] Context collection never gates capture startup; late hints update Speech best-effort.
- [x] Latest Xcode 27 product compile passes.
- [x] MorieTests pass with Application Context vocabulary and Memory-isolation coverage.
- [ ] Real-device validation records actual coverage in Chrome/ChatGPT.
- [ ] Real-device validation records actual coverage in Xcode.
- [ ] Real-device validation records actual coverage in WeChat.
- [ ] Real-device validation records actual coverage in TextEdit.

## Refinement safety prerequisite discovered during validation

Real-device validation exposed an existing Personal Memory leakage path: raw Memory notes were included in refinement prompts and a model could reuse an older clause as new user-authored text. Before Application Context is allowed into refinement:

- automatic long-term Memory admission is now conservative about one-off assistant/test/debug requests;
- machine-style automatic Memory names such as snake_case category labels are rejected;
- refinement receives topic-level Memory hints only, never raw Memory notes/evidence;
- raw Memory notes remain local-only for deterministic leakage checks;
- the output guard now checks comma-delimited clauses and long CJK fragments, not only complete Memory sentences.

Existing stored Memory is not automatically deleted or rewritten.

## Follow-up

After the Speech-vocabulary slice is validated on device:

1. tune extraction quality from real Chrome/Xcode/WeChat/TextEdit evidence;
2. decide whether runtime-only semantic Application Context should enter refinement at all;
3. if it does, add only a bounded reference representation, never raw page text by default;
4. update the cleanup prompt with a strict context-only/reference-material contract;
5. extend deterministic output guards so context-only facts cannot enter final text.
