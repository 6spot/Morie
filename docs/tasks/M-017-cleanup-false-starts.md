# M-017 — False-start and restart cleanup

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-017-cleanup-false-starts`
- **Depends on:** M-005 cleanup, M-015 native dictation punctuation, M-016 conservative Memory context
- **Issue / PR:** —

## Why

Natural dictation often contains a partial clause that the speaker abandons and immediately restarts. Morie's earlier prompt handled explicit corrections such as “不对 / 周四”, and handled stutters, but did not state the broader restart case clearly enough.

Examples include:

- beginning one sentence shape, stopping, then restating the same idea completely;
- saying “算了 / 我重新说 / let me rephrase” and replacing the unfinished clause;
- changing syntactic structure without changing the intended meaning.

Keeping both halves produces awkward duplicated text; deleting too aggressively can lose independent meaning. The model needs a general semantic rule rather than a mechanical adjacent-repeat rule.

## Scope

- Treat clearly abandoned half-sentences as removable spoken-language noise when a later complete clause replaces the same thought.
- Treat clear mid-sentence restarts as self-correction even when the replacement is not word-for-word.
- Preserve both clauses when they carry independent information or the replacement relationship is uncertain.
- Continue preserving uncertainty, alternatives, conditions, negation and intentional emphasis.
- Make the cleanup role explicitly support Chinese, English and mixed-language input.
- Keep the existing no-expansion/no-answer/no-translation boundary.

## Non-goals

- No local regex for filler/restart deletion.
- No mechanical edit-distance or duplicated-clause detector.
- No forced rewriting into formal prose.
- No Type4Me number normalization or mandatory list formatting.
- No Expression Profile yet.

## Acceptance criteria

1. A clear abandoned fragment followed by a complete restart may reduce to the final complete clause.
2. Two clauses that merely repeat a noun or share wording must both remain when each carries meaning.
3. Explicit uncertainty and alternatives remain intact.
4. English and mixed-language input follow the same light-edit contract rather than being treated as Chinese-only.
5. Existing Dictionary/Memory/punctuation protections remain unchanged.
6. Hosted macOS 27 tests/build pass; real Foundation Models behavior remains device acceptance.

## Progress

- [x] Generalize the cleanup role to Chinese, English and mixed-language input.
- [x] Add abandoned-fragment and sentence-restart guidance.
- [x] Add the preservation rule for independent clauses and uncertain replacement.
- [x] Add focused prompt/acceptance coverage.
- [x] Record the Type4Me concept-level reference decision.
- [ ] Pass hosted macOS 27 CI.
- [ ] Validate real-model false-start cleanup against independent-clause counterexamples.

## Reference decision

Type4Me's current Voice Polish prompt explicitly handles abandoned half-sentences and sentence restarts as self-correction. Morie adapts that narrow spoken-language lesson only. Its aggressive number normalization, count correction, generated headings, transitions and mandatory list structure remain excluded.
