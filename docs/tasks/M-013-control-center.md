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

## Validation

- Isolated macOS 27 Debug build: passed.
- Isolated macOS 27 logic suite: **103 tests passed**, 0 failures and 0 skips.
- Source audit found no remaining `SettingsLink`, nested filter `Menu`, or
  **使用引导与权限** product-code entry; `git diff --check` passed.
- Signed-app interaction/layout acceptance: pending.
- Recheck the activation transition on owner hardware: menu-bar-only idle must
  have no Dock presence; opening Control Center/setup must show Morie's normal
  macOS app menus and permit keyboard focus; closing the last Morie window must
  return to menu-bar-only accessory mode without leaving a blank top menu.

The task remains **IN PROGRESS** until keyboard, VoiceOver, menu/setup routing,
sidebar selection and Dictionary actions are exercised in the signed app.
