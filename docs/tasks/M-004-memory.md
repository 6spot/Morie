# M-004 — Personal Memory Foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-18
- **Phase:** Phase 2 (task area, not delivery order)
- **Active integration:** [M-009](M-009-macos-input-memory.md), branch `feature/m-009-input-dictionary-memory`.
- **Owner decision:** learn personal information automatically from saved daily input. Dictionary words are separate. Single-Mac work precedes sync/iOS; deferred hardware/model acceptance remains open.

## Why

Morie should become more useful through ordinary communication without making users approve a queue of routine memories. Personal Memory retains selective, supported context about the user, with inspectable evidence and user control.

## Scope

- Projects, people/relationships, stable preferences, personal facts and decisions.
- Automatic idle analysis of completed current-app input, using exact committed final text.
- Durable queue/retry, cancellation and immediate priority for new voice input.
- Grounded admission, weaker-evidence accumulation, idempotent merging and explicit later updates.
- Source provenance, origin/confidence/evidence dates and active/superseded/archived lifecycle.
- Relevant personal-context retrieval and native inspection/edit/archive/delete controls.

Excluded: custom dictionary spellings/aliases (M-009's separate dictionary), mandatory candidate review, inspiration follow-up, knowledge graphs, cloud services, iOS and compatibility/schema migrations.

## Acceptance criteria

1. Completed daily input is analyzed automatically from saved final text; recognized text is not substituted when a processed final text exists.
2. Memory is selective and evidence-backed. Quoted, temporary, hypothetical/uncertain and invented personal facts are not admitted.
3. Repeated evidence merges without counting one Capture twice. Later explicit updates can supersede automatic information; ambiguous/older conflicts and user-edited records are preserved.
4. New input never waits for background analysis, and cancelled/failed work remains recoverable across restart.
5. Personal Memory is distinct from dictionary rules; relevant context must not add unspoken background to input.
6. Native management offers optional corrections/deletion with exact sources, without a required confirmation inbox. Archive/delete prevent immediate relearning of the same normalized topic.
7. Logic tests/build pass; real model selectivity, topic consistency, update behavior, performance and native interaction are validated before `DONE`.

## Progress

- [x] Replace vocabulary/candidate schema with personal Memory and durable analysis records.
- [x] Implement final-text queue discovery, idle batches, retry/backoff and input preemption.
- [x] Implement admission, evidence accumulation, conflict/update/lifecycle and deleted-topic handling.
- [x] Preserve separate write contexts and atomic analysis/Memory saves.
- [x] Connect automatic learning, native Personal Memory and History evidence/status.
- [x] Update isolated tests and compile the real Foundation Models path.
- [ ] Complete actual model, keyboard/VoiceOver and input-preemption acceptance on the signed app.

## Implementation notes

`MemoryStore` owns personal information and analysis state in a separate non-autosaving context. `MemoryAnalysisRecord` records final text/date/Capture ID and durable work outcomes. `MemoryLearningController` waits 30 seconds idle, processes at most three inputs, retries transient failures and ignores late cancelled results. No active/capture-only/raw-only input is learned.

`MemoryLearner` uses Apple on-device generation with bounded source/context. Literal evidence and explicit personal connection are required. Confidence thresholds (0.9 explicit / 0.8 recurring with two distinct inputs) are filters, not calibrated accuracy. Normalized kind/topic identity and exact evidence consistency make merging/deletion predictable; broader semantic equivalence remains a real-model evaluation concern.

User edits, archive and deletion take priority. Automatic updates require newer explicit evidence and a still-current automatic record. Deleting Capture removes its analysis snapshots but leaves independent Memory and a truthful missing-source link. Detailed component contracts are in [architecture.md](../architecture.md).

## Validation evidence

The following dated results document earlier implementations. Their mandatory candidate-review/vocabulary rules are superseded by M-009; they are not current behavior or current acceptance. Current evidence is in [M-009](M-009-macos-input-memory.md#validation-evidence).

- Isolated Xcode 27 Debug app build passed: `/tmp/morie-memory-build.SjRXpL/final-build.log`.
- All **47 tests passed, 0 failed, 0 skipped**, confirmed with `xcresulttool get test-results summary` for `/tmp/morie-memory-tests.aceKML/FinalMemoryTests.xcresult`; log `/tmp/morie-memory-tests.aceKML/final-tests.log`. The 16 new Memory tests cover restart/provenance, no automatic promotion, name/alias validation and conflicts, source readiness/linking/deletion, edits, archive/restore/replacement, bounded Chinese/English retrieval and choosing the most specific matching alias. Existing 31 Capture/History/audio tests still pass with the expanded schema.
- Native UI was rendered offscreen using synthetic records and a temporary store at `/tmp/morie-memory-preview.DTPfub/verified/`: Memory list, detail, multiline editor, Save Memory from Capture sheet and Capture-memory section. Harness: `/tmp/morie-memory-preview.DTPfub/MemoryPreview.swift`; log: `/tmp/morie-memory-preview.DTPfub/verified-preview.log`. The native toolbar exposes status/New Memory/search and Edit/Delete. This checks layout only; no visible window, microphone, clipboard access, production database or product log was used.
- Device interaction remains pending tonight per the owner. This evidence does not complete M-004 or the earlier M-002/M-003 acceptance matrix.

### Candidate slice validation

- Isolated macOS 27/Xcode 27 Debug app build passed: `/tmp/morie-candidates-build.PpRbFV/final-build.log`.
- All **65 tests passed, 0 failed, 0 skipped**, confirmed using `xcresulttool get test-results summary` for `/tmp/morie-candidates-tests.6WH6uk/Candidates.xcresult`; log `/tmp/morie-candidates-tests.6WH6uk/tests.log`. The 18 candidate tests exercise final-text priority, recognized-text fallback, unsaved/live-source rejection, persisted snapshots, explicit/edited confirmation, duplicate/linking/archive behavior, dismissal/empty reuse, grounded bounded selection, stale/deleted sources, cancellation/preemption and failure privacy.
- Offscreen native rendering checked extraction entry/results, the separate candidate/active-memory list sections, review, stale-source disabled Save and confirmed-memory provenance. Six PNGs are in `/tmp/morie-candidates-preview.zkX9GG/verified/`; harness `/tmp/morie-candidates-preview.zkX9GG/CandidatePreview.swift`, log `/tmp/morie-candidates-preview.zkX9GG/verified-render.log`. These use synthetic final/recognized text, an injected non-model closure and temporary storage; no visible window or production data was used. The final UI changes also passed the app build above.
- The real Foundation Models path compiles. Tests inject results and do not invoke a model, microphone, clipboard, production store or product logger. Inference quality, model availability/context behavior, cancellation latency and interactive UI acceptance remain open for tonight.

## Known issues / follow-up

- Validate actual evidence selectivity, consistency across different phrasing, personal updates and forgotten/archived topics with disposable Chinese/English input.
- Measure background energy, cancellation/draining and responsiveness during repeated real voice input.
- Complete deferred M-002/M-003 microphone, recovery and delivery checks and M-008/M-009 native interaction checks.
- No current CloudKit enrollment/configuration requirement; future sync is a later milestone.

## Issue / PR

No new Issue/PR. Current integration branch is recorded in M-009; initial foundation work used `feature/m-004-memory-foundation`.

## References

- [Product baseline](../product-architecture-baseline.md)
- [M-003](M-003-capture.md)
- [M-009](M-009-macos-input-memory.md)
