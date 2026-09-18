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

The menu-bar panel is a compact status and launch surface, not the long-term product navigation hierarchy. History, Memory, Settings and Diagnostics belong in Morie's native management window, organized with a system `NavigationSplitView`; the panel exposes one **Open Morie** action instead of one action per section.

## Management window

M-008 uses one navigation language across the management window. A native sidebar groups **Library** (History, Memory) and **App** (Settings, Diagnostics). History and Memory show a selectable list beside the detail in a three-column split view. Settings and Diagnostics use the same sidebar with a full-width detail in a two-column split view. The default window is 1120 × 720; the minimum is 960 × 600. System split dividers control column resizing.

Lists use standard search, filter menus containing native Pickers, system selection and meaningful empty states. Search/filter/deletion clear hidden selections. Reading a source or linked memory uses the selected detail's NavigationStack; selecting a different record resets that stack. Creation/recording and filter controls belong to the list toolbar; copy/edit/review and the secondary action menu belong to the detail toolbar.

Capture, Memory and suggestion details use the same native ScrollView composition, 28-point padding and a readable maximum width of 760 points. Text is selectable, system typography establishes hierarchy, and native GroupBoxes/disclosures organize supporting information. Settings and editing use grouped Forms. Do not add custom cards, selection highlights, navigation bars or glass effects to reproduce these system surfaces.

Settings has a centered, flexible grouped Form with a 700-point maximum content width. Diagnostics uses the native Table with Time, Level, Category and Message columns, search and a level filter. Selecting an event reveals its full selectable message below a native split divider. Severity has a word/icon as well as semantic color. Copy All Events copies the whole current log; the action menu reveals the file or clears it after system confirmation.

## History recovery

History uses a system selectable `List` and a simultaneous reading detail. Search covers final/recognized text and the source app; filters provide All Captures, History Only and Needs Attention. The audio player is AVKit's native `AVPlayerView` with inline controls; Morie does not draw a replacement playback bar. Recording playback is user-initiated, stops when leaving the detail or starting a capture, and does not publish private recordings to Now Playing.

Re-recognition has a standard button, `ProgressView`, and Cancel action. Saved text stays visible while work runs. Details show **Final Text** first. **Copy Final Text** is in the toolbar and **Copy Recognition** is in its action menu. **Recognition & Refinement** discloses the separate recognized text and retained refinement record; **Source Recording** contains playback and retry controls. A Speech retry preserves previously delivered or refined final output, including capture-only output. Retry does not automatically paste into another app. Expired/missing audio and recognition failure have readable inline explanations. Deleting a Capture uses a destructive button and a system confirmation dialog.

An empty recognition with retained audio shows “未识别，录音已保存” in the existing HUD and appears as “Not Recognized” in History. A discarded no-input capture hides the HUD; neither case reports “已输入”.

History's native **Record Capture** toolbar button starts an intentional voice capture saved to History. It is disabled while another capture is active or capabilities are unavailable. Recording uses the existing HUD finish/cancel controls and shortcut; successful completion reports “已保存”. The **Source Recording** disclosure shows **Destination: History** or **Current App**, and an unfinished record reads “Recording…”. This entry point does not restore another app's focus, inject text or copy text automatically.

Explicit cancellation shows the existing status surface as “Stopping…” until capture closes and the unfinished record is discarded. Operational interruption retains available audio/text in History as a failed Capture. Shortcut loss keeps the blocked status until capability recheck; asynchronous cleanup must not report Ready or successful delivery over it. These states use the existing native status/HUD and History controls.

## Memory foundation

The **Memory** library uses the shared split navigation. A native searchable list and status filter show active, archived and superseded vocabulary/projects. Reading details prioritize names, aliases and notes. Confirmation and current personalization use remain visible; **Sources & History** discloses provenance and timestamps. Edit is a toolbar action, while archive/restore/replace/delete use the adjacent action menu. The editor is a system sheet with standard type/name controls, multiline TextEditors for aliases/notes, inline validation, and Save/Cancel actions. Permanent deletion uses a system confirmation dialog; archive remains reversible.

History offers **Save Memory…** with the source Capture visible. The user can enter a new term/project or link that Capture to an existing active entry. Matching active context and explicitly linked memories are labelled separately. Source inspection does not monitor another app or read the clipboard. Deleting a Capture explains that separately saved memories remain; missing sources are identified explicitly.

## Candidate extraction and review

M-005 attempts candidate extraction after completing input. History's **Find Memory Candidates** action provides an explicit retry when analysis was skipped or cancelled. Standard `ProgressView` and **Cancel Extraction** controls reflect its lifecycle. Suggestions have explicit **Review…**, saved and dismissed states; empty results remain visible and do not imply a failure. Starting voice input cancels this optional work.

The native review sheet shows the supporting quote, a **Text Used for Extraction** disclosure, editable type/name/aliases/notes, an existing-memory picker and Save/Cancel/Dismiss actions. The source identifies saved final or recognized text, retaining M-005's refined final output when refinement succeeds. Failed/skipped refinement is not described as polished. Changed/deleted source text prevents confirmation, with a readable recovery message. Save validation leaves the sheet open.

The Active Memory list includes current **Suggestions to Review**, separately from confirmed entries. Suggestions whose source is recording, cancelled, being refined, changed or deleted do not appear as reviewable. Selecting a suggestion opens its reading detail with evidence and a **Review & Save…** action; that action opens the native editor sheet. A saved AI-derived memory exposes its extraction snapshot in **Sources & History**. Deleting a Capture explicitly removes candidate snapshots as well as its text/audio, while confirmed Memory remains. All of these use the existing system list, form, sheet, picker, button and disclosure components; there is no custom review or AI-chat UI.

## Input refinement

Settings adds the system **Use Memory to Refine Input** toggle, enabled by default, with a short explanation that confirmed names and light punctuation cleanup preserve the user's wording. It is an optional input behavior within Private Mode.

History's **Input Refinement** content inside **Recognition & Refinement** shows the result, elapsed time and a readable reason when original text was kept. Standard disclosures show **Changes**, **Text Before Refinement** and immutable **Memory Considered** snapshots. Final text stays separate from later Speech retries so the text actually used remains inspectable. All status, copy and disclosure controls are native; this is provenance for input, not an AI chat or rewrite editor.

While refinement runs, the existing processing HUD stays in use and the menu reports **Refining…**. History mutation/extraction is disabled for the running source. A failed/slow refinement completes using saved original text; capability/session cancellation cannot cause a late paste. Actual VoiceOver, keyboard, rendering and latency acceptance remain device checks.

UI polish is not a reason to fork the product away from the system. Morie's differentiation is Capture, Personal Memory, and personalization—not a custom macOS widget toolkit.
