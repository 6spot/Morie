# M-010 — Simplified Chinese UI and native macOS setup

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-18
- **Branch:** `feature/m-010-native-chinese-setup`
- **Depends on:** M-008 native management and M-009 single-Mac input.
- **Issue / PR:** —

## Why

The owner requested a Chinese interface, standard macOS settings shortcuts, collapsible sidebar navigation, a permission-checking setup page and a revised menu-bar menu. These changes make the existing single-Mac product understandable and usable without changing its input or storage contract.

## Scope

- Simplified Chinese as the app's primary UI language, including labels, errors, accessibility descriptions and permission explanations.
- Native Settings with Command-comma, native sidebar commands and collapsible groups.
- A native menu-bar menu with clear management, settings and setup entries.
- Read-only capability inspection, explicit per-permission authorization and a setup page that shows requirements and recovery actions together.
- Compilation, isolated logic validation and native layout verification.

## Exclusions

Schema changes, data resets, legacy compatibility, iOS, cross-device sync, third-party dependencies, custom replacement controls and automated interaction with the owner's microphone or permissions.

## Acceptance criteria

1. App-owned interface copy uses consistent natural Simplified Chinese; user input, dictionary terms, model prompts, identifiers and stored enum values retain their meaning.
2. Command-comma opens native Settings. Sidebar visibility and group expansion use standard SwiftUI controls; shortcuts remain app-scoped.
3. Menu-bar actions use a system menu and retain clear access to management, setup, settings and Quit.
4. Opening or refreshing setup only inspects permissions. Authorization is requested by the corresponding explicit user action; denied permissions link to System Settings.
5. All required capabilities remain mandatory. Setup completion cannot enable recording while a requirement is unavailable; returning from System Settings refreshes the displayed status.
6. Existing Capture-first/input-priority behavior remains intact. App and logic tests pass with isolated storage; actual permission dialogs, keyboard and VoiceOver checks remain open until exercised in the signed app.

## Progress

- [x] Record owner requirements and native implementation boundary.
- [x] Translate and normalize UI copy and language metadata.
- [x] Integrate native menus, Settings shortcut and sidebar controls.
- [x] Implement capability inspection and permission setup.
- [x] Complete isolated checks, layout verification and documentation.
- [ ] Complete signed-app permission/keyboard/VoiceOver acceptance.

## Implementation notes

### Chinese interface

- App-owned management, settings, status, error, confirmation and accessibility copy uses Simplified Chinese. History, Dictionary and Personal Memory terms are consistent; correction confirmation says **加入字典 / 暂不添加**.
- `developmentRegion = zh-Hans` and the bundled `zh-Hans.lproj/InfoPlist.strings` establish the primary language and Chinese native privacy descriptions. SwiftUI/date formatting also uses Chinese.
- User text, dictionary spellings, model prompts, persisted raw enum values and diagnostic identifiers are retained. No persisted model, storage path or backup is changed.

### Native navigation

- `MenuBarExtra` uses `.menu`, with status, **打开 Morie / 设置… / 使用引导与权限… / 退出 Morie** and recording-shortcut guidance.
- SettingsLink entries and **⌘,** reuse one 640 × 600 native Settings scene. The former embedded settings page is removed.
- SidebarCommands and NavigationSplitView provide the native show/hide controls. One sidebar visibility choice maps to `doubleColumn` for hidden library navigation and `detailOnly` for hidden Diagnostics navigation.
- Native expandable **资料库 / 应用** Section headers retain expansion preferences. Management remains 1120 × 720 by default, minimum 960 × 600.

### Setup and permission behavior

- `CapabilityGate.inspect` reads Apple Intelligence, modern Chinese Speech availability, Microphone, Speech authorization and Accessibility together. Checks use the actual Speech locale, `zh-CN`.
- `PermissionSetupController` coalesces refreshes, serializes explicit requests, and checks the latest status before acting. Denied access opens System Settings; restricted/unsupported requirements cannot pass. Empty or partial snapshots cannot enable input.
- First use/startup failure opens a native guide. Consent occurs only through its explicit action. Native-dialog/app activation refreshes status without calling bootstrap or touching an input session.
- **开始使用** prepares required Speech assets, rechecks requirements and installs the hotkey before saving `setup.completed`. Existing completed setup is rechecked on every launch. Capture, active authorization and preparation block completion; **稍后设置** is unavailable once preparation begins.
- If Morie is already ready, completion only refreshes and returns to management. It does not cancel History work or restart services.
- The guide uses a standard Window, grouped Form, status labels, progress and buttons. Default 700 × 740, minimum 640 × 680; long content scrolls independently of the persistent footer.
- Startup errors stay in the guide instead of creating Morie consent/recovery modals. Existing runtime Capture-first failures and the recording shortcut remain in force.

### Reference decisions

Reviewed upstream Type4Me permission manager/guide/tests and relevant permission history before changing the flow. **ADAPT** explicit authorization, denial/settings return and completion gating; **DROP** custom drag overlays, Settings-window polling, provider routing, old signing recovery and automatic relaunch. **VERIFY** any actual macOS 27 restart issue before introducing a workaround. Full references and pinned revision are in [the permission audit](../reference/type4me.md#6-permissions-and-onboarding). No third-party code or dependency was added.

## Validation evidence

2026-09-18, macOS 27 / Xcode 27.0 (27A266a), arm64, Swift 6 strict concurrency:

- **Final app build passed** against `macosx27.0`, with signing disabled and isolated DerivedData. Log: `/tmp/morie-native-setup.dQL5cY/build-verified.log`.
- **99 logic tests passed**, 0 failures/skips/runtime warnings. Result: `/tmp/morie-native-setup.dQL5cY/Tests.xcresult`; log: `/tmp/morie-native-setup.dQL5cY/test.log`.
- The eight new setup tests cover complete mandatory snapshots, read-only revocation/recovery, explicit authorization, denial-to-Settings, stale buttons, restricted/unsupported states, coalesced inspection and duplicate/dialog-activation races. They inject all side effects and do not link the live gate.
- A Foundation bundle-only check confirms `zh-Hans` for both English-first and English-only preferences, and both privacy descriptions in Chinese. Log: `/tmp/morie-native-setup.dQL5cY/localization.log`.
- **23 isolated native layout fixtures** cover populated/empty History/Dictionary/Personal Memory, editors, correction prompts/long words/save errors, Settings top/bottom, Diagnostics, collapsed/hidden sidebars, and first-use/blocked/ready/preparing/error setup.
- Images: `/tmp/morie-native-setup.dQL5cY/preview/final/`; fixture source/compile log in `/tmp/morie-native-setup.dQL5cY/preview/`; layout/scroll/row evidence: `/tmp/morie-native-setup.dQL5cY/preview/final.log`.
- Native sidebar table rows change from 8 to 5 when **资料库** is collapsed; hidden Diagnostics renders at the full detail width. At minimum setup size the native Form scrolls through a 620-point document in a 452.5-point viewport. Settings scrolls through 680 points in 536 points; bottom actions remain reachable.
- Native fixtures use in-memory stores, synthetic data, injected controller actions, a memory-only logger, a separate temporary bundle and prohibited activation. No product bootstrap, model, microphone, TCC reset, AX field observation, clipboard operation, production data/log access or visible fixture window was used.
- Xcode project/resource plist validation and `git diff --check` passed. The only build warning is the existing App Intents metadata-extraction notice because no AppIntents framework is linked.

Bitmap caching does not reproduce all native material/selection layers (the sidebar material can appear black). Images establish content/layout and scroll bounds; actual native materials, keyboard, focus and VoiceOver remain signed-app acceptance.

## Known issues / follow-up

Implementation and available isolated validation are complete. Keep the task **IN PROGRESS** until the owner runs [the signed-app M-010 checklist](../validation.md#m-010-chinese-ui-and-native-setup): first launch/denial/Settings return, actual ⌘, and sidebar/menu actions, focus, VoiceOver, native materials, and no interruption during real input. The earlier device-validation deferral remains in effect; it has not been treated as acceptance.

Do not reset TCC or replace the owner's signed app with unsigned validation output. No Apple Developer enrollment, CloudKit container or iOS work is required for this slice.
