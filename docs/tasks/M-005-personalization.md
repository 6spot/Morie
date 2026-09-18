# M-005 — Context-aware Personalization

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-18
- **Phase:** Phase 3
- **Starts after:** M-004 can retrieve trustworthy relevant context

## Why

Stored Memory is only useful when it improves the user's next expression. This phase closes the loop by feeding relevant Personal Context back into correction and rewriting.

## Scope

Planned:

- context-aware correction;
- project/person/vocabulary-aware terminology recovery;
- restrained rewrite/cleanup;
- writing-style context;
- learning from explicit user corrections where appropriate;
- latency/quality measurement versus the Phase 0 baseline.

Excluded:

- generic AI assistant behavior unrelated to capture/input;
- autonomous task execution;
- cloud-only personalization requirements.

## Acceptance criteria

1. Relevant Memory measurably improves terminology/correction on representative user captures.
2. Basic voice input remains fast and reliable when personalization is unavailable or unnecessary.
3. Rewriting preserves user intent and trends toward the user's own expression rather than generic AI prose.
4. Incorrect/stale Memory can be excluded or superseded without persistent contamination.
5. Personalization latency and failure behavior are documented.
6. Persist polished output in Capture `finalText` before delivery/Memory extraction, while retaining Speech `recognizedText`. History and Memory provenance must retain the polished result actually used. This is the owner's explicit 2026-09-18 requirement; do not extract from raw recognition when a saved polished final text exists.
7. A final-text change makes pending candidates based on the previous text stale. Polishing failure keeps the saved Capture intact and must not mislabel recognized text as AI-polished output.

## Progress

### First slice — daily input loop (2026-09-18)

The owner reiterated the original purpose: remember the user so future voice input becomes more accurate and more like their own expression. This slice uses confirmed Vocabulary/Project context for named-term correction and light punctuation cleanup; broader style learning remains follow-up.

- [x] Request bounded structured edits from Apple Foundation Models after recognition is durable.
- [x] Validate every edit against the original text and confirmed context; constrain changes to terminology and punctuation/spacing. Actual preservation of intent/quality still requires human evaluation.
- [x] Bound optional model waiting and cancellation independently of model teardown; reject late results and overlapping sessions.
- [x] Persist final output, original refinement input, actual context and accepted edits before downstream use. Retain recognized text and existing audio.
- [x] Exclude changed/archived context and changed sources after inference; model/context failures use the durable original.
- [x] Protect capture-only output during History recovery and recover interrupted refinement without automatic inference/delivery.
- [x] Trigger best-effort candidate extraction after completion using the saved final output. Live input takes priority; candidates still require explicit confirmation.
- [x] Expose a native Settings toggle and truthful History refinement/provenance details.
- [x] Add deterministic persistence, validation, timeout/cancellation and source-state tests; compile in isolation.
- [x] Render and inspect native UI in isolation.
- [ ] Measure real terminology benefit, unintended edits, completion latency and input preemption on supported hardware.

The initial model-wait deadline is 2 seconds, a provisional engineering limit pending real-device latency measurements. Exceeding it resumes with the saved original without waiting for model teardown. Storage/validation and main-actor scheduling add overhead outside that limit. No cloud/provider routing, clipboard/selection context, arbitrary rewrite modes, historical migration or compatibility layer is included.

## Implementation notes

- `CapturePersonalizer` runs after durable Speech completion and before current-app delivery or capture-only success. Source text must agree with a separate committed context. Settings enables refinement by default; disabling it records a skip and uses the saved original.
- `InputRefiner` uses current macOS 27 `SystemLanguageModel`, `LanguageModelSession`, `@Generable`, greedy generation and native token/context accounting. A full request must fit; no silent input truncation. The response is at most eight anchored edits with an exact original substring, replacement and one-based occurrence.
- `RefinementValidator` allows explicit confirmed names/aliases to become the exact canonical name, and restrained horizontal spacing/missing comma/period cleanup. It preserves cleanup content/word tokens/newlines/existing punctuation, rejects partial words/overlaps/missing anchors, and protects numeric/technical tokens and backtick code. It does not invent aliases, rewrite prose or remove filler words. Overcautious rejection keeps the original.
- `InputRefinementRunner` owns one generation task plus a deadline and a single continuation. Timeout/cancellation resolves the caller independently of a slow model cancellation. Draining work remains owned, blocks other optional model work, and cannot update any Capture later. New Speech capture does not join candidate/refinement model teardown.
- `CaptureRefinement` stores exact input/context snapshots, changes, status, fixed reason and duration. Final text is saved before it can be returned for delivery/extraction. Recognized text remains separate; History retries preserve completed refined output and its actual old input even for capture-only entries. Late Speech partials cannot overwrite it.
- After inference, changed/archived/deleted relevant Memory causes original-text fallback. A changed/deleted source rejects stale output/delivery. Failed final persistence rolls back the AI result before using the verified durable original. If even outcome metadata cannot save, it may remain incomplete until a later terminal save/restart; no unsaved AI text is delivered. Recovery never overwrites an actual delivered/delivery-failed outcome.
- Running refinement blocks source playback/re-recognition/deletion and Memory creation/extraction. Cancellation/restart clears interrupted refinement, retains saved text/audio and does not start a model or paste automatically.
- Completed current-app/capture-only input, and clipboard-preserved delivery failure, request best-effort candidates from the saved final text. This does not await extraction or auto-confirm Memory. Busy work skips; there is no durable queue/retry loop. The History action remains available for recovery. Old pending candidates become stale after final-text changes.
- Native Settings, History reading details/disclosures (reorganized by [M-008](./M-008-macos-management-ui.md)) and the existing processing HUD expose the feature. Diagnostics contain only counts, status and duration; fixed failure reasons never include raw model error content.
- Type4Me prompt/guard and provenance lessons are recorded in the [reference audit](../reference/type4me.md#m-005-restrained-input-refinement-audit--2026-09-18). No code/dependency/compatibility framework was copied.

## Validation evidence

- Isolated macOS 27/Xcode 27 Debug app build passed, including the final native disclosure alignment: `/tmp/morie-personalization-build.Jdqg9D/verified-build.log`.
- All **91 tests passed, 0 failed, 0 skipped**, confirmed with `xcresulttool get test-results summary` for `/tmp/morie-personalization-tests.sAsng6/FinalLogic.xcresult`; log `/tmp/morie-personalization-tests.sAsng6/final-tests.log`.
- The 26 new personalization tests cover grounded edits and content protection; durable original/final ordering and provenance; disabled/busy/error outcomes; save rollback and preservation of delivery outcomes; History retry and late discard; recovery; source/Memory changes; blocked running-source actions; automatic final-text extraction and stale candidates; timeout/cancellation with a deliberately uncooperative model. Existing 65 Capture/History/audio/Memory/candidate tests still pass.
- Tests inject model results and use temporary storage and a test diagnostics sink. They do not open the microphone, invoke Apple Intelligence, paste/copy, launch the product app, or touch production History/logs. Compilation covers the real native model implementation.
- Four native views were rendered and inspected with synthetic data: final/recognized Capture detail, expanded refinement provenance, original text after timeout and Settings. PNGs: `/tmp/morie-personalization-preview.D1Aqw5/verified/`; harness: `/tmp/morie-personalization-preview.D1Aqw5/PersonalizationPreview.swift`; render log: `/tmp/morie-personalization-preview.D1Aqw5/verified-render.log`. Temporary presentation copies expose the detail and bind disclosure state for layout checks; Settings uses a memory-only controller so app bootstrap is never invoked. No visible window, model, microphone, clipboard, production store or product logger was used. Offscreen rendering checks layout, not interactive/material acceptance.
- Interactive hardware and real-model quality/latency checks remain deferred to tonight by the owner; they are not waived. M-005 is not `DONE`.

## Quality and latency acceptance

Use the [device checklist](../validation.md#m-005-input-personalization) with disposable Chinese, English and mixed-language captures. Compare the same recordings/recognition with refinement disabled, relevant Memory enabled, and that Memory archived/changed. Inspect the actual Speech text; an unstated alias is not a valid positive correction case.

Record confirmed-term recovery, unintended changes to wording/negation/numbers/technical syntax, result status, model time and final-to-delivery latency. Include short acknowledgments, conversational wording, repeated names, questions, commands, URLs/versions, long input and rapid consecutive captures. The initial acceptance sample must demonstrate useful confirmed-term correction without unintended content changes. Set latency expectations from the measured baseline and timeout rate; deterministic test duration is not model performance evidence.

## Blockers and follow-up

- M-002/M-003/M-004 device acceptance remains open.
- iCloud/CloudKit remains deferred to final integration after Apple Developer enrollment; no configuration is requested for this slice.
- Explicit correction learning and broader writing-style context follow the validated terminology/cleanup loop.
- Owner update: development remains macOS-only with no current iOS start plan. After this foundation slice, improve the native History/Memory/Settings/Diagnostics management experience and unify its design language. Hardware acceptance remains open.

## Issue / PR

- Task branch: `feature/m-005-personalization`, based on the M-004 implementation.
- No new Issue/PR yet.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- predecessor: [`M-004-memory.md`](./M-004-memory.md)
