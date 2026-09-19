# Morie Task Overview

`docs/tasks.md` is the **master task plan and progress index** for Morie.

It intentionally stays concise. Detailed background, scope, acceptance criteria, implementation notes, validation evidence, blockers, and follow-up items live in one file per task under [`docs/tasks/`](./tasks/README.md).

## Status

- `TODO` — not started
- `IN PROGRESS` — implementation or validation is active
- `BLOCKED` — cannot progress until an explicit dependency/blocker is resolved
- `DONE` — implementation and required validation are complete

## Task index

| Task | Phase | Summary | Status | GitHub | Detail |
| --- | --- | --- | --- | --- | --- |
| M-001 | Bootstrap | Initialize Morie repository and product baseline | DONE | — | [`M-001`](./tasks/M-001-repository-bootstrap.md) |
| M-002 | Phase 0 | macOS input foundation | IN PROGRESS | [#2](https://github.com/6spot/Morie/issues/2) / [PR #3](https://github.com/6spot/Morie/pull/3) | [`M-002`](./tasks/M-002-macos-input-foundation.md) |
| M-003 | Phase 1 | Durable local Capture, History, audio recovery and App Context | IN PROGRESS | — | [`M-003`](./tasks/M-003-capture.md) |
| M-004 | Phase 2 | Automatic personal Memory, provenance and relevant context | IN PROGRESS | — | [`M-004`](./tasks/M-004-memory.md) |
| M-005 | Phase 3 | Independent cleanup and restrained input personalization | IN PROGRESS | — | [`M-005`](./tasks/M-005-personalization.md) |
| M-008 | macOS UX | Unified native management navigation and page design | IN PROGRESS | — | [`M-008`](./tasks/M-008-macos-management-ui.md) |
| M-009 | Mac input loop | Independent cleanup, custom dictionary and automatic personal Memory | IN PROGRESS | — | [`M-009`](./tasks/M-009-macos-input-memory.md) |
| M-010 | macOS usability | Simplified Chinese, native menus/sidebar and permission setup | IN PROGRESS | — | [`M-010`](./tasks/M-010-macos-native-setup.md) |
| M-011 | Dictionary usability | Add a single word without alias configuration | IN PROGRESS | — | [`M-011`](./tasks/M-011-simple-dictionary.md) |
| M-012 | Performance | Stop hidden HUD rendering and establish idle CPU/RSS baseline | IN PROGRESS | — | [`M-012`](./tasks/M-012-idle-performance.md) |
| M-013 | macOS UX | Simplify menu, setup, filters, Settings and Dictionary navigation | IN PROGRESS | — | [`M-013`](./tasks/M-013-control-center.md) |
| M-014 | Input routing | Deliver final text to current keyboard focus like a system input method | IN PROGRESS | — | [`M-014`](./tasks/M-014-current-focus-input.md) |
| M-015 | Speech quality | Use Apple dictation punctuation for live and saved-audio transcription | IN PROGRESS | — | [`M-015`](./tasks/M-015-native-dictation-punctuation.md) |
| M-016 | Input quality | Keep cleanup Memory context small and directly relevant | IN PROGRESS | — | [`M-016`](./tasks/M-016-conservative-cleanup-context.md) |
| M-017 | Input quality | Clean abandoned fragments and sentence restarts without losing independent meaning | IN PROGRESS | — | [`M-017`](./tasks/M-017-cleanup-false-starts.md) |
| M-018 | Personalization | Learn aggregate Expression Profile from bounded post-insertion style edits | IN PROGRESS | — | [`M-018`](./tasks/M-018-expression-profile.md) |
| M-019 | Private sync | Add explicit opt-in iCloud/CloudKit sync and backup foundation | IN PROGRESS | — | [`M-019`](./tasks/M-019-icloud-opt-in.md) |
| M-020 | Architecture | Organize source and tests by feature/platform ownership without behavior changes | DONE | [#18](https://github.com/6spot/Morie/issues/18) / [PR #19](https://github.com/6spot/Morie/pull/19) | [`M-020`](./tasks/M-020-source-tree-organization.md) |
| M-021 | Architecture | Extract live Capture session lifecycle from AppController | DONE | [#20](https://github.com/6spot/Morie/issues/20) / [PR #21](https://github.com/6spot/Morie/pull/21) | [`M-021`](./tasks/M-021-capture-session-controller.md) |
| M-022 | History UX | Keep History stable during live persistence and right-align row time | IN PROGRESS | [#22](https://github.com/6spot/Morie/issues/22) / [PR #25](https://github.com/6spot/Morie/pull/25) | [`M-022`](./tasks/M-022-history-live-stability.md) |
| M-023 | Dictionary UX | Split user terms from built-in read-only terms | TODO | [#23](https://github.com/6spot/Morie/issues/23) | [`M-023`](./tasks/M-023-dictionary-readonly-sections.md) |
| M-024 | Speech quality | Improve transcription readability and diagnose native recognition quality | IN PROGRESS | [#24](https://github.com/6spot/Morie/issues/24) | [`M-024`](./tasks/M-024-transcription-quality.md) |
| M-025 | Input latency | Move History persistence off the normal input hot path | IN PROGRESS | [#26](https://github.com/6spot/Morie/issues/26) / [PR #27](https://github.com/6spot/Morie/pull/27) | [`M-025`](./tasks/M-025-async-capture-persistence.md) |
| M-006 | Phase 4 | iOS instant Capture entry points | TODO | — | [`M-006`](./tasks/M-006-ios-capture.md) |
| M-007 | Later | Optional Morie Cloud / API / MCP | TODO | — | [`M-007`](./tasks/M-007-cloud.md) |

## Current milestone

The owner's amended priority is **one Mac's input → dictionary/cleanup → automatic personal Memory loop**, tracked in M-009. M-002/M-003 preserve input and recovery; M-004/M-005 now supply personal Memory and independent cleanup; M-008 supplies native management; M-010 supplies Chinese/native setup usability, M-011 simplifies dictionary entry to a single word, M-014 replaces original-app restoration with current-keyboard-focus delivery, M-015 moves the Speech layer to Apple's punctuated dictation preset, and M-016 tightens personal-Memory context so cleanup sees only a few directly relevant items. Required real-device checks remain open. iCloud/CloudKit is outside this milestone, and iOS/inspiration follow-up are not scheduled. The historical phase numbers below are reference IDs, not the execution order.

### Implementation and remaining acceptance

M-009 connects custom dictionary/Speech hints, independent cleanup, automatic personal-Memory learning and opt-in correction suggestions. It replaces the old mandatory-review design directly. M-002/M-003 continue to own reliable capture, delivery and recovery; ambient-noise classification and device interactions remain open.

Current management follows the native M-008 structure with separate History, Dictionary and Personal Memory sections. M-010 adds Simplified Chinese, a system menu, shared Command-comma Settings, native sidebar controls and explicit permission setup. M-011 removes dictionary alias configuration and keeps one word per entry. Its task record holds the latest dictionary build/test/layout evidence; earlier counts remain historical evidence for their respective implementations.

M-010 also fixes the owner-observed Speech authorization callback crash and simplifies the setup window's title, permission state and footer actions. Signed-app permission and interaction retesting remains open; regression/build/layout evidence is in its task record.

M-025 additionally treats finish-to-paste latency as a first-class input metric: after the initial recovery shell, History persistence must not gate normal current-app delivery. The owner deferred interactive validation until the evening of 2026-09-18. Actual model fidelity/latency, correction prompts across supported fields, keyboard/VoiceOver, microphone/recovery and the delivery matrix must be tested before completion. The current execution order is input routing → native dictation punctuation → Dictionary/Cleanup/Memory quality → Expression Profile → optional iCloud/CloudKit sync/backup. M-018 starts the Expression Profile stage with bounded local style learning. M-019 follows with explicit opt-in iCloud/CloudKit sync and backup; no local automatic-backup subsystem is planned, and development schema changes may discard old local development data.

## Maintenance rules

1. Every formal task gets a stable task ID (`M-xxx`), a row in this file, and a corresponding `docs/tasks/M-xxx-*.md` detail document.
2. `docs/tasks.md` stores only task-level scope and overall progress; detailed execution history belongs in the task document.
3. Update the task detail document in the same PR as meaningful implementation progress.
4. If task-level status changes, update the master row in the same PR.
5. A GitHub Issue/PR does not replace repository task documentation; link them together.
6. Do not mark hardware/runtime-dependent work `DONE` until the required validation has actually been performed.
