# M-016 — Conservative cleanup Memory context

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-016-conservative-cleanup-context`
- **Depends on:** M-004 personal Memory, M-005 cleanup, M-009 integrated input loop
- **Issue / PR:** —

## Why

Cleanup must stay useful even as personal Memory grows. A large or weakly related personal context increases the chance that Foundation Models will borrow historical background that the user did not say in the current utterance.

The previous retriever accepted any single non-stopword overlap between the current text and one Memory name/notes record, and cleanup could receive up to eight records. That is useful for recall but too permissive for a text-rewriting step whose strongest contract is “do not add unspoken background.”

Memory learning and input cleanup therefore should not share the same relevance budget. Learning may inspect a broader bounded profile to detect updates/conflicts; cleanup should receive only a few memories with strong evidence that the current input is about them.

## Scope

- Keep explicit Memory-title mentions as the strongest relevance signal.
- Ignore one weak/common shared term as sufficient cleanup relevance.
- Score shared terms by specificity, length and whether they are unique across active Memory.
- Expand stopwords for generic input/work/project/system terms that should not pull personal facts into cleanup by themselves.
- Limit cleanup to four Memory items.
- Keep learning's broader bounded context unchanged.
- Recheck the same bounded cleanup context after model generation so stale Memory still cannot deliver.
- Strengthen the cleanup prompt: Memory not pointed to by the current input must be ignored.

## Non-goals

- No embedding/vector store.
- No LLM call just to retrieve Memory.
- No semantic output validator after Foundation Models.
- No style learning; Expression Profile is a later task.
- No changes to Dictionary/Speech hint budgets in this slice.
- No cloud or sync work.

## Acceptance criteria

1. Explicit Memory-name references remain retrievable.
2. A distinctive project/person/product term in Memory notes can still retrieve the relevant Memory.
3. Generic single-term overlap such as “功能 / 项目 / 工作 / system / feature” cannot inject personal Memory into cleanup by itself.
4. Cleanup receives at most four relevant Memory items.
5. Memory learning can continue using its broader bounded context for update/conflict detection.
6. The model payload still contains only Memory name/notes text, not IDs, timestamps, source metadata or match scores.
7. Memory edits/archives during generation still invalidate the stale cleanup result.
8. Hosted macOS 27 tests/build pass; real Foundation Models fidelity remains signed-device acceptance.

## Progress

- [x] Tighten lexical Memory relevance and common-term filtering.
- [x] Cap cleanup Memory context at four items.
- [x] Recheck the same cleanup context budget after generation.
- [x] Tell the cleanup model to ignore unreferenced Memory.
- [x] Add focused relevance and context-budget tests.
- [x] Update M-005/M-009/cleanup contract documentation.
- [ ] Pass hosted macOS 27 CI.
- [ ] Validate real-model behavior with relevant and intentionally unrelated Memory records.

## Implementation notes

`MemoryContextRetriever` remains deterministic and local. Exact Memory-name mentions score highest. For indirect matches, each shared term contributes its bounded character length and receives an additional specificity bonus when it appears in only one active Memory. Multiple shared terms can establish relevance even when none is unique. Generic words are filtered before scoring.

`CapturePersonalizer` requests a maximum of four Memory matches for cleanup and uses the same limit when checking snapshot freshness after generation. `MemoryStore.learningInput` intentionally keeps its existing broader profile because that path is analyzing durable personal evidence, not rewriting the user's current text.

This is a retrieval-scope safeguard, not a second semantic validator. Morie still trusts the structured Foundation Models output once source/dictionary/Memory snapshots are current and the returned text is usable.

## Validation

Unit tests cover:

- active/manual Memory retrieval and inactive exclusion;
- native word boundaries;
- distinctive note-term retrieval;
- rejection of generic single-term overlap;
- retrieval limits;
- a full `CapturePersonalizer` request with more than four explicit Memory topics.

Real-device/model acceptance should compare the same utterance with no Memory, directly relevant Memory and intentionally unrelated Memory. The final text must not gain background that was absent from the utterance.
