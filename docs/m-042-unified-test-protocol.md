# M-042 Unified Input-Pipeline Test Protocol

This protocol is the development baseline for context-aware dictation. Do not
change multiple pipeline behaviors while collecting a baseline.

## Preconditions

- Run a Debug build from the current branch.
- Verify Overview shows the expected Git commit and `Debug`.
- Do not add test terms to Dictionary.
- Keep the target app and visible page unchanged during one Capture.
- After each Capture, filter Diagnostics by its eight-character Capture ID and
  copy the filtered trace.

## Trace order

A healthy Capture should be reconstructable in this order:

1. `Dev/HotkeyEvent` / `Dev/Hotkey`
2. `Dev/Capture` and `Dev/Stage`
3. `Dev/Persistence` begin
4. `Dev/AudioSource` / `Dev/AudioStream` / `Dev/AudioEvidence`
5. `Dev/AX`
6. `Dev/ApplicationContext`
7. `Dev/Vocabulary`
8. `Dev/SpeechContext`
9. `Dev/SpeechLive`
10. `Dev/Speech`
11. `Dev/AccurateSpeech`
12. `Dev/RefinementInput` / `Dev/RefinementMemory`
13. `Dev/RefinementPrompt`
14. `Dev/RefinementModel` / `Dev/RefinementRunner`
15. `Dev/RefinementOutput` / `Dev/RefinementBoundary`
16. `Dev/Delivery` / `Dev/Injector` / `Dev/Clipboard`
17. `Dev/PostInsertion`
18. `Dev/Persistence` terminal flush
19. `Dev/MemoryLearning` / `Dev/MemoryPrompt` / `Dev/MemoryModel` /
    `Dev/MemoryAdmission` when the delayed learner runs

The first stage whose data becomes incorrect is the stage to investigate. Do not
compensate for an upstream defect in a downstream stage until the upstream defect
has been understood.

## Baseline cases

### A. Plain Chinese control

Visible page content is irrelevant. Dictate a normal Chinese sentence with no
unusual proper nouns.

Expected:
- Speech text is semantically correct.
- Application Context cannot introduce unrelated page facts.
- Refinement does not add unsupported content.
- Delivery succeeds.

### B. Surrounding UI must not become context

Place unique Latin proper nouns in surrounding application chrome (chat list,
sidebar, menu or unrelated page region), but not in the focused text control,
selection or Dictionary. Dictate a sentence that does not contain those terms.

Expected trace:
- `Dev/ApplicationContext` does not contain those surrounding UI terms;
- `Dev/Vocabulary` does not select them;
- `Dev/SpeechContext applied` does not receive them;
- final output cannot import them through Application Context.

Interpretation:
- surrounding UI appears in cursor context => AX collection-boundary defect;
- no cursor context because the focused control exposes no trustworthy caret/text
  range => acceptable fail-closed behavior;
- do not add word/app-specific filters. Fix only the focused-document boundary.

### C. Focused-editor term

Type a unique term in the focused editor before recording, then dictate it.

Expected:
- cursor context contains the term when it falls inside the 600-character caret window;
- Vocabulary source is `cursor`;
- it is derived only from the focused text control, not surrounding UI.

### D. Selected-text term

Select text containing a unique term before recording, then dictate it.

Expected:
- selected context contains it;
- Vocabulary source is `selected`;
- selected priority outranks a duplicate found in cursor context.

### E. Context must not become content

The focused document contains a nearby unique fact inside the bounded cursor
window that is not spoken. Dictate a sentence that mentions only a proper noun
from that same cursor window.

Expected:
- spelling may be repaired;
- the unspoken page fact must never enter final text;
- if a model incorrectly imports it, capture the prompt/output trace and fix the model contract or context representation; do not add a language-specific post-generation regex.

### F. Self-correction

Dictate a correction such as “周一，不，周二下午三点”.

Expected:
- preferred recognition preserves enough evidence;
- refinement keeps the final correction;
- no local fact/negation rule restores the superseded text; the model owns the correction.

### G. No speech / room noise

Start and stop without speaking, then repeat with ordinary room noise.

Expected:
- AudioEvidence explains the no-speech decision;
- unnecessary accurate recognition/refinement is skipped;
- no junk Capture is retained when audio is confidently empty.

### H. Cancellation

Start speaking, press Escape; then repeat and press Escape (or the capture shortcut) while the HUD is processing/refining.

Expected:
- HotkeyEvent records Escape ownership;
- Stage shows cancellation/stop path from both recording and processing;
- no delivery occurs after processing cancellation;
- persistence either discards or preserves according to the explicit stop
  disposition.

### I. Delivery fallback

Temporarily make Morie/frontmost-app delivery unavailable.

Expected:
- Injector shows target-resolution/paste failure;
- transcript is preserved on clipboard;
- Capture lifecycle becomes deliveryFailed rather than losing text;
- clipboard contents themselves are never logged.

### J. Memory isolation

Use speech that matches a stored Memory topic but does not speak its notes.

Expected:
- RefinementInput may show a Memory topic match;
- raw Memory notes are not in the refinement model payload;
- raw Memory notes are structurally absent from the model payload;
- if output is still wrong, diagnose the prompt/model path rather than adding note-matching output rules.

## Artifacts to collect per failed case

Send only:

1. History screenshot showing original recognition and final text.
2. Overview Application Context inspector screenshot for context cases.
3. Diagnostics filtered by the Capture ID using **复制当前筛选**.

For startup/capability failures, send the unfiltered `Dev/Environment`,
`Dev/Capability`, `Dev/CloudConfig`, `Dev/Keychain` and `Hotkey` entries
instead.

## Rule for fixing defects

When a case fails, identify the earliest incorrect stage in the trace. Fix and
re-run only that case plus the plain-Chinese control case first. Once both pass,
run the complete baseline again.
