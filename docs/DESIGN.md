# Design

This document defines the UI and interaction rules for Morie.

It applies to all user-facing interfaces. It does not document individual screens or historical UI implementations.

## Apple native UI

Morie uses **Apple's native macOS UI**.

This is the default design and implementation path.

Use current macOS system components provided by SwiftUI, AppKit and Apple system frameworks.

If macOS already provides a component or interaction for the requirement, use it. Do not replace a native component merely because a custom implementation is easier to style or gives more visual control.

The default order is:

1. SwiftUI native component.
2. AppKit native component when SwiftUI is insufficient.
3. Small custom implementation only when no suitable native component exists.

External UI frameworks, component libraries, design systems, rendering runtimes and other UI dependencies should not be introduced unless there is a concrete requirement that cannot reasonably be satisfied with Apple's native stack.

**No external UI dependency by default.**

## Native behavior before custom appearance

Correct macOS behavior has priority over visual customization.

Preserve native focus behavior, keyboard navigation, window behavior, menu behavior, selection, scrolling, resizing, accessibility, system appearance, reduced motion and contrast.

Custom styling must not break native interaction.

## System components

Prefer native system implementations for windows, panels, menus, menu bar items, sidebars, navigation, toolbars, forms, lists, tables, split views, sheets, popovers, alerts, confirmation dialogs, buttons, toggles, pickers, text fields, text editors, search, context menus and progress indicators.

Do not recreate these as custom components when the native component satisfies the interaction.

## Liquid Glass

Liquid Glass is provided by the system.

When a native component already receives the current macOS glass appearance, use that component directly.

Do not imitate system glass using custom combinations of blur, transparency, gradients, overlays, borders, shadows or shaders.

For genuinely custom surfaces that require glass behavior, use Apple's current native APIs.

## One navigation shell

A window should have one clear navigation structure.

Do not let individual pages recreate sidebars, navigation roots, title bars, global toolbars or window-level navigation state.

Navigation belongs to the window shell. Pages provide content.

## Page owns content, shell owns layout

The shell owns sidebar, routing, toolbar placement, window geometry and global navigation.

A page owns its content, local controls, local selection and feature-specific interaction.

Do not make every page invent its own outer margins, scroll container, navigation container or toolbar system.

## Use the native container that matches the content

Choose the system container based on the job of the page.

Use `Form` for settings, `ScrollView` for reading and free-form content, `List` for selectable collections, `Table` for structured tabular data, `NavigationSplitView` for native sidebar navigation, and split views for appropriate workspaces.

Do not force unrelated pages into one universal custom container.

## Stable layout

State changes should update the smallest appropriate part of the interface.

Navigation, sidebar, window shell and unrelated page structure should remain stable while feature content changes.

Do not recreate the surrounding page because loading started, a transcript changed, a background operation completed, selection changed or a small status changed.

## Consistent spacing

Pages at the same hierarchy level should follow the same layout rhythm.

Prefer current system spacing and control metrics. Avoid arbitrary hard-coded geometry when native layout can determine the appropriate size.

## Visual hierarchy

Use native hierarchy before decoration.

Prefer typography, spacing, grouping, alignment, system selection and native control prominence.

Do not create hierarchy primarily through custom cards, borders, background boxes, excessive glass or decorative colors.

## Avoid card-heavy UI

Do not turn every section into a card.

Use the natural native page structure first. A grouped surface should exist because the content forms a meaningful group, not because every block needs a background.

## Color

Use system semantic colors.

Color should communicate state or meaning rather than decorate the interface. Do not depend on color alone.

Support light mode, dark mode and increased contrast.

## Typography

Use system typography.

Prefer semantic system text styles and weights. Do not create a collection of arbitrary font sizes simply to manufacture hierarchy.

## Controls

Use the native control matching the interaction: Toggle for boolean state, Picker for choices, Button for actions, TextField or SecureField for short input, TextEditor for multiline input, Menu for secondary actions, and native confirmation for destructive actions.

## Toolbars

Use the native toolbar for actions belonging to the current window, workspace, page or selection.

Do not create toolbar-like rows inside content when the system toolbar is appropriate.

## Settings

Configuration interfaces use normal macOS settings patterns.

Prefer native Form and native controls. Use progressive disclosure for advanced configuration when appropriate.

Do not turn Settings into a custom dashboard, and do not turn ordinary product pages into Settings forms merely for visual consistency.

## Selection

Selection should use native selection behavior.

When filtering, deleting or changing data makes the current selection invalid, clear or update it explicitly.

Do not maintain invisible stale selection or draw a second custom selection layer over native selection.

## Empty states

Use native empty-state presentation where available.

An empty state should communicate what is empty and the natural next action when one exists.

## Loading and processing

Show activity when users need to know work is still running.

Use indeterminate feedback for indeterminate work. Do not invent progress percentages for operations whose progress cannot actually be measured.

## Success feedback

Use the minimum feedback needed to confirm success.

If the resulting state already makes success obvious, additional banners, checkmarks, success pages, artificial delays or bright success colors are usually unnecessary.

## Errors

User-visible errors should explain a meaningful product condition.

Do not surface internal framework or implementation errors directly. Prefer contextual or inline feedback when a modal interruption is unnecessary.

Technical details belong in diagnostics.

## Motion

Motion should communicate appearance, disappearance, state transition, spatial relationship or ongoing indeterminate activity.

Do not animate purely for decoration. Respect Reduce Motion.

## Floating UI

Temporary floating UI must remain subordinate to the application the user is working in.

Do not steal keyboard focus unless interaction genuinely requires it.

Floating surfaces should be compact, temporary and purpose-specific.

## Content density

Morie is a desktop application.

Use space efficiently. Do not introduce excessive whitespace merely to create a stylized appearance, and do not compress information to the point of harming readability.

## User content

User-created text is primary content.

Prefer readable line length, selectable text, natural wrapping and scrolling where needed.

Do not truncate meaningful user content to preserve decorative geometry.

## Accessibility

New or changed UI must remain compatible with keyboard navigation, VoiceOver, increased contrast, light and dark appearance, and reduced motion where relevant.

A custom component assumes responsibility for behavior that a native control would otherwise provide automatically.

## External UI dependencies

External UI dependencies are **not part of the normal Morie design stack**.

Do not introduce a third-party UI framework or component library simply for styling, convenience, custom navigation, custom controls, animation, glass effects or layout helpers.

Consider an external dependency only when there is a concrete requirement that cannot reasonably be achieved with current SwiftUI, AppKit or other Apple-native APIs.

Prefer a small repository-owned implementation when the missing behavior is small. Do not build a large custom UI framework either.

## Design consistency

Consistency means using the same interaction language and native system conventions.

It does not mean every page must look structurally identical.

Different jobs may appropriately use different native components while sharing navigation behavior, spacing rhythm, typography hierarchy, control conventions, feedback behavior and system appearance.

## Design principle

**Use Apple native macOS components by default.**

**Do not replace native UI without a real requirement.**

**Do not introduce external UI dependencies without necessity.**

Morie should feel native because it is built from the platform's own components and behaves according to macOS conventions.
