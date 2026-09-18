# M-009 — Mac input, custom dictionary and automatic personal Memory

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-18
- **Branch:** `feature/m-009-input-dictionary-memory`
- **Depends on:** existing M-002 input, M-003 durable Capture, M-004/M-005 foundations and M-008 native management.
- **Issue / PR:** —

## Why

The owner corrected the delivery sequence: prove useful input on one Mac before adding cross-device infrastructure. Basic cleanup must work on day one; a custom dictionary specifies spelling, while personal Memory learns about the user from everyday communication. Requiring users to approve routine candidates defeats that purpose.

## Scope

- Independent basic cleanup under the [approved contract](../input-cleanup.md).
- A native, user-maintained custom dictionary with exact spellings and explicit aliases.
- Automatic local personal-Memory learning from committed final input, scheduled in idle batches with restart/retry and input preemption.
- Evidence-aware admission, merging, replacement, user corrections/deletion and exact source snapshots.
- Input contextualization without adding unstated personal background.
- Native dictionary/Memory management without a required suggestion inbox.
- Opt-in native correction-to-dictionary prompt following the owner-supplied OpenLess behavior reference; explicit spelling confirmation, with no inferred global alias.
- Update task order and documentation to match these owner decisions.

## Exclusions

iOS, inspiration capture/follow-up, CloudKit/enrollment/container configuration, Morie backend, external dependencies, legacy schemas/migrations, keyboard monitoring and speculative platform abstractions. Existing capture-only persistence remains; no expansion is planned.

## Acceptance criteria

1. Cleanup works with an empty/unavailable Memory store, preserves meaningful tone and uncertainty, and never answers the dictated request.
2. User-defined dictionary entries persist, validate conflicting aliases and correct explicit matches without changing unrelated words or technical content.
3. Recognized text is saved before processing; final text and actual dictionary/Memory context are saved before insertion and learning.
4. Completed current-app input automatically enters local learning. Restart/cancellation/model failure does not silently drop unfinished work; new input never waits for background analysis.
5. Personal information is distinct from dictionary rules. Only supported, durable personal information is admitted; incidental, quoted, temporary or uncertain text must not become asserted user facts.
6. Repeated evidence merges without duplicate records or double-counting one Capture. Later explicit updates supersede stale information; ambiguous conflicts do not overwrite it. User edits/archive/delete take precedence over automatic learning.
7. Native pages offer inspection, correction and deletion without a required confirmation workflow. Exact final-text evidence remains inspectable.
8. Correction suggestions default off, observe only a verified recent insertion, wait for stable word edits, stop on ownership/focus changes, and save only the spelling after explicit confirmation.
9. Isolated logic tests and app compilation pass. Real microphone, model quality/latency, cross-app delivery, keyboard/VoiceOver and native-material acceptance remain open until actually run on the owner's signed app.

## Progress

- [x] Record revised milestone, independent cleanup, dictionary/Memory separation and deferred mobile inspiration follow-up scope.
- [x] Implement dictionary and independent cleanup.
- [x] Implement idle automatic learning and evidence/lifecycle handling.
- [x] Connect native management and current-app lifecycle.
- [x] Implement opt-in bounded correction observation and native spelling confirmation.
- [x] Complete isolated tests/build, native layout checks and documentation updates.
- [ ] Complete deferred real-device acceptance.

## Implementation notes

- Separate SwiftData dictionary/personal-Memory records and non-autosaving write contexts preserve the Capture checkpoint boundary. The old candidate schema/workflow is removed directly.
- Dictionary supplies bounded native Speech hints and deterministic explicit aliases. Cleanup generates full final text under the approved contract and keeps original/input/context/changes before delivery.
- Personal analysis uses a durable final-text queue, idle batches, evidence/lifecycle filters and immediate cancellation for new input. User edits and forgotten/archived topics take priority.
- Correction observation is independently opt-in and bounded to a verified recent insertion. The native panel confirms only a spelling, sizes to long content/errors and dismisses when its observation becomes invalid.

## Reference decisions

- **ADAPT:** existing durable recognition/final output and action-time provenance; Type4Me input-data isolation, content protection and duplicate/save-error lessons already recorded in [the reference audit](../reference/type4me.md).
- **DROP:** mandatory candidate approval, vocabulary-as-personal-Memory, immediate CloudKit sequencing and narrow punctuation-only cleanup. No compatibility adapter preserves the superseded design.
- **ADAPT:** [OpenLess](../reference/openless.md) stable-edit/explicit-word confirmation behavior in repository-owned Swift. No AGPL source or external dependency is copied.
- **VERIFY:** real Foundation Models selectivity, fidelity, cancellation/latency and signed-app interactions. Deterministic tests cannot establish semantic AI quality.

## Validation evidence

- Isolated app Debug build passed on macOS 27 / Xcode 27, with signing disabled and separate DerivedData. Log: `/tmp/morie-input-memory-build.e29ko88k/verified-build.log`. The owner’s signed app was not overwritten or launched.
- **91 logic tests passed, 0 failed, 0 skipped**, confirmed using `xcresulttool get test-results summary`: `/tmp/morie-input-memory-build.e29ko88k/VerifiedLogicTests.xcresult`; log `verified-logic-tests.log` in the same directory. Tests use isolated stores, synthetic audio, injected model results and the test logger, without microphone, clipboard, live AX observation or product bootstrap.
- Correction regression caught a shared-suffix boundary bug in **more e → Morie**. The fix aligns whole-word boundaries across both texts and also covers missing/extra letters and joined words. The final suite includes six correction tests, six dictionary tests, sixteen idle-learning tests and the retained cleanup/Memory/Capture/History/audio coverage.
- Twelve native offscreen fixture surfaces were rendered and inspected: dictionary at default/minimum sizes, empty dictionary, dictionary editor, personal Memory/editor, History/learning, Settings and normal/long/save-error correction panels. PNGs: `/tmp/morie-input-memory-build.e29ko88k/preview/verified/`; harness: `preview/InputMemoryPreview.swift`; compile/render logs: `preview/verified-compile.log` and `preview/verified-render.log` under the same isolated build directory.
- The prompt initially truncated long spellings. It now uses the hosting view's fitting size and native geometry updates; long text and save errors render fully. Fixtures use synthetic data, injected controller/model actions and a memory-only logger, with prohibited app activation and no ordered windows/AX observation. Offscreen images establish layout/content, not system glass, focus, keyboard or VoiceOver acceptance.
- `git diff --check` and local documentation path/heading-link checks passed. No external dependency or legacy compatibility layer was added.

## Known issues / deferred acceptance

- Actual model accuracy, topic consistency, system Speech-hint benefit, cancellation/energy/latency and native AX/prompt interactions remain unverified. The cleanup validator is a lexical guard, not proof of semantic equivalence. Deleted-topic blocks use normalized topic identity; evaluate semantic relabelling with real outputs.
- Background model work has no separate deadline in this slice; an uncooperative task retains ownership while new input proceeds and cleanup can skip. AX range length uses bounded character-count deltas and in-range selection checks, so unrelated document edits and field-specific range behavior remain explicit device checks.

## Follow-up

- Complete the deferred M-002/M-003/M-008 device matrix together with this input/Memory loop.
- Reconsider cross-device sync only when an actual multi-device milestone is scheduled; iOS/inspiration remain unscheduled.
