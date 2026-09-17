# Contributing to Morie

Morie is intentionally developed against a narrow product baseline. Before changing code, read:

- [`AGENTS.md`](./AGENTS.md)
- [`docs/product-architecture-baseline.md`](./docs/product-architecture-baseline.md)
- [`docs/tasks.md`](./docs/tasks.md)
- the active task document under [`docs/tasks/`](./docs/tasks/README.md)
- [`docs/development.md`](./docs/development.md)

## Workflow

1. Work from a documented `M-xxx` task.
2. Use a feature/task branch; do not develop directly on `main`.
3. Keep the implementation inside the active task's scope.
4. Prefer Apple system frameworks; new third-party dependencies require explicit justification.
5. Update the task detail document as the implementation changes.
6. Update architecture/development/deployment/validation docs when affected.
7. Open/update a pull request with acceptance criteria and actual validation evidence.
8. Leave hardware-dependent items open until tested on supported hardware.

## Definition of done

A task is not done just because code was written. `DONE` means:

- acceptance criteria are satisfied;
- required automated/manual checks have run;
- required real-device validation has run;
- known issues are documented;
- task/master documentation is current;
- affected engineering docs are current.

See [`AGENTS.md`](./AGENTS.md) for the detailed repository rules.