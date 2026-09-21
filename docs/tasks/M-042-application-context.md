# M-042 — Ephemeral Application Context

Status: **DONE** — 2026-09-21

GitHub: [#97](https://github.com/6spot/Morie/issues/97) / [PR #98](https://github.com/6spot/Morie/pull/98)

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
- read bounded selected text plus a focused-control cursor window through Apple Accessibility when available;
- pin the target application/PID at Capture Start, resolve bounded AX context asynchronously, and retain the resulting snapshot only for that active Capture;
- keep raw application text out of Capture/History/Memory and refinement input; only the bounded extracted term set may reach refinement as runtime-only reference data;
- Release diagnostics log metadata/counts only; Debug development tracing may log bounded raw context locally for troubleshooting;
- use no app-specific adapters, screen recording or OCR;
- extract at most 32 high-signal transient terms, prioritizing selected → cursor-window text;
- merge transient terms after durable Dictionary hints, with a total Speech context cap of 48;
- apply the same merged hints to live Speech and saved-audio high-accuracy re-recognition;
- allow late Application Context to update the active Speech analyzer without delaying capture startup.

## Host-document boundary

Real-device validation showed that AX tree traversal collects application chrome rather than document context (for example chat lists, menus and sidebars). M-042 therefore follows the OpenLess host-document boundary:

- trust only the focused AX text element that owns a real `AXSelectedTextRange`;
- read only that element's own `AXValue`, or bounded `AXStringForRange` for large/non-value controls;
- keep a 600-character cursor window, biased roughly 80% before / 20% after the caret;
- treat negative/missing caret locations, unknown document length or unsupported range reads as no context;
- never recover missing context by walking parents, siblings or descendant UI trees.

Wrong context is worse than absent context. Vocabulary extraction still reduces this cursor window to the same bounded runtime-only reference terms before Speech/refinement.

## Explicit exclusions

This slice does **not**:

- add raw Application Context text to the cleanup/model prompt;
- give Application Context any instruction/tool authority; extracted terms are read-only model reference data;
- persist Application Context in Capture/History/Memory;
- add Chrome/Xcode/WeChat-specific behavior;
- add sensitive-app profiles or generalized privacy modes.

## Privacy boundary

`ApplicationContextSnapshot` is intentionally not `Codable`. It must never be attached to `RefinementInput`, `CaptureRefinement`, SwiftData records, History, or Memory evidence. Release diagnostics never include raw context. Debug builds may emit bounded raw context to the local `Dev/*` diagnostic trace as an explicit development-only exception.

Secure Event Input and secure text fields contribute no selected/cursor text and therefore cannot enter either standard or development diagnostics.

## Acceptance criteria

- [x] Dedicated Application Context value and collector exist.
- [x] Collector uses only Apple Accessibility/AppKit APIs and runs blocking AX IPC on its own actor with native message timeouts.
- [x] Selected text and the focused-control cursor window have explicit character bounds; no ancestor/sibling/subtree traversal is performed.
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
- [x] Real-device validation confirms TextEdit exposes only the focused document cursor window and selected text.
- [x] Real-device validation confirms WeChat empty input fails closed instead of importing chat lists, menus or sidebars.
- [x] Real-device validation confirms bounded Application Context terms repair proper nouns through Cloud refinement without leaking unrelated context.
- [x] Real-device validation confirms empty live + saved-audio recognition is discarded instead of creating History junk.
- [x] Real-device validation confirms cancelling during Cloud refinement prevents late model output from being delivered.

## Development observability

Real-device validation also showed that counts alone are not sufficient to debug
context-aware dictation. Morie now treats development observability as shared
infrastructure rather than temporary logging.

Debug builds provide a Capture-correlated `Dev/*` trace covering:

- build/runtime identity and frozen Capture settings;
- microphone and Speech backend selection;
- Accessibility trust/secure-input/focused-element/caret-window decisions;
- bounded raw selected/cursor context;
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

## Validation result

Owner-device validation completed on 2026-09-21.

The temporary M-042 unified test protocol was consolidated into this task record after completion and removed from the top-level `docs/` directory.

- TextEdit returned the exact focused document window and extracted `Zevranta` / `Norvella` without menu/UI noise.
- WeChat with an empty focused input returned no cursor context, confirming the collector fails closed instead of traversing surrounding UI.
- Selected text, Dictionary terms and cursor-derived terms all reached refinement as bounded reference data and were used correctly by a standard OpenAI-compatible Cloud model.
- Self-correction, large deletion/restart, condition/negation/time semantics and unrelated-context non-leakage passed with Cloud refinement.
- Empty recognition no longer creates a History item or retains source audio after both live and saved-audio recognition produce no usable text.
- Escape during Cloud refinement ends the foreground Capture and late provider output is not delivered.
- The draining-provider concurrency invariant remains covered by automated tests rather than an artificial UI concurrency path.

Chrome/Xcode-specific coverage is not a correctness dependency for this slice because the collector is deliberately app-generic and fails closed when the focused control does not expose a trustworthy AX caret/document range. Additional host-application coverage can be added as regression evidence without changing the M-042 boundary.

## Follow-up

1. keep the focused-control host-document boundary unchanged unless real app evidence shows a generic AX gap;
2. evaluate richer semantic context only if the bounded term representation proves insufficient in real use;
3. keep any richer context explicitly bounded, runtime-only and separated as untrusted/reference data;
4. continue validating model behavior with real-device cases instead of adding language-specific output guards.
