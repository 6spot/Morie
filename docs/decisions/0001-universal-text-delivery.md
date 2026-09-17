# ADR 0001 — Universal current-app text delivery

- **Status:** Accepted
- **Date:** 2026-09-17
- **Task:** M-002 — macOS Input Foundation

## Context

Real-device macOS 27 validation produced a complete successful voice-input run through hotkey capture, Apple Speech finalization, target-app restoration, and the previous Accessibility selected-text delivery path. The Accessibility write returned success, while the target editor showed no visible inserted text.

That result demonstrates that `AXUIElementSetAttributeValue(..., kAXSelectedTextAttribute, ...) == .success` is not a sufficiently trustworthy cross-application delivery contract for Morie. Building per-application exceptions around that behavior would move Morie toward a growing compatibility matrix inside the implementation.

## Decision

Morie uses one generic delivery mechanism for `currentApp` text insertion in Phase 0:

1. capture the original target application before recording;
2. restore/activate that application after final transcription;
3. wait a short bounded focus-handoff interval;
4. snapshot safe text-like clipboard representations;
5. write the final transcript to the system pasteboard;
6. post a synthetic `Command + V`;
7. after a bounded grace period, restore the previous clipboard only if the pasteboard `changeCount` proves no user/application clipboard write occurred in the meantime.

Direct Accessibility selected-text mutation is not used as a primary or fallback delivery path.

No application bundle identifiers, Electron-family branches, or per-app injection engines are part of this strategy.

## Rationale

The clipboard + standard paste command follows the same application input path users already rely on manually. It provides a single behavior to validate across applications and avoids treating an Accessibility API success code as proof of visible insertion.

The tradeoff is a short temporary clipboard mutation. Morie mitigates that by preserving supported clipboard content and restoring it only when doing so cannot overwrite a newer clipboard value.

## Consequences

- Phase 0 compatibility testing validates one delivery path instead of AX-vs-paste branches.
- Accessibility permission remains required for Morie's global input/event-tap behavior even though direct AX text mutation is removed from delivery.
- If an application does not accept ordinary `Command + V`, that is recorded as a compatibility limitation rather than immediately adding app-specific code.
- Any future alternative delivery mechanism requires a separate evidence-backed architecture decision rather than a bundle-ID exception.
