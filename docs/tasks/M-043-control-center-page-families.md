# M-043 — Control Center page-family rebuild

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#99](https://github.com/6spot/Morie/issues/99)

## Why

M-041 over-generalized the current macOS Settings visual language into one grouped Form for every ordinary page. That made Overview, Dictionary and Personal Memory look like settings screens even though their content models are different.

The owner screenshots also show two layout failures:

- History's List/detail split sits around the vertical center with a large dead region above it.
- Diagnostics' Table/detail split is narrow and centered instead of filling the right-side workspace.

M-043 rebuilds the page-family contract using Morie's native-UI policy plus the review guidance in [twostraws/SwiftUI-Agent-Skill](https://github.com/twostraws/SwiftUI-Agent-Skill). The external repository is guidance only; no dependency is added.

## Page families

- **Overview** — route-owned ScrollView; concise dashboard/reading content.
- **History** — full-size native HSplitView workspace.
- **Dictionary** — route-owned ScrollView + compact LazyVGrid collection.
- **Personal Memory** — route-owned ScrollView + semantic topic sections.
- **Settings** — native grouped Form.
- **Permissions** — native grouped Form.
- **Diagnostics** — full-size native Table + VSplitView workspace.

## Shell rules

- exactly one persistent NavigationSplitView;
- exactly one persistent detail NavigationStack;
- system sidebar toggle only;
- no page-owned replacement sidebar/navigation shell;
- route host selects the native page container family;
- system sidebar width/metrics are not manually overridden without a concrete requirement.

## SwiftUI review rules applied

- use system controls and hierarchical foreground styles;
- use ContentUnavailableView for meaningful empty states;
- keep workspaces structurally stable rather than conditionally replacing the whole split;
- avoid universal custom wrappers for unrelated content models;
- keep button actions/business logic out of large inline body closures where practical;
- preserve structural identity and avoid unnecessary redraw-triggering container changes;
- use shared/default system spacing rather than inventing per-page visual constants.

## Implementation

- [x] Route host split into scrolling / form / workspace families.
- [x] Removed the M-041 rule that every ordinary page is a grouped Form.
- [x] Returned Sidebar width/section metrics to native defaults.
- [x] History HSplitView explicitly fills the full detail workspace.
- [x] History List/detail panes explicitly fill available height.
- [x] Diagnostics VSplitView/Table/detail explicitly fill available space.
- [x] Overview restored as a reading/dashboard page.
- [x] Dictionary restored as a compact collection page.
- [x] Personal Memory restored as a semantic reading page.
- [x] Settings and Permissions remain grouped Forms.
- [ ] Xcode 27 compile passes.
- [ ] MorieTests pass.
- [ ] Owner-device visual check: History begins immediately below the toolbar and fills to the bottom.
- [ ] Owner-device visual check: Diagnostics uses the full content width/height.
- [ ] Owner-device visual check: Sidebar toggle remains stable across all routes.

## Exclusions

- No third-party UI package.
- No compatibility layer.
- No new custom glass/card design system.
- No merge before owner-device visual acceptance.
