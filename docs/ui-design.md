# macOS 27 UI Design Rules

## Status

This is a hard implementation constraint for Morie, not a visual preference.

## Principle

Morie uses **Apple system UI itself**.

The target is not “Apple-like” or “Liquid-Glass-inspired”. On macOS 27, standard SwiftUI/AppKit components should be allowed to receive their current system appearance and behavior directly from macOS.

Apple's current platform guidance states that standard SwiftUI/AppKit controls and navigation surfaces adopt Liquid Glass automatically when built for the current platform. Morie should therefore prefer the standard component before adding any custom visual layer.

## Required order of implementation

For every UI requirement, use this order:

1. Find the current macOS 27 SwiftUI system component.
2. If SwiftUI does not expose the required native behavior, use the current AppKit system component/bridge.
3. If a truly custom control is unavoidable, use Apple's current native Liquid Glass APIs and interaction/layout conventions.
4. If none of the Apple-native options can satisfy the requirement, **stop**. Document the gap and ask the project owner for explicit approval before building a substitute.

There is no automatic step 5 that introduces an external UI library.

## System components first

Use system-provided implementations for, among others:

- windows and panels;
- menu bar extras and menus;
- buttons, toggles, pickers and text fields;
- toolbars and toolbar items;
- sheets, popovers, alerts and confirmation dialogs;
- lists/tables/forms;
- navigation and sidebars;
- settings surfaces;
- search;
- context menus;
- progress/status presentation;
- typography, spacing and control metrics;
- accessibility/focus/keyboard behavior.

Do not replace these solely to obtain a more stylized appearance.

## Liquid Glass

### Standard surfaces

When a standard macOS 27 control/surface already adopts Liquid Glass, do not layer a custom glass effect on top of it.

Examples include current system toolbar/navigation/control presentations where the OS owns the material, contrast, inactive-window behavior, scrolling interaction and hit testing.

### Custom surfaces

Only where there is no suitable standard system component, Apple-native APIs may be used, such as current SwiftUI/AppKit Liquid Glass primitives (`glassEffect`, `GlassEffectContainer`, system glass button styles, `NSGlassEffectView` and related current APIs).

Rules:

- use the system material, not a homemade blur/transparency recipe;
- interactive glass is reserved for actual interactive controls;
- do not cover content areas in decorative glass simply because the API exists;
- respect system hierarchy, contrast, motion, accessibility and reduced-transparency behavior;
- prefer system shapes/metrics and concentric corner behavior instead of fixed visual constants where Apple provides them.

## Prohibited by default

Without explicit project-owner approval, do not introduce:

- third-party UI component frameworks;
- third-party design systems;
- JavaScript/WebView UI shells;
- custom GPU/shader-based Liquid Glass imitation;
- hand-built blur/material stacks intended to mimic system glass;
- replacement title bars/toolbars when the native version can serve the requirement;
- custom controls that duplicate an existing system control just for styling;
- hard-coded visual metrics that intentionally fight current macOS layout/control behavior.

## Exception process

If native UI genuinely cannot meet a requirement, write down:

1. user/product requirement;
2. exact native components/APIs evaluated;
3. why each is insufficient;
4. smallest proposed exception;
5. accessibility implications;
6. maintenance/platform-evolution cost;
7. whether the exception adds an external dependency.

Then wait for explicit project-owner approval. Do not implement the exception first and ask afterward.

## Phase 0 application

The current menu-bar shell should stay system-native. As Phase 0 adds visible recording/permission/status experiences, they must be designed with macOS 27 native components and Liquid Glass behavior from the start rather than being retrofitted later.

The menu-bar panel is a compact status and launch surface, not the long-term product navigation hierarchy. History, Settings, Diagnostics, and future management sections belong in Morie's native management window, organized with a system `NavigationSplitView`; the panel exposes one **Open Morie** action instead of one action per section.

## History recovery

History uses a system `List` and `NavigationStack` to open a Capture detail `Form`. The audio player is AVKit's native `AVPlayerView` with inline controls; Morie does not draw a replacement playback bar. Recording playback is user-initiated, stops when leaving the detail or starting a capture, and does not publish private recordings to Now Playing.

Re-recognition has a standard button, `ProgressView`, and Cancel action. Saved text stays visible while work runs. A successful retry exposes recognized text separately from any different original output, with explicit system Copy buttons. Retry does not automatically paste into another app. Expired/missing audio and recognition failure have readable inline explanations. Deleting a Capture uses a destructive button and a system confirmation dialog.

An empty recognition with retained audio shows “未识别，录音已保存” in the existing HUD and appears as “Not Recognized” in History. A discarded no-input capture hides the HUD; neither case reports “已输入”.

History's native **Record Capture** toolbar button starts an intentional voice capture saved to History. It is disabled while another capture is active or capabilities are unavailable. Recording uses the existing HUD finish/cancel controls and shortcut; successful completion reports “已保存”. Capture details show **Destination: History** or **Current App**, and an unfinished record reads “Recording…”. This entry point does not restore another app's focus, inject text or copy text automatically.

Explicit cancellation shows the existing status surface as “Stopping…” until capture closes and the unfinished record is discarded. Operational interruption retains available audio/text in History as a failed Capture. Shortcut loss keeps the blocked status until capability recheck; asynchronous cleanup must not report Ready or successful delivery over it. These states use the existing native status/HUD and History controls.

UI polish is not a reason to fork the product away from the system. Morie's differentiation is Capture, Personal Memory, and personalization—not a custom macOS widget toolkit.
