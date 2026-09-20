# M-039 — Clean Control Center rebuild

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#89](https://github.com/6spot/Morie/issues/89)

## Why

M-038 failed visual acceptance. The implementation kept changing page containers, spacing and sidebar-toolbar ownership instead of replacing the presentation layer with one stable macOS System Settings-style shell.

The owner-provided recording is an example of what is wrong. It is not a design target.

M-039 starts from a new branch and rewrites the Control Center presentation structure again. Business stores/controllers remain intact.

## Apple-native constraints

Apple's current SwiftUI/HIG guidance is the implementation basis:

- `NavigationSplitView` is the root split-navigation primitive;
- its sidebar is the top-level navigation surface;
- the system-provided sidebar toggle remains owned by the split view;
- standard SwiftUI controls keep their native macOS appearance;
- one route host owns outer page geometry.

## Architecture

```text
MorieControlCenter
└── NavigationSplitView                    persistent
    ├── List(.sidebar)                     persistent
    └── NavigationStack                    persistent
        └── ControlCenterRouteHost
            ├── outer inset / scrolling    shell-owned
            └── routed feature page        content only
```

The routed feature page must not own:

- a page-level NavigationSplitView;
- a page-level NavigationStack;
- the management window's outer ScrollView;
- outer `padding`;
- outer `contentMargins`;
- the sidebar toggle.

## Shared geometry

- Sidebar width: 180 / 220 / 260 min / ideal / max.
- Route-host outer inset: 24 pt on all sides.
- The page body leading edge must visually align with the native navigation-title leading edge beside the sidebar divider.
- Workspace pages receive the same outer inset from the host; their internal split/list/table layout remains page-specific.

## Page-by-page review

### 1. 总览

- [x] Rewritten.
- [x] Uses shared page host.
- [x] Uses shared Settings-style groups.
- [x] Preserves usage metrics and runtime-model state.
- [x] No page-owned outer ScrollView/padding/margins.

### 2. 历史记录

- [x] Rewritten.
- [x] Native List + HSplitView detail.
- [x] Search, filter and record actions retained.
- [x] No nested page-level NavigationStack.
- [x] Route host owns outer workspace inset.

### 3. 字典

- [x] Rewritten.
- [x] Search/add/edit/delete retained.
- [x] User and built-in words remain separate.
- [x] Built-in words remain read-only.
- [x] No page-owned outer ScrollView/padding/margins.

### 4. 个人记忆

- [x] Top-level page rewritten.
- [x] Long-term / recent / archived-history behavior retained.
- [x] Semantic topic presentation retained; not a raw database list.
- [x] Search and manual-add retained.
- [x] No page-owned outer ScrollView/padding/margins.

### 5. 设置

- [x] Rewritten.
- [x] Refinement, Memory, prompt, cloud API, dictionary learning, expression learning, iCloud, sound, shortcut and audio-retention controls retained.
- [x] Uses shared Settings-style groups.
- [x] No page-owned outer ScrollView/padding/margins.

### 6. 权限

- [x] Rewritten.
- [x] Capability and permission groups retained.
- [x] Refresh/re-enable actions retained.
- [x] No unconditional refresh merely from route reconstruction.
- [x] No page-owned outer ScrollView/padding/margins.

### 7. 诊断

- [x] Rewritten.
- [x] Native Table and selected-message split retained.
- [x] Search/filter/copy/reveal/clear retained.
- [x] Route host owns outer workspace inset.

## Shell checks

- [x] Exactly one Control Center `NavigationSplitView`.
- [x] Exactly one persistent detail `NavigationStack`.
- [x] No custom sidebar-toggle button.
- [x] No `.toolbar(removing: .sidebarToggle)`.
- [x] Sidebar mount/unmount diagnostics retained for owner-device verification.
- [x] Old `ControlCenterScrollPage`, `ControlCenterSectionGroup` and page-level margin helpers removed from routed pages.

## Validation still required

- [x] Xcode 27 product build.
- [x] MorieTests.
- [ ] Owner-device page-by-page visual check.
- [ ] Switch all sidebar destinations repeatedly and confirm the system sidebar toggle never disappears/reappears as a page-owned control.
- [ ] Confirm title/body leading alignment on every destination.
- [ ] Confirm 960 × 600 minimum-size behavior.

macOS 27 CI run #275 passed on 2026-09-20: Xcode 27 product build passed and MorieTests passed. Do not mark DONE before the owner-device visual check passes.
