# M-036 — Semantic personal Memory and lifecycle

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#75](https://github.com/6spot/Morie/issues/75)

## Why

Owner testing found that the existing Personal Memory was technically elaborate but practically weak. Automatic learning extracted many small fact records, generated `name` was then reused as a pseudo semantic key, recurring evidence required near-identical drafts, updates depended on local keyword heuristics, and cleanup retrieval remained mostly lexical. The visible result could look like a Memory system without producing useful durable understanding.

The owner approved a different boundary:

- Memory should behave as a small semantic profile/topic store, not a flat log of isolated facts.
- Long-lived information and temporary working context are both useful, but they need different lifecycle behavior.
- The model should decide semantics; code should own lifecycle, provenance, user precedence, durability and bounded resource use.
- Internal storage may keep atomic evidence, but the user-facing page should not expose database taxonomy such as long-term vs working-context categories.
- A Personal Memory switch is required.
- Cleanup's broader Memory-use policy is intentionally a follow-up after the new Memory layer is stable.

## Scope

- Add a default-on **使用个人记忆** setting.
- When disabled:
  - do not analyze new completed input;
  - durably mark disabled-period input as skipped so re-enabling does not backfill it;
  - do not inject existing Memory into cleanup;
  - retain existing Memory and evidence for inspection.
- Upgrade one visible Memory record into a semantic topic/entity body with an internal `longTerm` or `workingContext` scope.
- Add independent evidence records retaining exact source text, supporting quote, Capture ID and evidence time.
- Ask Foundation Models to classify:
  - long-term vs working-context;
  - create / merge / update / reinforce;
  - semantic existing-memory identity by UUID from supplied context.
- Remove local semantic heuristics such as update-keyword detection, personal-pronoun requirements and exact repeated-draft accumulation.
- Keep deterministic safeguards for source freshness, exact evidence grounding, user edits, archive/delete, atomic save and input preemption.
- Give working context a deterministic 30-day lifetime refreshed by supporting evidence; model-directed promotion to long-term removes expiry.
- Supply user-archived/deleted topics to the model as protected context; keep a structural exact-match guard as a final deterministic safety net.
- Keep the current cleanup retriever otherwise unchanged for this task.

## Non-goals

- No vector database, embeddings dependency or third-party retrieval runtime.
- No broader cleanup prompt/context redesign; that follows after M-036.
- No hidden reuse of the user's external refinement API for Memory learning. M-036 remains Apple-local so enabling an external cleanup provider does not silently send daily Memory-learning input to it.
- No migration layer for the superseded development schema. A fresh current-schema development store is required after this persisted-model change.

## Design

### Semantic topic + evidence

`MemoryRecord` remains the visible/current topic body. It now carries an internal scope and optional expiry. `MemoryEvidenceRecord` is separate and records exact evidence independently from the current topic body.

This allows one topic such as Morie to absorb multiple supporting inputs instead of creating one visible record per claim, while still preserving the source trail.

### Model semantics, code policy

`MemoryLearner` receives the saved source, a bounded set of current active Memory snapshots and protected deleted/user-archived topics. The model chooses semantic topic identity and proposes one of:

- `create`
- `merge`
- `update`
- `reinforce`

Code does not re-decide semantic meaning. It verifies that evidence is an exact source substring, supplied UUIDs refer to unchanged active snapshots, user-authored bodies are not overwritten, and writes remain atomic.

### Lifecycle

- `longTerm`: no automatic expiry.
- `workingContext`: 30-day expiry from its most recent evidence.
- New evidence refreshes working-context expiry.
- A model-proposed merge/update may promote working context to long-term.
- Expired working context is archived internally and can be re-created later if it becomes relevant again.
- Explicit user archive/delete is protected from automatic recreation.

### UI

The Memory page stays a flat natural reading surface. It does not display the internal scope taxonomy. Internal `kind` selection is also removed from the manual editor; manual entries become durable user-authored Memory. The detail page exposes evidence/source history because provenance is useful user control, not because the storage schema should be visible.

## Acceptance criteria

- [x] Personal Memory has a default-on runtime setting.
- [x] Disabled-period Captures are not learned or silently backfilled later.
- [x] Cleanup receives no Memory context while the setting is off.
- [x] Semantic writer actions use model-selected existing UUIDs rather than generated title equality.
- [x] Local update-keyword and personal-reference semantic heuristics are removed.
- [x] Evidence is persisted separately from the current visible Memory body.
- [x] Working context expires deterministically, refreshes on evidence and can promote to long-term.
- [x] User edits/archive/delete outrank automatic learning.
- [x] Visible Memory UI does not expose long-term/working-context categories.
- [x] macOS 27 logic-test CI passes.
- [x] macOS 27 app compile CI passes.
- [ ] Owner-device Foundation Models testing confirms useful create/merge/update/scope decisions on real daily input.
- [ ] Cleanup Memory retrieval/use is redesigned as the explicit follow-up.

## Validation notes

Deterministic tests cover storage/restart, evidence survival, disabled-period skip semantics, stale-source rejection, semantic merge by existing UUID, keyword-free update admission, user edit precedence, working-context refresh/expiry/promotion, protected delete/archive context, atomic failure, retry/backoff and input preemption.

Hosted macOS 27 CI run [35486727249](https://github.com/6spot/Morie/actions/runs/35486727249) passed both gates after the working-context fixture was corrected to use a current evidence date: the Release product compile succeeded and **143 logic tests passed with 0 failures / 0 unexpected failures**. The initial test run correctly exposed that a 1970-dated fixture had already expired under the new lifecycle policy; no product workaround was added.

Model quality is not established by injected suggestions. Real Foundation Models behavior remains device acceptance.

## Development data

M-036 changes persisted SwiftData shapes and adds `MemoryEvidenceRecord`. Morie's development-stage policy intentionally provides no old-schema migration. Before launching the signed owner app against an existing development database, preserve the existing verified backup if it is still needed and initialize a fresh current-schema development store using the documented reset process.

## Follow-up

After M-036 is stable, redesign cleanup Memory retrieval and prompt constraints so the richer semantic Memory is actually useful during input without allowing unspoken background to leak into the final text.
