# Phase 0 Validation

This document defines the real-device acceptance checks for **M-002 — macOS Input Foundation**.

Phase 0 cannot be marked `DONE` solely from static review or compilation. Global keyboard capture, microphone behavior, permission lifecycle, current-focus routing, Accessibility APIs, and editor insertion must be exercised on a supported Mac.

Owner scheduling decision, 2026-09-18: defer interactive device validation until the evening and continue independent development now. Keep the checklist open; no device result is inferred from this deferral.

## Compile gate

Product/Xcode-project changes must first pass `.github/workflows/macos-27-ci.yml` on the hosted macOS 27 / Xcode 27 environment.

This proves current SDK/Swift compilation only. It does not replace any runtime check below.

## Test environment

Record for each validation run:

- macOS version/build;
- Mac model / chip;
- Apple Intelligence state;
- primary locale(s);
- Xcode/build version;
- Morie commit SHA/build number;
- relevant app versions.

## Capability gate

Verify:

- supported Mac + Apple Intelligence available → passes model capability check;
- unavailable model state → Morie remains blocked with a useful reason;
- unsupported Speech locale → blocked rather than silently falling back;
- denied microphone permission → blocked/recoverable;
- denied Speech permission → blocked/recoverable;
- missing Accessibility trust → blocked/recoverable;
- refreshing after permission changes updates the guide; **开始使用** can then reach Ready without a fallback implementation;
- revoking Accessibility after startup does not leave a broken/stuck global shortcut session.
- a system event-tap timeout disables Morie's shortcut and leaves ordinary keyboard input immediately usable; Morie must not automatically re-enable a repeatedly failing tap;

CloudKit/iCloud is outside the current single-Mac milestone. Account/container gating will be validated when a later cross-device task is scheduled; it is not a prerequisite for M-003 local persistence.

The initial `AVCaptureAudioFileOutput` integration caused a confirmed AVFoundation `SIGABRT` on macOS 27 and was removed. Its single-data-output replacement is implemented but must prove start, stop, cancellation, recognition failure, repeated capture, M4A playback, size, CPU and memory behavior on owner hardware before acceptance.

Verify the empty-result split explicitly: a silent start/stop must create neither a History row nor a retained M4A, while audible speech that produces no transcript must retain both the failed Capture and its retryable source audio.

2026-09-18 owner validation confirmed normal Chinese input and M4A creation, but the empty-result split did not pass: captures `CBCA4A24` and `5B073CAE` produced empty transcripts and were retained because ambient/input energy crossed the former meaningful-audio threshold. The History follow-up removes that amplitude-only decision and retains uncertain audio with explicit recovery actions. Automatic discard currently covers no input/zero signal only. **The quiet-room silence versus audible recognition failure acceptance item remains open.**

## M-003 History playback and recovery

Run from the owner's normal Xcode-signed build using disposable test Captures:

- [ ] Open a Capture and play, pause and seek using the native audio controls; opening alone must not play it.
- [ ] Leave the detail, switch sections, close the window, or start Fn recording while playback is active; playback must stop.
- [ ] Re-recognize a completed Capture; recovered text is saved to the same record and survives relaunch.
- [ ] Original delivered text/outcome remain visible when new recognition differs; retry itself must not paste or change the clipboard.
- [ ] Cancel retry during file analysis/finalization; prior text and audio remain intact, including when a late result arrives.
- [ ] Start live Fn capture during retry; the retry stops, the new microphone session starts once, and ordinary input remains usable.
- [ ] Repeatedly retry, cancel, navigate away and retry another Capture without a stuck progress indicator or incorrect-row update.
- [ ] Empty or failed re-recognition has readable recovery feedback and keeps the prior content. A later successful retry clears the retry error.
- [ ] An expired, missing or unplayable recording has useful feedback, with saved text still available.
- [ ] Let an open detail's recording expire and change retention while a recording is selected; playback/retry must not keep an expired recording usable.
- [ ] Relaunch with an empty failed Capture whose audio expired; the History row/error/duration remain.
- [ ] Delete one disposable Capture through confirmation; its row and audio disappear, and other Captures remain.
- [ ] Confirm native player/Copy/retry/cancel/delete controls with keyboard and VoiceOver, long text, and light/dark appearance.

Automated persistence/History tests cover success, empty results, failure, cancellation, input preemption, missing/expired audio, interrupted recovery and scoped deletion. These tests use temporary storage and injected file recognition, so they do not establish native playback, ASR accuracy, microphone behavior or visual acceptance.

2026-09-18: the final isolated app build and all **20 logic tests** passed on macOS 27 / Xcode 27, with no failures or skipped tests. A separate native `CaptureFileTranscriber` check recognized generated Chinese AAC audio, reported empty recognition for a silent M4A, and rejected a missing file. Offscreen rendering checked the Capture detail layout only. Evidence paths are recorded in [`M-003-capture.md`](./tasks/M-003-capture.md); the interactive checks above remain open.

## M-003 capture-only voice entry

- [ ] Choose **历史记录 → 开始录音**, speak and finish with the HUD; text/audio are saved with **保存位置：历史记录**, and feedback says “已保存”.
- [ ] Finish another capture-only recording with the configured shortcut; the entry's saved destination remains authoritative.
- [ ] Switch to another app before finishing; no paste, clipboard mutation or target-app activation occurs.
- [ ] Cancel with Escape/HUD; the unfinished row and audio are removed, and a new capture starts normally.
- [ ] Alternate capture-only and global-shortcut captures; current-app input still restores/delivers to the correct target and reports “已输入”.
- [ ] Retry an empty/failed capture-only recording; recovery retains its History destination and does not trigger delivery.
- [ ] Start capture-only during History playback/retry; preemption works and capture startup remains responsive.
- [ ] The native toolbar action is accessible by keyboard/VoiceOver and cannot start duplicate recordings during startup/finalization.

2026-09-18: isolated Debug compilation and all **24 logic tests** passed (0 failed/skipped). Offscreen native rendering confirms the History toolbar action and the completed capture-only destination/status. These checks do not establish microphone, clipboard/focus or live interaction acceptance; the checklist remains open.

## M-003 interruption and discard

Use disposable captures from the normal Xcode-signed app. Repeat the relevant cases for both the shortcut and History's **开始录音** entry:

- [ ] Start recording, speak, then open **使用引导与权限 → 重新检查**. Inspection leaves the recording running; normal finish retains/delivers the same text/audio exactly once. **开始使用** remains disabled during input.
- [ ] Refresh setup during Speech startup and normal finalization. It does not restart bootstrap, tear down capture or create an orphan microphone session, duplicate completion or stale state.
- [ ] Reproduce shortcut unavailability/Accessibility revocation while recording. Ordinary keyboard input remains usable; the Capture is retained and status stays blocked until setup is checked and **开始使用** succeeds.
- [ ] Exercise a real microphone/capture-session interruption where practical. Failure ends capture without requiring the user to press Finish; retained audio can be played or shows an accurate native error.
- [ ] Interrupt during focus handoff before paste. Saved text stays in History and no delayed clipboard staging/paste occurs. A paste already dispatched retains its actual delivery outcome.
- [ ] Cancel with Escape/HUD during startup and recording. Native recording closes before the row/file disappear; a subsequent capture starts normally.
- [ ] Repeat interruption/recheck/cancel followed by another capture. No stale text, stuck progress, duplicate recording or retained microphone indicator remains.

Automated AAC tests establish finalization and data preservation for controlled conversion/flush errors, immediate stop and repeated completion. They do not establish real session-notification timing, controller scheduling, microphone release, or decodability after a force quit/storage failure. Those checks remain open.

2026-09-18: final isolated Debug compilation and all **31 tests** passed on macOS 27 / Xcode 27 (0 failed/skipped). The seven new tests use real Apple AAC encoding/decoding plus temporary storage, without opening a microphone or launching Morie. Paths and limits are recorded in [M-003](./tasks/M-003-capture.md#validation-evidence).

## M-004 Memory foundation

Current acceptance follows [M-009](tasks/M-009-macos-input-memory.md), which supersedes mandatory candidate review. Use disposable records in the signed app when deferred evening validation resumes:

- [ ] Completed ordinary input creates selective personal Memory during idle time without a confirmation inbox. Empty Memory does not prevent useful input/cleanup.
- [ ] History's **用于学习的文字** is the exact committed final text, including dictionary/cleanup output; recognized text remains separate.
- [ ] Active, cancelled, capture-only, raw-only and running-refinement sources are excluded. Changed/deleted/unsaved sources cannot produce stale results.
- [ ] Check actual Chinese/English personal projects, people, stable preferences, facts and decisions. Quoted, third-person, hypothetical, temporary and uncertain statements are not asserted as personal facts.
- [ ] Repeat evidence and weaker recurring evidence across distinct inputs; sources merge without duplicate Memory or double-counting one Capture.
- [ ] Express a clear later personal update; current automatic Memory is superseded with source history. Older/ambiguous information and user-edited records are not overwritten.
- [ ] Edit, archive/restore, replace and delete Memory. Active context updates appropriately; the same normalized deleted topic is not immediately relearned. Evaluate differently phrased topic consistency too.
- [ ] Delete a disposable source Capture; its analysis snapshots disappear while independent Memory shows the missing source. User Memory deletion preserves the intentional Capture.
- [ ] New voice input promptly cancels optional analysis; no late result saves, and unfinished queue work resumes during idle time/relaunch. Exercise model unavailability/failure/backoff and optional retry.
- [ ] Measure model selectivity, evidence correctness, idle energy, cancellation/draining and native keyboard/VoiceOver behavior.

Historical foundation/candidate build and fixture evidence remains in [M-004](tasks/M-004-memory.md#validation-evidence). Current injected-model tests establish persistence/control flow; they do not establish real-model accuracy.

## M-005 input personalization

- [ ] With no personal Memory, cleanup removes meaningless speech redundancy and formats existing structure under [the approved contract](input-cleanup.md).
- [ ] Saved dictionary words supply useful Speech hints; same-word letter-case variants normalize to their saved spelling even with cleanup disabled. Full-/half-width spelling, other words and technical spans remain unchanged; no alias rules exist.
- [ ] Cover Chinese/English/mixed input, 嗯/好的/OK replies, meaningful repetitions, uncertainty/alternatives, clear self-corrections, questions, requests, steps and ordinary narrative. No changed viewpoint, summary, invented heading, answer, explanation, translation or unspoken background.
- [ ] Verify contextually unambiguous Chinese ASR corrections such as **尝试常文字效果 → 尝试长文字效果** and dictionary-assisted **试一试长蚊子 → 试一试长文字** occur, while ambiguous homophones remain unchanged. Corrections must follow whole-utterance meaning rather than a changed-character quota; confirm dictionary terms, names, numbers, negation, code and URLs remain protected.
- [ ] Preserve people/product names, numbers/dates, negation, conditions, technical commands/paths/URLs/versions and code. Judge actual Foundation Models output on supported hardware; Morie does not use a second mechanical language validator.
- [ ] Final text is saved before insertion; the target receives exactly that output. Original recognition, actual input, dictionary/Memory snapshots, changes, outcome and duration remain truthful.
- [ ] Speech retry preserves completed final output and its old processing evidence, including existing capture-only records. Capture-only completion still does not paste/copy or restore another app.
- [ ] Dictionary/Memory/source changes during inference invalidate stale results. Exercise unavailable/declined/oversized/slow models and save errors; unsaved AI text never reaches delivery.
- [ ] Refresh setup during refinement without interrupting normal completion. Separately exercise cancellation and resume recording: no late paste, overlapping optional models or stuck processing. Relaunch recovers saved Capture without replaying a paste; pending personal analysis may resume separately.
- [ ] Measure spelling-hint benefit, unintended edits, applied/skipped/failure rates, real model time and final-to-delivery latency with cleanup on/off across short and long input. There is no elapsed-time cutoff; verify explicit cancellation remains responsive and that model completion is not discarded solely for taking longer.
- [ ] Validate Settings persistence and native History/provenance/copy controls with keyboard, VoiceOver, long text and system appearance.

Earlier narrow-refinement evidence is retained in [M-005](tasks/M-005-personalization.md#validation-evidence); M-009 holds the current suite/build evidence. Device/model acceptance remains open.

## M-009 correction suggestions

This is an independent opt-in dictionary behavior, not personal-Memory approval. Use the normal signed app with disposable documents:

- [ ] Default-off setting starts no observation/prompt. Turning it on affects subsequent successfully dispatched current-app input only.
- [ ] Confirm exact insertion anchoring at the caret in current macOS native, browser and editor fields. Missing/unsupported range APIs cause a silent skip; no broad document fallback is used.
- [ ] Correct a word, including Chinese/mixed words, added/deleted letters and joined words. A suggestion waits for at least two seconds of settled text; undo/intermediate typing does not save a partial word.
- [ ] Pure append/delete of phrases, punctuation/numbers/code/URL edits and broad rewrites do not create word suggestions. Record false positives/negatives rather than assuming all edits are recognition corrections.
- [ ] The native panel appears without activating Morie or stealing text focus. Remember saves the correct spelling with **no automatic alias**. Not Now/expiry saves nothing; one word does not repeatedly prompt per process.
- [ ] Further edits, moving the selection outside the insertion, field/app changes, new input and disabling the setting stop observation/dismiss the suggestion. Exercise unrelated/concurrent edits elsewhere in the same document to check range inference.
- [ ] Secure input/password fields and excluded terminal/password-manager apps do not produce reads/prompts. Capture-only input and clipboard fallback never attach the watcher.
- [ ] Check the 30-second observation / 20-second prompt limits, save errors, longest supported words, keyboard/VoiceOver, fullscreen, multiple screens and system appearance.
- [ ] Inspect diagnostics/storage behavior: external field text is not logged, sent to AI or copied into Capture; only explicit Remember persists the spelling.

[OpenLess audit](reference/openless.md) records the behavior reference and native adaptation. Detector tests and offscreen rendering do not establish AX field semantics, no-focus-steal behavior or actual cross-app precision.

## M-008 unified macOS management UI

- [ ] Sidebar/list/detail and native toolbars are consistent across History, Dictionary, Personal Memory, Settings and Diagnostics at default/minimum sizes and resized columns.
- [ ] Keyboard selection, search, filters and deletion show the correct detail. Hidden selections clear and source navigation resets when selecting another record.
- [ ] Moving between History records stops playback/re-recognition without affecting another Capture. Background personal learning follows input-idle lifecycle, not page selection.
- [ ] Final text is primary; recognition/refinement/learning snapshots and recording destination/expiry/retry remain accessible. Long text scrolls/selects correctly.
- [ ] Dictionary editor accepts one word and validates duplicates/invalid input; Personal Memory editor handles personal information/lifecycle. Save/cancel/error/delete flows use native controls and system confirmations. No routine review inbox remains.
- [ ] Sidebar/menu/Command-comma Settings entries reuse one native Settings scene. Diagnostics supports filters, complete selected messages, resizing, copy-all, file reveal and confirmed clear.
- [ ] Verify empty/populated/error states, keyboard/VoiceOver, light/dark appearance, increased contrast, reduced motion and native glass/selection/toolbar rendering.

Earlier M-008 compilation/tests/layout fixtures are documented in [its task record](tasks/M-008-macos-management-ui.md#validation-evidence). Current M-009 fixtures cover the changed pages. Offscreen bitmap caching omits some native material/selection layers and cannot complete interactive acceptance.

## M-010 Chinese UI and native setup

These signed-app checks remain open; isolated logic/layout evidence does not establish permission or keyboard behavior.

- [ ] On first use, the native guide opens automatically without first opening Control Center and without any permission prompt. A fully configured launch stays menu-bar-only; a missing required capability or startup error reopens the guide.
- [ ] Review all five requirements together. Microphone/Speech consent occurs only after **授权**. Repeated clicks and returning from a native consent dialog do not produce duplicate requests.
- [ ] Complete Speech consent with Allow and Deny in an authorized disposable permission setup. The callback must not stop in `_dispatch_assert_queue_fail`; the request indicator clears, Allow refreshes the permission to **已授权**, and Deny keeps input blocked with **打开系统设置**. If the earlier crashing run already saved consent, relaunch/recheck must reflect it without another prompt.
- [ ] The native setup window shows its standard traffic-light controls without title text beside them. Unauthorized permission rows show the available action only; authorized rows show **已授权**. Restricted permissions retain an explanation. At default/minimum size, **稍后设置** stays at the far left and **重新检查 / 开始使用** at the right; verify Escape, Return, VoiceOver and waiting/refresh indicators.
- [ ] Denied access opens the corresponding native privacy pane. Accessibility opens its pane with Morie's signed identity registered. Returning updates status without a second Morie consent alert or a relaunch workaround.
- [ ] After allowing Microphone/Speech in the native dialog, the originating Morie window becomes key/front instead of remaining behind another window. After enabling access in an explicitly opened Privacy pane, the same originating window returns to the front and shows the refreshed state.
- [ ] One Morie click on Accessibility **授权** invokes native registration and opens the correct Settings pane with the signed Morie present in the list; a second Morie click must not be required. The required macOS confirmation may still appear. Closing/returning without granting stops the bounded wait and leaves the page usable.
- [ ] Restricted permissions, unsupported hardware/language and unready Apple Intelligence remain blocked with useful Chinese explanations. No required check can be skipped.
- [ ] **稍后设置** closes the guide without enabling recording; **打开 Morie** reopens it while setup is incomplete, and routine repair remains available on the Control Center Permissions page. Completing setup prepares Speech assets and enables input only after a fresh complete check. Test revocation during asset preparation with disposable permission state.
- [ ] During recording/startup/refinement, opening or refreshing setup leaves input intact and disables **开始使用**. Explicit failure/cancellation still preserves the existing Capture-first semantics.
- [ ] **⌘,** and sidebar **设置** open the embedded Control Center Settings page. The shortcut is app-scoped and does not replace the global recording shortcut or intercept another app's Settings command.
- [ ] The system sidebar toolbar/View command hides and restores navigation across library/Diagnostics switches. Native **资料库 / 应用** headers fold/unfold and remember their state.
- [ ] The menu-bar extra is a system menu. Its icon-free **打开 Morie** and **退出 Morie** actions, status and shortcut guidance work with pointer/keyboard and VoiceOver; it has no duplicate Settings or permanent setup destination.
- [ ] With English first in macOS language preferences, app-owned labels/status/errors/privacy text and dates are Chinese. User input, dictionary names, model prompts and technical diagnostic identifiers retain their content.
- [ ] At default/minimum sizes, scroll the setup and Settings Forms to the bottom. Long explanations, save/preparation errors and correction-word prompts remain readable and actionable; verify light/dark, native materials and VoiceOver in the actual windows.

2026-09-18: sampling the owner's paused process confirmed a background Speech authorization callback violating inherited main-actor isolation. The regression reproduces the same dispatch assertion before the explicit `@Sendable` fix; all **102 logic tests** and the isolated Debug build pass afterward, including the final title/status/footer changes. Background Allow/Deny and synchronous completion are covered without real TCC access. Eight offscreen native fixtures verify default/minimum layout, permission states, preparation/refresh feedback and footer placement. [M-010](tasks/M-010-macos-native-setup.md#validation-evidence) records the evidence; actual consent-dialog and keyboard acceptance above remain open.

Evidence and remaining limits are tracked in [M-010](tasks/M-010-macos-native-setup.md).

## M-011 single-word dictionary

- [ ] **字典 → 添加词语** opens a compact native sheet with only **词语**. The field has initial focus; Return adds the word and Escape cancels. Edit shows the same field and saves the changed word.
- [ ] Empty/whitespace input disables Add/Save. Duplicate words (including letter-case variants), invalid input and save failures show readable inline feedback without discarding edits or overwriting another word. Full-/half-width forms are not treated as equivalent.
- [ ] Add Chinese names, English product names and multiword technical terms. The Dictionary page packs short words across an adaptive native grid rather than one full-width row per word. Built-in/manual/correction-confirmed terms can appear together; built-ins are read-only and user terms remain editable. Relaunch preserves user terms; deletion removes their future Speech hints while saved input and personal Memory remain.
- [ ] Confirm manual entries and correction-confirmed entries retain distinct backend provenance after relaunch, while the small built-in baseline remains code-owned and does not create user records.
- [ ] Compare recognition with/without saved words and with the built-in baseline present. With **文字** saved, dictate **再来试一试长文字吧**; with **Codex** saved, reproduce Speech returning **Coldex** and confirm enabled cleanup receives **Codex** and can correct it from context. Finalized Chinese segments must not acquire Morie-inserted spaces such as **常 蚊 子**. With cleanup off, only letter-case variants of the same whole word normalize; full-/half-width spelling remains untouched. Dictionary context must not become an unconditional alias rule or change code/URLs.
- [ ] History's **本次使用的字典** shows the exact saved words used for refinement, even after later dictionary edits/deletion. Final text remains saved before insertion and Memory learning.
- [ ] Opt-in correction suggestions still offer **加入字典 / 暂不添加**, save one word and preserve typing focus. Validate keyboard, VoiceOver, long words/errors and native appearance in the signed app.

Isolated build, logic, separate-process storage and layout evidence is recorded in [M-011](tasks/M-011-simple-dictionary.md). Actual recognition benefit and interactive behavior remain deferred acceptance.

## Toggle-capture lifecycle

Verify repeated sequences:

1. place caret in target app;
2. press and release the configured shortcut once (solo `Fn / Globe` by default);
3. confirm recording begins once;
4. speak;
5. confirm that releasing the shortcut did not stop recording;
6. activate the configured shortcut again;
7. confirm capture stops/finalizes once;
8. verify Morie returns to Ready;
9. immediately repeat.

Also test:

- second press while Speech session setup is still starting — it must finish the same Capture without a late/orphaned recording;
- `Escape` while setup is still starting — it must cancel without a late/orphaned recording;
- rapid repeated toggles;
- long utterance;
- key autorepeat while physically held — each physical press toggles at most once;
- key-up events do not start, finish, or cancel capture;
- `Escape` is consumed only while recording and behaves normally otherwise;
- HUD cancel matches `Escape`; HUD confirm matches the second shortcut press;
- switch between apps and input fields while recording and while recognition/cleanup is still processing; delivery must follow the field that owns keyboard focus when final text is dispatched;
- close or leave the app where recording began; Morie must not reactivate it or treat that old window as a required target;
- Accessibility revocation after Morie has reached Ready;
- microphone interruption where practical;
- capture/transcription error followed by another successful attempt.

Record any stuck hotkey, duplicate start/stop, orphan microphone indicator, or event that leaks unexpectedly into the target application.

Safety invariant: a hotkey failure may disable Morie, but must never leave normal system keyboard input blocked. Recovery after a timeout is explicit through **使用引导与权限 → 重新检查 → 开始使用**.

## Session identity / stale result checks

Exercise timing-sensitive transitions deliberately:

- start → immediate finish → new start;
- start → immediate cancel → new start;
- start → error/cancel → immediate new start;
- finalize one utterance while rapidly beginning the next after Ready returns;
- repeat short sessions around Speech asset/session initialization.

Expected behavior:

- a previous session's partial/final callback never changes the visible transcript of a newer session;
- a cancelled setup never starts recording later;
- only the active session can finalize/deliver;
- every terminal path releases recording resources.

## Transcription

Test at least:

- English;
- Simplified Chinese where supported/configured;
- Chinese + English mixed sentence;
- common punctuation behavior;
- project/product names with and without dictionary Speech hints;
- quiet and normal office acoustic conditions.

Record whether partial/volatile text is sensible, whether finalization changes it materially, and whether the end of a short utterance is ever lost after the finish action.

## Capture HUD and Liquid Glass

Validate the HUD over light, dark, detailed, and full-screen backgrounds:

- the HUD renders as one continuous system Liquid Glass capsule that visibly samples the content behind its window, rather than an opaque black surface or three separate glass islands;
- the cancel, waveform, and finish grouping matches the approved compact reference hierarchy;
- the panel appears on the screen containing the pointer and near the bottom-center of its visible frame;
- it never activates itself, steals text focus, or replaces the original target application;
- cancel and finish buttons have correct pointer-down feedback, hit targets, tooltips, and accessibility labels;
- the waveform is present on the first frame, stays low at both edges and tallest in the middle, and changes its center with real microphone level without opening a second capture path;
- normal speech produces clearly visible changes; the Debug log reports a nonzero audio-channel count and changing average/peak/normalized meter values rather than a missing-channel or floor-pinned warning;
- processing, success, and failure states are distinguishable and do not block immediate subsequent input;
- successful delivery shows an animated, labelled “已输入” result rather than an isolated static checkmark;
- when there is no external current-focus destination or paste dispatch fails, the same HUD reports “已复制到剪贴板” and does not steal focus with a modal alert;
- Reduce Motion keeps stationary level feedback and avoids unnecessary panel animation;
- Reduce Transparency and Increase Contrast produce a legible system-controlled material;
- VoiceOver announces cancel, microphone input level, finish, processing, success, and failure meaningfully;
- light/dark appearance changes do not rely on a forced color scheme or hard-coded foreground/background colors.

## Menu bar shell

Verify that the menu-bar waveform icon remains visually stable through checking, ready, recording, processing, successful delivery, clipboard fallback, and recoverable failure. Runtime status should remain available in the HUD and menu text without making the persistent menu-bar item flicker between symbols.

## Delivery behavior

For every target app, validate:

- Morie does not activate or restore the app that was frontmost when recording began;
- the external app that is frontmost at delivery time receives the Cmd+V dispatch;
- insertion follows that app's current first responder / intended selection or caret;
- existing selected text replacement behaves predictably;
- multiline text works where appropriate;
- Chinese/English mixed text survives insertion;
- repeated captures do not steal focus or switch applications;
- undo behavior is acceptable;
- clipboard fallback does not overwrite a newer clipboard change;
- ordinary fallback restores the previous text-like clipboard value after delivery;
- if the clipboard was empty before successful delivery, Morie's temporary transcript is removed and the clipboard becomes empty again;
- clipboard-history tools that honor `org.nspasteboard.TransientType` (including the tested Raycast setup) do not retain Morie's temporary injection or automatic restoration entries;
- Morie's synthetic Cmd+V never triggers the toggle-capture shortcut path;
- no unexpected keystrokes are delivered to the target.

Do not add an app-specific workaround merely because an app fails once. Reproduce on macOS 27, record the exact failure here/M-002, then implement the smallest native fix.

## Compatibility matrix

Use the following as the first representative matrix. The purpose is to validate Morie's generic path across common native/web/electron/editor surfaces, not to create a permanent per-app compatibility subsystem.

| App | App/version | Current-focus routing | Paste delivery | Clipboard restore | Mixed text | Multiline | Repeat input | Undo | Result / notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Safari | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☐ | ☐ | One logged Fn capture completed; broader field/format coverage remains |
| Chrome | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| WeChat | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☑ | ☐ | Repeated short/normal captures plus ~85-second, 371-character capture completed |
| Slack | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Telegram | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Mail | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Notes | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☑ | ☐ | Two consecutive logged captures completed |
| Xcode | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☑ | ☐ | Two logged Fn captures completed; mixed text/multiline/undo remain |
| VS Code | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Cursor | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Terminal | current test build | ☑ | ☑ | ☑ | ☐ | ☐ | ☐ | ☐ | One logged Fn capture completed |
| Pages | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |
| Microsoft Word | TBD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | Not tested |

Morie intentionally validates one generic clipboard + synthetic paste delivery path. Do not add AX mutation or app-specific branches without a new evidence-backed decision.

## Shortcut conflict check

Solo `Fn / Globe` release is the approved default Phase 0 binding. Alternate combinations are available in native Settings.

On the validation Mac, record:

- configured Globe/Fn system action and input-source shortcuts;
- whether solo Fn release both toggles Morie and accidentally opens a system surface;
- whether Fn combined with another key passes through without toggling Morie;
- alternate shortcut selection, persistence across relaunch, and absence of unacceptable side effects;
- built-in and external-keyboard behavior.

If a conflict is material, record the exact macOS 27 behavior and use the approved alternate binding rather than building broad compatibility machinery.

## Reliability run

After individual app checks, perform repeated use rather than only one-shot tests.

Suggested initial baseline:

- at least 50 consecutive captures across several target apps;
- include rapid back-to-back captures, immediate finish, immediate cancel, and long captures;
- record any lost capture, stuck recording state, duplicate delivery, wrong current-focus target, unexpected app activation, orphan microphone session, or paste failure.

This reliability run remains required as Dictionary, cleanup and automatic Memory are integrated; model tests cannot replace it.

## Performance baseline

Record observations for the same tested build:

| Metric | Measurement | Environment / notes |
| --- | --- | --- |
| App bundle / executable size | 1,060,864-byte app bundle / 1,050,744-byte executable | Local unsigned arm64 Release build, Xcode 27 / macOS 27 SDK; establish signed-package size separately |
| Cold launch time | TBD | |
| Idle RSS | TBD | |
| Recording RSS | TBD | |
| RSS after 10 / 25 / 50 captures | TBD | Verify growth reaches a plateau rather than increasing roughly per capture |
| Memory Graph / Allocations | TBD | Check retained MemoryAnalysisRecord / CaptureRecord / LanguageModelSession counts after repeated use |
| Per-stage footprint log | TBD | Compare capture-start → speech-stop → refinement-finish → capture-complete → capture-settled and Memory-learning stages |
| Audio lifetime | TBD | Every completed/cancelled Capture should log CaptureAudioSource and CaptureAudioStream release; investigate any missing pair |
| ASR final latency | TBD | finish action → final transcript |
| Final → delivery latency | TBD | final transcript → inserted text |
| CPU / Energy Impact | TBD | Activity Monitor / Instruments as appropriate |
| Capture loss rate | TBD | from reliability run |

The first goal is a trustworthy baseline. Numeric regression budgets can be established after real measurements exist.

## Completion record

When validation is complete, update:

- this matrix;
- [`tasks/M-002-macos-input-foundation.md`](./tasks/M-002-macos-input-foundation.md) with evidence and remaining issues;
- [`tasks.md`](./tasks.md) task state;
- the current task branch/PR with the tested environment and results (PR #3 remains the merged implementation-baseline reference).

Do not replace device/runtime evidence with assumptions, Type4Me history, or compile success.
