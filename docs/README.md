# Morie Documentation

This directory is the maintained engineering documentation for Morie.

## Start here

- [`product-architecture-baseline.md`](./product-architecture-baseline.md) — product/architecture decisions that constrain implementation.
- [`tasks.md`](./tasks.md) — master task plan and overall progress.
- [`tasks/`](./tasks/README.md) — detailed task records and execution history.
- [`architecture.md`](./architecture.md) — code/module boundaries and current technical architecture.
- [`development.md`](./development.md) — local development workflow, conventions, permissions, and debugging.
- [`validation.md`](./validation.md) — Phase 0 real-device test and compatibility matrix.
- [`deployment.md`](./deployment.md) — signing, build, packaging, release, and deployment process.

## Documentation ownership

Documentation changes with the code. A behavior, architecture, task status, build process, permission requirement, or release process that changes in implementation must be updated here in the same pull request.

`docs/tasks.md` is the concise project-level task overview. Detailed execution history belongs in `docs/tasks/M-xxx-*.md`.

## Current product stage

Morie is currently in **Phase 0 — macOS Input Foundation**. iOS, Personal Memory implementation, and Morie Cloud are intentionally not in the active implementation scope.