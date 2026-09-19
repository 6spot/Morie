# Current Product and Architecture Baseline

This is the concise implementation policy for Morie, incorporating the owner's approved V0 amendments through 2026-09-18. The [source design](design/apple-native-first-v0-baseline-v2.md) preserves their provenance and the superseded original plan. Explicit later owner decisions take precedence over a stale summary.

## Product and current milestone

Morie turns intentional voice input into useful text and gradually learns selective personal context from daily communication. The active milestone is [M-009](tasks/M-009-macos-input-memory.md): make one Mac's input loop dependable, then validate its dictionary, independent cleanup and automatic personal Memory.

`record → durable recognition → dictionary / optional cleanup → durable final text → insertion → idle Memory learning`

Historical phase numbers identify task areas, not an order that puts sync or management UI before usable input. [The task index](tasks.md) owns progress; the [architecture map](architecture.md) owns implementation details.

## Platform and privacy

- macOS first, targeting **macOS 27+**, Apple Intelligence-capable Macs and the current Swift/Xcode toolchain for that platform.
- Apple frameworks and repository-owned Swift are the default implementation. Recognition uses `SpeechAnalyzer`, `SpeechTranscriber`, `AssetInventory` and current capture APIs. `SFSpeechRecognizer` is permitted only for authorization, never a recognition fallback. Foundation Models capability checks use `SystemLanguageModel`.
- Required Apple Intelligence, Speech/language/assets and permission capabilities gate Private Mode. Unsupported capabilities block input; there is no old-platform compatibility route or cloud fallback.
- V0 has no Morie backend. M-019 now begins the explicitly scheduled iCloud/CloudKit milestone: sync/backup is default-off, uses each user's private database and never creates a separate Device Only product mode. The repository does not invent a container identifier; signed runtime acceptance still depends on configuring the real Apple Developer/Xcode CloudKit capability/container. Original audio remains local in this slice.
- Only intentional input enters Capture. Ordinary typing is not monitored. The separate opt-in correction feature reads a bounded, verified recent Morie insertion; it does not log keystrokes, read whole documents or send external field text to AI.
- iOS, mobile inspiration/follow-up, Morie Cloud, public APIs/MCP and generalized provider runtimes are outside the active milestone. Existing `captureOnly` storage remains without expanding that experience.

## Capture and expression

The two existing destinations are `currentApp` (save and insert) and `captureOnly` (save to History). A stable Capture identity and destination are saved before recording; save recognized text before enrichment and committed final text before insertion or personal learning.

Operational failure must preserve available intentional audio/text. Explicit cancellation is a separate discard operation after native teardown. Current-version crash recovery remains required. Never silently delete user data to work around a development schema mismatch.

Default recording uses a solo **Fn / Globe release** as one activation: the first starts, the next finishes; Escape cancels. Fn chords pass through. Focus restoration and generic clipboard/synthetic-paste delivery follow [ADR 0001](decisions/0001-universal-text-delivery.md); the nonactivating native HUD follows [ADR 0002](decisions/0002-toggle-capture-hud.md).

Cleanup follows the [owner's contract](input-cleanup.md). It works with empty Memory, preserves meaning, terminology, tone, emphasis and uncertainty, and never answers, summarizes, translates or executes the dictated content. Unavailable, slow or uncertain enrichment keeps usable saved input. New voice input takes priority over optional model work.

## Dictionary and personal Memory

| Area | Required behavior |
| --- | --- |
| Dictionary | Each user-maintained entry saves one word/name/term. No aliases, replacement pairs, inferred substitutions or compatibility adapter for the removed design. Words supply native Speech hints; only letter-case variants of the same whole word normalize to its spelling. Full-/half-width forms remain distinct. |
| Correction suggestion | Independent, default-off observation of a verified recent insertion. A native nonactivating prompt saves only the corrected spelling after explicit confirmation. It creates neither a global replacement nor a personal fact. |
| Personal Memory | Automatically learn selective projects, relationships, stable preferences, facts and decisions from committed final daily input during idle time. No required candidate-review inbox. |
| Evidence and user control | Retain the exact final-text analysis snapshot, source IDs, origin, confidence, evidence date and lifecycle. Merge repeated evidence; supersede explicit later changes. Quotes, temporary/hypothetical/uncertain statements and unsupported inferences must not become personal facts. User edits/archive/delete take precedence. |
| Future input | Relevant Memory helps interpret what was said; it cannot insert unspoken background or override the current viewpoint/style. Dictionary and cleanup remain useful independently. |

Unfinished personal analysis is durable and retryable, yields to new input, and rejects stale/deleted source results. Structured model output and prompt constraints still require real-device quality validation; deterministic tests are not proof of semantic correctness.

## Native UI

Use Apple system UI, with Simplified Chinese as the current primary interface language. Prefer standard SwiftUI components, then AppKit when SwiftUI cannot expose the needed native behavior. Build for macOS 27 so controls, windows, menus, toolbars, sidebars, sheets and popovers receive the system Liquid Glass design.

A genuinely custom control without a system equivalent uses Apple's current Liquid Glass APIs and interaction/layout conventions. Do not hand-draw, shader-simulate or blur/overlay-stack an imitation, replace a native control for easier styling, or introduce a third-party UI system. Detailed screen behavior and current layout belong in [UI design](ui-design.md).

Setup inspects without prompting and authorizes only through explicit actions. Settings uses the native scene and Command-comma; the menu bar and sidebar use system components. Returning from System Settings refreshes status without interrupting input.

## Approval boundaries

These owner-controlled gates remain in force; routine native implementation within the requested scope does not require an exception.

| Proposed change | Boundary |
| --- | --- |
| Apple system UI cannot meet a concrete requirement | Stop before implementing a substitute. Document the native components/effects considered, exact gap, proposed UX, accessibility and technical trade-offs, maintenance cost and any dependency. Obtain explicit project-owner approval. |
| Any external dependency | Stop before adding a third-party package, runtime, model, SDK, binary framework, C/C++ bridge, Python component, JavaScript runtime, service, UI library, analytics/updater or database abstraction. Obtain explicit project-owner approval after the assessment below. |

An external-dependency assessment must state:

1. The requirement Apple-native APIs cannot satisfy, evaluated native alternatives and why they fail, plus the measurable benefit of the proposal.
2. Binary size, startup, memory, CPU/energy, privacy, signing, packaging and maintenance impact; new runtime/model/network requirements.
3. Security and update ownership, and a removal/migration path if Apple later supplies the capability.

Contributors and agents cannot approve exceptions for the owner. Explicit approval already given in the session remains valid for that scope. The expected Phase 0 third-party product dependency count is **zero**.

## Reference and development boundaries

Morie requirements govern architecture. Type4Me supplies evidence for solved input failure modes, not a compatibility target or migration template. Use the [scoped reference audit](reference/type4me.md) after defining the current Morie/macOS 27 requirement; retain proven concepts, drop irrelevant machinery, and verify suspected platform workarounds. Preserve applicable MIT attribution for substantial copied code. The [OpenLess audit](reference/openless.md) is behavior-only; no AGPL source is copied.

This is a development-stage product with no legacy contract. Implement current schemas/APIs directly: no old-data reconstruction, schema migrations, version routing or speculative upgrade paths. Current-version recovery and Capture-first protection are not optional. Extract shared packages only for a real consumer; do not prebuild iOS, provider or Cloud abstractions.

## Acceptance

Success means reliable, responsive daily input; selective and inspectable personal context; and measured improvement in future expression. Actual model fidelity, latency/energy, microphone/TCC behavior, keyboard/focus, native UI and cross-app delivery require supported-Mac evidence in [validation](validation.md).

Task completion requires its applicable acceptance criteria. Phase 0 must not merge before the required real-device matrix is complete unless the owner explicitly narrows it. Optional iCloud sync/backup now follows the useful single-Mac loop through M-019; iOS and Morie Cloud remain later work.
