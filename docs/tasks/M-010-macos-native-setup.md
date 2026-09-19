# M-010 — Simplified Chinese UI and native macOS setup

> **M-013 amendment (2026-09-19):** the welcome guide is no longer a permanent menu/sidebar/Settings destination. Choosing **打开 Morie** presents it only while required setup is incomplete. Routine permission management and Settings now live as separate Control Center pages; Command-comma selects the embedded Settings page. See [M-013](M-013-control-center.md).

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-18
- **Branch:** `feature/m-010-native-chinese-setup`
- **Follow-up branch:** `fix/m-010-speech-authorization`
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
7. Setup uses the system hidden-title-bar style. Unauthorized permission rows show the available action without a duplicate state label; authorized rows say **已授权**. **稍后设置** sits at the far left, with **重新检查 / 开始使用** on the right.

## Progress

- [x] Record owner requirements and native implementation boundary.
- [x] Translate and normalize UI copy and language metadata.
- [x] Integrate native menus, Settings shortcut and sidebar controls.
- [x] Implement capability inspection and permission setup.
- [x] Complete isolated checks, layout verification and documentation.
- [x] Reproduce and fix the Speech authorization callback's actor-isolation crash.
- [x] Simplify setup title/status/footer presentation and verify native layouts.
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
- The guide uses a standard Window with `.hiddenTitleBar`, grouped Form, status labels, progress and buttons. Default 700 × 740, minimum 640 × 680; long content scrolls independently of the persistent footer. The owner requested hiding the title text beside the native traffic-light controls.
- Unauthorized permission rows show **授权** or **打开系统设置** directly; authorized rows show **已授权**. Device capability and restricted/unavailable explanations remain visible. The footer puts **稍后设置** at the far left and **重新检查 / 开始使用** at the right, with the refresh indicator beside its button. Native Escape/Return actions and busy/preparation disabling remain.
- Startup errors stay in the guide instead of creating Morie consent/recovery modals. Existing runtime Capture-first failures and the recording shortcut remain in force.

### Reference decisions

Reviewed upstream Type4Me permission manager/guide/tests and relevant permission history before changing the flow. **ADAPT** explicit authorization, denial/settings return and completion gating; **DROP** custom drag overlays, Settings-window polling, provider routing, old signing recovery and automatic relaunch. **VERIFY** any actual macOS 27 restart issue before introducing a workaround. Full references and pinned revision are in [the permission audit](../reference/type4me.md#6-permissions-and-onboarding). No third-party code or dependency was added.

### Speech authorization callback isolation

The owner's evening permission check stopped with `EXC_BREAKPOINT` in `_dispatch_assert_queue_fail`. Sampling the paused process confirmed the TCC reply invoked `CapabilityGate.requestPermission`'s completion on `com.apple.root.default-qos`; Swift checked the closure's inherited `MainActor` isolation before it could resume the continuation. The macOS 27 SDK explicitly does not guarantee a main-queue Speech authorization callback.

The completion is now explicitly `@Sendable` and captures only its thread-safe checked continuation. Setup inspection and UI state still resume on the main actor. `requestSpeechAuthorization(using:)` keeps the native Objective-C call boundary and accepts a recognizer metatype for isolated tests; production uses `SFSpeechRecognizer` only for authorization, with the existing undetermined-status guard and explicit user action. No dispatch workaround, permission reset or Speech fallback is added.

## Validation evidence

### 2026-09-19 permission-window focus follow-up

- Explicit Microphone/Speech requests remember the originating Morie window and restore it as key/front after the native authorization dialog completes.
- Opening a Privacy pane starts a bounded 500 ms permission-status wait only for that explicit action. It stops immediately when access is granted, when the user returns to Morie without granting, on cancellation, or after five minutes; it is not an idle/background poll. On grant, Morie activates and restores the originating setup or Control Center window.
- Follow-up correction: `prompt: false` does not register a new signed app in the Accessibility list. One Morie **授权** action now calls the public registration route, `AXIsProcessTrustedWithOptions` with `prompt: true`, then opens the Accessibility pane after a 250 ms handoff. This also handles TCC states where the registration prompt no longer reappears, without requiring a second Morie click. The system confirmation itself cannot be bypassed with public APIs.
- A one-time read-only inspection from the menu-bar label automatically opens the welcome guide on launch when setup is incomplete. A fully configured launch remains menu-bar-only; **打开 Morie** uses the same setup gate.
- Focused `PermissionSetupTests` and the latest full **107-test** suite passed with 0 failures/skips/runtime warnings. The added check verifies Accessibility presents **授权** while ordinary denied permissions retain **打开系统设置**. Latest result: `/tmp/morie-startup-permission/Logs/Test/Test-MorieTests-2026.09.19_07-45-53-+0800.xcresult`. The isolated unsigned Debug app build passed in the same DerivedData; its only warning was the existing AppIntents no-framework metadata notice. Signed-app focus ordering, TCC registration and actual System Settings behavior remain required device acceptance.

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

Speech callback follow-up, 2026-09-18, macOS 27.0 (26A428), Xcode 27.0 (27A266a), arm64, Swift 6 language mode. Artifacts: `/tmp/morie-speech-permission.HILpZj`.

- `paused-process.sample.txt` confirms the owner's actual TCC → Speech completion → Swift isolation check → dispatch assertion stack without resuming or terminating the debug session.
- **Regression reproduced before the fix:** the injected `SFSpeechRecognizer` subclass invokes the actual production bridge from a background queue. With only the `@Sendable` annotation absent, it crashes with the same `EXC_BREAKPOINT` / `_dispatch_assert_queue_fail` stack. Evidence: `BeforeFixNativeCallback.xcresult`, `before-fix-native-callback.log`, and `/Users/me/Library/Logs/DiagnosticReports/xctest-2026-09-18-193213.ips`.
- **102 logic tests passed after the fix**, 0 failures/skips/runtime warnings in the result summary. The two new tests cover background allow/deny callbacks, the main-actor return, cleared request state, readiness/denial recovery, and synchronous completion. Evidence: `Tests.xcresult` and `test.log`.
- **App Debug build passed** with signing disabled and separate `AppDerivedData`; evidence: `build.log`. The existing App Intents metadata notice remains; Xcode also emitted its test-launcher diagnostic.
- The tests replace only the authorization class method and never query or request real TCC, open a microphone, launch Morie, or change production storage/logs. The signed Xcode app and its permissions remain intact. Actual signed-app consent/recheck acceptance stays open in [the checklist](../validation.md#m-010-chinese-ui-and-native-setup).

Presentation follow-up in the same environment and artifact directory:

- **Final Debug build and all 102 logic tests passed** after the title, permission-copy and footer changes; 0 failures/skips/runtime warnings in `SetupPolishTests.xcresult`. Logs: `setup-polish-build.log` and `setup-polish-test.log`.
- **Eight native fixtures rendered and inspected:** initial/default, initial/minimum, granted, requesting, refreshing, preparing, blocked/minimum and blocked/scrolled-to-bottom. Current `PermissionSetupContent` is rendered in isolated offscreen AppKit windows with the native hidden-title configuration. Images and fixture source: `setup-preview/`; rendering evidence: `setup-preview/render.log`.
- Permission actions replace redundant ungranted labels, granted rows show **已授权**, and the footer keeps **稍后设置** on the left with **重新检查 / 开始使用** on the right. The minimum blocked Form scrolls a 620-point document through a 452.5-point viewport; the footer remains outside the scrolling region. Every fixture reports hidden title text and `visible: false`.
- Fixture actions are no-ops and use synthetic checks, with no production controller or system permission access. These images establish layout/copy and native scroll behavior; actual SwiftUI-window keyboard, focus, materials and TCC acceptance remain open.

## Known issues / follow-up

Implementation and available isolated validation are complete. Keep the task **IN PROGRESS** until the owner runs [the signed-app M-010 checklist](../validation.md#m-010-chinese-ui-and-native-setup): first launch/denial/Settings return, actual ⌘, and sidebar/menu actions, focus, VoiceOver, native materials, and no interruption during real input. The earlier device-validation deferral remains in effect; it has not been treated as acceptance.

Do not reset TCC or replace the owner's signed app with unsigned validation output. No Apple Developer enrollment, CloudKit container or iOS work is required for this slice.
