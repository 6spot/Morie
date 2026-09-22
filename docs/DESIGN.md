# Design

This document is the source of truth for Morie's global macOS UI and interaction rules.

It defines reusable design constraints only. Feature-specific layouts, page-specific behavior and task history belong in the documentation that owns those features or structures.

## Non-negotiable rule

Morie's user-facing UI **MUST use Apple-native platform patterns and the project's shared global design system before introducing any custom presentation**.

This is a **MUST / MUST NOT** rule, not a preference.

### Reuse the global system

Views at the same hierarchy level **MUST share the same shell, title system, page origin, navigation behavior, spacing rules and control conventions**.

A local view **MUST NOT replace or imitate an existing global pattern with its own visual treatment**.

If a global pattern already exists, reuse or extend it. Do not create a parallel implementation.

### Native before custom

When Apple provides the required behavior, use the native SwiftUI/AppKit API and allow the system to own:

- intrinsic sizing;
- focus and keyboard behavior;
- accessibility;
- materials and appearance;
- platform adaptation;
- control semantics;
- window and layout behavior.

Do not recreate native controls or platform behavior with custom containers, fixed geometry, decorative wrappers or look-alike components.

### No local style inventions

A feature view **MUST NOT introduce local styling rules for concerns already governed globally**.

This includes:

- navigation chrome;
- titles;
- toolbars;
- search;
- outer page layout;
- spacing;
- control geometry;
- grouping;
- materials;
- common interaction patterns.

Implementation details that are not meaningful to the user must remain implementation details and must not leak into presentation merely to fill space or create visual distinction.

### Shared components encode shared rules

Repository-owned UI components are appropriate only when they encode a reusable product-wide rule or provide behavior the native platform does not supply.

A shared component must not exist only to give one feature a unique appearance.

### Exceptions require an explicit decision

A custom UI exception is allowed only when Apple-native and existing global patterns cannot satisfy a concrete product requirement.

Before implementing the exception:

1. identify the missing capability;
2. explain why the native/global pattern is insufficient;
3. keep the custom surface as small as possible;
4. document the exception in the appropriate design or architecture decision.

Do not introduce exceptions silently in implementation code.

## Design foundations

### Purpose before decoration

Every visible element must help the user understand, decide or act.

Do not add cards, color, glass, borders, shadows, animation, icons or secondary containers merely to make a surface look designed.

If an element does not improve hierarchy, feedback, navigation or comprehension, remove it.

### Simplicity is not minimalism

Do not hide useful information or common actions merely to make the interface look sparse.

A simple interface makes the common path obvious and reduces unnecessary decisions.

### Familiarity before invention

Use interaction patterns macOS users already understand.

Prefer native selection, toolbars, sidebars, menus, sheets, confirmation dialogs, keyboard navigation and system controls.

A custom interaction is acceptable only when a concrete product requirement cannot be satisfied by the current native/global pattern and the exception is documented.

### Stable geometry

Frequent navigation and state changes must not make the surrounding shell jump, flash, resize or rebuild unnecessarily.

Async work should update the smallest possible content region.

### Restraint

Morie is a high-frequency productivity tool.

Repeated interactions should feel immediate, quiet and unsurprising.

Do not spend visual or animation attention on interactions users may perform constantly.

## Apple-native implementation order

Use current Apple frameworks and APIs.

Implementation priority:

1. existing shared Morie pattern using native SwiftUI;
2. native SwiftUI component or modifier;
3. AppKit component when SwiftUI is insufficient;
4. minimal repository-owned custom implementation only when the native stack cannot satisfy the requirement.

Do not introduce external UI frameworks, component libraries, animation libraries or design systems without a concrete requirement the native stack cannot reasonably satisfy.

## Navigation and shell

A hierarchy must have one clear structural owner.

Child content may contribute route-specific content and native toolbar/search controls, but must not replace the surrounding navigation shell.

Do not duplicate titles, navigation roots, sidebars or window chrome inside child content.

## Page geometry

Peer views at the same hierarchy level must begin from the same visual coordinate system.

Do not introduce one-off outer margins, title offsets, padding systems or width constraints merely because content differs.

Use content-specific layout inside the shared page geometry.

## Native containers

Choose the native container that matches the information and interaction model.

Use native scrolling, lists, tables, forms and split views rather than simulating them with custom stacks and decoration.

Container choice may vary with content; the surrounding shell and global layout rules must remain consistent.

## Toolbar

Use Apple's native toolbar composition.

Route-specific actions belong to the view that owns their behavior. Do not mirror toolbar business logic in an unrelated parent router.

Do not create custom toolbar configuration arrays, placeholder items, fake toolbar containers or fixed-width compensation slots when native toolbar APIs can express the behavior.

### Semantic grouping

Search, filters and actions must remain visually distinct by function.

Related actions at the same semantic level may use native toolbar grouping.

Do not fuse unrelated control types into one visual group merely to stabilize geometry.

### Search

Prefer native `.searchable` when the platform provides the required search behavior.

Do not simulate native toolbar search with a manually sized text field.

Let the system own intrinsic width, focus, material treatment and window-size adaptation.

## Actions

Common actions should be directly discoverable.

Use menus for secondary, infrequent or overflow actions rather than hiding the normal path.

Destructive actions must use destructive semantics and require confirmation when irreversible.

## Visual hierarchy

Build hierarchy primarily with:

1. typography;
2. spacing;
3. alignment;
4. grouping;
5. native control prominence;
6. selection and state.

Decoration comes after structure.

Do not manufacture hierarchy primarily through custom backgrounds, card stacks, gradients, heavy borders or decorative color.

## Sections and grouping

A section should represent a meaningful conceptual group.

Prefer whitespace, typography and native grouping behavior over boxed containers.

Do not wrap every section in a card.

Do not add separators automatically after every row. Use them only when they clarify structure.

## Configuration surfaces

Configuration UI should use native controls that directly match the value being edited.

Prefer:

- Toggle for boolean state;
- Picker for bounded choices;
- TextField or SecureField for short text;
- TextEditor for long text;
- Stepper when stepwise adjustment is natural;
- Button for an explicit action.

Do not use one control to imitate another.

Common configuration should remain directly visible. Progressive disclosure is reserved for genuinely advanced, rare or potentially confusing controls.

## Information density

Use calm desktop information density.

Avoid:

- oversized empty areas without semantic purpose;
- mobile-style giant cards;
- unnecessarily tall rows;
- excessively large headings;
- decorative padding that pushes useful content away;
- arbitrary fixed control sizes used only to force a composition.

Do not compress content until scanning becomes difficult.

## Typography

Use the macOS system font and semantic text styles.

Use system navigation titles for page titles.

Use semantic hierarchy rather than many arbitrary font sizes.

Do not introduce custom application fonts without an explicit product requirement.

## Color and materials

Use semantic system colors and native materials.

Color communicates meaning, state or priority; it is not decoration.

Do not rely on color alone to communicate state.

Do not manually imitate system materials or Liquid Glass with custom blur, gradient and shadow stacks.

Support light appearance, dark appearance and increased contrast.

## Empty states

Use native empty-state presentation where available.

An empty state should explain what is empty and, when useful, the next meaningful action.

Do not add decorative empty-state UI without informational value.

## Loading and processing

Show activity only when users need to know work is still happening.

Use indeterminate feedback for indeterminate work.

Do not invent fake percentages.

Reserve stable layout where practical and update values in place rather than replacing large structures during loading.

## Errors and success

User-visible errors should describe meaningful product conditions and actionable recovery.

Do not expose raw framework or implementation errors directly.

Use the minimum success feedback necessary. If the resulting state already proves success, do not add redundant banners, screens or delays.

## Motion

Motion must serve a functional purpose:

- feedback;
- spatial consistency;
- state indication;
- preventing a jarring change;
- explaining a rare interaction.

If none apply, do not animate.

The more frequently an interaction occurs, the less motion it should use.

Prefer native transitions and interruptible state changes. Respect Reduce Motion.

## Interaction feedback

Controls should respond immediately.

Prefer native hover, pressed, focus and keyboard behavior.

Do not add custom effects to native controls that already provide correct feedback.

## Selection

Use native selection behavior.

When filtering, deletion or data changes invalidate selection, update or clear it explicitly.

Do not maintain stale hidden selection or draw a second fake selection layer.

## User content

User-created text is primary content.

Prefer natural wrapping, selectable text, readable line length and scrolling where needed.

Do not truncate meaningful user content merely to preserve a visual composition.

## Accessibility

Every new or changed UI must remain compatible with:

- keyboard navigation;
- VoiceOver;
- increased contrast;
- light and dark appearance;
- Reduce Motion;
- native focus behavior.

A custom component assumes responsibility for behavior a native component would otherwise provide automatically.

## Design review checklist

Before accepting a UI change, verify:

1. Does it reuse the existing global pattern for its hierarchy?
2. Does it use the Apple-native component or behavior where one exists?
3. Has any local visual system been invented for a concern already governed globally?
4. Does it preserve the shared title, shell, page origin and navigation behavior?
5. Does it rely on intrinsic/native sizing rather than arbitrary visual compensation?
6. Are search, filters and actions semantically grouped using native toolbar behavior?
7. Is hierarchy created with typography, spacing and alignment before decoration?
8. Is the surface unnecessarily card-heavy or decorative?
9. Is desktop information density appropriate?
10. Does async work update only the smallest necessary region?
11. Does every animation have a functional purpose?
12. Does the result remain correct with keyboard, VoiceOver, dark mode, increased contrast and Reduce Motion?
13. If custom UI was introduced, is the missing native/global capability explicitly documented?

## Design principle

**Global Apple-native design before local invention.**

**Native before custom.**

**Clarity before visual novelty.**

**Simplicity before minimalism.**

**Stable structure before animated polish.**

**Common actions should be visible.**

Morie should feel polished because its interactions behave like a coherent macOS application, not because individual views try to look unique.
