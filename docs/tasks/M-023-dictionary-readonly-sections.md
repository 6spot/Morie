# M-023 — Dictionary Read-only Sections

## Status

**IN PROGRESS** — 2026-09-19

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


## 2026-09-19 implementation

The Dictionary presentation is now explicitly split by ownership:

\`\`\`text
用户添加
  manual + correction
  selectable / editable / deletable

系统内置
  builtIn
  static read-only text
  no selection / button / context menu / edit / delete
\`\`\`

Built-ins use semantic secondary foreground and quaternary background treatment so their read-only ownership is visible without inventing a custom design language. They are rendered as static SwiftUI text rather than disabled buttons, so pointer, keyboard and VoiceOver semantics no longer imply an action.

Search still applies to both sections. Empty section headers are hidden during filtered search; in the normal unfiltered state the user section remains visible even when empty so the Add action and ownership model are obvious.

No source/provenance, persistence schema, Speech hint, cleanup or dictionary matching behavior changed.


## Validation

GitHub Actions \`macOS 27 CI\` run #78 passed the Release product compile on Xcode 27/macOS 27.

The repository CI does not currently execute \`MorieTests\`, so the existing Dictionary logic tests remain unexecuted in hosted CI. Owner visual/keyboard/VoiceOver validation remains open; the task stays IN PROGRESS until that interaction check is complete.
