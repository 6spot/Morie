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

Settings and Permissions are flexible grouped Forms inside Control Center rather than separate management windows. Command-comma opens Control Center and selects Settings. On launch, one read-only inspection automatically presents the welcome guide when required setup is incomplete; **打开 Morie** applies the same gate. Routine permission repair stays on the Permissions page. Diagnostics uses the native Table with Time, Level, Category and Message columns, search and a direct level filter. Selecting an event reveals its full selectable message below a native split divider. Severity has a word/icon as well as semantic color. Copy All Events copies the whole current log; the action menu reveals the file or clears it after system confirmation.

## Capture HUD visual language

The compact capture capsule is deliberately low-contrast. The surface uses `NSGlassEffectView.Style.clear` with no custom tint so macOS 27 owns the Liquid Glass translucency, refraction and environmental appearance. Recording controls and waveform use dynamic secondary-gray contrast rather than bright white controls or a near-black waveform.

Status color is reserved for state, not button identity:

- **Thinking** uses one restrained left-to-right shimmer band inside the compact capsule. It is not a progress fill and must not imply 0–100% completion. The shimmer runs once over about 2.2 seconds, then disappears while the native clear glass and Thinking text remain until processing finishes.
- normal successful completion has no separate success state: once processing completes, the `Thinking` capsule immediately runs its normal collapse/fade-out animation;
- this applies to both current-app delivery and capture-only completion; no `SUCCESS`, **已输入**, **已保存**, checkmark, green flash or other success badge is shown in the HUD;
- clipboard fallback, no-speech and recognition-failure messages remain visible because they communicate an outcome the user may need to act on; they stay text-only and visually secondary;
- accessibility labels remain descriptive Simplified Chinese.

Do not add decorative leading status icons back to these text messages. Normal success is communicated by the disappearance of the processing capsule itself; do not add another success dwell state unless new usability evidence requires one. Strong semantic color is reserved for outcomes that genuinely require attention.

The recording-to-processing morph uses motion rather than another status color: the wide recording capsule contracts around the waveform before `Thinking` replaces it. The processing capsule is narrower (94 pt versus 142 pt recording width). When Thinking first appears, a narrow low-contrast highlight traverses the glass once from left to right over about 2.2 seconds; because it leaves no filled track behind, it reads as activity rather than progress. Successful completion keeps that compact shape and fades almost in place instead of collapsing to a tiny dot. Reduced Motion skips the moving shimmer and uses only the compact static glass treatment.

## History recovery

History uses a system selectable `List` and a simultaneous reading detail. Search covers final/recognized text and the source app; filters provide All Captures, History Only and Needs Attention. History rows reserve a fixed two-line preview so progressive recognition does not continuously change native List row geometry or overlap neighboring rows. The secondary metadata stays on one line: source app followed by month/day/time, with status text only for active/error states; normal `已保存 / 已输入` badges are omitted as redundant. The audio player is AVKit's native `AVPlayerView` with inline controls; Morie does not draw a replacement playback bar. Recording playback is user-initiated, stops when leaving the detail or starting a capture, and does not publish private recordings to Now Playing.

Re-recognition has a standard button, `ProgressView`, and Cancel action. Saved text stays visible while work runs. Details show **最终文字** first. **复制最终文字** is in the toolbar and **复制识别文字** is in its action menu. **识别与润色** discloses the separate recognized text and retained refinement record; **原始录音** contains playback and retry controls. A Speech retry preserves previously delivered or refined final output, including capture-only output. Retry does not automatically paste into another app. Expired/missing audio and recognition failure have readable inline explanations. Deleting a Capture uses a destructive button and a system confirmation dialog.

An empty recognition with retained audio shows “未识别，录音已保存” in the existing HUD and appears as “未能识别” in History. A discarded no-input capture hides the HUD; neither case reports “已输入”.

History's native **开始录音** toolbar button starts an intentional voice capture saved to History. It is disabled while another capture is active or capabilities are unavailable. Recording uses the existing HUD finish/cancel controls and shortcut; successful completion reports “已保存”. The **原始录音** disclosure shows **保存位置：历史记录** or **当前应用**, and an unfinished record reads “正在录音…”. This entry point does not restore another app's focus, inject text or copy text automatically.

Explicit cancellation shows the existing status surface as “正在停止…” until capture closes and the unfinished record is discarded. Operational interruption retains available audio/text in History as a failed Capture. Shortcut loss keeps the blocked status until setup is checked and **开始使用** succeeds; asynchronous cleanup must not report Ready or successful delivery over it. These states use the existing native status/HUD and History controls.

## Dictionary

The **字典** library uses one native searchable content page, **添加词语 / 编辑词语** sheets and system deletion confirmation. Each entry is just one word: no aliases, replacement pairs or additional configuration. The page presents words in a compact adaptive grid of native bordered buttons rather than spending a full list row on each short term. Built-in baseline words, manually added words and correction-confirmed words may appear together; built-in words are read-only, while user-owned words retain edit/delete actions. Source is backend provenance rather than a required visible label.

The sheet is 420 points wide and fits its content, with one **词语** TextField, a brief purpose description and **取消 / 添加** (or **保存**) buttons. The word field receives initial focus. Return invokes the default action and Escape cancels; empty input disables saving. Duplicate/invalid/save errors remain inline without closing the editor, and editing clears stale error feedback. Cancel leaves saved data intact. Use the native columns Form and ordinary system controls.

## Personal Memory

**个人记忆** shows active, archived and superseded personal projects, people, preferences, facts and decisions. Topics and personal information are the primary reading content. Automatic/user origin and current use are visible; **来源与历史** discloses provenance, dates, exact learning snapshots and predecessor links.

Entries appear automatically from completed daily input. There is no candidate inbox or mandatory review. Optional native creation/editing, archive/restore/replace and system-confirmed deletion remain available to correct the profile. The editor uses a grouped Form with a kind Picker, topic TextField and multiline personal-information TextEditor. Dictionary words belong to their separate single-field editor.

History's **个人记忆** section shows idle scheduling, learning progress, outcomes, linked memories and **用于学习的文字**. Failed nonretryable analysis offers an optional retry. Opening/closing details does not control the background learner. Deleting a Capture explains that its analysis snapshots are removed while separate personal Memory remains; missing sources are labelled explicitly.

## Input cleanup

Settings exposes **自动润色语音输入**, on by default. Its explanation describes filler/redundancy removal and appropriate punctuation, paragraphs and clear lists while preserving meaning and tone. The dictionary applies independently of the toggle; Memory is not a prerequisite for cleanup.

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
