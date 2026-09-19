# M-014 — Current keyboard focus input

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-014-current-focus-input`
- **Depends on:** M-002 input foundation, M-003 durable Capture, M-009 integrated input loop
- **Issue / PR:** —

## Why

Morie is an interactive voice-input tool. Its delivery semantics should match a keyboard/input method: when final text is ready, the text goes to the application and field that currently own keyboard focus.

The superseded implementation pinned the application and window that were active when recording started, then reactivated that application before paste. That behavior can pull the user away from the app they intentionally switched to while Speech or Foundation Models is still processing, and it makes delivery depend on window identity that macOS does not require for ordinary keyboard input.

Type4Me reached the same conclusion after maintaining much more complex AX/focus-target logic. Morie adapts the product lesson without importing its compatibility machinery.

## Scope

- Stop pinning an application/window at recording start for ordinary `.currentApp` input.
- Resolve `NSWorkspace.shared.frontmostApplication` only when final text is ready to deliver.
- Never activate or switch back to the app that was active at recording start.
- Dispatch one generic clipboard-backed synthetic `Cmd+V`; let the receiving app's first-responder chain choose the field.
- Preserve change-count-aware clipboard restoration and clipboard fallback.
- Save the actual delivery app/bundle on the completed Capture.
- Pass that same actual delivery application into the bounded post-insertion dictionary-correction observer.
- Remove obsolete original-window persistence and focus-handoff delay directly.

## Exclusions

Automation/headless pinned targets, URL-scheme task routing, AX editability proof, app-specific delivery branches, legacy target-window schema compatibility, iOS, Cloud and external dependencies.

## Acceptance criteria

1. Starting an ordinary recording does not pin a delivery application or window.
2. If the user switches apps or fields while recording, Speech finalization or cleanup is running, delivery follows the external app that is frontmost when paste begins.
3. Morie never activates or restores the record-start app during ordinary interactive delivery.
4. If Morie itself is frontmost, no external app is available, or paste event creation fails, the final text is preserved on the ordinary clipboard and the HUD reports the fallback.
5. Successful delivery records the actual delivery app/bundle, not the app that happened to be frontmost at record start.
6. Clipboard restoration remains guarded by pasteboard `changeCount`; Morie never overwrites a newer user/app clipboard change.
7. Synthetic paste events remain identifiable to the hotkey layer and cannot retrigger capture.
8. Capture-only mode remains delivery-free.
9. App compilation and logic tests pass. Current-focus routing across native, Electron, terminal and custom-rendered editors remains signed-device acceptance.

## Progress

- [x] Record current-focus input as the active product contract.
- [x] Remove controller-owned target app/window state and original-window persistence.
- [x] Resolve delivery destination at final paste time without app activation.
- [x] Persist actual delivery app/bundle and use it for post-insertion correction observation.
- [x] Update M-002, architecture, validation and Type4Me reference decisions.
- [ ] Pass hosted macOS 27 CI.
- [ ] Complete signed-device current-focus routing matrix.

## Implementation notes

`TextInjector.deliver(_:)` resolves the external frontmost application immediately before writing the temporary clipboard value and posting `Cmd+V`. It does not query AX for an editable target and does not call `activate()`.

`AppController` no longer owns `targetApplication` or `targetWindowNumber`. A normal current-app Capture is created without application metadata; after paste dispatch, `CaptureStore.markDelivered` saves the application name and bundle identifier returned by the delivery path. Capture-only records can still retain Morie as their source context.

`CaptureRecord.originalWindowNumber` and the matching `beginVoiceCapture(... windowNumber:)` argument are removed directly. This repository is still in development and does not retain an adapter for the superseded target-window schema.

## Reference decision

- **ADAPT:** Type4Me's current-keyboard-focus model, generic paste dispatch, clipboard preservation and decision not to make AX editability a prerequisite for ordinary input.
- **DROP:** start-time target pinning, window identity validation, focus restoration, AX target proof, automation/headless dual routing and per-app compatibility branches.
- **VERIFY:** actual current-focus routing, custom editors, selected-text replacement, rapid app switching and clipboard-manager behavior on signed macOS 27.

## Validation

Hosted CI establishes compilation and deterministic logic only. It cannot prove which app owns keyboard focus, where a synthetic paste lands, or whether a custom-rendered editor responds correctly. Those remain interactive checks in `docs/validation.md`.
