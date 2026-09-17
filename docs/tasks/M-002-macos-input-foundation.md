# M-002 — macOS Input Foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-17
- **GitHub Issue:** https://github.com/6spot/Morie/issues/2
- **Pull Request:** https://github.com/6spot/Morie/pull/3
- **Branch:** `phase0/input-foundation`

## Why

Morie's first product dependency is not Memory or cloud infrastructure. It is a reliable macOS voice-input loop. If recording, transcription, focus restoration, and text delivery are not dependable in everyday apps, later Personal Memory work has no stable product surface to improve.

This is **not a greenfield voice-input implementation**. Type4Me already contains mature input infrastructure and real-world edge-case handling. M-002 must audit and selectively reuse/adapt that proven behavior while modernizing the actual recognition/UI path for macOS 27.

## Scope

Included:

- macOS 27+ only;
- Apple Intelligence-capable Macs;
- native Swift / SwiftUI / AppKit;
- native macOS 27 system UI and Liquid Glass behavior;
- Type4Me reference audit and selective input-foundation migration;
- Private Mode capability checks relevant to Phase 0;
- menu bar application shell;
- global hold-to-talk shortcut;
- reliable recording/session lifecycle;
- latest Apple Speech transcription stack;
- capture of the original frontmost application/input target;
- focus restoration;
- Accessibility/text delivery;
- clipboard + paste fallback;
- failure/resource cleanup;
- real-device target-app compatibility validation;
- initial performance baseline.

Explicitly excluded:

- iOS;
- Morie Cloud;
- provider abstraction;
- legacy ASR recognition fallback;
- unapproved third-party runtime/model/UI library/dependency;
- Type4Me's multi-provider and Python/sherpa-onnx runtime architecture;
- durable Capture storage and History;
- Personal Memory;
- MCP/Public API/Relay.

## Acceptance criteria

1. On a supported Mac, Morie enters Ready only when required Private Mode capabilities for the current phase are available.
2. Holding the global shortcut starts intentional voice capture and releasing it finalizes the session reliably, including repeated/edge-case use.
3. The modern Apple Speech stack produces partial/final transcription without a legacy recognition fallback.
4. Morie remembers the app/input context active before capture, restores it, and delivers final text reliably where supported.
5. Delivery fallback preserves the user's result and does not corrupt a newer clipboard change.
6. Cancel/error/interruption/stale-result paths release capture resources and leave the app recoverable.
7. Relevant Type4Me behavior has been reviewed and explicitly classified `ADOPT`, `ADAPT`, or `DROP` with rationale.
8. All user-visible Phase 0 UI uses Apple native macOS 27 components/Liquid Glass behavior. Any native-UI gap requires owner approval before a substitute is implemented.
9. The compatibility matrix is tested on real target applications.
10. Initial binary/startup/memory/latency/energy observations are recorded.
11. No external dependency is introduced without explicit project-owner approval; expected Phase 0 external dependency count is zero.

## Subtasks / progress

| Subtask | Status | Notes |
| --- | --- | --- |
| Native macOS project | DONE | `Morie.xcodeproj`, deployment target macOS 27.0. |
| Repository docs / task system | DONE | `AGENTS.md`, master/detail tasks, architecture/dev/deploy/validation docs established. |
| Full owner design baseline in repo | DONE | Repository transcription under `docs/design/`. |
| Native UI / Liquid Glass policy | DONE | Hard rule documented; system components required. |
| Type4Me reference boundary | DONE | `docs/reference/type4me.md` establishes migration rules. |
| Type4Me hotkey audit | IN PROGRESS | `HotkeyManager.swift` + state-machine tests identified; current Morie hotkey is only a scaffold until reconciled. |
| Type4Me audio/session audit | IN PROGRESS | `AudioCaptureEngine.swift` / `RecognitionSession.swift` identified; lifecycle/cleanup behavior must be carried forward where relevant. |
| Type4Me injection/focus audit | IN PROGRESS | `TextInjectionEngine.swift` identified; synthetic-event and clipboard restore behavior must be reconciled. |
| Type4Me Apple Speech audit | TODO | Compare old/reference behavior to current macOS 27 Speech APIs and retain only relevant lifecycle lessons. |
| Menu Bar shell | IN PROGRESS | Uses native SwiftUI `MenuBarExtra`; real macOS 27 appearance/interaction validation pending. |
| Foundation Models capability check | DONE | `SystemLanguageModel.default.availability` and locale check. |
| Speech capability/locale check | DONE | `SpeechTranscriber` availability and supported locale. |
| Microphone/Speech authorization | DONE | Permission checks implemented. |
| Accessibility trust check | DONE | Required for global interaction/text delivery. |
| iCloud/CloudKit capability check | DEFERRED | Belongs with the real CloudKit container/entitlements in M-003; do not fake it in Phase 0. |
| Global hold-to-talk hotkey | IN PROGRESS | Initial Control+Space scaffold exists; must be replaced/hardened using Type4Me state-machine lessons. |
| Reliable recording/session layer | IN PROGRESS | Initial direct Speech capture exists; must be reconciled with Type4Me session lifecycle rather than treated as complete. |
| Modern Apple Speech pipeline | IN PROGRESS | Uses current Speech framework concepts; API details/finalization behavior are being rechecked against macOS 27 SDK. |
| Original-app capture/focus restore | IN PROGRESS | Initial implementation exists; Type4Me target/focus behavior audit pending. |
| Text injection / clipboard fallback | IN PROGRESS | Initial implementation exists; must adopt relevant synthetic-event/change-count/clipboard safety lessons from Type4Me. |
| Cancellation/interruption/stale-result hardening | IN PROGRESS | Current scaffold is insufficient; Type4Me generation/state lessons are part of the required work. |
| Xcode/macOS 27 build | TODO | Must be performed on a supported Mac. |
| Compatibility matrix | TODO | See `../validation.md`. |
| Performance baseline | TODO | Record after the first stable device build. |

## Type4Me audit record

Reference: [`../reference/type4me.md`](../reference/type4me.md)

### Hotkey

**Current classification: ADAPT**

Morie does not need Type4Me's full multi-binding/media/mouse feature surface in V0, but it does need its mature state-machine lessons:

- explicit hold state;
- repeat handling;
- modifier transitions;
- active recording ownership;
- abort/reset idempotency;
- stale timer/state cleanup;
- synthetic event exclusion.

The first Morie `NSEvent` press/release implementation is therefore a scaffold, not the final architecture.

### Audio / recording session

**Current classification: ADAPT**

Keep relevant lifecycle behavior from Type4Me:

- explicit permission/device failure handling;
- reliable stop/cleanup;
- immediate capture graph/resource release;
- no accidental Bluetooth call-mode warm-up;
- stale asynchronous result protection;
- one authoritative recording generation/session.

Do not inherit its ASR provider requirements or PCM format solely for compatibility with external ASR engines.

### Text injection / clipboard

**Current classification: ADAPT**

Keep/reconcile:

- synthetic paste-event marker so internal Cmd+V cannot trigger input hotkeys;
- target validity/self-app exclusion;
- fallback that preserves dictated text if delivery is impossible;
- change-count-aware clipboard restore;
- Electron/native timing differences;
- defensive/bounded Accessibility access.

Do not inherit correction-observation complexity until the relevant later phase.

### Multi-provider/runtime architecture

**Classification: DROP**

Morie Phase 0 does not inherit Type4Me provider registries, cloud providers, sherpa-onnx, SenseVoice, Qwen3 Python/MLX, Silero VAD, CppJieba, subscription/pricing/build variants, or related configuration UI.

## Implementation notes

### Native UI

Morie must use native macOS 27 system components. Standard SwiftUI/AppKit surfaces should pick up Liquid Glass from the system. Custom imitation is prohibited.

If a future visible interaction has no adequate system component, the implementation must stop and request explicit owner approval before building a custom substitute or adding an external UI dependency.

### App state

The initial controller keeps the Phase 0 flow explicit:

`checking → ready → recording → delivering → ready`

This high-level state model may remain, but session-generation/terminal-path reliability should be reconciled with Type4Me's mature `RecognitionSession` lessons.

### Speech

Morie targets the current macOS 27 Speech framework path, centered on:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- current Apple capture/input APIs

There is no `SFSpeechRecognizer` recognition fallback. Older API usage is allowed only if the current SDK still requires it for authorization.

Partial/volatile transcription and analyzer finalization behavior must match the current SDK rather than assumptions from older Speech APIs.

### Delivery

The current scaffold captures the target application before recording and restores it before delivery. This is being reconciled with Type4Me's proven injection behavior before Phase 0 can be considered stable.

The final path must account for:

- self-target avoidance;
- focus timing;
- synthetic-event tagging;
- target disappearance;
- clipboard change-count safety;
- Electron/native paste timing;
- no-loss fallback.

### Capability gate boundary

The product baseline requires iCloud/CloudKit for Private Mode, but M-002 does not yet own persistence or a real CloudKit container. iCloud availability will therefore be added in M-003 when entitlements/container semantics are real. M-002 must not claim full Private Mode readiness beyond the capabilities it actually implements.

## Validation performed

Verified at repository/static level:

- source files are connected to the Xcode project;
- deployment target is macOS 27.0;
- no external package dependency is present;
- owner design baseline has been preserved in the repository;
- native UI and dependency approval gates are documented;
- Type4Me reference repository and key input-foundation paths have been identified;
- Phase 0 Issue and draft PR exist.

Not yet verified:

- Xcode 27 compilation;
- modern Speech API calls against the actual macOS 27 SDK;
- microphone/Speech runtime behavior;
- Apple Intelligence behavior on supported hardware;
- Accessibility permission lifecycle;
- global shortcut behavior across apps;
- robust repeated recording/session behavior;
- focus restoration timing;
- target-app injection matrix;
- native Liquid Glass appearance/behavior on actual macOS 27;
- performance/energy measurements.

These items keep the task `IN PROGRESS`.

## Known issues / risks

- The first Phase 0 code was intentionally small and is not allowed to bypass mature Type4Me lessons. Hotkey/audio/injection code remains provisional until the reference audit is reconciled.
- Current Apple Speech APIs must be compiled against the actual target SDK; API-shape changes should be fixed against the latest Apple API rather than introducing legacy fallback.
- Global event handling varies with Accessibility/Input Monitoring behavior and needs real-device validation.
- Accessibility support differs between native applications, Electron editors, terminals and custom text controls.
- Clipboard restoration must not overwrite a clipboard change made after Morie's paste.
- UI changes must not introduce custom faux-Liquid-Glass surfaces simply to match a mockup.

## Follow-up

After M-002 is stable, M-003 introduces the Capture-first persistence boundary:

- durable local Capture storage;
- History;
- App Context persistence;
- CloudKit/iCloud container and sync;
- iCloud capability gate.

Memory extraction/personalization remains later work.

## References

- Full product baseline: [`../design/apple-native-first-v0-baseline-v2.md`](../design/apple-native-first-v0-baseline-v2.md)
- Native UI rules: [`../ui-design.md`](../ui-design.md)
- Type4Me reference: [`../reference/type4me.md`](../reference/type4me.md)
- Type4Me repository: https://github.com/joewongjc/type4me
- Issue #2: https://github.com/6spot/Morie/issues/2
- Draft PR #3: https://github.com/6spot/Morie/pull/3
- Validation matrix: [`../validation.md`](../validation.md)
- Development guide: [`../development.md`](../development.md)
- Deployment guide: [`../deployment.md`](../deployment.md)