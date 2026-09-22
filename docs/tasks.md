# Morie Tasks

This file is an index of current and historical Morie development tasks.

Task records document implementation history, investigation and validation evidence. They are not the current product, architecture or development specification.

If a task record conflicts with the current documentation in `docs/`, the current documentation takes precedence.

Detailed task records live under [`docs/tasks/`](./tasks/README.md).

## Status

- `TODO` — not started
- `IN PROGRESS` — implementation or validation is active
- `BLOCKED` — cannot progress until an explicit dependency/blocker is resolved
- `DONE` — implementation and required validation are complete

## Task index

| Task | Phase | Summary | Status | GitHub | Detail |
| --- | --- | --- | --- | --- | --- |
| M-001 | Bootstrap | Initialize Morie repository and product baseline | DONE | — | [`M-001`](./tasks/M-001-repository-bootstrap.md) |
| M-002 | Phase 0 | macOS input foundation | IN PROGRESS | [#2](https://github.com/6spot/Morie/issues/2) / [PR #3](https://github.com/6spot/Morie/pull/3) | [`M-002`](./tasks/M-002-macos-input-foundation.md) |
| M-003 | Phase 1 | Durable local Capture, History, audio recovery and App Context | IN PROGRESS | — | [`M-003`](./tasks/M-003-capture.md) |
| M-004 | Phase 2 | Automatic personal Memory, provenance and relevant context | IN PROGRESS | — | [`M-004`](./tasks/M-004-memory.md) |
| M-005 | Phase 3 | Independent cleanup and restrained input personalization | IN PROGRESS | — | [`M-005`](./tasks/M-005-personalization.md) |
| M-008 | macOS UX | Unified native management navigation and page design | IN PROGRESS | — | [`M-008`](./tasks/M-008-macos-management-ui.md) |
| M-009 | Mac input loop | Independent cleanup, custom dictionary and automatic personal Memory | IN PROGRESS | — | [`M-009`](./tasks/M-009-macos-input-memory.md) |
| M-010 | macOS usability | Simplified Chinese, native menus/sidebar and permission setup | IN PROGRESS | — | [`M-010`](./tasks/M-010-macos-native-setup.md) |
| M-011 | Dictionary usability | Add a single word without alias configuration | IN PROGRESS | — | [`M-011`](./tasks/M-011-simple-dictionary.md) |
| M-012 | Performance | Stop hidden HUD rendering and establish idle CPU/RSS baseline | IN PROGRESS | [PR #68](https://github.com/6spot/Morie/pull/68) | [`M-012`](./tasks/M-012-idle-performance.md) |
| M-013 | macOS UX | Simplify menu, setup, filters, Settings and Dictionary navigation | IN PROGRESS | — | [`M-013`](./tasks/M-013-control-center.md) |
| M-014 | Input routing | Deliver final text to current keyboard focus like a system input method | IN PROGRESS | — | [`M-014`](./tasks/M-014-current-focus-input.md) |
| M-015 | Speech quality | Use Apple dictation punctuation for live and saved-audio transcription | IN PROGRESS | — | [`M-015`](./tasks/M-015-native-dictation-punctuation.md) |
| M-016 | Input quality | Keep cleanup Memory context small and directly relevant | IN PROGRESS | — | [`M-016`](./tasks/M-016-conservative-cleanup-context.md) |
| M-017 | Input quality | Clean abandoned fragments and sentence restarts without losing independent meaning | IN PROGRESS | — | [`M-017`](./tasks/M-017-cleanup-false-starts.md) |
| M-018 | Personalization | Learn aggregate Expression Profile from bounded post-insertion style edits | IN PROGRESS | — | [`M-018`](./tasks/M-018-expression-profile.md) |
| M-019 | Private sync | Add explicit opt-in iCloud/CloudKit sync and backup foundation | IN PROGRESS | — | [`M-019`](./tasks/M-019-icloud-opt-in.md) |
| M-020 | Architecture | Organize source and tests by feature/platform ownership without behavior changes | DONE | [#18](https://github.com/6spot/Morie/issues/18) / [PR #19](https://github.com/6spot/Morie/pull/19) | [`M-020`](./tasks/M-020-source-tree-organization.md) |
| M-021 | Architecture | Extract live Capture session lifecycle from AppController | DONE | [#20](https://github.com/6spot/Morie/issues/20) / [PR #21](https://github.com/6spot/Morie/pull/21) | [`M-021`](./tasks/M-021-capture-session-controller.md) |
| M-022 | History UX | Keep History stable during live persistence and right-align row time | IN PROGRESS | [#22](https://github.com/6spot/Morie/issues/22) / [PR #25](https://github.com/6spot/Morie/pull/25) | [`M-022`](./tasks/M-022-history-live-stability.md) |
| M-023 | Dictionary UX | Split user terms from built-in read-only terms | DONE | [#23](https://github.com/6spot/Morie/issues/23) / [PR #29](https://github.com/6spot/Morie/pull/29) | [`M-023`](./tasks/M-023-dictionary-readonly-sections.md) |
| M-024 | Speech quality | Improve transcription readability and diagnose native recognition quality | IN PROGRESS | [#24](https://github.com/6spot/Morie/issues/24) | [`M-024`](./tasks/M-024-transcription-quality.md) |
| M-025 | Input latency | Move History persistence off the normal input hot path | IN PROGRESS | [#26](https://github.com/6spot/Morie/issues/26) / [PR #27](https://github.com/6spot/Morie/pull/27) | [`M-025`](./tasks/M-025-async-capture-persistence.md) |
| M-026 | Control Center | Add Overview with local usage metrics and actual runtime model status | IN PROGRESS | [#31](https://github.com/6spot/Morie/issues/31) | [`M-026`](./tasks/M-026-control-center-overview.md) |
| M-027 | Dictionary learning | Learn confirmed ASR error → canonical word mappings | IN PROGRESS | [#35](https://github.com/6spot/Morie/issues/35) / [PR #36](https://github.com/6spot/Morie/pull/36) | [`M-027`](./tasks/M-027-confirmed-dictionary-corrections.md) |
| M-028 | Capture UX | Add native start/stop cues and center-morph capsule feedback | DONE | [#37](https://github.com/6spot/Morie/issues/37) | [`M-028`](./tasks/M-028-capture-feedback.md) |
| M-029 | No-speech handling | Discard true no-speech captures while retaining retryable speech audio | DONE | [#44](https://github.com/6spot/Morie/issues/44) | [`M-029`](./tasks/M-029-no-speech-retention.md) |
| M-030 | Validation | Execute deterministic MorieTests in macOS 27 CI | DONE | [#48](https://github.com/6spot/Morie/issues/48) | [`M-030`](./tasks/M-030-macos-logic-test-gate.md) |
| M-031 | Documentation | Align current source-of-truth docs and supersede stale Phase-0 instructions | DONE | [#49](https://github.com/6spot/Morie/issues/49) | [`M-031`](./tasks/M-031-source-of-truth-alignment.md) |
| M-032 | Capture lifecycle | Freeze per-Capture settings and Speech hint context | DONE | [#50](https://github.com/6spot/Morie/issues/50) | [`M-032`](./tasks/M-032-capture-session-context.md) |
| M-033 | Capture UX | Soften capsule controls and success/status feedback | IN PROGRESS | [#54](https://github.com/6spot/Morie/issues/54) | [`M-033`](./tasks/M-033-quiet-capture-hud.md) |
| M-034 | Refinement models | Add user-configured OpenAI-compatible cleanup models with Apple-local fallback | IN PROGRESS | — | [`M-034`](./tasks/M-034-external-refinement-models.md) |
| M-035 | Input quality | Simplify cleanup prompt and make it editable at runtime | IN PROGRESS | [#71](https://github.com/6spot/Morie/issues/71) | [`M-035`](./tasks/M-035-editable-refinement-prompt.md) |
| M-036 | Personal Memory | Rebuild Memory around semantic topics, evidence and lifecycle | IN PROGRESS | [#75](https://github.com/6spot/Morie/issues/75) / [PR #76](https://github.com/6spot/Morie/pull/76) | [`M-036`](./tasks/M-036-semantic-memory.md) |
| M-037 | Speech outcomes | Fast-exit no-speech captures and keep recognizer rejection out of fatal UI | IN PROGRESS | [#77](https://github.com/6spot/Morie/issues/77) | [`M-037`](./tasks/M-037-recognition-outcomes.md) |
| M-038 | Control Center | Rebuild the management UI around one macOS 27 System Settings-style layout contract | IN PROGRESS | [#86](https://github.com/6spot/Morie/issues/86) | [`M-038`](./tasks/M-038-control-center-rebuild.md) |\n| M-039 | Control Center | Clean rebuild with one persistent macOS System Settings-style shell and route-owned page geometry | IN PROGRESS | [#89](https://github.com/6spot/Morie/issues/89) | [`M-039`](./tasks/M-039-control-center-clean-rebuild.md) |
| M-040 | Architecture | Split AppController observable state into runtime and preferences domains | IN PROGRESS | [#92](https://github.com/6spot/Morie/issues/92) | [`M-040`](./tasks/M-040-app-controller-domains.md) |
| M-041 | Control Center | Redesign the management UI around native grouped Forms and stable workspaces | BLOCKED | [#94](https://github.com/6spot/Morie/issues/94) | [`M-041`](./tasks/M-041-control-center-visual-redesign.md) |
| M-042 | Input quality | Add bounded ephemeral Application Context for Speech and refinement | DONE | [#97](https://github.com/6spot/Morie/issues/97) / [PR #98](https://github.com/6spot/Morie/pull/98) | [`M-042`](./tasks/M-042-application-context.md) |
| M-043 | Control Center | Unify all Control Center pages under one native shell and current Morie design rules | IN PROGRESS | [#99](https://github.com/6spot/Morie/issues/99) / [PR #105](https://github.com/6spot/Morie/pull/105) | [`M-043`](./tasks/M-043-control-center-page-families.md) |
| M-006 | Phase 4 | iOS instant Capture entry points | TODO | — | [`M-006`](./tasks/M-006-ios-capture.md) |
| M-007 | Later | Optional Morie Cloud / API / MCP | TODO | — | [`M-007`](./tasks/M-007-cloud.md) |
