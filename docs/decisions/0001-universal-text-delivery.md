# ADR 0001 — Universal current-focus text delivery

- **Status:** Accepted, amended by M-014
- **Date:** 2026-09-17
- **Amended:** 2026-09-19
- **Tasks:** M-002 macOS Input Foundation / M-014 Current Keyboard Focus Input

## Context

Real-device macOS 27 validation showed that a successful Accessibility selected-text write is not a reliable proof that visible text reached the target editor. Morie therefore standardized on the same generic input path users already trust: clipboard staging plus one synthetic `Command + V`.

The original version of this ADR also pinned the application/window active when recording began and restored it before paste. M-014 superseded that routing behavior. For an interactive voice input tool, restoring the record-start application can pull the user away from a field they intentionally focused while Speech or cleanup was still running.

## Decision

Morie uses one generic delivery mechanism for ordinary `currentApp` input:

1. do **not** pin a delivery app/window when recording begins;
2. when final text is ready, resolve the external application that currently owns keyboard focus/frontmost interaction;
3. reject Morie itself or the absence of a usable external destination as an ordinary delivery failure/fallback condition;
4. snapshot safe text-like clipboard representations;
5. write the final text to the system pasteboard;
6. post one synthetic `Command + V`; the receiving application's current first-responder chain chooses the field;
7. after a bounded grace period, restore the previous clipboard only when pasteboard `changeCount` proves no user/application clipboard write occurred in the meantime.

Morie does not activate or restore the application that was active when recording began. There is no focus-handoff delay for ordinary current-app input.

Direct Accessibility selected-text mutation is not used as a primary or fallback delivery path. No application bundle identifiers, Electron-family branches, or per-app injection engines are part of this strategy.

## Rationale

Current-focus delivery behaves like a keyboard/input method rather than a deferred automation target. A user can start speaking in one app, move to another field while recognition/cleanup finishes, and receive the result wherever they intentionally left keyboard focus.

Clipboard + standard paste also keeps one cross-application contract to validate and avoids treating an Accessibility API success code as proof of visible insertion.

The tradeoff is a short temporary clipboard mutation. Morie mitigates that by preserving supported clipboard content and restoring it only when doing so cannot overwrite a newer clipboard value.

## Consequences

- Phase 0 compatibility testing validates one current-focus paste path instead of AX-vs-paste or restore-vs-current-focus branches.
- Successful Capture metadata records the application that actually received the paste, not the app that happened to be frontmost at record start.
- Post-insertion correction observation uses that same actual delivery application.
- Accessibility permission remains required for Morie's global input/event-tap and bounded post-insertion behavior even though direct AX mutation is removed from delivery.
- If an application does not accept ordinary `Command + V`, that is recorded as a compatibility limitation rather than immediately adding app-specific code.
- If delivery cannot resolve a valid external target or cannot dispatch paste, final text remains available on the ordinary clipboard and the HUD reports the fallback.
- Any future alternative delivery mechanism requires a separate evidence-backed architecture decision rather than a bundle-ID exception.
