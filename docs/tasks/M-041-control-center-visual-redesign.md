# M-041 — Control Center visual redesign

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#94](https://github.com/6spot/Morie/issues/94)

## Why

The Control Center navigation architecture is now stable, but the visual layer still mixes several unrelated presentation rules:

- standard pages manually build headline + GroupBox cards;
- page spacing is hand-tuned instead of following one macOS container;
- Settings exposes too many large editors and sections at once;
- Permissions puts routine maintenance actions in the toolbar;
- Diagnostics changes its split geometry when no row is selected.

The owner wants the management UI to feel like one current macOS Settings-style surface, not a collection of custom panels.

## Native design basis

The implementation uses native macOS/SwiftUI primitives:

- one persistent `NavigationSplitView`;
- one persistent detail `NavigationStack`;
- the system sidebar toggle;
- `Form(.grouped)` for ordinary settings/library pages;
- `Section` for semantic grouping;
- `List`, `Table`, `HSplitView`, `VSplitView` for dense workspaces;
- `DisclosureGroup` for advanced/rare configuration;
- native `Toggle`, `Picker`, `LabeledContent`, `TextField`, `Stepper`, buttons and toolbars.

No custom glass/card design system is introduced.

## Route ownership

`ControlCenterRouteHost` owns page container style.

### Standard pages

Overview, Dictionary, Personal Memory, Settings and Permissions are injected into one route-owned grouped Form.

The routed feature page provides Sections/content only. It does not own:

- a top-level ScrollView;
- top-level padding;
- top-level contentMargins;
- a replacement settings-card shell.

The grouped Form therefore owns the normal system spacing and section geometry for every standard page.

### Workspace pages

History and Diagnostics fill the detail region with their native split/list/table workspaces. Child reading panes may own internal reading margins because those margins are inside the workspace, not the routed page shell.

## Page-by-page redesign

### Overview

- [x] Native grouped usage section.
- [x] Native grouped runtime-model section.
- [x] Move descriptive copy into navigation subtitle / section footer.
- [x] Remove custom GroupBox dashboard shell.

### Dictionary

- [x] Native user/system Sections.
- [x] Keep adaptive compact word layout.
- [x] Keep search + add/edit/delete behavior.
- [x] Use compact native capsule buttons for editable user terms.

### Personal Memory

- [x] Native long-term / recent / archived Sections.
- [x] Keep topic navigation and semantic summaries.
- [x] Keep archived history behind disclosure.
- [x] Remove custom outer cards.

### Settings

- [x] Reduce the page to five logical groups:
  - Input & refinement
  - Personalization
  - Model & prompt
  - Sync & storage
  - Shortcut & feedback
- [x] Collapse prompt and external API editors by default.
- [x] Use switch-style Toggles and menu Pickers.
- [x] Keep all existing settings functionality.

### Permissions

- [x] Native device-capability and permission Sections.
- [x] Move routine refresh/re-enable actions into page content.
- [x] Remove page toolbar clutter.

### History

- [x] Retain native List + HSplitView workspace.
- [x] Keep search/filter/capture actions in the native toolbar.
- [x] Keep detail reading margins internal to the detail pane.

### Diagnostics

- [x] Retain native Table + VSplitView.
- [x] Keep a stable lower detail pane even when no log is selected.
- [x] Keep search/filter/copy/reveal/clear actions.

## Validation

- [ ] Xcode 27 product compile passes.
- [ ] MorieTests pass.
- [ ] Owner-device visual review of all seven sidebar destinations.
- [ ] Confirm system sidebar toggle remains stable across all destinations.
- [ ] Confirm ordinary pages use one system grouped-form spacing model.
- [ ] Confirm Settings remains usable at the 960 × 600 minimum window.

Do not mark DONE until owner-device visual review passes.
