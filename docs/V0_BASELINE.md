# Morie V0 architecture constraints

This repository implements the approved **Apple Native First · Product & Architecture Baseline v2 (2026-09-17)**.

The development constraints are treated as architecture rules, not suggestions:

1. macOS first. iOS work starts only after the macOS capture/input loop is stable.
2. Latest Apple only. V0 targets macOS 27+ and Apple Intelligence capable Macs; no old-platform compatibility layer.
3. V0 is Private Mode only: Apple-native processing plus iCloud/CloudKit. No Morie cloud backend and no Device Only mode.
4. Swift native client. No Rust core, Electron, Flutter, bundled model runtime, Python, ONNX, or third-party ASR/LLM provider layer in V0.
5. Capture first. User-initiated input must be durably saved before later AI/memory processing can affect it.
6. Memory must improve future recognition, correction, context, and expression; storage alone is not the product value.
7. External dependencies require an explicit, measurable benefit that Apple system frameworks cannot provide.

## Development order

- Phase 0 — Input Foundation
- Phase 1 — Capture + History + iCloud
- Phase 2 — Vocabulary / Project / Relevant Context memory
- Phase 3 — Context-aware correction and personalization
- Phase 4 — iOS instant capture
- Later — optional Rust cloud, public API, MCP/relay

The active work item is Phase 0: `#1`.
