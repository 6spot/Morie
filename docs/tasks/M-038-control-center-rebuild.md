# M-038 — Control Center Rebuild

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#86](https://github.com/6spot/Morie/issues/86)  
Pull request: [#87](https://github.com/6spot/Morie/pull/87)

## Why

The Control Center had accumulated several incompatible page-layout patterns:

- ordinary pages wrapped their own ScrollViews and padding;
- Overview used custom metric cards;
- Dictionary used a custom adaptive grid and custom selected/read-only surfaces;
- Personal Memory used hand-spaced narrative navigation;
- History owned separate navigation roots for its list and detail panes;
- Settings/Permissions used grouped Forms but then received extra Control Center scroll margins;
- changing sections therefore changed not only page content but also the right-side navigation/container hierarchy.

The visible result was inconsistent top/side spacing, different scrollbar positions, History width pressure, duplicated toolbar/navigation chrome and section changes that could look like the shell was redrawing.

The owner explicitly chose to discard the old presentation layer rather than continue patching it.

## Goal

Rebuild the Control Center around one macOS 27 System Settings-style native layout contract while preserving current business/data behavior.

## Source of truth

The implementation follows:

1. Apple's current sidebar/split-view/Form/List/Table conventions;
2. Morie's native-UI policy in `AGENTS.md`;
3. the rewritten **Control Center shell** rules in `docs/ui-design.md`;
4. owner-provided screenshots as the visual target for hierarchy, density and page-specific presentation; implementation is rewritten rather than copied.

## Layout contract

### Shell

- one persistent `NavigationSplitView`;
- one persistent native sidebar;
- one persistent right-side `NavigationStack`;
- route only page content when sidebar selection changes;
- no section-specific outer navigation root;
- no high-frequency AppController observation in the shell.

### Page families

The shell is uniform; the content presentation is not forced into one control type.

- Overview → dashboard composition using system `GroupBox`, adaptive grid and shared page margins.
- Dictionary → compact adaptive grid of system buttons/read-only terms, matching the owner-approved density.
- Personal Memory → natural document-style topic overview with optional recent/history sections, not a database list.
- Settings / Permissions → grouped native `Form`.
- History → `HSplitView` with one native list and one reading detail inside the persistent right-side navigation host.
- Diagnostics → native `Table` plus selected-message split detail.
- Capture/Memory reading details → shared ScrollView with 28-point scroll-content margins and 760-point readable max width.

### Prohibited layout patterns

- page-specific top/left outer padding that breaks the shared content grid;
- fixed-width outer ScrollViews that move the scrollbar away from the workspace edge;
- forcing every page into `Form` or `List` merely because those controls are native;
- nested page-level `NavigationSplitView` / `NavigationStack` roots;
- custom toolbar/title backgrounds;
- decorative custom glass or replacement system controls.

## Implementation progress

- [x] Create M-038 issue and feature branch.
- [x] Replace the conditional Control Center detail root with one persistent `NavigationStack`.
- [x] Replace shared ad-hoc page padding constants with one reading-detail-only layout contract.
- [x] Move History search/filter/record controls to the History workspace and remove its list/detail NavigationStack roots.
- [x] Rebuild Overview inside the persistent shell.
- [x] Correct Overview back to the dashboard hierarchy shown in the owner reference.
- [x] Rebuild Dictionary inside the persistent shell.
- [x] Correct Dictionary back to the compact adaptive word grid shown in the owner reference.
- [x] Rebuild Personal Memory inside the persistent shell.
- [x] Correct Personal Memory back to the narrative topic presentation; do not regress it to a database list.
- [x] Remove extra outer margins from grouped Settings.
- [x] Rebuild Permissions into native capability/permission Form sections.
- [x] Stop Permissions from unconditional refresh on every page revisit.
- [x] Align Diagnostics selected-message margins with the shared dense-workspace metric.
- [x] Rewrite `docs/ui-design.md` Control Center rules.
- [x] Run Xcode 27 compile/tests.
- [ ] Owner signed-app visual/interaction check.

## Acceptance criteria

- [ ] Sidebar remains mounted when switching every section.
- [ ] Section switching changes only routed content, not the outer split/navigation shell.
- [ ] Overview, Dictionary, Memory, Settings and Permissions align to one shared page content grid.
- [ ] Dictionary remains compact and Memory remains narrative while both use the same shell/margins.
- [ ] History stays within the available right workspace and no longer shows separate page-level navigation roots.
- [ ] Scroll indicators remain at the workspace edge.
- [ ] The 960 × 600 minimum window does not overflow.
- [ ] Search, toolbar, edit/delete, record, retry and permission actions remain functional.
- [x] Xcode 27 product build and logic tests pass.
- [ ] Signed macOS 27 visual check confirms stable sidebar and consistent page rhythm.

## Validation notes

Hosted CI can verify compilation and logic tests, but it cannot replace the owner-device check for:

- actual macOS 27 System Settings spacing/materials;
- toolbar/title placement;
- List/Form/Table rendering;
- sidebar persistence and disclosure behavior;
- minimum-window split sizing;
- absence of visible selection/page-switch flashing.

GitHub Actions `macOS 27 CI` run #251 passed on 2026-09-20:

- **Xcode 27 compile**: passed.
- **MorieTests**: **147 tests passed, 0 failures**.

The test log still contains temporary SQLite cleanup warnings about WAL/SHM files being unlinked while an in-memory test store is being torn down; they did not fail the suite and are not treated as Control Center acceptance evidence.

Owner video review after PR #87 exposed a design error: the rewrite correctly stabilized the shell, but incorrectly interpreted “Apple-native” as “convert every content page into Form/List.” That flattened the Overview, turned the Dictionary into a long database-like list, and regressed Personal Memory into the exact list presentation the owner had already rejected.

The corrective rule is: **standardize shell, navigation, spacing and system controls; preserve the page-specific information architecture that fits the content.** Native does not mean visually identical page bodies.

Do not mark this task DONE until those interactions are checked in the signed app.
