# M-005 — Context-aware Personalization

## Status

- **State:** TODO
- **Phase:** Phase 3
- **Starts after:** M-004 can retrieve trustworthy relevant context

## Why

Stored Memory is only useful when it improves the user's next expression. This phase closes the loop by feeding relevant Personal Context back into correction and rewriting.

## Scope

Planned:

- context-aware correction;
- project/person/vocabulary-aware terminology recovery;
- restrained rewrite/cleanup;
- writing-style context;
- learning from explicit user corrections where appropriate;
- latency/quality measurement versus the Phase 0 baseline.

Excluded:

- generic AI assistant behavior unrelated to capture/input;
- autonomous task execution;
- cloud-only personalization requirements.

## Acceptance criteria

1. Relevant Memory measurably improves terminology/correction on representative user captures.
2. Basic voice input remains fast and reliable when personalization is unavailable or unnecessary.
3. Rewriting preserves user intent and trends toward the user's own expression rather than generic AI prose.
4. Incorrect/stale Memory can be excluded or superseded without persistent contamination.
5. Personalization latency and failure behavior are documented.

## Progress

Not started. Exact quality metrics will be defined using data from Phases 0–2.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- predecessor: [`M-004-memory.md`](./M-004-memory.md)