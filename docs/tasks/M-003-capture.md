# M-003 — Durable Capture

## Status

- **State:** TODO
- **Phase:** Phase 1
- **Starts after:** M-002 macOS Input Foundation reaches an acceptable stable baseline

## Why

Morie must make every intentional user expression durable before optional AI processing. Phase 1 establishes the persistence boundary that later Memory and personalization depend on.

## Scope

Planned:

- shared `Capture` data model;
- durable local Capture storage;
- raw/recognized/final content states;
- source application/context fields;
- delivery mode (`currentApp` / `captureOnly`);
- basic History UI;
- App Context persistence;
- real iCloud/CloudKit container and entitlements;
- CloudKit sync semantics;
- iCloud/CloudKit capability check as part of full Private Mode readiness.

Excluded:

- full Memory extraction;
- knowledge graph;
- iOS client;
- Morie cloud backend.

## Acceptance criteria

1. Intentional Capture is durably written before optional enrichment.
2. AI/enrichment failure cannot lose the raw Capture.
3. History can inspect saved captures.
4. iCloud/CloudKit is configured against a real container, not a placeholder.
5. Private Mode readiness includes the required iCloud/CloudKit availability state.
6. Sync semantics are documented and tested for the macOS client.

## Progress

Not started. Detailed subtasks will be refined before implementation begins.

## Known design constraints

- Private Mode is not Device Only; iCloud/CloudKit is part of the intended long-term data path.
- Capture is the core model; Voice is only one source.
- Window title/context collection must remain minimal and intentional rather than expanding into passive surveillance.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- [`../architecture.md`](../architecture.md)
- predecessor: [`M-002-macos-input-foundation.md`](./M-002-macos-input-foundation.md)