# M-007 — Optional Morie Cloud

## Status

- **State:** TODO
- **Stage:** Later
- **Starts after:** Private Mode product loop is validated and there is a concrete cloud requirement

## Why

Morie may later provide a cloud mode for capabilities that cannot or should not run purely through Apple-native local intelligence + iCloud. This is deliberately a future service, not a dependency of V0.

## Potential scope

Only if justified by validated product needs:

- Rust server;
- cloud Memory/retrieval service;
- AI orchestration;
- public/private API contracts;
- MCP / relay capability;
- optional Cloud mode alongside Private Mode.

## Explicit constraints

- Do not introduce Rust into the Apple client merely because a future server may use it.
- Do not make V0 Private Mode depend on a Morie account/server.
- Do not build relay/API/MCP infrastructure before there is a concrete external-access use case and security model.
- Apple clients remain native Swift.

## Acceptance criteria

To be defined only after the Private product validates. A future design must explicitly cover privacy boundaries, authentication, encryption, data retention, availability, cost, observability, API compatibility, and deletion/export semantics.

## Progress

Not started by design.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- [`../architecture.md`](../architecture.md)