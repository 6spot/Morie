# M-035 — Editable concise refinement prompt

## Status

**IN PROGRESS** — 2026-09-20

Issue: [#71](https://github.com/6spot/Morie/issues/71)

## Why

Owner-device testing exposed a prompt-design regression:

`今天一共有三件事需要做第一件事好好上班，第二件事好好吃饭，第三件事好好睡觉`

was refined into only the three numbered items, dropping the spoken lead-in. The current implementation had accumulated three competing control layers:

1. a long `Instructions` document;
2. deterministic `compact / semanticParagraphs / explicitList` classification;
3. another long behavioral contract inside the generated `text` field's `@Guide`.

The result was increasingly brittle: the model could satisfy the forced list shape while losing content that another part of the prompt said to preserve.

## Reference audit

### Apple Foundation Models

Apple's current on-device prompting guidance is the governing constraint:

- prompts should be concise and specific;
- prefer one well-defined goal and direct imperative language;
- one to three paragraphs is a recommended size for an on-device prompt;
- excessive conditional logic can reduce instruction following;
- when a prompt becomes unreliable, simplify it rather than continuing to add emphasis/rules;
- hard-coded prompts are difficult to update because they require an app release; Apple documents text resources/string catalogs/server configuration as prompt-versioning options.

Relevant Apple documentation:

- [Prompting an on-device foundation model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)
- [Instructions](https://developer.apple.com/documentation/foundationmodels/instructions)
- [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions)

### Type4Me

The current Type4Me voice-polish prompt demonstrates useful boundaries: treat ASR text as data, do not answer it, handle restarts/filler and distinguish conversational from structured content. Its current formal-writing prompt also contains stronger behavior Morie intentionally does not inherit: mandatory number conversion, forced summary-plus-list formatting, generated point titles/subitems and transition phrases.

Type4Me's own prompt benchmark history is also useful evidence that smaller direct prompts can be competitive with larger instruction documents.

Decision: **ADAPT the boundary, DROP the stronger rewriting/formatting policy.**

### OpenLess

OpenLess likewise separates the dictation text from the instruction, forbids answering/executing it, preserves uncertain content and supports editable style prompts. Its mature prompt set is substantially broader because it serves multiple styles and technical-agent scenarios.

OpenLess is AGPL-3.0. Morie copies no source or prompt text; only the behavior lessons above are used.

Decision: **ADAPT the content boundary and runtime-editability lesson, DROP style-pack/persona/provider breadth.**

## Design

### 1. One concise default instruction

Morie ships `Morie/Resources/DefaultRefinementInstructions.txt` as the recoverable baseline. It is three paragraphs:

- task/content boundary;
- allowed light edits and protected content;
- semantic paragraphing and logical organization, including preservation of spoken lead-ins/notes/questions/closings around lists.

The instruction deliberately has no product-specific few-shot vocabulary.

### 2. Data stays data

The per-request prompt remains JSON containing only:

- `transcript`;
- transcript-relevant `spellingCandidates`;
- bounded `personalContext`;
- stable `expressionStyle`.

There is no `formattingHint`. The model infers natural layout from the transcript itself.

### 3. Guided generation is schema-only

The local Apple path keeps `@Generable`, but `@Guide` only names the field as the final cleaned body. Behavioral policy is not duplicated there.

### 4. Runtime-editable settings

The effective instruction is loaded once into `RefinementPromptController` process memory when the app starts. Settings exposes a native `TextEditor` with **保存提示词** and **恢复默认**.

- Save replaces the in-memory runtime instruction immediately for later Captures; the hot path never rereads the bundle or `UserDefaults`.
- The same value is persisted only so the next app launch restores it; no rebuild or relaunch is required for testing.
- Restore replaces the in-memory value with the bundled baseline and removes the persisted override so later default-prompt updates can flow through.
- Empty prompts are rejected.
- Apple-local and external OpenAI-compatible refinement use the same instruction.

### 5. Capture-level snapshot

M-032's transaction rule extends to the prompt. `RefinementConfiguration` contains both the model snapshot and instruction snapshot. A Capture freezes it when recording starts. Editing Settings during an in-flight Capture affects only the next Capture.

The external API credential is still resolved lazily at the refinement boundary without changing the frozen prompt.

### 6. Safety after generation

Prompt simplification does not remove deterministic boundaries:

- confirmed dictionary corrections are still applied before the model;
- the generated result must be nonempty and free of invalid control characters;
- longer generated clauses must remain grounded in the prepared transcript;
- dictionary/Memory/expression snapshots must still be current before the result can be committed.

## Acceptance criteria

- [x] Default prompt is a dedicated text resource rather than a hard-coded `InputRefiner` constant.
- [x] Settings can edit/save/restore the effective prompt without a rebuild.
- [x] New Captures snapshot prompt + model together.
- [x] Apple-local and external-model paths use the same snapshotted prompt.
- [x] `formattingHint` and its layout heuristics are removed from the model request.
- [x] `@Guide` no longer duplicates the behavior contract.
- [x] The baseline prompt explicitly preserves a spoken lead-in around an enumerated list.
- [x] The baseline prompt asks for semantic paragraphing at topic/intent/stance/stage boundaries instead of length-based splitting.
- [x] The baseline prompt asks the model to expose logical relations already present in the transcript (parallel, sequence, cause/effect, contrast, condition, whole-to-parts) without inventing new reasoning.
- [ ] macOS 27 product compile passes in CI.
- [ ] deterministic MorieTests pass in CI.
- [ ] Owner-device Apple Foundation Models smoke test confirms the reported three-item example retains its lead-in.
- [ ] Owner-device long conversational/technical samples confirm the smaller prompt does not regress meaning, punctuation or safe ASR correction.

## Validation notes

Automated tests cover prompt persistence/reset, helper-data serialization, absence of `formattingHint`, concise baseline rules and propagation of the frozen `RefinementConfiguration` through the runner. They do not establish semantic quality of the Apple system model; that remains a supported-device acceptance item.
