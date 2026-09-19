# M-023 — Dictionary Read-only Sections

## Status

**TODO** — 2026-09-19

Issue: [#23](https://github.com/6spot/Morie/issues/23)

## Goal

Make Dictionary provenance obvious: user-controlled terms are actionable, while Morie built-ins are visibly system-owned and non-interactive.

## Current baseline

The backend already distinguishes `builtIn`, `manual` and `correction`. Built-ins are code-owned and `isEditable == false`, but the current grid merges all sources and renders every entry as a Button, so built-ins still look selectable.

## Planned interaction

- Section **用户添加**: manual + correction-confirmed terms, selectable/editable/deletable.
- Section **系统内置**: built-in terms only, semantically differentiated and not clickable/selectable.
- Explain that built-ins help recognition and cannot be modified or removed.
- Search both groups while hiding empty groups.
- Preserve current Speech hint/provenance behavior and persistence schema.

## Acceptance criteria

- Built-ins cannot become selection and never enable edit/delete actions.
- User terms preserve existing edit/delete behavior.
- Built-ins have no context menu or button press affordance.
- VoiceOver communicates built-in terms as read-only text rather than actions.
- No schema migration or new dependency.
- macOS 27 compile and Dictionary tests pass.
