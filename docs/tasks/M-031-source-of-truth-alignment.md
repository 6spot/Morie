# M-031 — Source-of-Truth Alignment

## Status

**DONE** — 2026-09-19

Issue: [#49](https://github.com/6spot/Morie/issues/49)

## Goal

Keep agents and contributors from reintroducing behavior Morie has already replaced. Current runtime contracts must be easy to distinguish from historical design provenance.

## Current contracts aligned

- toggle capture: first accepted shortcut activation starts, the next finishes; Escape cancels while recording;
- ordinary current-app input does not pin or restore the record-start application/window;
- final text follows the external keyboard focus that exists when paste is dispatched;
- one generic clipboard + synthetic `Cmd+V` path remains the delivery contract;
- optional iCloud/CloudKit sync/backup is not a local-input startup gate;
- the visible Dictionary stores canonical words, while explicitly confirmed post-insertion corrections may persist bounded internal observed-ASR → canonical-word mappings;
- `SpeechTranscriber` is preferred, with `DictationTranscriber` only as the Apple-native runtime fallback already implemented by Morie.

## Changes

- reordered `AGENTS.md` source-of-truth precedence so current baseline/architecture/tasks precede historical design provenance;
- amended ADR 0001 to the M-014 current-focus routing contract;
- aligned README, current product baseline, development/validation guidance and the OpenLess reference;
- added explicit amendments to the historical V0 source document instead of rewriting its historical body;
- marked legacy GitHub Issue #1 as superseded/duplicate and rewrote active Phase-0 Issue #2 around the current contract.

## Acceptance criteria

- [x] AGENTS.md does not instruct record-start target capture/focus restore as current behavior.
- [x] ADR 0001 describes delivery-time current-focus routing.
- [x] Current product/readme/development/validation wording agrees with M-014 and M-027.
- [x] Historical design sections remain available but explicit amendments prevent them from overriding current behavior.
- [x] Legacy Phase-0 GitHub issues cannot be mistaken for current execution instructions.
- [x] No runtime/product code is changed.

## Validation

This is documentation/issue metadata only. The repository CI intentionally does not run for documentation-only changes. Validation is a cross-check against current `main` implementation and M-014/M-027 task records.
