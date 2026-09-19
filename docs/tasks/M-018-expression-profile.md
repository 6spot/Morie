# M-018 — Expression Profile

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-018-expression-profile`
- **Depends on:** M-005 cleanup, M-009 integrated input loop, M-014 current-focus delivery, M-016 conservative context
- **Issue / PR:** —

## Why

Personal Memory describes what the user knows, prefers or is working on. It should not become a dumping ground for writing-style observations such as sentence length, paragraph frequency or Chinese/English spacing.

The owner wants Morie to learn how the user actually edits its output. The strongest signal is therefore a bounded edit to text Morie just inserted, not a model guess about style.

Type4Me's current Expression Profile implementation validates this direction: aggregate style features can be learned separately from semantic Memory, with explicit learning states and minimum evidence before a preference affects future output. Morie adapts the concept with a much smaller first slice.

## Scope

- Add a local Expression Profile data model separate from Personal Memory and Dictionary.
- Reuse one bounded post-insertion observer for both dictionary suggestions and style learning.
- Observe only the verified Morie-inserted range in the currently focused non-secure text field.
- Learn only edits that keep lexical content unchanged after ignoring punctuation, whitespace and structural list markers.
- Persist aggregate features only; do not persist edited source text as profile data.
- Initial features:
  - average sentence length;
  - line-break density;
  - list usage;
  - terminal punctuation usage;
  - exclamation usage;
  - Chinese/English spacing.
- Require at least 5 samples before a feature leaves insufficient state and at least 10 samples spanning 3 days before stable style can affect cleanup.
- Send at most four stable directives to Foundation Models.
- Persist the actual directives used in each `RefinementInput` so History provenance remains exact.
- Add a default-off native Settings toggle and explicit profile reset.

## Safety and privacy boundaries

- No global keyboard monitoring.
- No arbitrary document scan.
- No secure text fields or Secure Event Input.
- Terminal/iTerm/Keychain remain excluded from post-insertion observation in this first slice.
- Leaving the anchored field, starting another recording or exceeding the 30-second observation window ends observation.
- Word/content/number changes are not Expression Profile evidence.
- Dictionary corrections remain dictionary evidence and do not become style evidence.
- Expression directives cannot override current meaning, tone, explicit structure, negation, numbers or other semantic content.

## Acceptance criteria

1. A punctuation/line-break/list/spacing-only user edit can become aggregate style evidence.
2. A lexical, factual, numeric or word-correction edit cannot become Expression Profile evidence.
3. Fewer than 10 samples or evidence spanning fewer than 3 days produces no stable cleanup directive.
4. Stable profile directives are limited to four and appear in the cleanup payload/provenance only when Expression Profile is enabled.
5. Disabling Expression Profile stops both observation and use of existing directives.
6. Clearing Expression Profile removes aggregate style learning without deleting History, Dictionary or Personal Memory.
7. Starting a new recording stops the previous post-insertion observer.
8. Existing dictionary suggestion behavior remains opt-in and uses the same bounded observer without changing one-word dictionary semantics.
9. Hosted macOS 27 tests/build pass. Actual Accessibility field coverage and Foundation Models style fidelity remain signed-device acceptance.

## Progress

- [x] Add aggregate Expression Profile model/store.
- [x] Add conservative style-only feature extraction.
- [x] Require repeated multi-day evidence before stable directives.
- [x] Persist stable directives with cleanup provenance.
- [x] Replace dictionary-only post-insertion observer with one shared bounded learning controller.
- [x] Add native Settings toggle/reset controls.
- [x] Add focused extraction/store/cleanup integration tests.
- [x] Update architecture/UI/cleanup/reference documentation.
- [ ] Pass hosted macOS 27 CI.
- [ ] Validate real post-insertion observation and stable-style effects on the signed app.

## Implementation notes

`ExpressionStyleExtractor` admits an edit only when a case/width-folded alphanumeric projection is unchanged after structural list markers are removed. This intentionally rejects wording, spelling, number and factual edits. It means the first version learns presentation, not vocabulary or semantic preference.

`ExpressionProfileStore` uses the existing SwiftData container. Development-stage schema changes are applied directly; there is no migration or pre-upgrade backup layer. The profile stores only aggregate measurements/evidence counts.

`PostInsertionLearningController` supersedes the earlier dictionary-only controller. It retains the same short Accessibility messaging timeout and verified inserted-range anchor, then independently feeds:
- explicit word corrections to the existing dictionary confirmation prompt;
- stable style-only edits to Expression Profile.

The first slice is global rather than per-app. Current-focus delivery intentionally resolves the target only at paste time, and app-specific style scopes are not necessary to prove the basic value. They can be reconsidered after real usage evidence.

## Reference decision

From Type4Me current `ExpressionProfileStore.swift` / `UserEditObservation.swift`:

- **ADAPT:** separate semantic Memory from aggregate expression habits; learn from actual post-insertion edits; use insufficient/learning/stable states; require repeated evidence; keep reset control.
- **ADAPT:** sentence length, line breaks, list usage, terminal punctuation, exclamation and Chinese/English spacing as low-risk presentation features.
- **DROP:** per-app/category scopes, raw user-edit history rebuild machinery, accepted-unchanged weak evidence, complex decay/migration logic, sensitive-content subsystems tied to Type4Me runtimes, and broad output guards.
- **MORIE-SPECIFIC:** admit only edits with unchanged lexical content, persist no edited raw text, and apply no style directive until it is stable.

## Validation

Hosted tests can establish deterministic extraction, aggregation, reset, prompt serialization and persistence. They cannot prove that AX exposes the expected inserted range in every editor or that stable directives improve real Foundation Models output without changing meaning. Those remain interactive acceptance items.
