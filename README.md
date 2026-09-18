# Morie

Morie is an Apple-native voice-input product that learns useful personal context from everyday communication.

## Current direction

- **One Mac first:** finish reliable input, a custom dictionary, independent AI cleanup and automatic personal Memory before cross-device work.
- **Latest Apple only:** macOS 27+ on Apple Intelligence-capable Macs, using Swift and Apple system frameworks/components.
- **Capture first:** save intentional input before AI processing; save final text before insertion and Memory analysis.
- **Expression first:** preserve meaning and tone. Cleanup never answers, summarizes or adds information to what the user said.
- **Dictionary and Memory are separate:** the dictionary specifies words and spellings; personal Memory learns projects, relationships, preferences, facts and decisions.
- **Private Mode:** local Apple intelligence with no Morie backend. iCloud/CloudKit belongs to a later cross-device milestone and uses each user's own private database. It is outside the current milestone; iOS and mobile inspiration follow-up are unscheduled.
- **Development stage:** implement the current design directly, with no legacy schemas, migration layers or compatibility shims.

## Current development status

[M-009](docs/tasks/M-009-macos-input-memory.md) integrates the single-Mac loop:

`record → durable recognition → dictionary + optional AI cleanup → durable final text → insertion → idle personal-Memory learning`

The app includes native toggle capture, Apple Speech, focus restoration, clipboard/paste delivery, source-audio recovery and a system management window for **History / Dictionary / Personal Memory / Settings / Diagnostics**. Dictionary spellings supply native Speech hints; explicitly configured aliases also apply when AI cleanup is off. Basic cleanup works with an empty Memory store.

Personal Memory analyzes saved final input during idle time, retains exact source snapshots and retries unfinished work. New voice input takes priority. Memories appear automatically; users can inspect, correct, archive or delete them without processing a confirmation inbox.

An independent, default-off setting offers to remember a word after the user corrects recently inserted Morie text. A native nonactivating prompt saves the correct spelling only after **Remember**; an automatic global replacement alias is never created. See the [OpenLess behavior reference](docs/reference/openless.md).

Isolated logic tests and compilation cover the implementation. Real-model quality/latency, cross-app correction prompts, microphone/recovery interactions, keyboard/VoiceOver and system-material acceptance remain open. The owner deferred interactive validation until the evening of 2026-09-18; it has not been waived. M-002/M-003/M-004/M-005/M-008/M-009 remain `IN PROGRESS` for their outstanding acceptance items.

## Run locally

1. Use macOS 27+ with Apple Intelligence enabled and open `Morie.xcodeproj` in the current Xcode.
2. Configure signing if Xcode requests it, run Morie, and grant Microphone, Speech Recognition and Accessibility permissions.
3. Place the caret in another app, press and release **Fn / Globe**, speak, then release Fn again to finish. **Escape** cancels; Settings offers alternate shortcuts.
4. Open **Morie → Dictionary → Add Word** to save names and terms. Add an **Always Replace** alias only when it should always become the specified word.
5. **Settings → Clean Up Voice Input** controls AI cleanup and defaults to on. The [cleanup contract](docs/input-cleanup.md) preserves intent, meaningful emphasis and uncertainty while removing speech redundancy and organizing clear structure.
6. Inspect **History → Final Text** and **Recognition & Refinement** for the actual saved output, original input and processing context. **Source Recording** offers native playback and explicit re-recognition.
7. **Personal Memory** fills automatically from completed current-app input. History shows learning status and the final-text snapshot; management actions remain optional.
8. To try correction learning, enable **Settings → Suggest Words After I Correct Input**. Correct a word in recently inserted text and pause. Supported fields can show **Remember / Not Now** without interrupting typing.

The existing **History → Record Capture** action remains available for saved-only recordings; its inspiration/follow-up experience is not being expanded in this milestone.

## Documentation

- [Documentation index](docs/README.md)
- [Product and architecture baseline](docs/product-architecture-baseline.md)
- [Architecture](docs/architecture.md)
- [Task overview](docs/tasks.md)
- [Development guide](docs/development.md)
- [Validation matrix](docs/validation.md)
- [Deployment guide](docs/deployment.md)
- [Contributor rules](AGENTS.md)

Development uses feature branches and pull requests.
