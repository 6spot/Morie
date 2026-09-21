# Documentation

Morie documentation is divided by responsibility.

Use the document that owns the topic. Do not treat historical task records or reference material as current project rules.

## Current documentation

| Topic | Document |
| --- | --- |
| Product scope and behavior | [`PRODUCT.md`](PRODUCT.md) |
| Project structure, ownership, dependencies and runtime flows | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Development rules and engineering practices | [`DEVELOPMENT.md`](DEVELOPMENT.md) |
| macOS UI and interaction design | [`DESIGN.md`](DESIGN.md) |
| Testing and validation | [`TESTING.md`](TESTING.md) |
| Build, signing, packaging and release | [`DEPLOYMENT.md`](DEPLOYMENT.md) |
| Voice-input refinement behavior | [`features/REFINEMENT.md`](features/REFINEMENT.md) |

Repository-level agent navigation is defined in [`../AGENTS.md`](../AGENTS.md).

## Task records

Current and historical implementation work is stored under [`tasks/`](tasks/).

Task documents record work, decisions, investigation and validation evidence. They are not project specifications.

If a task record conflicts with the current documentation above, the current documentation takes precedence.

## Reference material

Reference implementations, audits and research are stored under [`reference/`](reference/).

Reference material supports research and implementation decisions. It does not define Morie's current product or architecture.

## Architecture decisions

Accepted architecture decisions are stored under [`decisions/`](decisions/).

An ADR explains why a specific architecture decision was made. The current architecture is still defined by `ARCHITECTURE.md`.

## Historical material

Old designs and superseded specifications should not remain as a second current documentation system.

Historical implementation evidence belongs in task records. When an old standalone design document is no longer useful, remove it.
