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
| M-006 | Phase 4 | iOS instant Capture entry points | TODO | — | [`M-006`](./tasks/M-006-ios-capture.md) |
| M-007 | Later | Optional Morie Cloud / API / MCP | TODO | — | [`M-007`](./tasks/M-007-cloud.md) |

## Current milestone

The owner's amended priority is **one Mac's input → dictionary/cleanup → automatic personal Memory loop**, tracked in M-009. M-002/M-003 preserve input and recovery; M-004/M-005 now supply personal Memory and independent cleanup; M-008 supplies native management and M-010 supplies Chinese/native setup usability. Required real-device checks remain open. iCloud/CloudKit is outside this milestone, and iOS/inspiration follow-up are not scheduled. The historical phase numbers below are reference IDs, not the execution order.

### Implementation and remaining acceptance

M-009 connects custom dictionary/Speech hints, independent cleanup, automatic personal-Memory learning and opt-in correction suggestions. It replaces the old mandatory-review design directly. M-002/M-003 continue to own reliable capture, delivery and recovery; ambient-noise classification and device interactions remain open.

Current management follows the native M-008 structure with separate History, Dictionary and Personal Memory sections. M-010 adds Simplified Chinese, a system menu, shared Command-comma Settings, native sidebar controls and explicit permission setup. Its task record holds the latest build/test/layout evidence; earlier counts remain historical evidence for their respective implementations.

The owner deferred interactive validation until the evening of 2026-09-18. Actual model fidelity/latency, correction prompts across supported fields, keyboard/VoiceOver, microphone/recovery and the delivery matrix must be tested before completion. CloudKit is deferred to a later cross-device milestone; no enrollment/container IDs are required for current work.

## Maintenance rules

1. Every formal task gets a stable task ID (`M-xxx`), a row in this file, and a corresponding `docs/tasks/M-xxx-*.md` detail document.
2. `docs/tasks.md` stores only task-level scope and overall progress; detailed execution history belongs in the task document.
3. Update the task detail document in the same PR as meaningful implementation progress.
4. If task-level status changes, update the master row in the same PR.
5. A GitHub Issue/PR does not replace repository task documentation; link them together.
6. Do not mark hardware/runtime-dependent work `DONE` until the required validation has actually been performed.
