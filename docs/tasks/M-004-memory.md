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

The first slice is an explicit, user-confirmed Memory loop: create Vocabulary/Project entries from a saved Capture or the Memory section; preserve provenance; edit/archive/replace them; and retrieve active context for a Capture. Automatic candidate extraction follows this foundation.

| Subtask | State | Scope |
| --- | --- | --- |
| Memory schema and store | IMPLEMENTED / VERIFY | Vocabulary/Project, aliases, notes, provenance, confirmation and lifecycle in the existing SwiftData container. Separate Memory write context protects Capture checkpoints from rollback. |
| Native Memory management | IMPLEMENTED / VERIFY | Standard searchable list, detail and editor sheet; explicit saving/linking from History; source inspection and archive/restore/replace/delete. Interactive acceptance is deferred. |
| Relevant Context retrieval | IMPLEMENTED / VERIFY | Native word boundaries and literal name/alias matching; only active confirmed records; deterministic ranking and eight-result cap. History distinguishes related context from linked provenance. |
| Tests and documentation | IMPLEMENTED / PASS | 16 new Memory tests and all 31 prior tests pass. Offscreen native UI rendering checks layout; device interaction remains open. |
| Automatic Memory Candidates | TODO | Selective Apple-native extraction and explicit review, after the manual foundation. |

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
- The explicit editor is a user decision, not an inferred AI confidence score. Automatic candidate extraction and input personalization are not claimed complete by this slice.
- Manual memory has `userConfirmed = true` and no model confidence score. Source IDs are checked when saved/linked; recording or empty Captures cannot become sources. Linking is idempotent and never overwrites a memory's name/notes.
- Editing preserves identity and sources. Replacement creates a fresh active entry with the predecessor/source IDs and marks the old record superseded in one save. Archived entries can be restored if the name is available; superseded entries cannot be restored or edited.
- Memory and Capture use the same `ModelContainer` but separate write contexts. Memory rollback cannot erase a pending live Capture checkpoint. No Memory operation changes the source transcript or delivery state.
- Deleting a Capture retains separately confirmed Memory and its source ID; source inspection reports deletion explicitly. Deleting Memory leaves its source Captures and other memories intact.
- Retrieval normalizes case/width/whitespace, respects native word boundaries, and retains meaningful punctuation. It matches Chinese/English names and aliases without matching `Git` inside `GitHub` or `C++` as bare `C`. Canonical matches rank before aliases, longer phrases before shorter ones, then recency/UUID break ties. This is lexical matching and does not infer unstated semantic relevance.
- Related-context computation is skipped while the source Capture is recording. No model, network request, built-in dictionary or speech-provider hotword configuration is introduced.

## Validation evidence

- Isolated Xcode 27 Debug app build passed: `/tmp/morie-memory-build.SjRXpL/final-build.log`.
- All **47 tests passed, 0 failed, 0 skipped**, confirmed with `xcresulttool get test-results summary` for `/tmp/morie-memory-tests.aceKML/FinalMemoryTests.xcresult`; log `/tmp/morie-memory-tests.aceKML/final-tests.log`. The 16 new Memory tests cover restart/provenance, no automatic promotion, name/alias validation and conflicts, source readiness/linking/deletion, edits, archive/restore/replacement, bounded Chinese/English retrieval and choosing the most specific matching alias. Existing 31 Capture/History/audio tests still pass with the expanded schema.
- Native UI was rendered offscreen using synthetic records and a temporary store at `/tmp/morie-memory-preview.DTPfub/verified/`: Memory list, detail, multiline editor, Save Memory from Capture sheet and Capture-memory section. Harness: `/tmp/morie-memory-preview.DTPfub/MemoryPreview.swift`; log: `/tmp/morie-memory-preview.DTPfub/verified-preview.log`. The native toolbar exposes status/New Memory/search and Edit/Delete. This checks layout only; no visible window, microphone, clipboard access, production database or product log was used.
- Device interaction remains pending tonight per the owner. This evidence does not complete M-004 or the earlier M-002/M-003 acceptance matrix.

## Known issues / follow-up

- Complete the deferred microphone, History and interruption checks from M-002/M-003 on the owner's signed build.
- Validate Memory editor/navigation with keyboard, VoiceOver and real Chinese/English content.
- Follow with selective Memory Candidate extraction, then M-005 personalization quality/latency work.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- predecessor: [`M-003-capture.md`](./M-003-capture.md)
