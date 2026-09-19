# Documentation Map

Choose the document that owns the question. Routine edits do not require reading every guide. Start with [README](../README.md) if unfamiliar with Morie, or the [task index](tasks.md) when continuing implementation.

## Current requirements and implementation

| Question | Source of truth |
| --- | --- |
| What is in scope, and what requires owner approval? | [Current product baseline](product-architecture-baseline.md) |
| Which component owns this state or behavior? | [Architecture map](architecture.md), then [input/setup](architecture/input.md), [Capture/recovery](architecture/capture.md), or [dictionary/cleanup/Memory](architecture/intelligence.md) |
| How should a native screen or control behave? | [UI design](ui-design.md) |
| What may cleanup change in the user's words? | [Approved cleanup contract](input-cleanup.md) |
| How do I build, test or diagnose locally? | [Development guide](development.md) |
| Which device/model/UI checks remain? | Relevant section of [validation](validation.md) |
| How do signing, packaging and release work? | [Deployment guide](deployment.md) |
| What task is active or complete? | [Task index](tasks.md); [detail-record convention](tasks/README.md) |

## Decisions and historical evidence

| Need | Read |
| --- | --- |
| Why generic paste delivery? | [ADR 0001](decisions/0001-universal-text-delivery.md) |
| Why toggle capture and a nonactivating HUD? | [ADR 0002](decisions/0002-toggle-capture-hud.md) |
| Which Type4Me failure modes have already been audited? | Matching section of [Type4Me reference](reference/type4me.md) |
| Where did correction suggestions come from? | [OpenLess behavior audit](reference/openless.md) |
| What did the owner originally approve or later amend? | [Original V0 design and amendments](design/apple-native-first-v0-baseline-v2.md) |
| What was built or actually tested in a change? | Its `tasks/M-xxx-*.md` record, linked from the task index |

The original design body and dated task evidence may describe superseded implementations. They preserve provenance, not a second current specification. Explicit owner amendments win; current requirements are summarized in the product baseline. Current code explains how an approved requirement is implemented, but does not override the requirement.

## Keep each fact in its owning document

- **Policy** belongs in the product baseline; **agent navigation and execution boundaries** belong in [AGENTS.md](../AGENTS.md).
- **Current mechanics** belong in subsystem architecture; **visible behavior/layout** belongs in UI design.
- **Repeatable local commands** belong in development; **release operations** belong in deployment.
- **Device checklists and matrix results** belong in validation; **dated logs, measurements, failures and approvals** belong in task records. Link evidence rather than copying it into every guide.
- Keep the task index to scope/status/links. New work within an existing task updates that record; a new formal task gets a stable ID and detail file.

Update affected documents with the implementation. Preserve historical evidence, label superseded behavior, and correct stale current summaries instead of appending another competing rule. Prefer a short route to an existing explanation over a new checklist. Documentation-only work calls for link/anchor and consistency checks, not an unrelated app build.

This organization follows [OpenAI's guidance on skills and prompts](https://developers.openai.com/blog/rethinking-skills-and-prompts-for-gpt-6-astra): task-specific context, progressive disclosure and explicit completion/decision boundaries. It does not change Morie's product approvals or require a particular coding model.
