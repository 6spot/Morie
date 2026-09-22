# Design

This document is the source of truth for Morie's macOS UI and interaction design.

It applies to every user-facing surface: Control Center, History, Dictionary, Personal Memory, Settings, Permissions, diagnostics, floating capture UI and future macOS features.

The goal is not to make Morie look custom. The goal is to make it feel **native, fast, predictable and carefully made**.

## Non-negotiable Apple-native UI rule

This is a **MUST / MUST NOT** rule, not a preference.

Morie's user-facing UI **MUST use Apple-native platform patterns and the project's shared global design system before introducing any custom presentation**.

### Reuse the global system

Views at the same hierarchy level **MUST share the same shell, title system, page origin, navigation behavior, spacing rules and control conventions**.

A local view **MUST NOT replace or imitate an existing global pattern with its own visual treatment**.

If a global pattern already exists, extend or reuse it. Do not create a parallel implementation.

### Native before custom

When Apple provides the required behavior, use the native SwiftUI/AppKit API and allow the system to own intrinsic sizing, focus behavior, materials, accessibility, platform adaptation and interaction semantics.

Do not recreate native controls or platform behavior with custom containers, fixed geometry, decorative wrappers or look-alike components.

### No local style inventions

A feature view **MUST NOT introduce page-local styling rules for concerns that are already governed globally**.

This includes navigation chrome, titles, toolbars, search, outer layout, spacing, control geometry, materials, grouping and common interaction patterns.

Implementation details that are not meaningful to the user must remain implementation details and must not leak into presentation merely to fill space or create visual distinction.

### Shared components encode shared rules

Repository-owned UI components are appropriate only when they encode a reusable product-wide rule or provide behavior that the native platform does not supply.

A shared component must not exist only to give one feature a unique appearance.

### Exceptions require an explicit decision

A custom UI exception is allowed only when the Apple-native and existing global patterns cannot satisfy a concrete product requirement.

Before implementing the exception:

1. identify the missing capability;
2. explain why the existing global/native pattern is insufficient;
3. keep the custom surface as small as possible;
4. document the exception in the appropriate design or architecture decision.

Do not introduce exceptions silently in implementation code.

## Design foundations

Morie follows these principles in order.

### Purpose before decoration

Every visible element must help the user understand, decide or act.

Do not add cards, color, glass, borders, shadows, animation, icons or secondary containers only to make a page look designed.

If an element does not improve hierarchy, feedback, navigation or comprehension, remove it.

### Simplicity is not minimalism

Do not hide useful information or common actions merely to make the interface look sparse.

A simple interface makes the common path obvious and keeps the number of decisions small.

Adding a useful label, status, action or explanation can make an interface simpler if it removes uncertainty.

### Familiarity before invention

Use the interaction patterns macOS users already understand.

Use native selection, toolbar placement, sidebars, menus, sheets, confirmation dialogs, keyboard navigation and system controls.

For page-level UI and Control Center structure, native/global patterns are mandatory. Do not replace them with a custom pattern merely because another layout seems visually interesting.

A custom interaction is acceptable only when a concrete product requirement cannot be satisfied by the current Apple-native/global pattern and the exception is documented.

### Stable geometry builds trust

Frequent navigation and state changes must not make the shell jump, flash, resize or rebuild.

Sidebar, window title area, toolbar structure and page origin should remain visually stable while route-specific content changes.

Async work should update the smallest possible content region.

### Restraint

Morie is a high-frequency productivity tool.

Repeated interactions should feel immediate, quiet and unsurprising.

Do not spend visual or animation attention on things the user may see dozens or hundreds of times a day.

## Apple-native implementation

Morie uses **Apple's native macOS UI stack**.

Use current SwiftUI, AppKit and Apple system frameworks.

Implementation priority:

1. SwiftUI native component and the existing global Morie page/shell pattern.
2. AppKit native component when SwiftUI is insufficient.
3. Small repository-owned custom implementation only when the native stack and existing global pattern cannot satisfy the requirement.

For Control Center page structure and common macOS controls, this priority is mandatory. Do not skip directly to a custom implementation.

Do not introduce an external UI framework, component library, animation library or design system without a concrete requirement that cannot reasonably be met with Apple's native stack.

**No external UI dependency by default.**

## Native behavior before custom appearance

Correct macOS behavior has priority over visual customization.

Preserve:

- focus and keyboard navigation;
- native selection;
- window and split-view resizing;
- menu and toolbar behavior;
- scrolling;
- accessibility;
- light and dark appearance;
- increased contrast;
- Reduce Motion;
- system control sizing and hit targets.

Custom styling must not break native interaction.

## One window shell

A Control Center window has one persistent structural shell.

The shell owns:

- sidebar;
- route selection;
- navigation stack;
- primary title;
- top-level toolbar;
- window geometry.

Pages provide content.

A routed page must not create a replacement sidebar, navigation root or title-bar shell. The current routed page may contribute route-specific toolbar/search controls to the persistent NavigationStack using Apple's native SwiftUI toolbar APIs.

## Page coordinate system

Top-level pages at the same hierarchy level must begin from the same visual coordinate system.

Overview, Dictionary, Personal Memory, Settings and Permissions use the same outer content inset and content origin.

A page must not introduce a different outer margin merely because it uses a different native control internally.

Do not let default Form/List margins silently create a different page geometry.

History and Diagnostics may use full-size workspace layouts, but they must remain subordinate to the outer Control Center shell.

## Containers are content choices, not alternate shells

Use the native container that matches the content:

- `ScrollView` for reading and free-form content;
- `List` for selectable collections;
- `Table` for structured tabular data;
- `Form` or form-like native controls for configuration content when appropriate;
- split views for workspace-style content.

These containers live **inside the shared page shell**.

Do not switch the whole right-side root between unrelated container systems.

## Toolbar

The Control Center keeps one persistent NavigationStack/window toolbar surface.

Route-specific controls are declared by the routed page that owns them, using Apple's native `.searchable` and `.toolbar` APIs. The shell/router must not contain a route switch that reconstructs page-specific toolbar business logic, custom action arrays, AnyView wrappers, placeholder items or fixed-width fake toolbar slots.

### Toolbar controls preserve semantic grouping

Search, filters and actions must remain visually distinct by function.

Do not merge a search field with action buttons, or a filter control with unrelated actions, into one large custom capsule or fake toolbar surface merely to keep geometry stable.

Related action buttons at the same semantic level may use native macOS toolbar grouping. For example, Edit / Delete / Add may appear as one action group.

Prefer this structure:

- search field;
- fixed visual separation;
- filter when present;
- fixed visual separation;
- one related action group.

Stability must come from native toolbar structure, not from visually fusing unrelated control types together.

### Search

When search belongs to the current route, prefer Apple-native `.searchable(text:placement:prompt:)` with toolbar placement unless the page specifically requires inline search.

Do not simulate toolbar search with a manually sized TextField. Let macOS own the search field's intrinsic width, glass/material treatment, focus behavior and window-size adaptation.

Search state belongs to route/page presentation state, not to the global application controller.

### Action visibility

Common and important actions should be directly visible.

Use a `Menu` for secondary, infrequent or overflow actions — not to hide the normal path.

Do not bury an action merely to reduce the number of visible controls.

Destructive actions should be visually restrained and confirmed when irreversible.

## Visual hierarchy

Build hierarchy primarily with:

1. typography;
2. spacing;
3. alignment;
4. grouping;
5. native control prominence;
6. selection/state.

Decoration comes after structure.

Do not manufacture hierarchy primarily through custom backgrounds, heavy borders, card stacks, gradients or decorative color.

## Section design

A section should represent a meaningful conceptual group.

Use a clear section title, then the controls/content, then optional explanatory text.

Prefer whitespace and typography over boxed containers.

Do not wrap every section in a card.

Do not add a divider after every row automatically. Use separation only where it clarifies structure.

## Settings design

Settings is configuration, not a dashboard.

Settings should use the shared Control Center page geometry and native controls.

A good Settings section normally contains:

- a concise heading;
- direct controls;
- current status when useful;
- short explanatory text only where the behavior is not obvious.

### Show common controls directly

Frequently used or conceptually important settings should be visible without expansion.

Do not use `DisclosureGroup` simply to make a page look shorter.

Use progressive disclosure only for genuinely advanced, rare or potentially confusing configuration.

Examples that may justify progressive disclosure:

- raw provider/API configuration;
- advanced diagnostic details;
- expert-only model parameters.

Even then, the collapsed state must clearly communicate what is inside and its current status.

### Avoid setting-row ambiguity

A label should make clear what a control changes.

Prefer:

- Toggle for boolean state;
- Picker for bounded choices;
- TextField/SecureField for short values;
- TextEditor for long prompts;
- Stepper only when stepwise adjustment is natural;
- Button for an explicit action.

Do not use a Button to imitate a Toggle or Picker.

### Destructive settings

Actions such as clearing learned data or factory reset must:

- use destructive semantics;
- explain the scope clearly;
- require confirmation when irreversible;
- never be visually confused with ordinary configuration.

Factory reset means restoring Morie-owned state to first-run defaults. macOS-owned system permissions are outside Morie's control and must be described separately.

## Overview design

Overview is a status summary, not a diagnostics dump.

The first screen should answer quickly:

- what Morie is currently using;
- whether the main capabilities are ready;
- useful high-level usage information;
- the current model/backend.

Do not give implementation/debug metadata the same visual weight as user-facing status.

Development-only diagnostics may appear in development builds, but they should be visually subordinate.

### Stable async metrics

Overview must reserve layout for async values before data arrives.

Do not replace an entire block such as a ProgressView with a structurally different Grid after loading.

Prefer stable placeholders such as `—`, then update only the values.

Async metric refreshes must not invalidate the window shell or toolbar.

## Dictionary design

Dictionary is a lightweight management surface.

Priorities:

1. fast search;
2. clear distinction between user entries and built-in entries;
3. direct add/edit/delete for editable entries;
4. visible count/status;
5. no unnecessary navigation depth.

Built-in entries must look read-only without appearing disabled or broken.

Do not decorate every word as a heavy card.

Use compact native density suitable for desktop scanning.

## Personal Memory design

Personal Memory should explain Morie's understanding, not expose raw storage.

Priorities:

1. stable long-term memory;
2. recent context;
3. clear provenance/status where useful;
4. direct edit/delete when appropriate;
5. readable grouping by topic.

Avoid raw database-style rows.

Do not hide ordinary memory content behind disclosure controls merely to reduce vertical length.

Archived/history content may be visually secondary, but should remain easy to inspect.

## History design

History is a desktop workspace.

The list and detail panes should remain stable while selection changes.

The workspace must never impose minimum widths that squeeze or distort the outer sidebar.

### History detail

The selected record detail should expose the useful information directly.

Do not require repeated disclosure for ordinary record data.

Recognition/refinement information and original recording controls should be visible when a record is selected.

Common record actions such as copy, re-recognize and delete should be directly available unless there is a strong reason to demote them.

Use menus only for true overflow/secondary actions.

## Permissions design

Permissions should show:

- current device capability status;
- current permission status;
- the action required to resolve a missing permission;
- a direct Recheck action in the top-level toolbar.

Do not duplicate the same refresh action in both the toolbar and page content unless there is a specific usability reason.

## Information density

Morie is a desktop productivity application.

Use space efficiently.

Avoid:

- oversized empty areas with no semantic purpose;
- mobile-style giant cards;
- unnecessarily tall rows;
- excessively large headings;
- decorative padding that pushes useful information below the fold.

At the same time, do not compress information until scanning becomes difficult.

The target is calm desktop density: compact enough to scan, spacious enough to understand.

## Typography

Use the macOS system font and semantic text styles.

Hierarchy should come from appropriate system size and weight, not many arbitrary font sizes.

Guidelines:

- page title: system navigation title;
- section heading: headline/subheadline as appropriate;
- primary content: body;
- metadata/help text: callout/caption/secondary;
- numeric metrics: tabular/monospaced digits where value stability matters.

Do not use custom fonts for application UI without a product requirement.

## Color

Use semantic system colors.

Color communicates state, priority or meaning.

Do not use color as decoration.

Do not rely on color alone to communicate state.

Support light mode, dark mode and increased contrast.

## Borders, backgrounds and shadows

Use system materials and separators before custom borders.

Avoid opaque card outlines around ordinary content.

Avoid shadows on flat management/settings content unless the surface truly floats above another surface.

Do not imitate Liquid Glass with custom blur/gradient/shadow stacks.

If the system already provides current macOS glass/material behavior, use it directly.

## Empty states

Use native empty-state presentation where available.

An empty state should answer:

- what is empty;
- whether that is normal;
- what the user can do next.

If a natural next action exists, show it directly.

## Loading and processing

Show activity only when users need to know work is still happening.

Use indeterminate feedback for indeterminate work.

Do not invent fake percentages.

Do not replace large portions of stable layout merely to show loading.

Prefer to reserve the final layout and update values in place.

## Errors

User-visible errors should explain a meaningful product condition and what the user can do.

Do not surface raw framework or implementation errors directly.

Prefer contextual/inline feedback when a modal interruption is unnecessary.

Technical details belong in Diagnostics.

## Success feedback

Use the minimum feedback needed.

If the resulting state already proves success, do not add another banner, success screen, bright green state or artificial delay.

## Motion

Morie should use less motion than a consumer entertainment app.

Motion must serve one of these purposes:

- feedback;
- spatial consistency;
- state indication;
- preventing a jarring visual change;
- explaining a rare/first-run interaction.

If none apply, do not animate.

### Frequency rule

The more frequently an interaction occurs, the less motion it should use.

- keyboard/global shortcut actions: no decorative transition;
- sidebar/page switching: instant or effectively imperceptible;
- frequently used toolbar/list interactions: minimal feedback only;
- sheets/popovers: normal native transition;
- rare onboarding/empty/success moments: may use more expressive motion.

Do not animate navigation simply to make it feel modern.

### Animation behavior

Prefer native system animation behavior.

For custom motion:

- keep UI feedback fast;
- prefer interruptible state changes;
- preserve spatial continuity;
- enter and exit along the same conceptual path;
- animate transform/opacity rather than layout where possible;
- avoid bounce unless momentum or physical interaction justifies it;
- respect Reduce Motion.

## Press and interaction feedback

Controls should feel responsive immediately.

Prefer the native macOS pressed/hover/focus behavior.

Do not add custom scale effects to native controls that already provide correct feedback.

Custom controls must provide equivalent immediate feedback and keyboard/accessibility behavior.

## Selection

Use native selection behavior.

When filtering, deleting or changing data invalidates the current selection, clear or update it explicitly.

Do not maintain hidden stale selection.

Do not draw a second fake selection layer over native selection.

## User content

User-created text is primary content.

Prefer:

- natural wrapping;
- selectable text;
- readable line length;
- scrolling where necessary;
- full content over decorative truncation.

Do not truncate meaningful user content merely to preserve a visual composition.

## Floating capture UI

Floating capture UI must remain subordinate to the application the user is working in.

It should:

- respond immediately;
- avoid stealing keyboard focus unless required;
- remain compact;
- use spatially consistent enter/exit behavior;
- clearly communicate recording/thinking/cancel state;
- disappear as soon as the interaction is complete.

Do not add decorative motion that slows repeated voice input.

## Accessibility

Every new or changed UI must remain compatible with:

- keyboard navigation;
- VoiceOver;
- increased contrast;
- light/dark appearance;
- Reduce Motion;
- native focus behavior.

A custom component assumes responsibility for behavior a native component would otherwise provide automatically.

## Design review checklist

Before accepting a UI change, verify:

1. Is this using the existing global Morie pattern and Apple-native macOS component where one exists?
2. Does this page keep the exact same page-title system and page origin as its peers, without a custom replacement header?
3. Has any page-specific visual invention been introduced that should instead be removed or shared globally?
4. Is the common action directly visible?
5. Is anything hidden only to make the interface look cleaner?
6. Does the page begin from the same coordinate system as peer pages?
7. Does route/state change keep sidebar, title and toolbar geometry stable?
8. Does the page use Apple-native searchable/toolbar APIs, with search/filter/actions semantically separated and only related actions grouped?
9. Is hierarchy created with type/spacing/alignment before decoration?
10. Is the page unnecessarily card-heavy?
11. Is desktop information density appropriate?
12. Does async work update only the smallest necessary region?
13. Does every animation have a functional purpose?
14. Would a high-frequency user find this interaction slower or more distracting after the hundredth use?
15. Does the page still work with keyboard, VoiceOver, dark mode, increased contrast and Reduce Motion?

## Design principle

**Global Apple-native design before page-specific invention.**

**Native before custom.**

**Clarity before visual novelty.**

**Simplicity before minimalism.**

**Stable structure before animated polish.**

**Common actions should be visible.**

**High-frequency workflows should feel immediate.**

Morie should feel polished because every small interaction behaves exactly as a macOS user expects — not because the interface is visually loud.
