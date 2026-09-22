# M-044 — Control Center process boundary

## Status

**IN PROGRESS** — 2026-09-22

Implementation: PR #106

## Goal

Keep Morie's always-running voice-input runtime lightweight by moving the occasional Control Center SwiftUI/AppKit hierarchy into a disposable process that terminates when its window closes.

## Boundary

- The resident Morie process owns menu bar, hotkey, live Capture, Speech, refinement, delivery, learning and maintenance.
- The Control Center is a new instance of the same signed Morie application, selected by a process-role launch argument.
- The Control Center opens persisted product data for presentation and explicit edits but does not become a second live Capture runtime.
- Runtime-only actions are sent to the resident process.
- Persisted configuration edits notify the resident process to reload its in-memory runtime configuration.
- Closing the Control Center window terminates the Control Center process.
- There is no allocator purge, page-by-page framework-cache workaround or separately signed helper application.

## Evidence

Release Instruments validation showed that Morie-owned Control Center/History presentation objects were released on close, while the original process still retained a materially higher post-UI heap/footprint dominated by generic/framework allocations. Process termination is therefore the presentation-memory ownership boundary.

## Implementation

- [x] Add explicit runtime and Control Center process roles.
- [x] Launch the same signed Morie app as a new Control Center process using native `NSWorkspace` APIs.
- [x] Prevent the Control Center role from running Capture-store launch maintenance.
- [x] Prevent the Control Center role from installing hotkeys, preparing Speech or starting background learning.
- [x] Proxy Capture-only, bootstrap and factory-reset runtime actions to the resident process.
- [x] Notify the resident process when shared persisted configuration changes.
- [x] Reload resident shortcut, refinement, Memory, learning, sound, iCloud and prompt/model configuration after Control Center edits.
- [x] Terminate the Control Center process when its window closes.
- [x] Remove disproven History projection and Dictionary/Memory cache-release experiments.
- [x] Remove temporary per-page/deinit memory probes.
- [x] Document the accepted process boundary in ADR 0002 and `ARCHITECTURE.md`.
- [ ] Xcode 27 compile passes on final implementation.
- [ ] MorieTests pass on final implementation.
- [ ] Owner-device process, feature and memory acceptance passes.

## Owner-device acceptance

- [ ] starting Morie creates one resident runtime process and one menu bar item;
- [ ] opening Control Center creates a second Morie PID and does not create a second menu bar item;
- [ ] opening Control Center repeatedly while it is already open reuses/activates the existing Control Center process;
- [ ] closing the Control Center removes the second PID while the resident runtime and global shortcut remain alive;
- [ ] the resident runtime's heap/physical footprint after Control Center termination returns close to its pre-launch baseline instead of retaining the UI working set;
- [ ] opening Control Center while a Capture is active does not mark that Capture interrupted or run duplicate Speech/hotkey/background workflows;
- [ ] Overview, History, Dictionary, Personal Memory, Settings, Permissions and Diagnostics remain usable;
- [ ] History pagination/detail/audio and explicit re-recognition still work;
- [ ] Dictionary and Personal Memory edits persist and are visible after reopening the Control Center;
- [ ] Capture-only action from History is executed by the resident runtime;
- [ ] Settings changes affect the resident runtime before the next relevant Capture, including shortcut, refinement mode/prompt, Memory/learning flags and sound feedback;
- [ ] factory reset is executed by the resident runtime and exits Morie as before;
- [ ] setup completion launches the isolated Control Center;
- [ ] closing and reopening Control Center repeatedly does not accumulate presentation memory in the resident process.

Do not mark this task DONE until owner-device acceptance passes.
