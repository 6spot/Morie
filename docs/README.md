# Morie Documentation

This directory is the maintained engineering documentation for Morie.

## Start here

- [`design/apple-native-first-v0-baseline-v2.md`](./design/apple-native-first-v0-baseline-v2.md) — repository transcription of the project-owner supplied V0 design baseline, plus explicitly approved amendments.
- [`product-architecture-baseline.md`](./product-architecture-baseline.md) — concise implementation baseline and hard constraints.
- [`ui-design.md`](./ui-design.md) — macOS 27 Native UI Only / Liquid Glass rules and owner-approval gate.
- [`input-cleanup.md`](./input-cleanup.md) — approved meaning-preserving cleanup contract.
- [`reference/type4me.md`](./reference/type4me.md) — input-foundation reference and selective adaptation boundary.
- [`reference/openless.md`](./reference/openless.md) — opt-in correction-to-dictionary behavior reference; no source copied.
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

[M-009](tasks/M-009-macos-input-memory.md) is the active single-Mac milestone: independent cleanup, custom dictionary, automatic personal Memory and an opt-in native prompt after a word correction. Final text is saved before insertion and idle learning. Current implementation evidence and remaining acceptance are in the task record.

Interactive device and real-model checks remain deferred to the evening of 2026-09-18, not waived. iCloud/CloudKit belongs to later cross-device work; iOS/mobile inspiration and Morie Cloud are unscheduled. No compatibility or migration layer is required during development.
