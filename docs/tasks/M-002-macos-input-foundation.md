# M-002 — macOS Input Foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-17
- **GitHub Issue:** https://github.com/6spot/Morie/issues/2
- **Pull Request:** https://github.com/6spot/Morie/pull/3
- **Merged baseline:** `main` at `2cda9a3`; continue implementation on task branches

## Why

Morie's first product dependency is a reliable macOS voice-input loop. Recording, transcription, session finalization, focus restoration, and text delivery must be dependable before persistence and Personal Memory have a stable product surface to improve.

M-002 is not a Type4Me port. It starts from Morie's design and macOS 27 architecture, then uses Type4Me only as evidence for failure modes worth retaining.

Mandatory order:

`Morie design → Morie architecture → M-002 requirement → current macOS 27 Apple API → Type4Me reference → smallest Morie-native implementation`

### Approved migration mode

M-002 uses **extractive migration by subsystem**:

`Morie requirement → inspect matching Type4Me code/tests → ADAPT / DROP / VERIFY → smallest macOS 27-native implementation`

Do not copy Type4Me wholesale and trim it afterward. Direct source transfer is exceptional; the normal path is to reimplement the small retained behavior against current Apple APIs. The optimization target is completing Morie, not maximizing Type4Me code reuse.

## Scope

Included:

- macOS 27+ only;
- Apple Intelligence-capable Macs;
- native Swift / SwiftUI / AppKit;
- native macOS 27 system UI / Liquid Glass behavior;
- focused global toggle-capture shortcut;
- authoritative recording-session lifecycle;
- latest Apple Speech stack;
- original target-app capture and focus restoration;
- Accessibility text delivery;
- safe clipboard + paste fallback;
- cancellation/error/stale-result cleanup;
- native in-app runtime diagnostics for Phase 0 validation;
- macOS 27 compile CI and test-package artifact;
- real-device compatibility validation;
- initial performance baseline.

Explicitly excluded:

- support for macOS older than 27;
- old Speech recognition fallback;
- Type4Me media-key/mouse/multi-mode hotkey machinery;
- Type4Me provider/runtime architecture;
- unapproved third-party runtime/model/UI dependencies;
- iOS;
- Morie Cloud;
- durable Capture/History persistence;
- Personal Memory;
- MCP/Public API/Relay.

## Acceptance criteria

1. A supported Mac enters Ready only when the capabilities owned by this phase are available.
2. The first shortcut press starts intentional voice capture, releasing it leaves capture active, and a second press reliably finalizes the same session; `Escape` cancels only while recording.
3. Finishing or cancelling while Speech setup is still in flight cannot create a late/orphaned microphone session.
4. The modern Apple Speech stack produces live/partial and final output without a legacy recognition fallback.
5. Stale results from an earlier session cannot mutate a newer session.
6. Morie remembers the app active before capture, restores it, and delivers final text where supported.
7. Delivery fallback preserves the user's transcript and does not overwrite newer clipboard content.
8. Cancel/error/interruption paths release capture resources and leave Morie recoverable.
9. Relevant Type4Me behavior is classified `ADAPT`, `DROP`, or `VERIFY` only after the Morie/macOS 27 requirement is defined.
10. All Phase 0 UI is Apple-native macOS 27 UI; any native-UI gap requires owner approval before a substitute is implemented.
11. The project compiles against the macOS 27 SDK with Swift 6 strict concurrency.
12. Runtime diagnostics distinguish capability, hotkey, Speech/session, focus/injection, and clipboard paths without recording full transcript content by default.
13. The real-app validation matrix and initial performance observations are recorded before M-002 is DONE.
14. No external product dependency is introduced without explicit project-owner approval; expected Phase 0 product dependency count is zero.

## Subtasks / progress

| Subtask | Status | Notes |
| --- | --- | --- |
| Native macOS project | DONE | `Morie.xcodeproj`, macOS 27.0 deployment target, Swift 6. |
| Repository docs / task system | DONE | `AGENTS.md`, master/detail tasks, architecture/dev/deploy/validation docs. |
| Full owner design baseline | DONE | Preserved under `docs/design/`. |
| Native UI / Liquid Glass policy | DONE | Native system controls are a hard gate. |
| Type4Me migration boundary | DONE | Morie-first, extractive per-subsystem migration documented. |
| Type4Me hotkey audit | DONE | Retained physical-press ownership, repeat suppression, reset/failure lessons; dropped generalized hotkey features. |
| Type4Me audio/session audit | DONE | Retained session identity/stale-result/cleanup principles; dropped external-ASR audio architecture. |
| Type4Me injection/focus audit | DONE | Retained no-loss/clipboard/synthetic-event lessons; app-specific branches remain VERIFY-only. |
| Type4Me Apple Speech audit | DONE | Used only as behavioral reference; implementation follows current Apple Speech APIs. |
| Menu Bar shell | IN PROGRESS | Native `MenuBarExtra` with a stable waveform entry icon; runtime state remains in the HUD and textual menu content instead of changing the persistent system-bar icon. Real macOS 27 visual/interaction validation still required. |
| Native Diagnostics surface | DONE / VERIFY | Native `List` within the Morie management window; Copy All/Clear/Show Log File; traces capability/hotkey/session/Speech/delivery paths and mirrors the current launch to `~/Library/Logs/Morie/morie-debug.log` without transcript content. Real-device log usefulness is being validated. |
| Foundation Models capability check | DONE | `SystemLanguageModel` availability + locale. |
| Speech capability/locale check | DONE | `SpeechTranscriber` availability + locale. |
| Microphone/Speech authorization | DONE / VERIFY | Native first-request prompts plus persistent menu/alert System Settings recovery after denial; microphone revoke/re-enable/recheck needs another real-device pass. |
| Accessibility trust check | DONE | Native trust prompt/check plus direct System Settings recovery; user manually enables Morie, then rechecks. |
| iCloud/CloudKit capability check | DEFERRED | M-003 owns the real container/entitlements and Private Mode persistence gate. |
| Global toggle-capture hotkey | IMPLEMENTED / VERIFY | Owner-approved default is solo `Fn / Globe` release: first release starts, second finishes, Fn chords do not trigger, and `Escape` cancels. A timed-out event tap now fails open and is released instead of entering an automatic re-enable loop that can block keyboard input. Native Settings provides alternate combinations; real-device timeout recovery and Fn/system-conflict validation remain. |
| Reliable recording/session layer | IMPLEMENTED / VERIFY | Unique session IDs, setup cancellation, stale-result rejection, deterministic terminal cleanup. |
| Modern Apple Speech pipeline | IMPLEMENTED / VERIFY | `SpeechAnalyzer` + `SpeechTranscriber` + `CaptureInputSequenceProvider`; runtime finalization still needs device proof. |
| Original-app capture/focus restore | IMPLEMENTED / VERIFY | App and original on-screen window identity are captured before recording; a closed original window now blocks false-success paste and preserves the transcript on the ordinary clipboard. Remaining timing/alternate-window behavior requires validation. |
| Text injection / clipboard fallback | IMPLEMENTED / VERIFY | Universal synthetic Cmd+V delivery, change-count-aware restore (including an originally empty clipboard), and transient markers for Raycast/clipboard-history exclusion; no app-specific compatibility branch. |
| Cancellation/stale-result hardening | IMPLEMENTED / VERIFY | Finish/cancel during in-flight setup stays bound to its session; per-session identity protects new sessions. |
| Liquid Glass capture HUD | IMPLEMENTED / VERIFY | One native `NSGlassEffectView` capsule in the non-activating panel, system buttons, and a Type4Me-informed live waveform. The HUD uses quiet-speech-sensitive mapping, real-signal transient emphasis, 60 Hz metering/rendering, and asymmetric per-bar history. Edge bars remain active while the center keeps the largest travel. Successful delivery now uses animated, labelled feedback; recoverable delivery failure reports “已复制到剪贴板” in the HUD instead of opening a modal alert. Visual response/accessibility validation remains. |
| macOS 27 / Xcode 27 compile | DONE | GitHub hosted `xcode-27`: diagnostics build/package passed at `ec888bd4`. |
| Compatibility matrix | TODO | Real app/device validation in `../validation.md`. |
| Performance baseline | IN PROGRESS | Local unsigned arm64 Release bundle/executable size recorded; cold launch, RSS, final/delivery latency, CPU/energy and capture-loss measurements still require real runtime observation. |

`IMPLEMENTED / VERIFY` means the implementation exists and compiles, but the acceptance criterion is intentionally not marked DONE until actual macOS 27 runtime/device behavior is observed.

## Implemented design

### 1. Toggle-capture hotkey

`PushToTalkHotkey` is now deliberately small rather than a Type4Me-style generalized subsystem.

Current behavior:

- session-level `CGEventTap`;
- one active persisted V0 shortcut, defaulting to solo `Fn / Globe` release, with a small native set of alternate keyboard combinations;
- exact modifier match;
- autorepeat suppression;
- one action per physical press;
- key release only resets press ownership;
- first press starts, second press finishes, and `Escape` cancels an active recording;
- matched shortcut events are consumed;
- Morie-generated synthetic delivery events are ignored;
- Accessibility loss in the event path immediately releases the tap and passes the current event through;
- tap-disabled/timeout events release the tap and block Morie until an explicit capability recheck, protecting system-wide keyboard availability.

Intentionally not present:

- media keys;
- mouse buttons;
- modifier-prefix gesture machinery;
- multiple modes/bindings;
- compatibility paths for older macOS releases;
- Type4Me's generalized hotkey watchdog/state infrastructure.

Current classification: **ADAPT + DROP**.

### 2. Authoritative capture identity

`AppController` and `SpeechPipeline` share a UUID session identity for each intentional toggle capture.

Current rule:

- press creates the authoritative session ID immediately;
- Speech setup belongs to that ID;
- finish before setup completion remains pending for that ID and finalizes it as soon as setup is ready;
- cancel before setup completion cancels that ID and cannot start a late session;
- transcript callbacks carry the ID;
- callbacks/results whose ID is no longer active are ignored;
- cancel/error/success all clear the same identity.

This prevents finish/cancel-during-setup races from later creating an orphaned microphone session. No generalized session framework was introduced.

### 3. Speech asset readiness

Speech asset preparation occurs during bootstrap, before the global shortcut is installed and before Morie enters Ready.

A model-asset download must not begin after the user has already started an intentional capture.

The current Speech path uses:

- `SpeechTranscriber(locale:preset:.progressiveTranscription)`;
- `AssetInventory`;
- `CaptureInputSequenceProvider`;
- `SpeechAnalyzer`.

There is no legacy recognition fallback.

### 4. Speech finish vs cancel

Finish and cancellation are different lifecycle events.

Finish:

1. stop microphone capture;
2. release the provider so the analyzer input sequence can end;
3. await consumed audio/sample time;
4. finalize analysis through that point;
5. await transcriber result completion;
6. return accumulated text;
7. reset the session.

Cancellation:

1. stop capture;
2. cancel analysis/result tasks;
3. `cancelAndFinishNow()`;
4. reset the matching session.

The latest volatile segment is retained when producing Morie's final string because the current Speech result contract does not guarantee that every volatile result is emitted again as a final result.

### 5. Text delivery

Delivery remains generic and evidence-driven:

1. reject missing/terminated/self target and preserve transcript on clipboard;
2. restore the original app;
3. snapshot safe text-like clipboard representations;
4. write the transcript and send synthetic Cmd+V;
5. tag Morie's generated events so the hotkey layer ignores them;
6. restore the old clipboard only if `changeCount` proves nobody changed it after Morie's temporary write.

There is currently **no Electron/app-family branch**. Any app-specific delay or workaround requires a reproduced macOS 27 validation case first.

### 6. Capability gate

Phase 0 checks:

- Apple Intelligence / `SystemLanguageModel` availability and locale;
- modern Speech availability and locale;
- microphone permission;
- Speech authorization;
- Accessibility trust.

Launch bootstrap now begins from `AppController.init`, not from opening the menu-bar panel, so capability detection and hotkey installation cannot remain dormant just because the user has not clicked the menu extra.

Apple Intelligence failure reasons are surfaced explicitly for device ineligibility, Apple Intelligence disabled, model not ready, locale unsupported, and other unavailable states.

The Swift 6 build exposed that `kAXTrustedCheckOptionPrompt` comes through the C framework without concurrency annotations. The native ApplicationServices import is explicitly bridged with `@preconcurrency`; no replacement permission framework or dependency was introduced.

### 7. Native runtime diagnostics

Real-device testing exposed that a silent shortcut failure is not diagnosable from the menu-bar status alone. M-002 now includes a native `Morie Debug` window.

Implementation:

- native SwiftUI `Window`;
- native `List` for in-memory entries;
- system **Copy All** and **Clear** buttons;
- maximum 1,000 entries per process lifetime;
- no third-party logging/UI dependency;
- no full transcript content logged by default.

Tracked categories include:

- `App` — bootstrap and Ready/blocked transitions;
- `Capability` / `Permission` — Apple Intelligence, Speech, microphone, Speech authorization, Accessibility;
- `Hotkey` — event-tap install, accepted keyDown/keyUp, repeats, modifier mismatch, tap disable/fail-open release;
- `Session` — capture IDs, target app/bundle, cancellation/completion;
- `Speech` — assets, microphone/provider/analyzer lifecycle, result lengths, finalization/cancel;
- `Delivery` — target activation, AX write, clipboard fallback, synthetic Cmd+V;
- `Clipboard` — temporary write and change-count-aware restore;
- `UI` — native failure alerts.

This diagnostic surface is explicitly a developer/runtime-validation aid. It does not replace user-facing product feedback design.

File output is serialized on a dedicated background queue. The hotkey/UI path does not synchronously flush every Speech update to disk; the earlier synchronous per-entry flush contributed to real-device event-tap timeouts after idle microphone wake-up.

## Compile / package validation

A repository workflow compiles and packages product code on GitHub's macOS 27 hosted image using:

- macOS 27.0;
- Xcode 27.0;
- macOS 27 SDK;
- Swift 6 project settings;
- Release test build with ad-hoc signing;
- `codesign` verification;
- zipped GitHub Actions artifact.

The diagnostics build containing the native Debug window and cross-layer instrumentation passed Xcode 27 build/sign/package at commit `ec888bd4`.

This is compile/package evidence only. CI cannot prove microphone routing, TCC permission UI, physical global keyboard behavior, focus restoration, target-app insertion, Liquid Glass appearance, or latency on the user's real Mac.

## Type4Me audit result

### Hotkey — ADAPT / DROP

ADAPT:

- repeat suppression;
- explicit physical-press ownership;
- deterministic reset/failure semantics;
- synthetic-event exclusion;
- session-level event-tap reliability concept.

DROP:

- media/mouse input;
- arbitrary modifier-only combos;
- multiple mode switching;
- old-platform compatibility machinery;
- unrelated watchdog/state complexity.

### Audio / session — ADAPT / VERIFY

ADAPT:

- one active session identity;
- stale async result protection;
- cleanup on every terminal path;
- recoverability after failure.

VERIFY before adding:

- device/route-specific behavior;
- Bluetooth workarounds;
- custom PCM conversion;
- warmup/retry paths.

### Injection / focus — ADAPT / VERIFY

ADAPT:

- self-target avoidance;
- preserve undelivered transcript;
- synthetic-event identity;
- bounded AX calls;
- change-count-aware clipboard restore.

VERIFY before adding:

- per-app timing;
- Electron-specific behavior;
- application-specific injection engines.

### Multi-provider/runtime and old-platform compatibility — DROP

M-002 does not inherit provider registries, cloud ASR, SenseVoice/sherpa-onnx, Python/MLX, alternate runtimes, media/mouse hotkeys, or earlier-macOS paths.

## Validation performed

Verified:

- deployment target is macOS 27.0;
- current Phase 0 files are connected to the Xcode target;
- no external Swift/package product dependency is present;
- the project compiles with Xcode 27 / macOS 27 SDK and Swift 6;
- current `SpeechAnalyzer`/`SpeechTranscriber`/capture-input API usage compiles against that SDK;
- current `CGEventTap` implementation compiles against that SDK;
- native debug window/instrumentation compiles and packages against that SDK;
- Morie-first Type4Me extraction boundaries are documented.
- local clean Debug and Release builds passed against the macOS 27 SDK after the event-tap fail-open and background diagnostics changes; the obsolete `activateIgnoringOtherApps` option was removed in favor of the current native activation call.
- real-device solo Fn toggle produced 16 accepted releases forming exactly 8 start/finish pairs with no duplicate trigger, failure, or orphaned session in the captured run;
- all 8 logged captures completed Speech finalization, target activation, synthetic paste delivery, and change-count-safe clipboard restoration;
- the same run successfully delivered to WeChat, Safari, QQ, Xcode, and Otty, including repeated captures in Xcode and Otty;
- Chinese `zh-CN` progressive/final transcription and the native HUD/audio meter operated throughout the run.
- subsequent real-device testing verified Fn chord rejection for a regular key and Shift, with candidate-cancel/pass-through diagnostics and no Capture start;
- rapid empty captures terminated cleanly without injection, two Escape cancellations released/reset Speech, and repeated short captures remained recoverable;
- native Settings switched live between Control+Space and Fn and reinstalled the matching event tap;
- Terminal and Notes delivery succeeded, WeChat sustained repeated delivery, and an approximately 85-second/371-character capture completed successfully with clipboard restoration.

Still required on a supported real Mac:

- first-launch permission lifecycle;
- Apple Intelligence/Speech asset runtime behavior;
- Fn chord rejection, system Globe/Fn conflict observation, alternate-binding persistence, and external keyboards (solo Fn start/finish is now evidenced on the built-in keyboard);
- use Debug log to identify the current observed no-response shortcut path;
- additional interruption/failure recovery beyond the verified rapid/short/repeated toggle and Escape paths;
- microphone/session cleanup after failure/cancel;
- volatile/final transcript edge cases such as immediate finish and end-of-short-utterance retention;
- remaining focus restoration and universal clipboard/paste delivery matrix applications/fields;
- clipboard replacement race where another app/user changes it during Morie's restore window;
- native Liquid Glass appearance/interaction;
- Reduce Motion, Reduce Transparency, Increase Contrast, VoiceOver, and keyboard-control behavior for the capture HUD;
- performance and energy measurements.

These items keep M-002 **IN PROGRESS** even though the initial Phase 0 implementation baseline has merged to `main`.

## Known risks / decisions still open

- solo `Fn / Globe` release is the owner-approved default; macOS system-action conflicts and external-keyboard behavior must be evaluated in real use, with alternate bindings retained in Settings.
- a 2026-09-17 Xcode test run later produced capture sessions pinned at `-758.6 dB` and empty transcripts after the repository build directory had also been overwritten by unsigned command-line builds. The owner approved deferring this case unless it reproduces from a clean, Xcode-signed run. Automated agent builds must use isolated temporary DerivedData and must not overwrite the locally running Xcode product.
- Hosted compile validation is not a substitute for TCC/Accessibility/microphone and cross-app behavior on real hardware.
- Do not add a compatibility branch merely because Type4Me has one. Reproduce on macOS 27 first.
- Do not add custom/faux Liquid Glass UI if a native system component exists.

## Follow-up

After M-002 runtime validation is stable, M-003 introduces the Capture-first reliability boundary:

- durable local Capture storage;
- History;
- App Context persistence;
- CloudKit/iCloud container and sync;
- iCloud capability gate.

Memory extraction/personalization remains later work.

## References

- Full design baseline: [`../design/apple-native-first-v0-baseline-v2.md`](../design/apple-native-first-v0-baseline-v2.md)
- Architecture: [`../architecture.md`](../architecture.md)
- Native UI rules: [`../ui-design.md`](../ui-design.md)
- Type4Me reference: [`../reference/type4me.md`](../reference/type4me.md)
- Validation matrix: [`../validation.md`](../validation.md)
- Development guide: [`../development.md`](../development.md)
- Issue #2: https://github.com/6spot/Morie/issues/2
- Draft PR #3: https://github.com/6spot/Morie/pull/3
