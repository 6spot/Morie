# M-015 — Native dictation punctuation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-015-native-dictation-punctuation`
- **Depends on:** M-002 Speech foundation, M-005 cleanup, M-014 current-focus input
- **Issue / PR:** —

## Why

The owner observed that punctuation between spoken clauses is sometimes missing even when the words are recognized correctly. Morie's previous live path used the general-purpose `SpeechTranscriber(.progressiveTranscription)`. Final and volatile result segments were concatenated exactly as Apple emitted them so Morie would not introduce bad Chinese spaces such as “常 蚊 子”, but that also means Morie cannot recover punctuation that the recognizer never emitted.

Apple's current `DictationTranscriber` is the native module intended to behave like system dictation. Its `.progressiveLongDictation` preset keeps volatile live results and enables punctuation; `.longDictation` does the same for saved-audio transcription without live volatile updates.

Morie should use the Apple layer best aligned with the product instead of guessing punctuation between Speech result segments.

## Scope

- Replace the live general-purpose Speech transcriber with `DictationTranscriber(.progressiveLongDictation)`.
- Keep the existing `SpeechAnalyzer`, single microphone data output, `AnalyzerInputConverter`, source-audio stream and session ownership.
- Keep dictionary contextual strings on the same analyzer.
- Use `DictationTranscriber(.longDictation)` for History re-recognition.
- Concatenate native result text exactly; do not insert spaces, commas or periods between result segments in Morie.
- Keep Foundation Models cleanup as the second punctuation pass when native dictation still misses a boundary.
- Gate locale support against `DictationTranscriber`, the module Morie actually uses.

## Explicit non-goals

- No local punctuation heuristic or regex sentence splitter.
- No pause-duration punctuation inference.
- No app-specific Speech behavior.
- No legacy Speech fallback.
- No cloud ASR or external dependency.
- No compatibility layer for earlier Speech behavior or old development data.

## Acceptance criteria

1. Live input uses Apple's punctuated progressive long-dictation preset.
2. History re-recognition uses Apple's punctuated long-dictation preset.
3. Native punctuation survives final/volatile segment assembly unchanged.
4. Chinese segments do not gain Morie-inserted spaces.
5. Dictionary hints still reach the analyzer and remain optional.
6. Cleanup still receives the resulting transcript and can add missing semantic punctuation without inventing meaning.
7. Setup checks the locale capability of DictationTranscriber.
8. Hosted macOS 27 compilation/tests pass.
9. Real-device validation covers several clauses, questions, long pauses, long dictation and Chinese/English mixed input.

## Progress

- [x] Switch live Speech to `DictationTranscriber(.progressiveLongDictation)`.
- [x] Switch saved-audio re-recognition to `DictationTranscriber(.longDictation)`.
- [x] Gate supported locale using DictationTranscriber.
- [x] Keep result assembly separator-free and add punctuation-preservation assertions.
- [x] Update cleanup/architecture/validation documentation.
- [ ] Pass hosted macOS 27 CI.
- [ ] Validate punctuation quality on the signed owner build.

## Design notes

Apple documents `DictationTranscriber.Result` as an ordered phrase or passage. With volatile results enabled, the same phrase may be emitted repeatedly until finalized. Morie therefore preserves Apple's text exactly and retains its existing final + latest-volatile accumulation behavior. It does not guess a separator from result boundaries.

The native dictation pass and Foundation Models cleanup have different responsibilities:

```text
microphone
  → DictationTranscriber
      words + first-pass native punctuation
  → Dictionary spelling context
  → Foundation Models cleanup
      semantic punctuation + restrained spoken-language cleanup
  → current keyboard focus
```

The second pass remains necessary because punctuation is semantic: even a dictation-oriented ASR can miss clause/question boundaries in noisy, rapid or ambiguous speech.

## Development data and backup decision

No local automatic-backup feature is introduced. During development, schema or behavior changes may discard obsolete local development data instead of adding migrations or pre-upgrade backups solely to preserve test data.

The intended later product feature is optional iCloud/CloudKit sync/backup after the single-Mac data model and Expression Profile settle.

## References

- Apple DictationTranscriber preset documentation: https://developer.apple.com/documentation/speech/dictationtranscriber/preset
- Apple progressiveLongDictation documentation: https://developer.apple.com/documentation/speech/dictationtranscriber/preset/progressivelongdictation
- Apple DictationTranscriber.Result documentation: https://developer.apple.com/documentation/speech/dictationtranscriber/result
- Cleanup contract: [../input-cleanup.md](../input-cleanup.md)
- Validation: [../validation.md](../validation.md)
