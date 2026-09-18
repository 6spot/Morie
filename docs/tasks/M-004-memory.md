# M-004 — Personal Memory Foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-18
- **Phase:** Phase 2
- **Starts after:** M-003 establishes reliable Capture persistence
- **Current branch:** `feature/m-004-memory-foundation`, based on M-003 commit `3ce05a4`.
- **Owner sequencing decision:** continue development while M-002/M-003 device validation is deferred until the evening. Those acceptance items remain open; CloudKit remains deferred to final integration.

## Why

Morie's long-term value comes from Personal Context that improves later input. This phase introduces restrained, provenance-aware Memory rather than a general knowledge graph.

## Scope

Planned first-class capabilities:

- Vocabulary;
- Project;
- Relevant Context retrieval;
- Memory Candidate flow;
- provenance from source Capture IDs;
- confidence and user-confirmed state;
- active / superseded / archived lifecycle;
- data-model support for Person, Topic, Decision, Preference, Fact, Open Thread, and Writing Style where useful.

Excluded:

- autonomous agents;
- broad knowledge graph infrastructure;
- cloud Memory service;
- speculative long-running background intelligence.

## Acceptance criteria

1. Captures can produce a small, high-signal set of Memory Candidates.
2. Long-term Memory retains provenance and lifecycle state.
3. Relevant Context retrieval can surface useful Vocabulary/Project context for a new capture.
4. Superseded/archived facts stop polluting active context.
5. Memory creation is selective rather than permanently storing every journal entry as knowledge.

## Progress

The first slice established explicitly confirmed Memory and retrieval. The candidate slice now adds on-demand Apple AI extraction from History, input snapshots and a review loop. M-005 follows with polishing/personalization; device and real-model acceptance remain open.

| Subtask | State | Scope |
| --- | --- | --- |
| Memory schema and store | IMPLEMENTED / VERIFY | Vocabulary/Project, aliases, notes, provenance, confirmation and lifecycle in the existing SwiftData container. Separate Memory write context protects Capture checkpoints from rollback. |
| Native Memory management | IMPLEMENTED / VERIFY | Standard searchable list, detail and editor sheet; explicit saving/linking from History; source inspection and archive/restore/replace/delete. Interactive acceptance is deferred. |
| Relevant Context retrieval | IMPLEMENTED / VERIFY | Native word boundaries and literal name/alias matching; only active confirmed records; deterministic ranking and eight-result cap. History distinguishes related context from linked provenance. |
| Tests and documentation | IMPLEMENTED / PASS | All 65 tests pass: 18 candidate, 16 Memory and 31 Capture/History/audio tests. Native rendering checks layout; device interaction remains open. |
| Automatic Memory Candidates | IMPLEMENTED / VERIFY | Apple on-device extraction requested from History, durable input snapshots, selective suggestions and explicit review. Final text takes precedence; M-005 polished output will feed this same boundary. Real inference quality/latency remains unvalidated. |

## Candidate-slice acceptance criteria

1. History can request a small Vocabulary/Project candidate set through Apple Foundation Models. A successful empty result is valid; candidate extraction never silently creates long-term Memory.
2. Extraction reads durably saved `finalText`, or saved recognized text when no final text exists, and persists the exact input text/type with its result. AI polishing is not implemented in this slice. The owner's 2026-09-18 requirement makes saving polished final text before extraction an explicit M-005 dependency.
3. Candidates retain source evidence and review state across restart. Users can edit and confirm a suggestion, link it to an existing active memory, or dismiss it. Confirmation and Memory persistence are atomic.
4. If the source is changed/deleted while extraction or review is open, stale candidates cannot be saved. Repeated analysis of the same saved text preserves previous review decisions. Deleting a Capture also removes its extraction snapshots; separately confirmed Memory remains.
5. Model unavailability, context limits, failures and cancellation preserve Capture and existing Memory. Starting live input cancels optional extraction without waiting for it before Speech starts. No model content is logged.
6. Use native forms, sheets, progress and review controls; keep real model quality, latency and interaction acceptance open for tonight.

## First-slice acceptance criteria

1. Explicitly saved Vocabulary/Project memory survives restart and never changes the source Capture's recognized/final text or delivery outcome.
2. Source Capture IDs are saved at creation; manual entries are honestly identified as manual. Deleting a Capture does not delete an independently confirmed memory; unavailable sources are shown as such.
3. Empty/invalid entries and duplicate active names within a kind are rejected without silently overwriting memory. Aliases are normalized and deduplicated.
4. Only confirmed active entries participate in retrieval. Archive and replacement remove stale entries immediately, and replacement records its predecessor.
5. Native Memory UI supports creation, editing, source inspection, archive/restore, replacement and explicit deletion. History exposes matching memory and an explicit Save Memory action.
6. Name/alias matching works for Chinese and English, avoids partial Latin-word matches, has deterministic order and a bounded result count. This slice adds no model/network work to live capture or delivery.

## Implementation notes

- Use Apple SwiftData and repository-owned Swift with native SwiftUI controls. There is no schema migration, old-version compatibility layer or external dependency.
- Type4Me's vocabulary command/store tests establish useful case-insensitive deduplication and surfaced-save-error behavior. Its file migration, built-in word lists, snippet routing, cloud hotword sync and external ASR reloads are outside Morie's requirement.
- The explicit editor is a user decision, not an inferred AI confidence score. Candidate extraction is now implemented below; AI polishing and input personalization remain M-005 work.
- Manual memory has `userConfirmed = true` and no model confidence score. Source IDs are checked when saved/linked; recording or empty Captures cannot become sources. Linking is idempotent and never overwrites a memory's name/notes.
- Editing preserves identity and sources. Replacement creates a fresh active entry with the predecessor/source IDs and marks the old record superseded in one save. Archived entries can be restored if the name is available; superseded entries cannot be restored or edited.
- Memory and Capture use the same `ModelContainer` but separate write contexts. Memory rollback cannot erase a pending live Capture checkpoint. No Memory operation changes the source transcript or delivery state.
- Deleting a Capture retains separately confirmed Memory and its source ID; source inspection reports deletion explicitly. Deleting Memory leaves its source Captures and other memories intact.
- Retrieval normalizes case/width/whitespace, respects native word boundaries, and retains meaningful punctuation. It matches Chinese/English names and aliases without matching `Git` inside `GitHub` or `C++` as bare `C`. Canonical matches rank before aliases, longer phrases before shorter ones, then recency/UUID break ties. This is lexical matching and does not infer unstated semantic relevance.
- Related-context computation is skipped while the source Capture is recording. It adds no model/network step, built-in dictionary or speech-provider hotword configuration to live input.

### Candidate implementation

- `MemoryExtractionInput` reads committed final text first; recognized text is used only when final text is empty. The owner's 2026-09-18 decision is recorded in the design/product baselines and M-005: persist AI-polished `finalText` before extraction, preserve `recognizedText`, and retain the actual extraction text. No polishing is claimed in M-004.
- Foundation Models uses `SystemLanguageModel.default`, a fresh session, `@Generable` Vocabulary/Project output, greedy generation, native token/context accounting and a 1,024-token response cap. The complete source is analyzed or refused for size, never silently truncated. Apple guardrails remain enabled.
- Up to three suggestions pass field validation, literal evidence/name checks, explicit-alias checks, deduplication and a finite confidence estimate of 0.8–1.0. The model score is not calibrated confidence in truth. Human review remains mandatory; bad suggestions are dropped and an empty successful result is retained.
- `MemoryExtractionRecord` stores exact source text/type plus candidates and pending/accepted/dismissed states. Repeated analysis of identical saved text reuses the existing result. Changed input gets a separate snapshot; stale suggestions cannot be confirmed. Source deletion removes snapshots while confirmed Memory remains.
- Confirmation, Memory creation/source-linking and the candidate decision use one Memory-context save. An edited proposal clears model confidence; linking never overwrites an existing memory's name/notes. Capture text/delivery is not changed.
- History's explicit extraction action has native progress/cancel and review; current pending suggestions appear in Memory. The same native editor supports editing, linking, saving or dismissing. Both candidate review and saved AI-derived Memory can inspect the extraction snapshot.
- One optional controller task owns inference. Leaving the detail or starting voice input cancels it, and late results recheck cancellation and saved source text. Voice startup does not wait for the model. There is no automatic background extraction in the recording/delivery loop, external service or logged model content.

## Validation evidence

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

- Complete the deferred microphone, History and interruption checks from M-002/M-003 on the owner's signed build.
- Validate Memory editor/navigation with keyboard, VoiceOver and real Chinese/English content.
- Validate real Memory Candidate selectivity/evidence and cancellation behavior on disposable Chinese/English captures.
- Continue with M-005 polishing/personalization. Save polished final text before candidate extraction and retain the original recognized text and extraction snapshot.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- predecessor: [`M-003-capture.md`](./M-003-capture.md)
