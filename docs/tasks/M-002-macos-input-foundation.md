# M-002 — macOS Input Foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-17
- **GitHub Issue:** https://github.com/6spot/Morie/issues/2
- **Pull Request:** https://github.com/6spot/Morie/pull/3
- **Branch:** `phase0/input-foundation`

## Why

Morie's first product dependency is not Memory or cloud infrastructure. It is a reliable macOS voice-input loop. If recording, transcription, focus restoration, and text delivery are not dependable in everyday apps, later Personal Memory work has no stable product surface to improve.

## Scope

Included:

- macOS 27+ only;
- Apple Intelligence-capable Macs;
- native Swift / SwiftUI / AppKit;
- Private Mode capability checks relevant to Phase 0;
- menu bar application shell;
- global hold-to-talk shortcut;
- latest Apple Speech transcription stack;
- capture of the original frontmost application;
- focus restoration;
- Accessibility text insertion;
- clipboard + paste fallback;
- failure/resource cleanup;
- real-device target-app compatibility validation;
- initial performance baseline.

Explicitly excluded:

- iOS;
- Morie Cloud;
- provider abstraction;
- legacy ASR fallback;
- third-party runtimes/models;
- durable Capture storage and History;
- Personal Memory;
- MCP/Public API/Relay.

## Acceptance criteria

1. On a supported Mac, Morie enters Ready only when required Private Mode capabilities for the current phase are available.
2. Holding the global shortcut starts intentional voice capture and releasing it finalizes the session.
3. The modern Apple Speech stack produces the transcript without a legacy recognition fallback.
4. Morie remembers the app active before capture, returns focus to it, and inserts the final transcript at the intended input location where supported.
5. Direct Accessibility insertion falls back safely to clipboard paste when necessary.
6. Cancel/error/interruption paths release capture resources and leave the app recoverable.
7. The compatibility matrix is tested on real target applications.
8. Initial binary/startup/memory/latency/energy observations are recorded.
9. No third-party runtime or package is required.

## Subtasks / progress

| Subtask | Status | Notes |
| --- | --- | --- |
| Native macOS project | DONE | `Morie.xcodeproj`, deployment target macOS 27.0. |
| Menu Bar shell | DONE | SwiftUI `MenuBarExtra`. |
| Foundation Models capability check | DONE | `SystemLanguageModel.default.availability` and locale check. |
| Speech capability/locale check | DONE | `SpeechTranscriber` availability and supported locale. |
| Microphone/Speech authorization | DONE | Permission checks implemented. |
| Accessibility trust check | DONE | Required for global interaction/text delivery. |
| iCloud/CloudKit capability check | DEFERRED | Belongs with the real CloudKit container/entitlements in M-003; do not fake it in Phase 0. |
| Global hold-to-talk hotkey | IN PROGRESS | Control+Space implementation exists; real-device validation pending. |
| Modern Apple Speech pipeline | IN PROGRESS | `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory`, `CaptureInputSequenceProvider`; compile/runtime validation pending. |
| Original-app capture/focus restore | IN PROGRESS | Implemented with `NSWorkspace`/`NSRunningApplication`; validation pending. |
| Accessibility insertion | IN PROGRESS | Selected-text mutation implemented; matrix validation pending. |
| Clipboard paste fallback | IN PROGRESS | Cmd+V path implemented; clipboard timing/restore behavior requires validation. |
| Cancellation/interruption hardening | IN PROGRESS | Basic cleanup exists; interruption cases remain. |
| Xcode/macOS 27 build | TODO | Must be performed on a supported Mac. |
| Compatibility matrix | TODO | See `../validation.md`. |
| Performance baseline | TODO | Record after the first stable device build. |

## Implementation notes

### App state

The initial controller keeps the Phase 0 flow explicit:

`checking → ready → recording → delivering → ready`

Blocked/failed states carry user-visible reasons. This is deliberately small rather than introducing a generic workflow framework.

### Speech

The implementation targets the current Speech framework path:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- `CaptureInputSequenceProvider`

There is no `SFSpeechRecognizer` recognition fallback. The older type is currently used only for Speech authorization where needed by the platform API.

### Delivery

The target application is captured before recording. On completion:

1. reactivate the target application;
2. allow focus to settle;
3. attempt Accessibility selected-text insertion;
4. if unavailable, temporarily place the transcript on the pasteboard and synthesize Cmd+V;
5. restore representable previous pasteboard contents after a short delay.

Real applications vary considerably, so this is not considered complete before matrix testing.

### Capability gate boundary

The product baseline requires iCloud/CloudKit for Private Mode, but M-002 does not yet own persistence or a real CloudKit container. iCloud availability will therefore be added in M-003 when entitlements/container semantics are real. M-002 must not claim full Private Mode readiness beyond the capabilities it actually implements.

## Validation performed

Verified at repository/static level:

- source files are connected to the Xcode project;
- deployment target is macOS 27.0;
- no external package dependency is present;
- implementation boundaries match the V0 architecture baseline;
- Phase 0 Issue and draft PR exist.

Not yet verified:

- Xcode 27 compilation;
- microphone/Speech runtime behavior;
- Apple Intelligence behavior on supported hardware;
- Accessibility permission lifecycle;
- global shortcut behavior across apps;
- focus restoration timing;
- target-app injection matrix;
- performance/energy measurements.

These items keep the task `IN PROGRESS`.

## Known issues / risks

- New Apple Speech APIs must be compiled against the actual target SDK; API shape changes discovered by Xcode should be fixed against official current APIs rather than introducing legacy fallback.
- Global event monitoring behavior can vary with Accessibility/Input Monitoring permissions.
- `kAXSelectedTextAttribute` support differs between applications and custom editors.
- Clipboard restoration timing needs careful testing so it neither overwrites a user's subsequent copy nor races the target app's paste action.
- Focus restoration may need app/editor-specific handling discovered by the compatibility matrix.

## Follow-up

After M-002 is stable, M-003 introduces the Capture-first persistence boundary:

- durable local Capture storage;
- History;
- App Context persistence;
- CloudKit/iCloud container and sync;
- iCloud capability gate.

Memory extraction/personalization remains later work.

## References

- Product baseline: Apple Native First · Product & Architecture Baseline v2 · 2026-09-17
- Issue #2: https://github.com/6spot/Morie/issues/2
- Draft PR #3: https://github.com/6spot/Morie/pull/3
- Validation matrix: [`../validation.md`](../validation.md)
- Development guide: [`../development.md`](../development.md)
- Deployment guide: [`../deployment.md`](../deployment.md)