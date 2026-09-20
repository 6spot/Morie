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

## First slice

Implement only the capture foundation:

- capture the frontmost application identity at voice-input start;
- read bounded selected/focused/nearby text through Apple Accessibility when available;
- freeze that snapshot for the Capture lifetime;
- keep all raw application text in process memory only;
- log metadata/counts only, never raw application text;
- use no app-specific adapters, screen recording or OCR.

## Explicit exclusions

This slice does **not**:

- inject Application Context vocabulary into Speech yet;
- add Application Context to the cleanup/model prompt yet;
- persist Application Context in Capture/History/Memory;
- add Chrome/Xcode/WeChat-specific behavior;
- add sensitive-app profiles or generalized privacy modes.

## Privacy boundary

`ApplicationContextSnapshot` is intentionally not `Codable`. It must never be attached to `RefinementInput`, `CaptureRefinement`, SwiftData records, History, Memory evidence, or diagnostic message bodies.

Secure text fields contribute no selected/focused/nearby text.

## Acceptance criteria

- [x] Dedicated Application Context value and collector exist.
- [x] Collector uses only Apple Accessibility/AppKit APIs.
- [x] Selected/focused/nearby reads have explicit character/node/depth bounds.
- [x] A Capture freezes one snapshot at Start.
- [x] Diagnostics contain only app identity and counts, never raw context.
- [x] Snapshot is released when Capture session identity resets.
- [ ] Xcode 27 product compile passes.
- [ ] Real-device validation records actual coverage in Chrome/ChatGPT.
- [ ] Real-device validation records actual coverage in Xcode.
- [ ] Real-device validation records actual coverage in WeChat.
- [ ] Real-device validation records actual coverage in TextEdit.

## Follow-up

After real-device collection evidence is understood:

1. extract bounded contextual vocabulary;
2. merge it with Dictionary hints for Apple Speech;
3. add runtime-only Application Context to refinement input;
4. update the cleanup prompt with a strict context-only/reference-material contract;
5. extend deterministic output guards so context-only facts cannot enter final text.
