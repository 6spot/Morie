# Morie Documentation

This directory is the maintained engineering documentation for Morie.

## Start here

- [`design/apple-native-first-v0-baseline-v2.md`](./design/apple-native-first-v0-baseline-v2.md) — repository transcription of the project-owner supplied V0 design baseline, plus explicitly approved amendments.
- [`product-architecture-baseline.md`](./product-architecture-baseline.md) — concise implementation baseline and hard constraints.
- [`ui-design.md`](./ui-design.md) — macOS 27 Native UI Only / Liquid Glass rules and owner-approval gate.
- [`reference/type4me.md`](./reference/type4me.md) — Type4Me input-foundation reference and selective migration boundary.
- [`tasks.md`](./tasks.md) — master task plan and overall progress.
- [`tasks/`](./tasks/README.md) — detailed task records and execution history.
- [`architecture.md`](./architecture.md) — code/module boundaries and current technical architecture.
- [`development.md`](./development.md) — local development workflow, conventions, permissions, and debugging.
- [`validation.md`](./validation.md) — Phase 0 real-device test and compatibility matrix.
- [`deployment.md`](./deployment.md) — signing, build, packaging, release, and deployment process.

## Documentation ownership

Documentation changes with the code. A behavior, architecture, UI rule, task status, build process, permission requirement, reference-migration decision, or release process that changes in implementation must be updated here in the same pull request.

`docs/tasks.md` is the concise project-level task overview. Detailed execution history belongs in `docs/tasks/M-xxx-*.md`.

## Hard implementation rules

- UI uses Apple system components and native macOS 27 Liquid Glass behavior.
- If native UI cannot satisfy a requirement, implementation stops until the project owner explicitly approves an exception.
- External dependencies require explicit owner approval; they are never introduced unilaterally.
- Phase 0 input infrastructure must audit/adapt proven Type4Me behavior rather than re-inventing solved recording/hotkey/focus/injection problems.

## Current product stage

Morie is validating **Phase 0 — macOS Input Foundation**, extending **Phase 1 — Durable Capture**, and implementing **Phase 2 — Personal Memory**. The owner deferred interactive device checks until the evening of 2026-09-18 and CloudKit sync until final integration. Current Memory work includes vocabulary/project storage, provenance, relevant-context retrieval and on-demand Apple AI candidate extraction with explicit review. M-005 will persist polished final text before Memory extraction; iOS and Morie Cloud remain later work.
