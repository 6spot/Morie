# ADR 0002 — Disposable Control Center process

- **Status:** Accepted
- **Date:** 2026-09-22
- **Task:** M-044 Control Center process boundary

## Context

Morie is primarily an always-running voice-input runtime. The menu bar process owns the global shortcut, Speech, refinement, delivery, background learning and maintenance, while the Control Center is opened only occasionally.

Owner-device memory diagnostics and a Release Instruments trace showed that closing the Control Center correctly destroyed Morie-owned presentation objects, including the Control Center session, presentation state, History controller, History records and presentation ModelContext. The resident process nevertheless stayed materially above its cold baseline after the first full SwiftUI/AppKit Control Center session.

The persistent remainder was dominated by generic heap/anonymous VM and framework/runtime allocations warmed by presentation, including AppKit/SwiftUI/CoreUI/font/language resources, rather than a retained Morie page owner. Apple does not expose a supported API for forcing those process-wide framework caches back to the pre-UI cold state.

Continuing to add page-specific cleanup, allocator purge tricks or artificial cache invalidation would therefore treat a process-lifetime platform behavior as if it were a feature-state leak.

## Decision

The always-running runtime and the Control Center use separate process lifetimes.

The resident Morie process:

- owns the menu bar item;
- owns the global shortcut and active Capture lifecycle;
- owns Speech, refinement, delivery, background learning and maintenance;
- does not create the Control Center window hierarchy.

Opening the Control Center launches a new instance of the **same signed Morie application** using `NSWorkspace.OpenConfiguration` with `createsNewApplicationInstance = true`.

The Control Center instance:

- is selected by an explicit process-role launch argument;
- creates the normal native SwiftUI/AppKit Control Center;
- opens the same persisted Morie data for presentation and explicit user edits;
- does not install the global shortcut, prepare Speech, recover interrupted Captures, prune audio, or start background learning;
- sends runtime-only commands and persisted-configuration change notifications to the resident instance through `DistributedNotificationCenter`;
- terminates when its Control Center window closes.

The launcher reuses an already-running Control Center process rather than intentionally creating multiple UI instances.

The same application bundle is used for both roles. Morie does not add a separately signed helper application merely to host the UI. This keeps the existing application identity, permission identity, Keychain service access, UserDefaults domain and product packaging boundary.

## Consequences

Closing the Control Center ends the process that owns its SwiftUI/AppKit/CoreUI/font/language-service allocations, allowing macOS to reclaim that entire presentation working set without requiring unsupported purge behavior in the resident runtime.

Cross-process ownership must be explicit:

- runtime-only work remains in the resident process;
- persisted feature data remains owned by its existing feature stores;
- Control Center edits that affect resident in-memory configuration notify the runtime to reload;
- runtime actions exposed from Control Center are requests to the resident process rather than a second Capture runtime.

Both processes may open the same SwiftData store. The Control Center role must avoid launch maintenance or other background mutations that belong to the resident runtime, and owner-device validation must cover concurrent presentation/edit behavior.

If future functionality needs richer bidirectional live state than the current narrow command/configuration bridge, that transport must remain explicit. It must not collapse the runtime and presentation ownership boundaries again.
