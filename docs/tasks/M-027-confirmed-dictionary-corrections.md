# M-027 — Confirmed Dictionary Corrections

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#35](https://github.com/6spot/Morie/issues/35)  
Pull request: [#36](https://github.com/6spot/Morie/pull/36)

## Goal

Stop repeating ASR mistakes the user has already explicitly corrected, without polluting the visible Dictionary with every historical misrecognition.

## Design

Morie keeps three separate responsibilities:

```text
1. canonical Dictionary words
   Issues / GitHub / 总览
          ↓ Speech contextual hints

2. confirmed correction mappings
   Athers → Issues
   总版   → 总览
          ↓ deterministic pre-cleanup repair

3. Foundation Models cleanup
          ↓ semantic cleanup / punctuation / paragraphing
```

Canonical words remain the only normal Dictionary rows. Confirmed aliases are internal learning data.

## Learning flow

The existing post-insertion observer already anchors to the exact text Morie inserted and only inspects a short-lived bounded edit window. The existing `DictionaryCorrectionDetector` rejects broad/non-word edits.

When the detector sees a stable candidate, the confirmation UI now says **记住这次纠错？** and shows the relation:

```text
Athers → Issues
```

On confirmation:

- if `Issues` does not yet exist, add it as a user correction word;
- save/update `Athers → Issues` as a confirmed rule;
- if `Issues` is already a user word or system built-in, do not create a duplicate canonical row;
- do not show `Athers` as a Dictionary row.

## Runtime application

`CapturePersonalizer` snapshots up to 100 recent correction rules / 2,000 combined characters, matching the bounded-dictionary philosophy.

Exact confirmed mappings run before optional AI cleanup, so they still work when Foundation Models is disabled, busy or unavailable. The prepared text then receives ordinary canonical spelling normalization.

Confirmed relations remain part of `RefinementInput` provenance/staleness checks, but after the 2026-09-19 cleanup-leakage finding they are no longer serialized into the Foundation Models prompt. Exact confirmed mappings are applied deterministically before AI cleanup; this avoids turning historical wrong/correct word pairs into generation vocabulary.

## Safety

- no learning without explicit user confirmation;
- no arbitrary document monitoring;
- no paragraph-level replacement rules;
- protected code, URL, path and identifier ranges are never deterministically rewritten;
- one observed form maps to one current canonical replacement;
- later explicit confirmation can update that mapping;
- deleting a user canonical word removes aliases targeting it;
- no imported giant typo table from Type4Me/OpenLess/another ASR provider.

## Acceptance criteria

- [x] Existing canonical words no longer suppress learning of an observed wrong form.
- [x] A mapping may target a system built-in without creating a duplicate user row.
- [x] Missing canonical replacement is added as a correction-sourced user word.
- [x] Exact mappings apply before optional AI cleanup.
- [x] Correction provenance is carried in `RefinementEdit.correctionRuleID`.
- [x] Confirmed mappings are applied before cleanup and retained as provenance; they are intentionally excluded from the model prompt after the cleanup-leakage follow-up.
- [x] Mapping changes participate in refinement staleness checks.
- [x] Visible Dictionary remains canonical-word only.
- [x] macOS 27 Release product compile passes.
- [ ] Dictionary/Personalization logic tests execute in a test-capable validation session.
- [ ] Owner device confirms one learned real correction is applied on a later dictation.

## First real validation target

The owner has already observed Apple Speech producing wrong technical/semantic forms such as `Athers` for `Issues` and `总版` for `总览`. The next time one of these is manually corrected after Morie inserts it, the confirmation should retain the full relation; a later matching recognition should be repaired before Foundation Models.

## Validation

GitHub Actions `macOS 27 CI` run #91 passed the Release product compile on Xcode 27/macOS 27 for the branch head containing the full M-027 implementation and task documentation.

The hosted workflow still does not execute the MorieTests logic target. The new Dictionary/Personalization regression tests are present but remain an explicit test-capable validation item.
