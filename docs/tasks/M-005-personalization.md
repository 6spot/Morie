# M-005 — Input Cleanup and Personalization

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Phase:** Phase 3 (task area, not execution order)
- **Active integration:** [M-009](M-009-macos-input-memory.md), branch `feature/m-009-input-dictionary-memory`.
- **Dependency:** durable Capture. Basic cleanup does not require personal Memory.

## Why

Voice input should be immediately useful and readable while retaining the user's meaning and tone. Dictionary spellings improve words, and relevant personal context can help interpret the current expression without adding historical background.

## Scope

- The [approved independent cleanup contract](../input-cleanup.md): meaningless filler/repetition removal, clear self-corrections, punctuation, paragraphs and lists only for existing structure.
- Dictionary spelling normalization of the same word's letter case before optional AI processing; full-/half-width forms remain distinct and [M-011](M-011-simple-dictionary.md) removes alias rules.
- Bounded native Foundation Models cleanup, independently useful with empty Memory.
- Durable original/final text and exact dictionary/context/outcome provenance.
- Input priority, deadline/cancellation, save-error and stale-source/context handling.
- Opt-in word-correction suggestions to the separate user dictionary (M-009).

Excluded from M-005 itself: answering/executing dictated content, generic rewrites, unexpressed background, inspiration/follow-up, external runtimes, cloud providers and compatibility layers. Aggregate style learning is now owned separately by [M-018](M-018-expression-profile.md) and may influence presentation only after stable evidence.

## Acceptance criteria

1. Basic cleanup works without Memory and preserves meaning, tone, terminology, uncertainty and complete short replies.
2. Clear fillers/redundancy/self-corrections can be removed; clear structure can become paragraphs/lists without new content, summary, explanation, translation or answers.
3. Saved dictionary words supply Speech hints and same-word spelling normalization even when AI is disabled, busy, unavailable or timed out. No alias or inferred substitution rules remain.
4. Original recognition is durable before processing; final text and its actual processing context are durable before insertion and idle learning.
5. Changed/deleted sources and stale dictionary/Memory snapshots cannot deliver a late AI result. Save failure cannot expose unsaved output.
6. New recording does not wait for optional model teardown. Recover current-version interruptions without replaying a paste; preserve existing final output during Speech retry.
7. Actual quality and latency are measured with supported hardware before completion; prompt assertions and unit tests are not proof of semantic equivalence.

## Progress

- [x] Replace anchored punctuation-only proposals with independent cleanup under approved instructions.
- [x] Normalize saved dictionary spellings first and keep dictionary fallback independent of model availability.
- [x] Retain deadline/cancellation ownership and durable source/final/provenance checks.
- [x] Recheck source/dictionary/Memory after generation; preserve Capture through errors/restart/retry.
- [x] Connect native Settings/History and automatic analysis of saved final input through M-009.
- [x] Verify with isolated model stubs, persistence tests and actual SDK compilation.
- [x] Simplify the Foundation Models cleanup prompt and send only dictionary word strings plus useful Memory name/notes text; omit UUIDs, timestamps, status/origin and matching metadata from the model payload. Native Speech already receives only `[String]` dictionary hints, so no Speech metadata path required a code change.
- [x] Tighten cleanup fidelity for words being discussed as UI labels/terms: apparent repetition must not remove or rename labels such as `已输入`.
- [x] Make punctuation completion an explicit model requirement and schema guide.
- [x] Remove over-specific examples that could leak wording into unrelated input; explicitly forbid introducing unspoken stance words, generalize semantic-vs-stutter repetition handling, and normalize ordinary Chinese clock times such as `9:00 → 9点` without inventing AM/PM.
- [x] Reorganize the cleanup prompt using the proven Type4Me lesson of role → goal → boundaries → spoken cleanup → formatting → structure/register → context → generic examples, while deliberately dropping its aggressive number/list/title/transition rewriting behavior.
- [x] Keep personal Memory context conservative: cleanup receives at most four directly relevant items, common single-word overlap is insufficient, and the prompt must ignore Memory that the current input does not actually point to.
- [x] Handle clear abandoned fragments and sentence restarts as spoken-language cleanup while preserving both clauses when they carry independent meaning; make the cleanup role explicitly support Chinese, English and mixed-language input.
- [ ] Measure fidelity, unintended changes, hint benefit, timeout rate, final-to-delivery latency and native interactions.

## Implementation notes

`InputRefiner` supplies JSON input/context as data under the Chinese cleanup contract, uses current Apple `LanguageModelSession` and `@Generable`, and bounds the entire request with native token accounting. It returns complete final text. Morie trusts that structured model result instead of applying a second mechanical language validator; the save boundary rejects only empty or malformed text, while stale snapshots and save failures remain protected independently.

`CapturePersonalizer` saves dictionary-corrected fallback even if cleanup is off/busy/fails. Stale dictionary or failed final save uses verified durable original text. `CaptureRefinement` stores original input, dictionary/personal snapshots, edits, outcome/reason and elapsed time; Speech recognition remains separate from final output.

Cleanup has no elapsed-time deadline. Foundation Models completion/failure or explicit caller cancellation ends the operation, allowing duration to scale with the input and actual model work. Cancellation resumes without joining an uncooperative model; no new optional model task overlaps draining cancelled work. Idle personal Memory learns from the completed current-app Capture after final save; it has no confirmation inbox.

Existing capture-only persistence/refinement remains without expanding inspiration or admitting it to daily-input learning. Native word-correction prompts require separate opt-in and explicit spelling confirmation; they do not create global aliases or personal facts.

## Validation evidence

The dated results below belong to the earlier confirmed-term/anchored-edit slice. M-009 directly replaces its narrow cleanup and mandatory candidate review. Current behavior/tests are recorded in [M-009](M-009-macos-input-memory.md#validation-evidence).

- Isolated macOS 27/Xcode 27 Debug app build passed, including the final native disclosure alignment: `/tmp/morie-personalization-build.Jdqg9D/verified-build.log`.
- All **91 tests passed, 0 failed, 0 skipped**, confirmed with `xcresulttool get test-results summary` for `/tmp/morie-personalization-tests.sAsng6/FinalLogic.xcresult`; log `/tmp/morie-personalization-tests.sAsng6/final-tests.log`.
- The 26 new personalization tests cover grounded edits and content protection; durable original/final ordering and provenance; disabled/busy/error outcomes; save rollback and preservation of delivery outcomes; History retry and late discard; recovery; source/Memory changes; blocked running-source actions; automatic final-text extraction and stale candidates; timeout/cancellation with a deliberately uncooperative model. Existing 65 Capture/History/audio/Memory/candidate tests still pass.
- Tests inject model results and use temporary storage and a test diagnostics sink. They do not open the microphone, invoke Apple Intelligence, paste/copy, launch the product app, or touch production History/logs. Compilation covers the real native model implementation.
- Four native views were rendered and inspected with synthetic data: final/recognized Capture detail, expanded refinement provenance, original text after timeout and Settings. PNGs: `/tmp/morie-personalization-preview.D1Aqw5/verified/`; harness: `/tmp/morie-personalization-preview.D1Aqw5/PersonalizationPreview.swift`; render log: `/tmp/morie-personalization-preview.D1Aqw5/verified-render.log`. Temporary presentation copies expose the detail and bind disclosure state for layout checks; Settings uses a memory-only controller so app bootstrap is never invoked. No visible window, model, microphone, clipboard, production store or product logger was used. Offscreen rendering checks layout, not interactive/material acceptance.
- Interactive hardware and real-model quality/latency checks remain deferred to tonight by the owner; they are not waived. M-005 is not `DONE`.

## Quality and latency acceptance

Use [the cleanup/model checklist](../validation.md#m-005-input-personalization) with disposable Chinese, English and mixed-language samples. Compare cleanup with an empty personal profile, dictionary hints, same-word letter-case variants, distinct full-/half-width forms, related Memory, and cleanup disabled.

Include meaningful 嗯/好的/OK replies, emphatic repetitions, unclear alternatives, dates/numbers, questions/requests, names, code, commands/URLs and long inputs. Confirm no summary, answer, new background or changed stance. Measure actual Speech hint benefit separately from deterministic spelling normalization. Record model outcomes and the final-to-delivery latency/timeout rate instead of inferring quality from test runtimes.

## Blockers and follow-up

- Device and actual model acceptance remain open, together with M-002/M-003/M-004/M-008/M-009.
- Validate useful correction suggestions and focus behavior across current macOS fields.
- iOS/mobile inspiration and cross-device sync remain unscheduled. No current enrollment/container IDs are required.

## Issue / PR

No new Issue/PR. M-009 owns the current integration; the earlier slice used `feature/m-005-personalization`.

## References

- [Product baseline](../product-architecture-baseline.md)
- [Cleanup contract](../input-cleanup.md)
- [M-004](M-004-memory.md)
- [M-009](M-009-macos-input-memory.md)
