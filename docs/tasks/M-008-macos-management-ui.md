# M-008 — Unified macOS Management UI

## Status

- **State:** IN PROGRESS
- **Phase:** macOS UX
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-008-native-management`, after foundation commit `aecc307`
- **Owner direction:** finish the current macOS foundation, then improve the management pages and unify their design language. iOS is not scheduled.

## Why

Morie is a personal voice-input tool. Its management window should make saved expression and useful Memory easy to read, inspect and correct. The preceding pages mixed full-page navigation, long read-only forms, fixed-width settings and manually aligned diagnostic rows. This slice gives them a coherent macOS structure and hierarchy.

## Scope

M-010 adds Simplified Chinese, native sidebar visibility/group expansion, a system menu and a permission guide. Settings entry points now share the native Command-comma Settings window. Its [task record](M-010-macos-native-setup.md) holds current layout evidence; M-008's earlier dated screenshots describe the former arrangement.

M-009 extends this native navigation to Dictionary and automatic Personal Memory. Its current rules supersede candidate-review surfaces; the dated M-008 validation below remains historical evidence for that earlier UI.

- A shared native sidebar and consistent list/detail browsing for History, Dictionary and Personal Memory.
- Readable final Capture text and Memory content, with secondary provenance/recovery information disclosed progressively.
- Consistent native toolbar actions, search, filters, selection and empty states.
- Native grouped settings with a readable, flexible width.
- A native diagnostics table with consistent navigation and actions.
- Existing editor/review sheets retain explicit validation, confirmation and source semantics.

Excluded: iOS, CloudKit integration, model behavior changes, new runtimes/dependencies, custom control/material imitations, and new capture/hotkey/injection behavior.

## Acceptance criteria

1. History, Dictionary and Personal Memory share a predictable sidebar → list → detail structure. Selection/search/filter changes do not show another record's data or keep stale media/model work alive.
2. Final text, dictionary spellings and personal information are the primary reading content. Recognition/refinement/learning provenance remains available without dominating the page.
3. Equivalent actions occupy equivalent native toolbar positions; destructive actions retain system confirmation. Optional editing and dictionary-word confirmation keep save errors visible; routine personal Memory has no review inbox.
4. Settings uses the shared native Settings scene, reached through Command-comma and sidebar/menu links. Diagnostics remains in management; both use system typography, spacing and semantic colors. Diagnostics uses the system table.
5. All controls/presentation primitives use SwiftUI/AppKit system components. No decorative glass, custom navigation/control library or external dependency is introduced.
6. Empty, populated, long-content, learning status and error states have clear layouts. Isolated compilation and offscreen layout checks pass; keyboard/VoiceOver/material/interaction acceptance remains open until real-device validation.

## Progress

- [x] Inspect current pages and approved native UI rules.
- [x] Unify navigation, list selection, search/filter and toolbar placement.
- [x] Rework Capture/Memory details around reading and progressive disclosure.
- [x] Align Settings and Diagnostics; M-009 replaces the former candidate review with automatic learning status.
- [x] Compile and inspect native offscreen previews; fix layout issues.
- [x] Update architecture/UI/development/validation records.
- [x] Stabilize live History rows with a reserved two-line preview, move month/day/time beside the source app, and remove redundant normal-state 已保存/已输入 labels while retaining active/error status.
- [ ] Complete supported-device keyboard, accessibility and live-input checks.

## Design decisions

- Apply the familiarity, spatial consistency, hierarchy and restraint principles from the local `apple-design` skill. Its web implementation examples are not used; the repository's native-control rules remain authoritative.
- Use system split navigation for browsing, standard Lists/Tables, readable system text, native GroupBoxes/disclosures for supporting information and grouped Forms for actual settings/editing.
- Keep one content-width/padding convention through small native view compositions. No parallel design system, custom glass or custom button implementation.
- Interactive device checks remain deferred by the owner. Offscreen fixtures must never launch app bootstrap, invoke a model/microphone, manipulate the clipboard or touch product stores/logs.

## Implementation notes

- `MorieControlCenter` owns separate Capture/Dictionary/Personal Memory selections and the shared sidebar. Library sections use the native three-column split; Settings/Diagnostics use two columns. Default size is 1120 × 720 with a 960 × 600 minimum.
- History and Memory use system List selection, search and filter menus. Hidden/deleted entries clear selection. Each selected detail has its own NavigationStack identity, so related/source navigation cannot carry over to another record. Capture open/close, cancellation and audio-expiry hooks remain in place.
- Final Capture text is the primary reading content. The list normalizes whitespace for its preview only; saved text and the full detail remain exact. Recognition/refinement and source recording use native disclosures. The Recognition label stays neutral because later Speech retries can update that field; Text Before Refinement retains the actual earlier input.
- Personal Memory details prioritize personal information, automatic/user origin and source/history. Dictionary saves one word per entry under M-011. M-009 removes pending-candidate detail/review; History displays automatic learning status and exact final-text evidence.
- Capture/Memory supporting content uses native GroupBoxes. Primary copy/edit actions and secondary menus occupy matching toolbar positions; destruction retains native confirmation. The editor keeps native validation and puts Cancel beside the default Save action.
- Settings uses a flexible grouped Form. Diagnostics uses a native Table, search/level filter and a resizable selected-event detail. Copy All Events still copies the whole log, and Clear Diagnostics now confirms before clearing the existing logger/file.
- The shared reading surface is a small ScrollView/VStack composition, not a replacement control system. No dependency, compatibility layer, schema, model policy, hotkey, microphone or delivery implementation changed.

## Validation evidence

2026-09-18, macOS 27 / Xcode 27, arm64:

- Final isolated app build: **BUILD SUCCEEDED**. Log: `/tmp/morie-management-build.Dr6In2/final-build.log`; DerivedData: `/tmp/morie-management-build.Dr6In2/DerivedData`. The only build warning is the existing AppIntents metadata skip for an app without that framework dependency.
- **91 existing logic tests passed**, 0 failed/skipped, with no runtime warnings in the result summary. Bundle: `/tmp/morie-management-build.Dr6In2/ManagementLogic.xcresult`; log: `/tmp/morie-management-build.Dr6In2/tests.log`. Tests cover Capture/History/audio/Memory/candidates/personalization and use the no-op test logger. No new tests were added for view-only layout.
- Thirteen native offscreen fixture surfaces were rendered: History at default/minimum sizes, delivery failure, expanded provenance, Memory, candidate detail, candidate editor, Settings, Diagnostics, empty History/Memory, stale candidate and long History. PNGs: `/tmp/morie-management-preview.nVfoQ4/final/`; harness: `/tmp/morie-management-preview.nVfoQ4/ManagementPreview.swift`; compile/render logs: `/tmp/morie-management-preview.nVfoQ4/final-compile.log` and `/tmp/morie-management-preview.nVfoQ4/final-render.log`.
- Fixtures compile the presentation sources with temporary initial selection/disclosure state, a memory-only AppController and diagnostic logger, isolated SwiftData stores and injected controller actions. The window is never ordered onscreen. No product app bootstrap, real model, microphone, keyboard injection, clipboard operation, production History or product logger is used. The active Xcode-signed app was not overwritten or relaunched.
- Layout inspection prompted clearer candidate action rows, separate Memory link/source lines, a more prominent Final Text heading and compact paragraph previews. Native sidebar/selection/glass layers are incompletely captured by offscreen bitmap caching, so actual material/color/interaction acceptance remains open. These fixtures do not establish live input or model quality.
- `git diff --check` passes. Current architecture, UI rules, README, development steps, task overview and validation checklist reflect the new navigation.

Implementation is ready for the deferred [device checklist](../validation.md#m-008-unified-macos-management-ui); task state remains IN PROGRESS until those checks are complete.

M-009 adds current isolated Dictionary/Personal Memory/Settings/word-prompt layouts and retains the outstanding interactive checks. See [its validation evidence](M-009-macos-input-memory.md#validation-evidence).

## Known issues / follow-up

- Validate the current M-009 Dictionary, Personal Memory, automatic-learning status and nonactivating correction prompt using the updated [device matrix](../validation.md). Earlier candidate screenshots are not evidence for these new surfaces.

- M-008 keyboard/VoiceOver, search/filter/selection interactions, native material appearance and live-input preemption require the normal signed window. Offscreen snapshots cannot close those items.
- Real-device validation of M-002 through M-005 remains open.
- iCloud belongs to a later scheduled cross-device milestone after the single-Mac loop works; it does not gate local task completion.
- iOS is not the next task; reconsider it only after the macOS product is proven.

## Issue / PR

No new Issue/PR. Repository task records remain the source of truth.
