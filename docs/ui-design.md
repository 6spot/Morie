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

The menu-bar panel is a compact status and launch surface, not the long-term product navigation hierarchy. History, Dictionary, Personal Memory, Settings and Diagnostics belong in Morie's native management window, organized with a system `NavigationSplitView`; the panel exposes one **Open Morie** action instead of one action per section.

## Management window

M-008 uses one navigation language across the management window. A native sidebar groups **Library** (History, Dictionary, Personal Memory) and **App** (Settings, Diagnostics). History, Dictionary and Personal Memory show a selectable list beside the detail in a three-column split view. Settings and Diagnostics use the same sidebar with a full-width detail in a two-column split view. The default window is 1120 × 720; the minimum is 960 × 600. System split dividers control column resizing.

Lists use standard search, filter menus containing native Pickers, system selection and meaningful empty states. Search/filter/deletion clear hidden selections. Reading a source or linked memory uses the selected detail's NavigationStack; selecting a different record resets that stack. Creation/recording and filter controls belong to the list toolbar; copy/edit and the secondary action menu belong to the detail toolbar.

Capture, Dictionary and Personal Memory details use the same native ScrollView composition, 28-point padding and a readable maximum width of 760 points. Text is selectable, system typography establishes hierarchy, and native GroupBoxes/disclosures organize supporting information. Settings and editing use grouped Forms. Do not add custom cards, selection highlights, navigation bars or glass effects to reproduce these system surfaces.

Settings has a centered, flexible grouped Form with a 700-point maximum content width. Diagnostics uses the native Table with Time, Level, Category and Message columns, search and a level filter. Selecting an event reveals its full selectable message below a native split divider. Severity has a word/icon as well as semantic color. Copy All Events copies the whole current log; the action menu reveals the file or clears it after system confirmation.

## History recovery

History uses a system selectable `List` and a simultaneous reading detail. Search covers final/recognized text and the source app; filters provide All Captures, History Only and Needs Attention. The audio player is AVKit's native `AVPlayerView` with inline controls; Morie does not draw a replacement playback bar. Recording playback is user-initiated, stops when leaving the detail or starting a capture, and does not publish private recordings to Now Playing.

Re-recognition has a standard button, `ProgressView`, and Cancel action. Saved text stays visible while work runs. Details show **Final Text** first. **Copy Final Text** is in the toolbar and **Copy Recognition** is in its action menu. **Recognition & Refinement** discloses the separate recognized text and retained refinement record; **Source Recording** contains playback and retry controls. A Speech retry preserves previously delivered or refined final output, including capture-only output. Retry does not automatically paste into another app. Expired/missing audio and recognition failure have readable inline explanations. Deleting a Capture uses a destructive button and a system confirmation dialog.

An empty recognition with retained audio shows “未识别，录音已保存” in the existing HUD and appears as “Not Recognized” in History. A discarded no-input capture hides the HUD; neither case reports “已输入”.

History's native **Record Capture** toolbar button starts an intentional voice capture saved to History. It is disabled while another capture is active or capabilities are unavailable. Recording uses the existing HUD finish/cancel controls and shortcut; successful completion reports “已保存”. The **Source Recording** disclosure shows **Destination: History** or **Current App**, and an unfinished record reads “Recording…”. This entry point does not restore another app's focus, inject text or copy text automatically.

Explicit cancellation shows the existing status surface as “Stopping…” until capture closes and the unfinished record is discarded. Operational interruption retains available audio/text in History as a failed Capture. Shortcut loss keeps the blocked status until capability recheck; asynchronous cleanup must not report Ready or successful delivery over it. These states use the existing native status/HUD and History controls.

## Dictionary

The **Dictionary** library uses native searchable list/detail navigation, **Add Word / Edit Word** sheets and system deletion confirmation. The correct spelling is primary. Optional **Always Replace** aliases appear separately, with clear language that users should add them only for unconditional replacement. A spelling hint does not imply a global alias. Save errors stay in the native editor and Cancel leaves saved data intact.

## Personal Memory

**Personal Memory** shows active, archived and superseded personal projects, people, preferences, facts and decisions. Topics and personal information are the primary reading content. Automatic/user origin and current use are visible; **Sources & History** discloses provenance, dates, exact learning snapshots and predecessor links.

Entries appear automatically from completed daily input. There is no candidate inbox or mandatory review. Optional native creation/editing, archive/restore/replace and system-confirmed deletion remain available to correct the profile. The editor uses a grouped Form with a kind Picker, topic TextField and multiline personal-information TextEditor. Dictionary aliases never appear in this editor.

History's **Personal Memory** section shows idle scheduling, learning progress, outcomes, linked memories and **Text Used for Learning**. Failed nonretryable analysis offers an optional retry. Opening/closing details does not control the background learner. Deleting a Capture explains that its analysis snapshots are removed while separate personal Memory remains; missing sources are labelled explicitly.

## Input cleanup

Settings exposes **Clean Up Voice Input**, on by default. Its explanation describes filler/redundancy removal and appropriate punctuation, paragraphs and clear lists while preserving meaning and tone. The dictionary applies independently of the toggle; Memory is not a prerequisite for cleanup.

History's **Input Refinement** inside **Recognition & Refinement** shows status, duration and a readable fallback reason. Standard disclosures show **Changes**, **Text Before Refinement**, **Dictionary Used** and **Memory Considered**, retaining immutable snapshots. Recognition can change after a Speech retry while saved final output and its actual earlier provenance stay intact.

The existing processing HUD remains visible during cleanup and the menu reports **Refining…**. Running-source mutation/retry is disabled. Slow/failed AI processing retains saved dictionary-corrected/original text, and session cancellation prevents a late paste. Actual model fidelity, VoiceOver and latency require device checks.

## Word-correction suggestion

**Suggest Words After I Correct Input** is a separate default-off Settings toggle. Explain the short observation of recently inserted text and the explicit spelling confirmation. It is dictionary learning; personal Memory does not inherit this confirmation requirement.

After a stable eligible correction, show a native nonactivating utility `NSPanel` with standard Text and **Remember / Not Now** buttons. Present the old and corrected spellings and explain that the new spelling helps future input. Size the native panel to its content, including long words and save errors, without truncating the spelling being confirmed. Use system panel/control appearance, with no custom bubble, blur stack, overlay or imitation glass. Appearing must not activate Morie or steal the target's typing focus.

Remember saves the spelling only; saving can display an inline error. Not Now, expiry, changing the text again, leaving the observed field, starting input or disabling the setting dismisses it. Unsupported or secure fields do not show a suggestion. Keep the same word from repeatedly interrupting a session. Validate focus, keyboard/VoiceOver, long words, failure layout and fullscreen/multiple-screen behavior in the signed app; an offscreen image cannot establish those interactions.

Morie's differentiation remains useful input and personal context built on Apple system UI.
