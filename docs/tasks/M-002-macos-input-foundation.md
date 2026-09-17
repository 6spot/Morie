# M-002 — macOS Input Foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-17
- **GitHub Issue:** https://github.com/6spot/Morie/issues/2
- **Pull Request:** https://github.com/6spot/Morie/pull/3
- **Branch:** `phase0/input-foundation`

## Why

Morie's first product dependency is not Memory or cloud infrastructure. It is a reliable macOS voice-input loop. If recording, transcription, focus restoration, and text delivery are not dependable in everyday apps, later Personal Memory work has no stable product surface to improve.

This is **not a greenfield voice-input implementation**, but Type4Me is also **not a migration target**. M-002 starts from Morie's own design/architecture and macOS 27 requirements, then uses Type4Me only to identify proven failure modes and lessons worth retaining.

Mandatory order:

`Morie design → Morie architecture → M-002 requirement → current macOS 27 Apple API → Type4Me reference → smallest Morie-native implementation`

## Scope

Included:

- macOS 27+ only;
- Apple Intelligence-capable Macs;
- native Swift / SwiftUI / AppKit;
- native macOS 27 system UI and Liquid Glass behavior;
- selective Type4Me reference audit after Morie requirements are defined;
- Private Mode capability checks relevant to Phase 0;
- menu bar application shell;
- focused global hold-to-talk shortcut;
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
- support for macOS older than 27;
- historical Type4Me compatibility layers not required by current macOS 27;
- generalized hotkey/media/mouse/device compatibility not required by Morie's V0 interaction;
- unapproved third-party runtime/model/UI library/dependency;
- Type4Me's multi-provider and Python/sherpa-onnx runtime architecture;
- durable Capture storage and History;
- Personal Memory;
- MCP/Public API/Relay.

## Acceptance criteria

1. On a supported Mac, Morie enters Ready only when required Private Mode capabilities for the current phase are available.
2. Holding the selected global shortcut starts intentional voice capture and releasing it finalizes the session reliably, including repeated use.
3. The modern Apple Speech stack produces partial/final transcription without a legacy recognition fallback.
4. Morie remembers the app/input context active before capture, restores it, and delivers final text reliably where supported.
5. Delivery fallback preserves the user's result and does not corrupt a newer clipboard change.
6. Cancel/error/interruption/stale-result paths release capture resources and leave the app recoverable.
7. Relevant Type4Me issues are classified `ADAPT`, `DROP`, or `VERIFY` only after the Morie/macOS 27 requirement is defined.
8. No Type4Me compatibility behavior is migrated solely for older systems, broader hardware, multiple providers, or generalized feature coverage.
9. All user-visible Phase 0 UI uses Apple native macOS 27 components/Liquid Glass behavior. Any native-UI gap requires owner approval before a substitute is implemented.
10. The compatibility matrix is tested on real target applications.
11. Initial binary/startup/memory/latency/energy observations are recorded.
12. No external dependency is introduced without explicit project-owner approval; expected Phase 0 external dependency count is zero.

## Subtasks / progress

| Subtask | Status | Notes |
| --- | --- | --- |
| Native macOS project | DONE | `Morie.xcodeproj`, deployment target macOS 27.0. |
| Repository docs / task system | DONE | `AGENTS.md`, master/detail tasks, architecture/dev/deploy/validation docs established. |
| Full owner design baseline in repo | DONE | Repository transcription under `docs/design/`. |
| Native UI / Liquid Glass policy | DONE | Hard rule documented; system components required. |
| Type4Me reference boundary | DONE | Morie-first migration order and macOS 27 filter documented. |
| Type4Me hotkey audit | IN PROGRESS | Inspect only behaviors relevant to Morie's selected hold-to-talk interaction; generalized compatibility is out of scope. |
| Type4Me audio/session audit | IN PROGRESS | Keep only lifecycle/failure lessons still relevant to current Apple-native macOS 27 path. |
| Type4Me injection/focus audit | IN PROGRESS | Keep current-relevant no-loss/clipboard/focus lessons; do not create a speculative per-app framework. |
| Type4Me Apple Speech audit | TODO | Behavioral reference only; implementation stays on current macOS 27 Speech APIs. |
| Menu Bar shell | IN PROGRESS | Uses native SwiftUI `MenuBarExtra`; real macOS 27 appearance/interaction validation pending. |
| Foundation Models capability check | DONE | `SystemLanguageModel.default.availability` and locale check. |
| Speech capability/locale check | DONE | `SpeechTranscriber` availability and supported locale. |
| Microphone/Speech authorization | DONE | Permission checks implemented. |
| Accessibility trust check | DONE | Required for global interaction/text delivery. |
| iCloud/CloudKit capability check | DEFERRED | Belongs with the real CloudKit container/entitlements in M-003; do not fake it in Phase 0. |
| Global hold-to-talk hotkey | IN PROGRESS | Initial scaffold exists; harden only the state handling actually needed by Morie's macOS 27 shortcut design. |
| Reliable recording/session layer | IN PROGRESS | Current direct Speech path is being hardened with only current-relevant lifecycle protections. |
| Modern Apple Speech pipeline | IN PROGRESS | Current API details/finalization behavior being checked against macOS 27 SDK. |
| Original-app capture/focus restore | IN PROGRESS | Current implementation exists; validate before adding any compatibility branching. |
| Text injection / clipboard fallback | IN PROGRESS | Current implementation now includes selected proven safety behaviors; more compatibility logic requires current macOS 27 evidence. |
| Cancellation/interruption/stale-result hardening | IN PROGRESS | Add only protections justified by Morie's current session lifecycle. |
| Xcode/macOS 27 build | TODO | Must be performed on a supported Mac. |
| Compatibility matrix | TODO | See `../validation.md`. |
| Performance baseline | TODO | Record after the first stable device build. |

## Type4Me audit record

Reference: [`../reference/type4me.md`](../reference/type4me.md)

### Hotkey

**Current classification: ADAPT / DROP split**

Adapt only:

- repeat suppression;
- explicit active hold ownership;
- deterministic reset/abort semantics;
- synthetic-event exclusion if the chosen macOS 27 event path needs it.

Drop by default:

- media-key support;
- mouse-button support;
- arbitrary modifier-only combo machinery;
- multi-mode switching;
- broad legacy/platform compatibility behavior.

Anything beyond this requires a concrete Morie requirement or a reproduced macOS 27 defect.

### Audio / recording session

**Current classification: ADAPT / VERIFY**

Adapt only generally useful lifecycle principles:

- deterministic resource cleanup;
- one active session identity;
- stale async result protection where the current Speech pipeline can actually produce it;
- recoverability after failure.

Verify before adding current-device/audio-route compatibility behavior. Do not inherit Type4Me's external-ASR-driven PCM/conversion/device architecture.

### Text injection / clipboard

**Current classification: ADAPT / VERIFY**

Adapt current-relevant no-loss safety:

- self-target avoidance;
- preserve transcript if direct delivery fails;
- change-count-aware clipboard restoration;
- synthetic-event marking if the event path can observe Morie's own Cmd+V;
- bounded Accessibility calls.

Verify actual macOS 27 app behavior before adding app-specific or Electron-specific compatibility branches.

### Multi-provider/runtime architecture

**Classification: DROP**

Morie Phase 0 does not inherit Type4Me provider registries, cloud providers, sherpa-onnx, SenseVoice, Qwen3 Python/MLX, Silero VAD, CppJieba, subscription/pricing/build variants, or related configuration UI.

### Old-platform compatibility

**Classification: DROP**

Morie starts at macOS 27+. We do not preserve compatibility code whose purpose is supporting earlier macOS versions, older Speech APIs, older hardware, or alternative runtimes for unsupported machines.

## Implementation notes

### Native UI

Morie must use native macOS 27 system components. Standard SwiftUI/AppKit surfaces should pick up Liquid Glass from the system. Custom imitation is prohibited.

If a future visible interaction has no adequate system component, the implementation must stop and request explicit owner approval before building a custom substitute or adding an external UI dependency.

### App state

The initial controller keeps the Phase 0 flow explicit:

`checking → ready → recording → delivering → ready`

Additional state machinery is introduced only when a real current lifecycle requirement demands it.

### Speech

Morie targets the current macOS 27 Speech framework path, centered on:

- `SpeechAnalyzer`
- `SpeechTranscriber`
- `AssetInventory`
- current Apple capture/input APIs

There is no `SFSpeechRecognizer` recognition fallback. Older API usage is allowed only if the current SDK still requires it for authorization.

Partial/volatile transcription and analyzer finalization behavior must match the current SDK rather than assumptions from Type4Me or older Speech APIs.

### Delivery

The current implementation captures the target application before recording and restores it before delivery.

Any additional compatibility behavior follows this rule:

`reproduce on macOS 27 → document in M-002 → implement smallest native fix`

No speculative compatibility matrix/code is added just because Type4Me needed it historically.

### Capability gate boundary

The product baseline requires iCloud/CloudKit for Private Mode, but M-002 does not yet own persistence or a real CloudKit container. iCloud availability will therefore be added in M-003 when entitlements/container semantics are real. M-002 must not claim full Private Mode readiness beyond the capabilities it actually implements.

## Validation performed

Verified at repository/static level:

- source files are connected to the Xcode project;
- deployment target is macOS 27.0;
- no external package dependency is present;
- owner design baseline has been preserved in the repository;
- native UI and dependency approval gates are documented;
- Morie-first Type4Me migration order is documented;
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

- The current Phase 0 code remains provisional until compiled/run against the actual macOS 27 SDK/runtime.
- Type4Me contains significantly more compatibility behavior than Morie needs; importing it wholesale would violate the project baseline.
- Current Apple Speech API assumptions must be validated against the actual target SDK rather than compensated with legacy fallback.
- Compatibility code should be evidence-driven from macOS 27 testing, not inherited historically.
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