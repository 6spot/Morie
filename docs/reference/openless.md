# OpenLess correction-learning reference

## Scope and source

Owner reference: [Open-Less/openless](https://github.com/Open-Less/openless), inspected at commit [`cbde1fc2677a9e7dac97570bbd2262f9c3af1d26`](https://github.com/Open-Less/openless/tree/cbde1fc2677a9e7dac97570bbd2262f9c3af1d26), branch `beta`, on 2026-09-18. The relevant interaction offers to save a word after the user corrects dictated text.

The repository is **AGPL-3.0**. This audit uses observable behavior and failure-mode lessons only. No OpenLess source, component, runtime or dependency is copied into Morie.

Inspected paths:

- [README.zh.md](https://github.com/Open-Less/openless/blob/cbde1fc2677a9e7dac97570bbd2262f9c3af1d26/README.zh.md): opt-in correction learning and vocabulary suggestions.
- [VocabSuggestionCard.tsx](https://github.com/Open-Less/openless/blob/cbde1fc2677a9e7dac97570bbd2262f9c3af1d26/openless-all/app/src/components/VocabSuggestionCard.tsx): explicit word confirmation; automatic admission had precision problems.
- [host_document/macos.rs](https://github.com/Open-Less/openless/blob/cbde1fc2677a9e7dac97570bbd2262f9c3af1d26/openless-all/app/src-tauri/src/host_document/macos.rs) and [host_document/mod.rs](https://github.com/Open-Less/openless/blob/cbde1fc2677a9e7dac97570bbd2262f9c3af1d26/openless-all/app/src-tauri/src/host_document/mod.rs): Accessibility observation, stable editing and observation lifetime.
- [host_document/diff.rs](https://github.com/Open-Less/openless/blob/cbde1fc2677a9e7dac97570bbd2262f9c3af1d26/openless-all/app/crates/openless-core/src/host_document/diff.rs): changed-word identification.

## Morie decisions

- **ADAPT:** wait for stable edits; offer a small, explicit Remember / Not Now decision; expire the suggestion; stop observing when ownership/focus changes.
- **ADAPT:** dictionary confirmation is separate from automatic personal Memory. The visible Dictionary remains canonical-word only. After explicit confirmation Morie may retain the bounded observed-ASR → canonical-word relation internally; it must never infer a broad/unconfirmed replacement rule.
- **DROP:** a web/Tauri UI, whole-document observation, model/provider machinery and passive general keyboard tracking. Morie uses repository-owned Swift and native AppKit/SwiftUI.
- **VERIFY:** native Accessibility range support, field identity, selection behavior, password/secure-input exclusion, focus preservation, pointer/keyboard/VoiceOver interaction and useful correction precision on the actual macOS 27 app matrix.


## M-035 cleanup-prompt behavior audit — 2026-09-20

For M-035, Morie also inspected OpenLess prompt composition/style-pack behavior at revision `a8ebcf6ffae7f179f09adf6f0afbc164cd791d21`.

Useful mature-product lessons are behavioral only:

- OpenLess clearly separates the raw transcription from the instruction and does not answer or execute questions/requests contained in dictated text.
- It treats uncertain text conservatively and keeps a direct-output contract.
- Its style-pack architecture treats prompts as editable product data rather than requiring a source edit for every iteration.

Morie deliberately does **not** adopt OpenLess's larger multi-mode/persona/technical-term prompt surface. Morie's Apple on-device cleanup has one narrower job, and Apple's own Foundation Models guidance favors a concise, specific prompt. M-035 therefore keeps one three-paragraph default, removes the deterministic formatting classifier, and exposes only the effective cleanup instruction in native Settings.

OpenLess remains AGPL-3.0. No prompt text, source implementation, component or dependency is copied.

## Current implementation

M-009 adds a default-off **Suggest Words After I Correct Input** setting. Only a successfully dispatched current-app insertion can begin observation; the exact inserted text must then be verified at the caret. Unsupported/secure fields and selected terminal/password-manager apps are excluded. No clipboard fallback or capture-only recording starts a watcher.

A dedicated actor reads only a bounded range using `AXStringForRange`, with native IPC timeouts. The observed insertion is at most 1,200 UTF-16 units, the inferred length change is at most 64, and the lifetime is at most 30 seconds. Field/PID/caret checks stop on focus departure; new input, disabling the setting and secure input also stop it. Editing the proposed text again dismisses the pending prompt. Range support and document changes outside the observed selection remain integration risks; this is a conservative best-effort feature, not a general document tracker.

The pure detector expands differences to aligned native word boundaries, including Chinese/mixed language, added/deleted letters and joined words. It accepts small word-like changes after two seconds of stable samples, rejecting appended sentences, punctuation/numbers/code/URL edits and broad rewrites. This heuristic cannot prove whether a changed word is a recognition correction; explicit confirmation is intentional.

A nonactivating native `NSPanel` contains standard Text and Buttons. Explicit confirmation keeps/adds the canonical spelling and, under M-027, may also persist the detected observed-ASR → canonical-word mapping in the internal correction-rule store. The wrong form is not shown as a normal Dictionary row. Not Now/20-second expiry saves nothing, and a normalized word is offered at most once per process. Observed external text is not sent to AI, logged or persisted into Capture.

See [M-009](../tasks/M-009-macos-input-memory.md) for current evidence and the [validation matrix](../validation.md#m-009-correction-suggestions) for uncompleted device checks.
