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
| M-003 | Phase 1 | Durable Capture store, History, App Context and iCloud/CloudKit | IN PROGRESS | — | [`M-003`](./tasks/M-003-capture.md) |
| M-004 | Phase 2 | Vocabulary, Project and Relevant Context retrieval | TODO | — | [`M-004`](./tasks/M-004-memory.md) |
| M-005 | Phase 3 | Context-aware correction, personalization and style learning | TODO | — | [`M-005`](./tasks/M-005-personalization.md) |
| M-006 | Phase 4 | iOS instant Capture entry points | TODO | — | [`M-006`](./tasks/M-006-ios-capture.md) |
| M-007 | Later | Optional Morie Cloud / API / MCP | TODO | — | [`M-007`](./tasks/M-007-cloud.md) |

## Current milestone

### Phase 0 — macOS Input Foundation

The current priority is the reliable daily input loop:

`press shortcut → speak → press again → final transcript → restore original app → insert text`

Phase 0 remains `IN PROGRESS` until it has been built and exercised on a supported macOS 27 Apple Intelligence-capable Mac and the target-app compatibility matrix has been completed.

M-003's local Capture-first slice now includes SwiftData History, App Context basics, single-output compressed source audio, and configurable local retention. It remains `IN PROGRESS`: empty-result classification and History retry/playback are follow-up work, while App Context completion and real iCloud/CloudKit persistence are still outstanding. M-002 also remains open for the remaining runtime/performance validation matrix.

## Maintenance rules

1. Every formal task gets a stable task ID (`M-xxx`), a row in this file, and a corresponding `docs/tasks/M-xxx-*.md` detail document.
2. `docs/tasks.md` stores only task-level scope and overall progress; detailed execution history belongs in the task document.
3. Update the task detail document in the same PR as meaningful implementation progress.
4. If task-level status changes, update the master row in the same PR.
5. A GitHub Issue/PR does not replace repository task documentation; link them together.
6. Do not mark hardware/runtime-dependent work `DONE` until the required validation has actually been performed.
