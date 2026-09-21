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
- keep raw application text out of Capture/History/Memory and refinement input; only the bounded extracted term set may reach refinement as runtime-only reference data;
- Release diagnostics log metadata/counts only; Debug development tracing may log bounded raw context locally for troubleshooting;
- use no app-specific adapters, screen recording or OCR;
- extract at most 32 high-signal transient terms, prioritizing selected → focused → nearby text;
- merge transient terms after durable Dictionary hints, with a total Speech context cap of 48;
- apply the same merged hints to live Speech and saved-audio high-accuracy re-recognition;
- allow late Application Context to update the active Speech analyzer without delaying capture startup.

## Explicit exclusions

This slice does **not**:

- add raw Application Context text to the cleanup/model prompt;
- give Application Context any instruction/tool authority; extracted terms are read-only model reference data;
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
- generated output, transport/lifecycle boundary decisions and final text;
- delivery destination and post-insertion learning;
- Memory learner prompts, suggestions, grounding and admission decisions.

Debug diagnostics may contain user-authored/current-app/model text and are local
development artifacts. Release builds keep the existing privacy-preserving
summary logs and hide the raw Application Context inspector. API keys,
authorization headers, Keychain credential contents, secure text fields and
unrelated clipboard contents are never logged.

See [development diagnostics](../development-diagnostics.md) for the complete
contract and troubleshooting workflow.

## Refinement boundary discovered during validation

Validation exposed two separate concerns that are now intentionally separated:

- raw Personal Memory notes/evidence are not sent to refinement; only topic-level hints are;
- bounded Application Context terms may be sent as runtime-only reference data;
- reference data is serialized separately from trusted instructions and cannot grant tools or actions;
- the model, not local regex/word-list code, decides semantic relevance, self-correction, number/time meaning, negation, language and structure;
- post-generation code validates only payload/lifecycle integrity. Stale, cancelled, timed-out or unsaved results cannot be delivered.

This avoids rebuilding a weaker multilingual NLP engine in `CaptureRefinement` while keeping privacy, authority and lifecycle boundaries deterministic.

## Follow-up

After the Speech-vocabulary slice is validated on device:

1. tune extraction quality from real Chrome/Xcode/WeChat/TextEdit evidence;
2. evaluate whether the bounded term representation is sufficient before considering richer semantic context;
3. keep any richer context explicitly bounded, runtime-only and separated as untrusted/reference data;
4. validate model behavior with real-device cases instead of adding language-specific output guards.
