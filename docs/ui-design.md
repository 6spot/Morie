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

The menu-bar extra uses the system `.menu` presentation. It contains textual status, **打开 Morie**, a native **设置…** link, **使用引导与权限…**, recording-shortcut guidance and **退出 Morie**. Navigation belongs in the management window. Settings and setup each have one native window shared by all entry points; the menu does not embed a custom panel or transcript preview.

Because Morie is an `LSUIElement` app, its idle activation policy is accessory and therefore has no application menu bar. When a real management/setup window is visible, Morie temporarily uses AppKit's regular activation policy before activation so macOS can present the native application menus and keyboard/window behavior. Closing the last Morie window returns to accessory mode; do not permanently turn Morie into a Dock app and do not replace the missing menu with a custom imitation.

## Language and system conventions

The current app's primary language is Simplified Chinese (`zh-Hans`), including app-owned controls, errors, accessibility descriptions and privacy usage strings. Keep user input, dictionary spelling, prompts, persisted raw values, external application names and technical diagnostics intact. Format display dates in Chinese while retaining the user's time zone.

Use the system Settings scene and **⌘,**. Sidebar and menu SettingsLink controls open that same scene. These are app-scoped commands; the global recording shortcut retains its existing behavior. NavigationSplitView and SidebarCommands own show/hide-sidebar controls. Native expandable Section headers fold **资料库 / 应用**, with saved expansion state. Do not build a replacement toggle, title bar, menu or shortcut listener.

## Permission and capability guide

M-010 uses a native Window, default 700 × 740, minimum 640 × 680. Its system `.hiddenTitleBar` style hides the title text beside the standard traffic-light controls. A grouped Form separates **设备能力** (Apple 智能, 中文语音转写) from **使用权限** (麦克风, 语音识别, 辅助功能). Every row explains its purpose. An unauthorized permission with an available action shows only **授权** or **打开系统设置**, without a redundant pending/denied status label. An authorized permission shows a green checkmark and **已授权**. Device capability status and restricted/unavailable reasons remain explicit. Long explanations scroll inside the system Form; the bottom actions remain visible.

First use and startup failures show this guide instead of a sequence of Morie modal alerts. Initial inspection and **重新检查** never prompt. **授权** requests an undetermined permission; denied access offers **打开系统设置**. Restricted/unavailable requirements remain explicit. Returning from System Settings refreshes without resetting input. **开始使用** is enabled only after every requirement passes and no capture/preparation/request is active. It prepares Speech assets and installs the shortcut before completing setup. The footer places **稍后设置** at the far left, with **重新检查** and **开始使用** together on the right. The refresh indicator stays beside its action. **稍后设置** closes the guide without enabling recording and retains Escape; **开始使用** retains Return as the default action.

After a native authorization dialog completes, the originating Morie window returns to the front. When an explicitly opened Privacy pane reports the requested access as granted, Morie likewise restores the originating setup or Control Center window. One **授权** click for Accessibility first invokes the public registration prompt required to make Morie appear in the system list, then opens the correct Settings pane after a short handoff. macOS may still require its own confirmation, but a second Morie click is not required.

Permission check/authorization state and bootstrap preparation feedback remain distinct. A model download or startup/storage error is displayed in the guide, and the native setup entry remains accessible from management, Settings and the menu. No CloudKit enrollment step appears in this milestone.

## Management window

M-008/M-010/M-013 use one native navigation language. The sidebar groups **资料库** (历史记录, 字典, 个人记忆) and **应用** (设置, 权限, 诊断). History and Personal Memory show list and detail in three columns. Dictionary, Settings, Permissions and Diagnostics use one full-width detail beside the sidebar; Dictionary edits the selected word from its list toolbar or context menu instead of opening a third column. Both split configurations share visibility state so switching sections preserves the sidebar preference. The default management window is 1120 × 720; the minimum is 960 × 600. System split dividers control resizing.

Lists use standard search, direct menu-style Pickers for single-dimension filters, system selection and meaningful empty states. Search/filter/deletion clear hidden selections. Reading a source or linked memory uses the selected detail's NavigationStack; selecting a different record resets that stack. Creation/recording and filter controls belong to the list toolbar; copy/edit and the secondary action menu belong to the detail toolbar.

Capture and Personal Memory details use the same native ScrollView composition, 28-point padding and a readable maximum width of 760 points. Text is selectable, system typography establishes hierarchy, and native GroupBoxes/disclosures organize supporting information. Settings and Permissions use grouped Forms; the single-word dictionary sheet uses a compact native columns Form. Do not add custom cards, selection highlights, navigation bars or glass effects to reproduce these system surfaces.

M-036 keeps **个人记忆** intentionally natural rather than database-shaped. List rows show the remembered topic and current body, not internal `longTerm / workingContext` or kind labels. The detail may expose source/evidence history because provenance is meaningful user control. Manual add/edit asks only for **主题 / 内容**; internal classification and lifecycle are system-owned. Settings uses a standard **使用个人记忆** Toggle. Turning it off preserves existing visible Memory while stopping new learning and Memory use during cleanup.

Settings and Permissions are flexible grouped Forms inside Control Center rather than separate management windows. Command-comma opens Control Center and selects Settings. On launch, one read-only inspection automatically presents the welcome guide when required setup is incomplete; **打开 Morie** applies the same gate. Routine permission repair stays on the Permissions page. Diagnostics uses the native Table with Time, Level, Category and Message columns, search and a direct level filter. Selecting an event reveals its full selectable message below a native split divider. Severity has a word/icon as well as semantic color. Copy All Events copies the whole current log; the action menu reveals the file or clears it after system confirmation.

## Capture HUD visual language

The compact capture capsule is deliberately low-contrast. The surface uses `NSGlassEffectView.Style.clear` with no custom tint so macOS 27 owns the Liquid Glass translucency, refraction and environmental appearance. Recording controls and waveform use dynamic secondary-gray contrast rather than bright white controls or a near-black waveform.

Status color is reserved for state, not button identity:

- **Thinking** uses a restrained repeating left-to-right shimmer band inside the compact capsule. The band travels across the **entire visible processing capsule**, from fully outside the left edge to fully outside the right edge. It is bright-neutral (white highlight on glass), never `Color.primary`, so light appearance must not produce a black sweep. It is not a progress fill and must not imply 0–100% completion. One cycle is about 3 seconds: ~2.4 seconds linear travel followed by ~0.6 seconds fully clear before restarting. Real completion interrupts the cycle immediately.
- normal successful completion has no separate success state: once processing completes, the `Thinking` capsule immediately runs its normal collapse/fade-out animation;
- this applies to both current-app delivery and capture-only completion; no `SUCCESS`, **已输入**, **已保存**, checkmark, green flash or other success badge is shown in the HUD;
- clipboard fallback, no-speech and recognition-failure messages remain visible because they communicate an outcome the user may need to act on; they stay text-only and visually secondary;
- accessibility labels remain descriptive Simplified Chinese.

Do not add decorative leading status icons back to these text messages. Normal success is communicated by the disappearance of the processing capsule itself; do not add another success dwell state unless new usability evidence requires one. Strong semantic color is reserved for outcomes that genuinely require attention.

The recording-to-processing morph uses motion rather than another status color: the wide recording capsule contracts around the waveform before `Thinking` replaces it. The processing capsule is narrower (94 pt versus 142 pt recording width). While Thinking is active, a narrow low-contrast highlight repeatedly traverses the glass from left to right. The band fully exits before a short pause and reset, so it reads as ongoing activity rather than accumulated progress. Successful completion keeps that compact shape and fades almost in place instead of collapsing to a tiny dot. Reduced Motion skips the moving shimmer and uses only the compact static glass treatment.

## Control Center shell

The Control Center follows one **macOS 27 System Settings-style layout contract**. The owner screenshots document required functions/content only; they are not a visual-style template.

The window owns one persistent `NavigationSplitView` for its entire lifetime. The left `List(.sidebar)` is created once and remains mounted while the selected section changes. The right side owns one persistent `NavigationStack`; section routing replaces only the page content inside that stack. Do not switch between different outer split-view/navigation roots for History, Dictionary, Memory or settings pages.

The shell itself must not observe Morie's high-frequency runtime controller. Only the visible feature page observes the state it needs. Sidebar selection and disclosure state must therefore remain independent from capture, transcription, model and permission updates.

### Shared visual grid

Overview, Dictionary, Personal Memory, Settings and Permissions share one 24-point scroll-content inset so their left/top content baselines do not move between sections. The leading edge is intentionally chosen to align with the native navigation-title leading edge beside the sidebar. Their ScrollView fills the whole right workspace, so the vertical scroll indicator remains at the workspace edge.

Settings and Permissions no longer use top-level grouped Forms because the grouped Form adds its own outer inset and breaks title/content alignment. They use the same `ControlCenterContentPage` and `ControlCenterSectionGroup` primitives as the other ordinary pages, while the controls inside remain native SwiftUI controls.

### Page families

Native-first means using the right native building blocks for the content, not making every page a Form/List:

- **Overview**, **Dictionary**, **Personal Memory**, **Settings**, and **Permissions** all use the same page container and section shell (`ControlCenterContentPage` + `ControlCenterSectionGroup`). Their inner controls differ only where the function requires it.
- **Overview** keeps its metrics and model information, but the visual grouping follows the shared section style.
- **Dictionary** keeps compact word management behavior while its outer sections follow the shared section style.
- **Personal Memory** keeps topic/recent/history behavior while its outer sections follow the shared section style.
- **Settings / Permissions** keep all existing native controls and actions inside the same shared section style instead of using a separately inset top-level Form.
- **History** uses a native `HSplitView` inside the persistent right-side navigation host: an inset selectable List on the left and a reading detail on the right.
- **Diagnostics** stays a native `Table` with a native split detail for the selected message.
- **Reading details** such as a Capture or Memory detail use one shared ScrollView composition with 28-point scroll-content margins and a readable maximum width of 760 points.

Native navigation titles, search, toolbars, split dividers, Forms, Lists, Tables, buttons, sheets, alerts and confirmation dialogs own their appearance. Custom composition is allowed when it represents the information architecture (dashboard/grid/narrative), but do not draw replacement system controls, title bars, selection chrome or decorative fake glass.

### Layout invariants

- The sidebar uses the system accent color and system row/control metrics.
- No top-level page may force the Control Center wider than its available right workspace.
- Scroll indicators belong at the workspace edge; never place the ScrollView inside a fixed-width outer frame.
- Page-specific content may differ, but its outer content baseline must stay on the shared grid.
- Dense workspaces may be edge-to-edge; readable text detail alone uses the shared reading max width.
- Page titles and toolbar/search controls terminate in the one right-side navigation hierarchy instead of leaking through nested page roots.

## History recovery

History uses the Control Center's single right-side navigation host plus one system `HSplitView`. The list pane and detail pane do not create their own page-level NavigationStacks. Search, filter and **开始录音** belong to the History workspace toolbar; selected-record actions join that same native toolbar instead of creating a second toolbar strip.

The list column uses a native selectable `List` and stays within a bounded 260–360 point range. The detail may compress to 360 points before expanding. These widths are workspace constraints, not decorative page widths, and must not make the overall Control Center exceed the available window.

The loaded History page is retained by `CaptureHistoryController`; leaving and returning to History first compares a cheap completed-record count/latest-update signature instead of rebuilding an all-record `@Query`. Capture completion, retry and deletion explicitly invalidate that retained page.

Search covers final/recognized text and the source app; filters provide All Captures, History Only and Needs Attention. History rows reserve a fixed two-line preview so progressive recognition does not continuously change native List row geometry or overlap neighboring rows. The secondary metadata stays on one line: source app followed by month/day/time, with status text only for active/error states; normal `已保存 / 已输入` badges are omitted as redundant.

The audio player is AVKit's native `AVPlayerView` with inline controls; Morie does not draw a replacement playback bar. Recording playback is user-initiated, stops when leaving the detail or starting a capture, and does not publish private recordings to Now Playing.

Re-recognition has a standard button, `ProgressView`, and Cancel action. Saved text stays visible while work runs. Details show **最终文字** first. **复制最终文字** is in the toolbar and **复制识别文字** is in its action menu. **识别与润色** discloses the separate recognized text and retained refinement record; **原始录音** contains playback and retry controls.

An empty recognition with retained audio shows “未识别，录音已保存” in the existing HUD and appears as “未能识别” in History. A discarded no-input capture hides the HUD; neither case reports “已输入”.

History's native **开始录音** toolbar button starts an intentional voice capture saved to History. It is disabled while another capture is active or capabilities are unavailable. Recording uses the existing HUD finish/cancel controls and shortcut; successful completion reports “已保存”. The **原始录音** disclosure shows **保存位置：历史记录** or **当前应用**, and an unfinished record reads “正在录音…”.

## Dictionary

The **字典** library is one searchable full-width page beside the sidebar. The content is a compact adaptive grid because the primary objects are short canonical words rather than row-shaped records.

- **用户添加**: editable/selectable native bordered buttons with toolbar/context-menu edit and delete.
- **系统内置**: compact read-only terms with restrained secondary styling; they do not enter edit/delete selection flows.

Each entry remains one canonical word: no aliases, replacement pairs or additional user configuration. Source is backend provenance rather than a required visible label.

The editor remains a compact native **添加词语 / 编辑词语** sheet, 420 points wide, using a columns Form with one **词语** TextField, short purpose text and standard **取消 / 添加** or **保存** buttons.

## Personal Memory

**个人记忆** is intentionally not a database list. It is a full-width reading surface that shows Morie's current understanding as semantic topics.

Durable topics are rendered as natural topic + body blocks. Temporary working context is separated only under the natural **最近** heading. Archived/superseded material stays collapsed under **已归档与历史** so the ordinary page remains focused on current understanding. Search filters these topic blocks in place.

Opening a topic pushes the existing detail inside the Control Center's one NavigationStack for correction and provenance. The detail may expose source/evidence history because provenance is meaningful user control. Manual add/edit asks only for **主题 / 内容**; internal classification and lifecycle are system-owned.

Settings uses a standard **使用个人记忆** Toggle. Turning it off preserves existing visible Memory while stopping new learning and Memory use during cleanup.

## Input cleanup

Settings exposes **自动润色语音输入**, on by default. Its explanation describes filler/redundancy removal and appropriate punctuation, paragraphs and clear lists while preserving meaning and tone. The dictionary applies independently of the toggle; Memory is not a prerequisite for cleanup.

M-035 adds a separate native **润色提示词** section using the system `TextEditor`. The editor shows the effective instructions, with ordinary system **保存提示词** and **恢复默认** buttons plus secondary status/help text. Saving affects only Captures started afterward and does not require an app rebuild or relaunch; an in-flight Capture keeps its start-time prompt snapshot. Restore removes the user override and reloads Morie's bundled default. Do not add a custom code editor, prompt marketplace or live-as-you-type model call to this surface. Apple-local and external refinement share the same edited instruction.

History's **输入润色** inside **识别与润色** shows status, duration and a readable fallback reason. Standard disclosures show **修改内容**, **润色前的文字**, **本次使用的字典** (saved words only) and **本次参考的个人记忆**, retaining immutable snapshots. Recognition can change after a Speech retry while saved final output and its actual earlier provenance stay intact.

The existing processing HUD remains visible during cleanup and the menu reports **正在润色…**. Running-source mutation/retry is disabled. Slow/failed AI processing retains saved dictionary-corrected/original text, and session cancellation prevents a late paste. Actual model fidelity, VoiceOver and latency require device checks.

## Word-correction suggestion

**修改输入后建议加入字典** is a separate default-off Settings toggle. Explain the short observation of recently inserted text and the explicit spelling confirmation. It is dictionary learning; personal Memory does not inherit this confirmation requirement.

After a stable eligible correction, show a native nonactivating utility `NSPanel` with standard Text and **加入字典 / 暂不添加** buttons. Present the old and corrected spellings and explain that the new spelling helps future input. Size the native panel to its content, including long words and save errors, without truncating the spelling being confirmed. Use system panel/control appearance, with no custom bubble, blur stack, overlay or imitation glass. Appearing must not activate Morie or steal the target's typing focus.

Remember saves the spelling only; saving can display an inline error. Not Now, expiry, changing the text again, leaving the observed field, starting input or disabling the setting dismisses it. Unsupported or secure fields do not show a suggestion. Keep the same word from repeatedly interrupting a session. Validate focus, keyboard/VoiceOver, long words, failure layout and fullscreen/multiple-screen behavior in the signed app; an offscreen image cannot establish those interactions.

Morie's differentiation remains useful input and personal context built on Apple system UI.


## Expression Profile settings

Expression Profile is controlled from the native **设置** page rather than adding another library/sidebar destination in its first slice.

- **学习我的表达习惯** is a native Toggle and defaults off while post-insertion observation is still being validated.
- Supporting copy states that Morie observes only the text it just inserted, learns aggregate punctuation/paragraph/list/spacing preferences, and does not persist the edited source text as profile data.
- **清除已学习的表达习惯…** uses a destructive native confirmation dialog and clears only aggregate style learning, not History, Dictionary or Personal Memory.
- Do not expose raw accumulator values or developer-style confidence controls in the ordinary settings UI.


## iCloud settings

The first iCloud control lives in the native **设置** page.

- **使用 iCloud 同步与备份** is a native Toggle and defaults off.
- Turning it on first checks the current iCloud account and only persists the request when CloudKit reports an available account.
- Because SwiftData's CloudKit configuration belongs to the launched `ModelContainer`, a change that alters the active storage mode clearly states that Morie must be restarted before it takes effect.
- Status uses a native `LabeledContent`; an enabled configuration exposes **重新检查 iCloud**.
- Supporting copy states the data boundary: History text, Dictionary, Personal Memory and Expression Profile use the user's private iCloud database; original recordings remain local.
- iCloud is optional. A CloudKit startup failure falls back to the local current-schema store and surfaces the cloud error instead of blocking normal voice input.
