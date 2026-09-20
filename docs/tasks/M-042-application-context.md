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
- keep raw application text out of Capture/History/Memory and refinement input;
- Release diagnostics log metadata/counts only; Debug development tracing may log bounded raw context locally for troubleshooting;
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

`ApplicationContextSnapshot` is intentionally not `Codable`. It must never be attached to `RefinementInput`, `CaptureRefinement`, SwiftData records, History, or Memory evidence. Release diagnostics never include raw context. Debug builds may emit bounded raw context to the local `Dev/*` diagnostic trace as an explicit development-only exception.

Secure Event Input and secure text fields contribute no selected/focused/nearby text and therefore cannot enter either standard or development diagnostics.

## Acceptance criteria

- [x] Dedicated Application Context value and collector exist.
- [x] Collector uses only Apple Accessibility/AppKit APIs and runs blocking AX IPC on its own actor with native message timeouts.
- [x] Selected/focused/nearby reads have explicit character/node/depth bounds.
- [x] Capture Start pins app/PID without blocking the main actor; the resulting snapshot is accepted only while that Capture remains active.
- [x] Release/standard diagnostics contain only app identity and counts; Debug-only `Dev/*` diagnostics can expose bounded raw context locally for troubleshooting.
- [x] Snapshot is released when Capture session identity resets.
- [x] High-signal Application Context vocabulary is bounded; verbatim vocabulary appears only in Debug-only `Dev/*` traces and the runtime inspector.
- [x] Dictionary hints retain priority when transient Application Context hints are merged.
- [x] Live Speech and saved-audio re-recognition receive the same ephemeral vocabulary.
- [x] Context collection never gates capture startup; late hints update Speech best-effort.
- [x] Latest Xcode 27 product compile passes.
- [x] MorieTests pass with Application Context vocabulary and Memory-isolation coverage.
- [x] Debug Capture traces expose AX, vocabulary and exact Speech context decisions without persisting them into Capture/History/Memory.
- [x] Release builds hide raw Application Context inspection and keep privacy-preserving diagnostics.
- [ ] Real-device validation records actual coverage in Chrome/ChatGPT.
- [ ] Real-device validation records actual coverage in Xcode.
- [ ] Real-device validation records actual coverage in WeChat.
- [ ] Real-device validation records actual coverage in TextEdit.

## Development observability

Real-device validation also showed that counts alone are not sufficient to debug
context-aware dictation. Morie now treats development observability as shared
infrastructure rather than temporary logging.

Debug builds provide a Capture-correlated `Dev/*` trace covering:

- build/runtime identity and frozen Capture settings;
- microphone and Speech backend selection;
- Accessibility trust/secure-input/focused-element/traversal decisions;
- bounded raw selected/focused/nearby context;
- every vocabulary candidate, ranking/rejection/de-duplication decision;
- exact contextual strings applied to live and accurate Apple Speech;
- throttled live recognition evolution plus live/accurate/preferred final text;
- Dictionary, Memory and Expression Profile inputs to refinement;
- effective refinement instructions/payload, model backend and token budgets;
- generated output, exact deterministic guard rejection rule/evidence and final text;
- delivery destination and post-insertion learning;
- Memory learner prompts, suggestions, grounding and admission decisions.

Debug diagnostics may contain user-authored/current-app/model text and are local
development artifacts. Release builds keep the existing privacy-preserving
summary logs and hide the raw Application Context inspector. API keys,
authorization headers, Keychain credential contents, secure text fields and
unrelated clipboard contents are never logged.

See [development diagnostics](../development-diagnostics.md) for the complete
contract and troubleshooting workflow.

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
