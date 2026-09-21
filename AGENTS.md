# AGENTS.md

Before working on Morie, identify the type of task and read the corresponding current project documentation.

Do not start implementation from historical task notes, reference material, old design documents, or assumptions.

If historical task records or reference material conflict with current documentation, **the current documentation takes precedence**.

## Documentation

| Task | Read |
| --- | --- |
| Product behavior, scope, and feature boundaries | `docs/PRODUCT.md` |
| Project structure, ownership, dependencies, runtime flows, and where code belongs | `docs/ARCHITECTURE.md` |
| Coding, refactoring, dependencies, debugging, and development workflow | `docs/DEVELOPMENT.md` |
| macOS UI and interaction design | `docs/DESIGN.md` |
| Testing and validation | `docs/TESTING.md` |
| Build, signing, packaging, and release | `docs/DEPLOYMENT.md` |
| Voice-input refinement behavior | `docs/features/REFINEMENT.md` |
| Current and historical task records | `docs/tasks/` |
| External project research and audits | `docs/reference/` |
| Accepted architecture decisions | `docs/decisions/` |

A task may require more than one document. Read the documents that own the parts of the system you are changing.

Do not duplicate detailed rules into `AGENTS.md`. This file only routes agents to the current source of truth.
