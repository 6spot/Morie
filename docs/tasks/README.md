# Task Detail Documents

This directory contains the detailed execution record for Morie development tasks.

The task index lives in [`../tasks.md`](../tasks.md). Do not turn the index into an implementation diary or project specification.

## Naming

Use:

`M-xxx-short-task-name.md`

Example:

`M-002-macos-input-foundation.md`

## Required sections

Every active task document should contain:

1. **Status** — current task state and last update date.
2. **Why** — product/technical reason for the task.
3. **Scope** — what is included and explicitly excluded.
4. **Acceptance criteria** — concrete completion conditions.
5. **Subtasks / progress** — implementation-level checklist.
6. **Implementation notes** — important technical decisions and changed areas.
7. **Validation** — what was actually built/tested and where.
8. **Known issues / blockers** — unresolved risks and external dependencies.
9. **Follow-up** — work intentionally deferred to later tasks.
10. **References** — GitHub Issue, PR, design/baseline docs, and relevant Apple documentation.

## Status semantics

- `TODO`: no implementation work has started.
- `IN PROGRESS`: implementation, review, or required validation remains.
- `BLOCKED`: task cannot currently progress and the blocker is written down.
- `DONE`: all acceptance criteria, including required real-device validation, are satisfied.

## Update rule

Whenever code materially changes a task:

- update its task record with the implementation and evidence that actually occurred;
- update `docs/tasks.md` if task-level status changed;
- update the relevant current documentation only when the current product, architecture, development, design, testing or deployment contract changed;
- keep the GitHub Issue/PR linked when one exists.

Historical task records may describe superseded designs. Current documentation takes precedence.
