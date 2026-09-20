# M-040 — Split AppController observable state domains

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#92](https://github.com/6spot/Morie/issues/92)

## Problem

Control Center redraw/flicker on Overview, Settings and Permissions exposed a broader architecture issue: `AppController` owned unrelated runtime, setup and preference `@Published` values and also forwarded `PermissionSetupController.objectWillChange`.

That meant a single page could be invalidated by state it did not render. Permissions could also receive the same setup change through both `PermissionSetupController` and the forwarded `AppController` notification.

## Target architecture

```text
AppController
├── AppRuntimeController
│   ├── state / transcript
│   ├── needsSetup / setupError
│   ├── isBootstrapping
│   └── speechBackend
│
├── AppPreferencesController
│   ├── shortcut / audio retention
│   ├── refinement / memory
│   ├── correction / expression learning
│   ├── sound
│   └── iCloud
│
├── PermissionSetupController
├── RefinementModelController
├── RefinementPromptController
├── CaptureHistoryController
├── DictionaryStore
└── MemoryStore
```

`AppController` remains the orchestration/action boundary. It is no longer the broad observable state source for routed pages.

## Implementation

- [x] Added `AppRuntimeController`.
- [x] Added `AppPreferencesController`.
- [x] Removed AppController's `@Published` state ownership.
- [x] Removed setup -> AppController `objectWillChange` forwarding.
- [x] Kept AppController actions and compatibility accessors while state storage moved to focused domains.
- [x] Overview observes runtime + preferences + refinement model only.
- [x] Settings observes preferences + refinement model/prompt only.
- [x] Permissions observes runtime + PermissionSetupController only.
- [x] Setup window observes runtime + PermissionSetupController only.
- [x] Menu views observe only runtime/preferences/setup domains they render.
- [x] History no longer observes AppController broadly.
- [x] Added the new state-domain files to the app target.
- [x] Updated architecture documentation.

## Acceptance

- [x] No routed Control Center page uses `@ObservedObject AppController`.
- [x] AppController does not republish `PermissionSetupController.objectWillChange`.
- [ ] Xcode 27 product compile passes.
- [ ] MorieTests pass.
- [ ] Owner-device check: Overview / Settings / Permissions do not flash the system sidebar toggle during normal navigation.
- [ ] Owner-device check: Settings does not redraw in response to transcript/capture-phase changes.

Do not mark DONE until the owner-device visual check passes.
