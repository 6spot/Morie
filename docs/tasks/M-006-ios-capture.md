# M-006 — iOS Instant Capture

## Status

- **State:** TODO
- **Phase:** Phase 4
- **Starts after:** the macOS Private product loop is validated

## Why

iPhone should become an extremely fast intentional Capture entry point after the macOS core experience is proven, not a parallel source of product complexity during V0 validation.

## Scope

Planned:

- native Swift iOS app shell;
- Action Button / AppIntent entry where supported;
- intentional voice Capture;
- intentional text Capture;
- iCloud/CloudKit sharing of Capture/Memory data semantics with macOS;
- reuse of shared Swift packages where real shared logic exists.

Excluded:

- cloning the complete macOS UI;
- Android/Web clients;
- requiring Morie Cloud for basic Capture.

## Acceptance criteria

1. User can invoke an iPhone Capture flow with minimal friction.
2. Captures are durable and synchronize through the same Private data model.
3. iOS reuses shared core logic without forcing macOS-specific abstractions into shared packages.
4. Mobile lifecycle failures do not lose an intentional Capture once persistence begins.

## Progress

Not started. iOS is intentionally not developed in parallel with current macOS Phase 0 work.

## References

- [`../product-architecture-baseline.md`](../product-architecture-baseline.md)
- predecessor: [`M-005-personalization.md`](./M-005-personalization.md)