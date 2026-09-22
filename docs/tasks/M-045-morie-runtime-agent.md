# M-045 — Morie primary app + background Runtime agent

## Status

**IN PROGRESS** — 2026-09-22

Implementation is CI-green on the M-045 branch. Owner-device process, permission, functionality and memory validation is still required before DONE.

Supersedes the process-role direction explored in M-044 / PR #106.

## Goal

Make `Morie.app` the product-facing macOS application and move always-on voice-input execution into a dedicated background `Morie Runtime` agent.

## Product ownership

`Morie.app` is the primary application users install and open. It owns the product icon, Dock / Launchpad / Finder identity, Control Center, History, Dictionary, Personal Memory, Settings and permission-management UI.

`Morie Runtime` is a background agent. It has no product window and no Dock / Cmd-Tab identity. It owns the always-running input runtime: Hotkey, Capture, Speech, refinement, text delivery, runtime Dictionary / Memory usage, background learning, maintenance and durable stores.

Closing the Morie Control Center must be allowed to terminate the GUI process without stopping voice input. Reopening Morie starts/activates the GUI and reconnects to the already-running Runtime.

## Target architecture

```text
Morie.app
├─ App icon / Dock / Launchpad / Finder identity
├─ Control Center
├─ SwiftUI / AppKit UI
├─ lightweight presentation state
├─ History / Dictionary / Memory / Settings view models
└─ Runtime IPC client

Morie Runtime
├─ Menu bar status entry
├─ Hotkey
├─ Capture / Speech
├─ Refinement / delivery
├─ Capture / Dictionary / Memory stores
├─ Background learning / maintenance
└─ Runtime IPC server
```

## Process and service model

- `Morie.app` remains the main macOS Application target.
- `Morie Runtime` is registered as an embedded background launch agent using Apple ServiceManagement (`SMAppService`).
- The agent advertises a launchd Mach service and exposes a narrow typed IPC boundary through `NSXPCConnection` / `NSXPCListener`.
- The GUI never starts a second Capture runtime.
- The Runtime never constructs Control Center views.
- Runtime data stores have one process owner: `Morie Runtime`.
- The GUI consumes Codable / transport-safe DTOs and sends explicit commands through IPC.
- Do not use `DistributedNotificationCenter` as the primary RPC transport.
- Do not share mutable SwiftData model objects or `ModelContext` instances across process boundaries.

## Development-stage migration policy

Morie is still in active development. M-045 makes **no compatibility guarantee** for pre-M-045 local data, preference domains or process-owned state. Do not add migration or compatibility shims for old development builds; existing development data may be reused or discarded only as a consequence of the current implementation.

## Runtime-owned capabilities

- [x] global shortcut / Hotkey
- [x] live Capture lifecycle
- [x] microphone / Speech recognition
- [x] saved-audio re-recognition
- [x] refinement providers and prompt execution
- [x] text delivery to the focused application
- [x] CaptureStore / History persistence
- [x] DictionaryStore
- [x] MemoryStore and learning
- [x] expression / post-insertion learning
- [x] launch maintenance and recovery
- [x] menu-bar runtime status / quick actions
- [x] typed XPC service

## Morie.app-owned capabilities

- [x] primary application identity and app icon
- [x] native Control Center shell
- [x] Overview presentation
- [x] History list/detail presentation
- [x] Dictionary presentation and editing
- [x] Personal Memory presentation and editing
- [x] Settings and Permissions UI
- [x] Runtime connection / reconnect state
- [x] typed XPC client

## IPC surface

The public Runtime IPC contract must be intentionally small. Expected groups include:

- runtime snapshot / health;
- start / stop or capture-only actions;
- permission state and permission actions;
- History page, detail, delete and saved-audio re-recognition;
- Dictionary query / mutations;
- Memory query / mutations;
- Settings snapshot / mutations;
- factory reset / runtime restart where required.

Prefer request/response DTOs over leaking feature controllers or persistence models into the GUI process.

## Migration plan

- [x] Freeze PR #106 as the M-044 experimental checkpoint; do not merge it.
- [x] Add `Morie Runtime` agent target and launch-agent plist.
- [x] Register / ensure Runtime through `SMAppService` from Morie.app.
- [x] Add typed XPC protocol, transport DTOs, listener and client.
- [x] Move menu-bar / Hotkey / Capture composition from Morie.app into Runtime.
- [x] Keep Morie.app as the normal GUI / Control Center application.
- [x] Move durable Store ownership to Runtime only.
- [x] Replace direct Control Center Store access with IPC-backed presentation models.
- [x] Remove the temporary `Morie Control Center` helper-tool architecture from M-044.
- [x] Remove duplicate microphone / Speech capabilities from the GUI target.
- [x] Preserve the current global Control Center UI contract; architecture work must not redesign page geometry or toolbar styling.
- [x] Update tests and CI for both targets.

## Acceptance

- [ ] Finder / Launchpad identifies the product as `Morie`; opening it displays the Control Center.
- [ ] Morie has the normal application icon and GUI application identity.
- [ ] `Morie Runtime` runs without Dock icon, Cmd-Tab entry or product window.
- [ ] closing the Morie Control Center terminates/releases the GUI process while `Morie Runtime` remains alive;
- [ ] global shortcut still records, recognizes, refines and inserts text while Morie.app is closed;
- [ ] reopening Morie reconnects to the existing Runtime instead of creating a second Runtime;
- [x] only Runtime owns microphone / Speech execution and runtime maintenance;
- [x] only Runtime owns writable Capture / Dictionary / Memory persistence;
- [x] Control Center History / Dictionary / Memory / Settings operate through IPC-backed presentation state;
- [x] UI layout, unified toolbar, sidebar geometry and established Apple-native Control Center styling remain unchanged by the architecture migration;
- [ ] Runtime idle physical footprint stays near the pre-Control-Center baseline;
- [ ] closing / reopening Morie repeatedly does not accumulate Control Center presentation memory in Runtime;
- [x] Xcode 27 compile and MorieTests pass;
- [ ] owner-device process, permission, functionality and memory validation passes.

Do not mark this task DONE until the owner-device process and memory boundary is verified.
