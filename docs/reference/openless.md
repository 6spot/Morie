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
- **ADAPT:** dictionary confirmation is separate from automatic personal Memory. Saving the correct spelling must not silently turn the old word into an always-replace alias.
- **DROP:** a web/Tauri UI, whole-document observation, model/provider machinery and passive general keyboard tracking. Morie uses repository-owned Swift and native AppKit/SwiftUI.
- **VERIFY:** native Accessibility range support, field identity, selection behavior, password/secure-input exclusion, focus preservation, pointer/keyboard/VoiceOver interaction and useful correction precision on the actual macOS 27 app matrix.

## Current implementation

M-009 adds a default-off **Suggest Words After I Correct Input** setting. Only a successfully dispatched current-app insertion can begin observation; the exact inserted text must then be verified at the caret. Unsupported/secure fields and selected terminal/password-manager apps are excluded. No clipboard fallback or capture-only recording starts a watcher.

A dedicated actor reads only a bounded range using `AXStringForRange`, with native IPC timeouts. The observed insertion is at most 1,200 UTF-16 units, the inferred length change is at most 64, and the lifetime is at most 30 seconds. Field/PID/caret checks stop on focus departure; new input, disabling the setting and secure input also stop it. Editing the proposed text again dismisses the pending prompt. Range support and document changes outside the observed selection remain integration risks; this is a conservative best-effort feature, not a general document tracker.

The pure detector expands differences to aligned native word boundaries, including Chinese/mixed language, added/deleted letters and joined words. It accepts small word-like changes after two seconds of stable samples, rejecting appended sentences, punctuation/numbers/code/URL edits and broad rewrites. This heuristic cannot prove whether a changed word is a recognition correction; explicit confirmation is intentional.

A nonactivating native `NSPanel` contains standard Text and Buttons. Remember saves only the corrected spelling. Not Now/20-second expiry saves nothing, and a normalized word is offered at most once per process. Observed external text is not sent to AI, logged or persisted into Capture.

See [M-009](../tasks/M-009-macos-input-memory.md) for current evidence and the [validation matrix](../validation.md#m-009-correction-suggestions) for uncompleted device checks.
