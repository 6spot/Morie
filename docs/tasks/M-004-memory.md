# M-004 — Personal Memory Foundation

## Status

- **State:** TODO
- **Phase:** Phase 2
- **Starts after:** M-003 establishes reliable Capture persistence

## Why

Morie's long-term value comes from Personal Context that improves later input. This phase introduces restrained, provenance-aware Memory rather than a general knowledge graph.

## Scope

Planned first-class capabilities:

- Vocabulary;
- Project;
- Relevant Context retrieval;
- Memory Candidate flow;
- provenance from source Capture IDs;
- confidence and user-confirmed state;
- active / superseded / archived lifecycle;
- data-model support for Person, Topic, Decision, Preference, Fact, Open Thread, and Writing Style where useful.

Excluded:

- autonomous agents;
- broad knowledge graph infrastructure;
- cloud Memory service;
- speculative long-running background intelligence.

## Acceptance criteria

1. Captures can produce a small, high-signal set of Memory Candidates.
2. Long-term Memory retains provenance and lifecycle state.
3. Relevant Context retrieval can surface useful Vocabulary/Project context for a new capture.
4. Superseded/archived facts stop polluting active context.
5. Memory creation is selective rather than permanently storing every journal entry as knowledge.

## Progress

Not started. Detailed subtasks will be refined from real Capture usage after M-003.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- predecessor: [`M-003-capture.md`](./M-003-capture.md)