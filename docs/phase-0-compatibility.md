# Phase 0 · Text Injection Compatibility Matrix

Phase 0 is not accepted based on one demo text field. Each app below must be exercised on a real macOS 27+ Apple Intelligence capable Mac.

| App | Target/focus restore | AX selected-text insert | Clipboard fallback | CJK + Latin | Multiline | Repeated input | Undo | Status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Safari | — | — | — | — | — | — | — | Not tested |
| Chrome | — | — | — | — | — | — | — | Not tested |
| WeChat | — | — | — | — | — | — | — | Not tested |
| Slack | — | — | — | — | — | — | — | Not tested |
| Telegram | — | — | — | — | — | — | — | Not tested |
| Mail | — | — | — | — | — | — | — | Not tested |
| Notes | — | — | — | — | — | — | — | Not tested |
| Xcode | — | — | — | — | — | — | — | Not tested |
| VS Code / Cursor | — | — | — | — | — | — | — | Not tested |
| Terminal | — | — | — | — | — | — | — | Not tested |
| Pages | — | — | — | — | — | — | — | Not tested |
| Microsoft Word | — | — | — | — | — | — | — | Not tested |

## Current injection order

1. Capture the frontmost app before recording.
2. Restore that app after final transcription.
3. Attempt Accessibility `kAXSelectedTextAttribute` insertion at the current selection/caret.
4. If the target does not expose a writable selected-text attribute, preserve the full pasteboard, paste through ⌘V, then restore the pasteboard.

Compatibility results must be recorded here before Phase 0 is marked complete.
