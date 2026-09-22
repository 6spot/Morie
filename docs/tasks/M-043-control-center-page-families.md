# M-043 — Unified Control Center page design

## Status

**IN PROGRESS** — 2026-09-22

Issue: [#99](https://github.com/6spot/Morie/issues/99)  
Current implementation: [PR #105](https://github.com/6spot/Morie/pull/105)

## Goal

Rebuild every Control Center destination as one coherent native macOS product surface while keeping each page appropriate to its job.

The shell is shared. Page content is not flattened into one universal Form/List.

The current design source of truth is `docs/DESIGN.md`.

## Shell contract

- one persistent `NavigationSplitView`;
- one persistent sidebar;
- one persistent detail `NavigationStack`;
- one `ControlCenterDetailHost`;
- the shell owns the persistent NavigationSplitView / NavigationStack and primary title;
- routed pages contribute route-specific search and actions through Apple-native `.searchable` / `.toolbar`;
- the shell/router contains no route-specific toolbar switch, placeholder slots or custom toolbar configuration model;
- Overview, Dictionary, Personal Memory, Settings and Permissions share `ControlCenterPage` and the same 24-point content origin;
- History and Diagnostics are full-size workspaces inside the same shell;
- page state updates must not invalidate the window-level shell.

## Page design

### Overview

- runtime readiness and active models come first;
- usage metrics are stable in place while loading;
- build and Application Context debugging are development-only and visually secondary.

### History

- native selectable list plus persistent detail workspace;
- list has an explicit record-count header;
- History itself contributes native toolbar search/filter/record controls;
- selected record exposes final text, recognition/refinement and original recording directly;
- common record actions are directly visible;
- internal split widths must never squeeze the outer sidebar.

### Dictionary

- Dictionary itself contributes native toolbar search and add/edit/delete actions;
- user and system terms remain clearly separated;
- user terms are editable/selectable;
- built-in terms are visibly read-only;
- compact desktop density without capsule-heavy/card-heavy presentation.

### Personal Memory

- long-term, recent and archived/history groups are directly visible;
- no disclosure control solely to shorten the page;
- memory detail directly exposes usage, source and history;
- edit and lifecycle actions remain native and clear.

### Settings

- normal settings controls use the shared Control Center page grid;
- common configuration is directly visible;
- refinement prompt and external API configuration are not hidden merely for visual minimalism;
- destructive actions remain explicit and confirmed;
- factory reset is a top-level toolbar action.

### Permissions

- overall readiness appears first;
- device capabilities and macOS permissions are separate groups;
- each missing requirement exposes the action needed to resolve it;
- Recheck is a top-level toolbar action and is not duplicated inside the page.

### Diagnostics

- native Table plus selected-log detail workspace;
- Diagnostics itself contributes native toolbar search/filter/copy/overflow actions;
- page shows a compact log-count/status strip;
- workspace fills the available detail region.

## Design rules applied

- native before custom;
- simplicity before minimalism;
- familiar macOS interaction before invention;
- common actions stay visible;
- hierarchy comes from type, spacing and alignment before decoration;
- no card-heavy dashboard styling;
- calm desktop information density;
- async changes update the smallest possible region;
- high-frequency navigation has no decorative animation;
- no third-party UI dependency.

## Implementation

- [x] Rewrite `docs/DESIGN.md` as the current Morie UI source of truth.
- [x] Keep one persistent Control Center shell.
- [x] Add shared `ControlCenterPage` page rhythm.
- [x] Remove the custom parent toolbar abstraction and let each page use Apple-native `.searchable` / `.toolbar` directly.
- [x] Redesign Overview information hierarchy.
- [x] Redesign Settings and remove unnecessary disclosure.
- [x] Redesign Permissions around readiness and required actions.
- [x] Redesign Dictionary as a compact management surface.
- [x] Redesign Personal Memory and directly expose archived/history content.
- [x] Redesign Memory detail and directly expose provenance/history.
- [x] Redesign History list/detail workspace and directly expose record detail.
- [x] Redesign Diagnostics workspace.
- [x] Persist Overview usage metrics incrementally instead of scanning Capture history on page open.
- [x] Make History presentation data lazy/bounded and release its ModelContext/list/player when hidden.
- [x] Scope History controller to the Control Center rather than CaptureSession/AppController.
- [x] Keep Diagnostics entries in memory only while the Diagnostics page is visible.
- [x] Reset Control Center presentation state when the window closes.
- [x] Move Control Center presentation into the disposable process boundary defined by M-044 / ADR 0002 after Release Instruments showed framework-owned UI working-set retention in the resident process.
- [x] Xcode 27 compile passes on the final M-043 page implementation before the process-boundary follow-up.
- [x] MorieTests pass on the final implementation.
- [ ] Owner-device visual acceptance passes.

## Owner-device acceptance

Check at the normal development window size and at the 960 × 600 minimum:

- [ ] switch every top-level destination repeatedly with no sidebar/title flash;
- [ ] search fields use native toolbar search and never share one glass group with unrelated actions; related action buttons may group natively;
- [ ] Overview, Dictionary, Memory, Settings and Permissions begin on the same content grid;
- [ ] History starts immediately below the toolbar and never distorts the outer sidebar;
- [ ] History selected-record detail shows ordinary content without disclosure clicks;
- [ ] Dictionary and Memory remain compact/readable rather than becoming database-style Forms;
- [ ] Settings remains understandable without hiding normal controls;
- [ ] Permissions exposes current state and recovery actions clearly;
- [ ] Diagnostics fills the detail workspace;
- [ ] History loads the initial bounded page and additional rows only when scrolling reaches the end;
- [ ] closing the Control Center releases History presentation records/player/context and Diagnostics in-memory entries before the disposable Control Center process terminates;
- [ ] M-044 owner-device validation confirms that terminating the Control Center process returns the resident runtime near its pre-Control-Center memory baseline;
- [ ] light/dark appearance and resizing remain native.

Validation: the page-family implementation previously passed macOS 27 CI. M-044 now owns the subsequent process-boundary refactor and its compile/runtime/memory acceptance.\n\nDo not mark this task DONE until owner-device visual acceptance passes.
