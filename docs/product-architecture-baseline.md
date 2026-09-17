# Product & Architecture Baseline

Version: V0 Baseline v2  
Date: 2026-09-17

This is the repository-native summary of the approved Morie product baseline. It exists to constrain implementation, not to collect feature ideas.

## Product definition

Morie is an Apple-native voice input and intentional capture product that gradually builds Personal Memory from the user's own captures and uses that context to improve future recognition, correction, understanding, and expression.

## Five V0 constraints

1. **macOS First** — finish the macOS end-to-end loop before iOS development.
2. **Latest Apple Only** — target the latest Apple platform capabilities and Apple Intelligence-capable Macs; do not create compatibility layers for old Macs or old APIs.
3. **Private Mode only in V0** — no Morie-hosted cloud backend in V0.
4. **Private Mode = Apple Native + iCloud** — there is no Device Only product mode.
5. **Apple Native First** — avoid external dependencies whenever Apple system frameworks can satisfy the requirement.

## Core loop

`Capture → Understand → Remember → Personalize → Express Better → Capture`

Two intentional Capture modes are planned:

- `currentApp`: transcribe, deliver to the current app, and retain the intentional capture.
- `captureOnly`: record an idea without injecting it into another app.

Normal keyboard input is not monitored and Morie is not a global keylogger.

## V0 platform boundary

Active implementation scope is macOS only.

Current platform baseline:

- macOS 27+
- Apple Intelligence-capable Mac
- latest stable Xcode / Swift supported by the platform baseline
- Foundation Models / `SystemLanguageModel`
- modern Speech APIs
- SwiftUI + AppKit where needed
- AVFoundation
- NaturalLanguage
- Accessibility / AppKit / NSPasteboard for macOS delivery
- iCloud / CloudKit once Capture persistence ships

Unsupported required capabilities block Private Mode. V0 does not add a cloud fallback.

## Phase plan

### Phase 0 — Input Foundation

Validate the core daily input loop:

`hold → speak → release → transcript → restore focus → inject text`

Scope includes audio/session lifecycle, global shortcut, modern Speech APIs, capability gate, target-app capture, focus restoration, Accessibility injection, clipboard fallback, compatibility testing, and performance baseline.

### Phase 1 — Capture

Add Capture-first persistence:

- durable Capture model/store;
- History;
- App Context persistence;
- iCloud/CloudKit sync;
- iCloud capability gate.

Raw intentional Capture must be durable before optional AI enrichment.

### Phase 2 — Memory

Start with restrained high-value context rather than a knowledge graph:

- Vocabulary;
- Project;
- Relevant Context retrieval;
- data-model support for Person, Topic, Decision, Preference, Fact, Open Thread, and Writing Style.

Memory must retain provenance and lifecycle information such as source captures, confidence, confirmation state, timestamps, and active/superseded/archived status.

### Phase 3 — Personalization

Use relevant historical context to improve current input:

- context-aware correction;
- terminology recovery;
- style-aware rewrite;
- learning from user corrections.

The goal is increasingly user-like output, not generic AI prose.

### Phase 4 — iOS

iPhone becomes an instant Capture surface after the macOS loop works:

- Action Button;
- AppIntent;
- voice/text Capture;
- shared iCloud data semantics.

Do not copy the entire macOS UI to iPhone.

### Later — Optional Morie Cloud

Only after the Private product loop is validated:

- Rust server;
- cloud Memory/retrieval;
- API/MCP/relay;
- optional Cloud mode.

Do not introduce Rust or server-oriented runtime abstractions into the Apple client in anticipation of future cloud work.

## Dependency rule

Before adding any external dependency, document:

1. why Apple-native capability is insufficient;
2. the measurable accuracy/performance/stability benefit;
3. impact on binary size, launch time, memory, energy, signing and packaging;
4. additional runtime/model/network requirements;
5. whether it can be removed when Apple APIs improve.

For Phase 0, expected third-party dependency count is zero.

## Capture-first reliability rule

Once persistence exists:

> Save the intentional Capture first. AI classification, rewriting, Memory extraction, or retrieval failure must never cause the original Capture to be lost.

## Memory quality rule

Journal may be comprehensive; long-term Memory must be selective. Morie should become more useful with usage, not accumulate indiscriminate context.

## Success criteria

V0 exists to answer three questions:

1. Is Morie stable, fast, and natural enough to become a daily macOS voice-input tool?
2. Do users naturally accumulate meaningful Personal Context through intentional voice/text capture?
3. Does that context measurably improve recognition and expression over time?

Platform expansion comes after these questions are validated.