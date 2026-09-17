# M-002 — macOS Input Foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-17
- **GitHub Issue:** https://github.com/6spot/Morie/issues/2
- **Pull Request:** https://github.com/6spot/Morie/pull/3
- **Branch:** `phase0/input-foundation`

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
- focused global hold-to-talk shortcut;
- authoritative recording-session lifecycle;
- latest Apple Speech stack;
- original target-app capture and focus restoration;
- Accessibility text delivery;
- safe clipboard + paste fallback;
- cancellation/error/stale-result cleanup;
- macOS 27 compile CI;
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
2. Holding the selected global shortcut starts intentional voice capture and releasing it finalizes the same session reliably, including repeated use.
3. Releasing while Speech setup is still in flight cannot create a late/orphaned microphone session.
4. The modern Apple Speech stack produces live/partial and final output without a legacy recognition fallback.
5. Stale results from an earlier session cannot mutate a newer session.
6. Morie remembers the app active before capture, restores it, and delivers final text where supported.
7. Delivery fallback preserves the user's transcript and does not overwrite newer clipboard content.
8. Cancel/error/interruption paths release capture resources and leave Morie recoverable.
9. Relevant Type4Me behavior is classified `ADAPT`, `DROP`, or `VERIFY` only after the Morie/macOS 27 requirement is defined.
10. All Phase 0 UI is Apple-native macOS 27 UI; any native-UI gap requires owner approval before a substitute is implemented.
11. The project compiles against the macOS 27 SDK with Swift 6 strict concurrency.
12. The real-app validation matrix and initial performance observations are recorded before M-002 is DONE.
13. No external product dependency is introduced without explicit project-owner approval; expected Phase 0 product dependency count is zero.

## Subtasks / progress

| Subtask | Status | Notes |
| --- | --- | --- |
| Native macOS project | DONE | `Morie.xcodeproj`, macOS 27.0 deployment target, Swift 6. |
| Repository docs / task system | DONE | `AGENTS.md`, master/detail tasks, architecture/dev/deploy/validation docs. |
| Full owner design baseline | DONE | Preserved under `docs/design/`. |
| Native UI / Liquid Glass policy | DONE | Native system controls are a hard gate. |
| Type4Me migration boundary | DONE | Morie-first, extractive per-subsystem migration documented. |
| Type4Me hotkey audit | DONE | Retained hold/release ownership, repeat suppression, reset/failure lessons; dropped generalized hotkey features. |
| Type4Me audio/session audit | DONE | Retained session identity/stale-result/cleanup principles; dropped external-ASR audio architecture. |
| Type4Me injection/focus audit | DONE | Retained no-loss/clipboard/synthetic-event lessons; app-specific branches remain VERIFY-only. |
| Type4Me Apple Speech audit | DONE | Used only as behavioral reference; implementation follows current Apple Speech APIs. |
| Menu Bar shell | IN PROGRESS | Native `MenuBarExtra`; real macOS 27 visual/interaction validation still required. |
| Foundation Models capability check | DONE | `SystemLanguageModel` availability + locale. |
| Speech capability/locale check | DONE | `SpeechTranscriber` availability + locale. |
| Microphone/Speech authorization | DONE | Native permission checks. |
| Accessibility trust check | DONE | Native Accessibility trust/prompt path. |
| iCloud/CloudKit capability check | DEFERRED | M-003 owns the real container/entitlements and Private Mode persistence gate. |
| Global hold-to-talk hotkey | IMPLEMENTED / VERIFY | Minimal session-level `CGEventTap`; real-device hold/release/permission-revocation validation remains. |
| Reliable recording/session layer | IMPLEMENTED / VERIFY | Unique session IDs, setup cancellation, stale-result rejection, deterministic terminal cleanup. |
| Modern Apple Speech pipeline | IMPLEMENTED / VERIFY | `SpeechAnalyzer` + `SpeechTranscriber` + `CaptureInputSequenceProvider`; runtime finalization still needs device proof. |
| Original-app capture/focus restore | IMPLEMENTED / VERIFY | Target captured before recording; timing requires target-app validation. |
| Text injection / clipboard fallback | IMPLEMENTED / VERIFY | AX first, synthetic Cmd+V fallback, change-count-aware restore, no app-specific compatibility branch. |
| Cancellation/stale-result hardening | IMPLEMENTED / VERIFY | Early release cancels in-flight setup; per-session identity protects new sessions. |
| macOS 27 / Xcode 27 compile | DONE | GitHub hosted `xcode-27`: macOS 27.0, Xcode 27.0, macOS 27 SDK; build passed at `66d7bbf8`. |
| Compatibility matrix | TODO | Real app/device validation in `../validation.md`. |
| Performance baseline | TODO | Measure after runtime loop is proven on supported hardware. |

`IMPLEMENTED / VERIFY` means the implementation exists and compiles, but the acceptance criterion is intentionally not marked DONE until actual macOS 27 runtime/device behavior is observed.

## Implemented design

### 1. Push-to-talk hotkey

`PushToTalkHotkey` is now deliberately small rather than a Type4Me-style generalized subsystem.

Current behavior:

- session-level `CGEventTap`;
- one current V0 shortcut: `Control + Space`;
- exact modifier match;
- autorepeat suppression;
- one explicit active hold;
- release belongs to the active hold even if Control is released before Space;
- matched shortcut events are consumed;
- Morie-generated synthetic delivery events are ignored;
- tap-disabled events attempt native re-enable;
- loss of Accessibility trust blocks the input path rather than silently degrading.

Intentionally not present:

- media keys;
- mouse buttons;
- modifier-prefix gesture machinery;
- multiple modes/bindings;
- compatibility paths for older macOS releases;
- Type4Me's generalized hotkey watchdog/state infrastructure.

Current classification: **ADAPT + DROP**.

### 2. Authoritative capture identity

`AppController` and `SpeechPipeline` now share a UUID session identity for each intentional hold.

This closes an important race in the initial scaffold: previously, key release could call `stop()` while async Speech setup was still awaiting. That could yield `notRunning` while the setup task later continued and created an orphaned microphone session.

Current rule:

- press creates the authoritative session ID immediately;
- Speech setup belongs to that ID;
- release before setup completion cancels setup;
- release after setup completion finalizes that ID;
- transcript callbacks carry the ID;
- callbacks/results whose ID is no longer active are ignored;
- cancel/error/success all clear the same identity.

No generalized session framework was introduced.

### 3. Speech asset readiness

Speech asset preparation occurs during bootstrap, before the global shortcut is installed and before Morie enters Ready.

A model-asset download must not begin after the user has already started an intentional push-to-talk hold.

The current Speech path uses:

- `SpeechTranscriber(locale:preset:.progressiveTranscription)`;
- `AssetInventory`;
- `CaptureInputSequenceProvider`;
- `SpeechAnalyzer`.

There is no legacy recognition fallback.

### 4. Speech stop vs cancel

Normal release and cancellation are different lifecycle events.

Normal release:

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
3. try bounded Accessibility selected-text replacement;
4. fall back to synthetic Cmd+V;
5. tag Morie's generated events so the hotkey layer ignores them;
6. restore the old clipboard only if `changeCount` proves nobody changed it after Morie's temporary write.

There is currently **no Electron/app-family branch**. Any app-specific delay or workaround requires a reproduced macOS 27 validation case first.

### 6. Capability gate

Phase 0 currently checks:

- Apple Intelligence / `SystemLanguageModel` availability and locale;
- modern Speech availability and locale;
- microphone permission;
- Speech authorization;
- Accessibility trust.

The Swift 6 build exposed that `kAXTrustedCheckOptionPrompt` comes through the C framework without concurrency annotations. The native ApplicationServices import is explicitly bridged with `@preconcurrency`; no replacement permission framework or dependency was introduced.

The UI now says it is checking device capabilities rather than claiming that full Private Mode is available. iCloud/CloudKit remains M-003 work.

## Compile validation

A repository workflow now compiles product code on GitHub's macOS 27 hosted image using:

- macOS 27.0;
- Xcode 27.0;
- macOS 27 SDK;
- Swift 6 project settings;
- code signing disabled for CI compilation.

The first run exposed the ApplicationServices strict-concurrency issue above. After the native bridge fix, build `66d7bbf8` completed successfully.

The workflow is scoped to product/Xcode/workflow changes so documentation-only commits do not create redundant compile runs.

This is compile evidence only. CI cannot prove microphone routing, TCC permission UI, global keyboard behavior, focus restoration, target-app insertion, Liquid Glass appearance, or latency on the user's real Mac.

## Type4Me audit result

### Hotkey — ADAPT / DROP

ADAPT:

- repeat suppression;
- explicit hold ownership;
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
- Morie-first Type4Me extraction boundaries are documented.

Still required on a supported real Mac:

- first-launch permission lifecycle;
- Apple Intelligence/Speech asset runtime behavior;
- actual `Control + Space` hold/release semantics across apps and keyboard input sources;
- rapid/short/repeated hold behavior;
- microphone/session cleanup after failure/cancel;
- volatile/final transcript behavior under real speech;
- focus restoration;
- AX insertion and clipboard fallback matrix;
- clipboard restore timing;
- native Liquid Glass appearance/interaction;
- performance and energy measurements.

These items keep M-002 **IN PROGRESS** and PR #3 **Draft**.

## Known risks / decisions still open

- `Control + Space` is the current implementation shortcut, not a permanent product decision; macOS input-source conflicts must be evaluated in real use before freezing the default.
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
