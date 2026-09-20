# M-013 — Control Center information architecture

- **Status:** IN PROGRESS
- **Branch:** `feature/m-013-control-center`
- **Depends on:** M-008, M-010 and M-011

## Goal

Make Morie's menu and management window follow a clear macOS hierarchy:
first-use setup is not a permanent destination, routine Settings and permission
management live in the Control Center, and simple content does not acquire an
extra navigation level.

## Owner decisions

- The menu-bar menu has one management entry and no decorative item icons.
  Settings and setup are not duplicate menu destinations.
- The welcome/setup window opens only when the user chooses **打开 Morie** and
  required authorization or setup is incomplete. It is not a permanent page.
- Routine permission inspection and recovery use a separate **权限** page in
  Control Center.
- Settings are embedded in Control Center. Command-comma opens Control Center
  and selects Settings instead of opening another window.
- Morie remains an `LSUIElement` menu-bar app while no management window is
  visible. A visible Control Center/setup window temporarily switches the app
  to regular activation policy so macOS owns a normal application menu bar;
  closing the last Morie window restores accessory mode.
- A filter with one dimension presents its choices directly, without a
  `Menu` containing another `Picker` submenu.
- Dictionary uses sidebar + one content page. Selection-scoped edit/delete and
  add actions live with the word list; there is no third detail column and no
  source/time explanation.
- The Control Center owns one stable root `NavigationSplitView`. Changing the
  selected section replaces only the right-side routed page; it must not swap
  the entire split-view hierarchy or remount the sidebar.
- The right side has one persistent detail host. Ordinary pages share one
  `NavigationStack` inside that host, so Settings, Permissions, Diagnostics,
  Overview, Dictionary and Memory cannot publish navigation/title/toolbar state
  directly into the outer sidebar navigation environment.
- Ordinary right-hand pages follow one System Settings-like content grid:
  24-point horizontal and vertical scroll-content insets, with native navigation
  titles/toolbars outside that content inset. Dense workspaces such as History
  remain edge-to-edge.
- The shell does not observe the whole `AppController`. Runtime state is
  observed only by the currently visible page that needs it, so transcript and
  capture-phase updates cannot invalidate the sidebar/navigation root.
- Standard reading/form pages keep their scroll container full-width and use
  shared scroll-content margins. This keeps scroll indicators at the same
  right edge while aligning page content. Dense native workspaces such as
  History lists and Diagnostics tables remain edge-to-edge by design.

## Implementation

- Removed the always-available setup entries from the menu, Settings and
  Control Center, and removed automatic setup presentation during background
  app launch.
- Added a daily permission-management Form reusing the same native requirement
  rows and explicit system authorization actions.
- Embedded Settings in Control Center and routed Command-comma to that section.
- Fixed the owner-observed blank macOS application-menu area when Control
  Center became active. `LSUIElement` maps to AppKit accessory policy, which
  intentionally has no app menu; window presentation now switches to
  `.regular` before activation and restores `.accessory` after the last
  managed window closes. The menu-bar-only idle state and LSUIElement setting
  remain unchanged.
- Replaced the History, Personal Memory and Diagnostics nested filter menus
  with direct menu-style Pickers.
- Reworked Dictionary into a two-column Control Center section with native list
  selection, toolbar/context edit and delete actions, and the existing compact
  editor sheet.
- Replaced the selection-dependent three-root Control Center implementation
  with one stable outer shell and one explicit right-side detail router.
  Ordinary sections now share the same persistent `NavigationStack` in that
  detail host instead of attaching their title/search/toolbar preferences
  directly to the outer `NavigationSplitView`.
- History remains a special dense split workspace inside the right-side host.
  Its list and detail navigation stay local to that workspace. The previous
  minimum-width combination could exceed the available detail width; the list
  is now capped at 340 pt and the detail can compress to 320 pt before
  expanding, preventing the History workspace from forcing the window wider.
- Removed `@ObservedObject AppController` from the Control Center shell. Views
  such as Overview, History, Settings and Permissions keep their own scoped
  observation only while visible.
- Added shared Control Center scroll-content margins and applied them to
  Overview, Personal Memory, Dictionary, Settings, Permissions, diagnostics
  detail and reading-detail surfaces. The grid is now one 24-point inset on
  both axes so right-hand pages align consistently instead of mixing 28-point
  horizontal and 24-point vertical offsets.
- Removed the extra large in-body Personal Memory title so top-level pages use
  the native navigation title consistently.
- Personal Memory and Dictionary now avoid repeated full store reloads when the
  user merely switches away and back.
- History no longer recreates an all-record `@Query` each time its section is
  selected. `CaptureHistoryController` retains the loaded page, checks a cheap
  count/latest-update signature when History becomes visible again, and reloads
  only after capture mutations or when that signature changes. New completed
  captures, deletion and re-recognition explicitly invalidate the retained
  snapshot.
- Permissions no longer runs a full capability inspection every time the user
  switches back to that page when a valid snapshot already exists; explicit
  recheck and permission actions remain fresh.
- Overview no longer owns an always-recreated all-Capture `@Query`. The
  Control Center retains one metrics snapshot for the window session; returning
  to Overview first checks only completed-record count and the latest
  `updatedAt`, and scans all completed records again only when that signature
  changed.
- Added lightweight Sidebar mount/unmount diagnostics so owner-device testing
  can distinguish a normal selection redraw from an actual sidebar remount.

## Validation

- Isolated macOS 27 Debug build: passed.
- Isolated macOS 27 logic suite: **103 tests passed**, 0 failures and 0 skips.
- Source audit found no remaining `SettingsLink`, nested filter `Menu`, or
  **使用引导与权限** product-code entry; `git diff --check` passed.
- Added History controller coverage for retaining an off-screen list snapshot
  and refreshing it only after invalidation when the page becomes visible.
- Signed-app interaction/layout acceptance: pending.
- Recheck the activation transition on owner hardware: menu-bar-only idle must
  have no Dock presence; opening Control Center/setup must show Morie's normal
  macOS app menus and permit keyboard focus; closing the last Morie window must
  return to menu-bar-only accessory mode without leaving a blank top menu.

The task remains **IN PROGRESS** until keyboard, VoiceOver, menu/setup routing,
sidebar selection and Dictionary actions are exercised in the signed app.
