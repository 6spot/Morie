# M-011 — Save a single dictionary word

> **M-013 amendment (2026-09-19):** Dictionary now uses one full content page beside the management sidebar rather than list + detail columns. Selection-scoped edit/delete actions stay with the list, and the removed detail surface no longer explains source or update time. See [M-013](M-013-control-center.md).

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-013-control-center`
- **Depends on:** M-009 dictionary/input and M-010 Chinese native UI.
- **Issue / PR:** —

## Why

The owner clarified that adding a dictionary entry should require only one word. Asking for a correct spelling and replacement aliases makes a simple vocabulary feature unnecessarily complicated. This decision supersedes the explicit-alias design in M-009.

## Scope

- A compact native add/edit sheet containing one **词语** field.
- Word-only storage, search, detail and retained processing snapshots; remove alias configuration and replacement semantics directly.
- Keep native Speech hints and normalize only the same word's letter case to its saved spelling, independently of optional AI cleanup.
- Keep explicit **加入字典** confirmation after a supported manual correction; save just the corrected word.
- Update current product/task documentation and verify compilation, persistence, input fallback and native layout.

## Exclusions

Fuzzy or inferred substitutions, unconditional homophone replacement rules, personal-Memory changes, general keyboard observation, iOS, CloudKit, external dependencies, schema migrations, legacy decoding and automatic data resets. Existing intentional input remains protected.

## Acceptance criteria

1. Add/edit requires only a word, with native initial focus, Return to save and Escape to cancel. Empty/invalid/duplicate entries cannot overwrite saved words; errors remain visible in the editor.
2. Stored entries and processing snapshots contain no alias rules. Search, list/detail and History expose the saved word only.
3. Words supply bounded native Speech hints. Post-recognition normalization affects only letter-case variants of the same whole word and preserves unrelated words, names, full-/half-width spelling and technical spans. Morie never invents a candidate or turns a previous error into an unconditional replacement rule.
4. Optional cleanup failure/disablement keeps usable saved text; dictionary changes invalidate stale results. Final text and processing evidence are saved before insertion and learning.
5. A fresh temporary store passes separate-process write/read. Any check of current development data uses an isolated consistent copy; no production data or backup is reset.
6. App compilation, relevant logic tests and isolated native layout checks pass. Signed-app keyboard/VoiceOver, actual Speech benefit and correction focus behavior remain open until exercised.

## Progress

- [x] Record the owner's one-word dictionary decision.
- [x] Simplify native dictionary UI and word storage/processing.
- [x] Update current design, architecture and validation documentation.
- [x] Complete isolated build, logic, cold-open and layout verification.
- [ ] Complete deferred signed-app acceptance.

## Implementation notes

The native sheet uses a columns Form with one **词语** field and **取消 / 添加** (or **保存**). FocusState, native default/cancel keyboard actions, empty-input disablement and inline error feedback keep the interaction compact. Search, list/detail and History show words only.

`DictionaryDraft`, `DictionaryEntry` and `DictionarySnapshot` no longer contain aliases. Duplicate validation is case-insensitive but does not equate full-/half-width spelling; internal control characters and line separators are invalid. `DictionarySpelling` applies same-word letter-case normalization before optional cleanup, protects technical spans and gives longer names precedence even when already spelled correctly. Correction confirmation saves through the same single-word store.

Each capture loads the current bounded word list into macOS 27 `AnalysisContext.contextualStrings`. Result text and its native whitespace are appended verbatim; Morie does not insert separators between Apple's finalized segments. This prevents Chinese output such as **常 蚊 子** while preserving spaces Apple actually emitted.

The separate non-autosaving dictionary write context and Capture-first save ordering remain. No schema migration, legacy decoding, replacement-rule adapter or automatic data reset was added. Word-correction observation remains independently opt-in and bounded to a verified recent Morie insertion.

## Reference decisions

- **ADAPT:** native Speech contextual strings; Type4Me's direct, separator-free composition of recognized segments; duplicate/save-error handling and action-time provenance audited in [Type4Me](../reference/type4me.md); explicit one-word confirmation from the [OpenLess behavior reference](../reference/openless.md).
- **DROP:** canonical-word/alias configuration, provider hotword machinery, global homophone replacement tables and cross-entry alias conflicts. They are unnecessary or unsafe for the owner's word-only dictionary.
- **VERIFY:** on a signed macOS 27 device, actual contextual-string benefit for spoken **长文字吧**, separator-free Chinese output and native focus/keyboard/VoiceOver behavior. Automated tests cannot establish model behavior.

## Validation evidence

2026-09-18, macOS 27 / Xcode 27, arm64, Swift 6. Isolated artifacts: `/tmp/morie-simple-dictionary.HMTVJ7`.

- **App Debug build passed**, with signing disabled and separate DerivedData: `build.log`.
- **100 logic tests passed**, 0 failures/skips/runtime warnings, confirmed by `xcresulttool get test-results summary`: `Tests.xcresult`; log `test.log`. Dictionary coverage now checks word-only persistence, normalized duplicates, invalid-word preservation, bounded hints, whole-word/technical protection and overlapping terms. Personalization fixtures verify the same durable ordering, fallback and stale-dictionary rejection using single words; an unknown word still cannot be rewritten merely because another word is saved.
- **Separate-process persistence passed.** Current sources seeded a fresh store with one word and four Captures spanning absent, completed, dictionary-backed and interrupted refinement, then opened it twice in independent processes. A pre-change synthetic fixture containing alias fields also opens directly with the new sources; retained Capture text, edits, word snapshots and metadata hashes match. Evidence: `PersistenceProbe.swift`, `fresh-*.log`, `prior-*.log` and `probe-*-compile.log`.
- A consistent SQLite backup of the current development database was opened with both source revisions in isolation. Its one Capture, zero dictionary/Memory/analysis entries and retained evidence hashes match. Logs: `development-before-inspect.log` / `development-current-inspect.log`. The active database, recordings, prior verified backup and signed application were not modified. No reset is needed for this change.
- **Six native fixtures rendered and inspected:** add, edit, duplicate error, long word/save error, populated list/detail and empty dictionary. Each editor contains exactly one native editable field. Content measures 420 × 175 points normally and 420 × 206 with the tested errors; long words remain in the native horizontally scrolling text field. Evidence: `preview/rendered/`, `preview/render.log`, `preview/DictionaryPreview.swift` and `preview/compile.log`.
- Fixtures use in-memory stores, synthetic words, a no-op logger, temporary presentation state and prohibited activation. No visible window, product bootstrap, model, microphone, TCC action, clipboard or AX observation was used. Bitmap caching establishes content/layout, not native materials, focus or VoiceOver acceptance.
- `git diff --check` and repository documentation-link checks passed. No product dependency was added.

2026-09-19 Type4Me recognition follow-up inspected upstream `cc56207b46a30c4c6bf7af0c04b48cc44d06ffc4`. Its Apple client deliberately ignores shared hotword options and composes recognized segments without adding separators; external providers alone send hotwords/keyterms to provider-native APIs. Morie therefore retains current native contextual strings, removes its unproven alternative-candidate experiment, and adapts separator-free segment composition.

- **104 logic tests passed**, 0 failures/skips/runtime warnings. New coverage proves Chinese pieces `常` + `蚊` + `子` become `常蚊子`, while an Apple-owned English boundary `hello ` + `world` remains `hello world`. Dictionary coverage proves full-width `ＭＯＲＩＥ` is neither a duplicate of nor rewritten to `Morie`. Result: `/tmp/morie-type4me-fix.CWLFDW/Logs/Test/Test-MorieTests-2026.09.19_07-12-09-+0800.xcresult`.
- **App Debug build passed** with signing disabled and isolated DerivedData at `/tmp/morie-type4me-fix.CWLFDW`. The AppIntents metadata tool emitted its existing no-framework warning; there were no compiler errors.

## Known issues / follow-up

Implementation and available isolated validation are complete. The earlier device-validation deferral remains in effect. Keep this task open until [the signed-app word-entry and recognition checks](../validation.md#m-011-single-word-dictionary) pass; no device or model acceptance is inferred from compilation or offscreen layouts.
