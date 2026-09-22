# Architecture

This document is the structural map of Morie.

Use it to understand how the repository is organized, where new code belongs, how major components depend on each other, how the main runtime flows through the system, and which component owns which state.

For product behavior, read `PRODUCT.md`. For engineering rules, read `DEVELOPMENT.md`.

## Architecture overview

Morie is organized into four main areas:

- `App`: application composition and cross-feature coordination.
- `Features`: product functionality and product state.
- `Platform`: macOS / Apple framework integration and external system boundaries.
- `Support`: shared infrastructure that does not own product behavior.

Persistence currently belongs to the feature that owns the data. There is no generic repository-wide Persistence layer simply for architectural symmetry.

## Repository layout

The current source tree is organized approximately as follows:

- `Morie/App/`
  - application entry, composition and application-level state
- `Morie/Features/Capture/`
  - live Capture lifecycle, Speech, refinement, persistence and History
- `Morie/Features/Dictionary/`
  - Dictionary data, correction data and Dictionary UI
- `Morie/Features/Memory/`
  - Personal Memory storage, retrieval, learning and UI
- `Morie/Features/Personalization/`
  - post-insertion learning and expression profile behavior
- `Morie/Features/Setup/`
  - setup and permission UX
- `Morie/Platform/Capabilities/`
  - operating-system capability checks
- `Morie/Platform/Input/`
  - global input / shortcut integration
- `Morie/Platform/TextDelivery/`
  - cross-application text delivery
- `Morie/Platform/Cloud/`
  - external model and cloud-facing configuration
- `Morie/Support/`
  - diagnostics and genuinely shared infrastructure
- `Morie/Resources/`
  - bundled runtime resources
- `MorieTests/`
  - tests organized around the same ownership boundaries

The exact file list may evolve. The ownership represented by these directories is the important part.

## Where new code goes

Before creating a new file, identify which area owns the responsibility.

### App

Use `App/` when code exists to compose or coordinate the application as a whole.

Examples include application startup, connecting major features, application-wide state, applying preference changes across boundaries and application-level routing.

Do not place feature implementation here merely because `AppController` can access everything.

### Features

Use `Features/` when the code represents something Morie itself does.

Examples:

- voice Capture → `Features/Capture/`
- History → `Features/Capture/History/`
- Dictionary → `Features/Dictionary/`
- Personal Memory → `Features/Memory/`
- post-input learning → `Features/Personalization/`
- permission/setup UX → `Features/Setup/`

Feature-specific models, controllers, stores and views should normally remain with the feature that owns them.

### Platform

Use `Platform/` when the responsibility exists because Morie integrates with macOS, Apple frameworks or another external system.

Examples:

- global keyboard events → `Platform/Input/`
- text insertion / clipboard → `Platform/TextDelivery/`
- system capability checks → `Platform/Capabilities/`
- external model configuration → `Platform/Cloud/`

Platform code provides capabilities to Features. It does not own product workflows.

### Support

Use `Support/` for genuinely cross-cutting infrastructure such as diagnostics.

Do not use `Support/` as a miscellaneous folder.

### Resources

Use `Resources/` for bundled runtime resources such as default prompts, localized resources, sounds and static application assets.

Business behavior does not belong in Resources.

### Tests

Tests should follow the ownership of production code.

Capture tests belong under Capture tests, Dictionary tests under Dictionary tests, Memory tests under Memory tests, and so on.

Detailed test rules belong in `TESTING.md`.

## Dependency direction

The normal dependency direction is:

`App → Features → Platform`

Feature-owned storage remains owned by the Feature.

UI sits at the outer edge:

`View → Feature state/actions → Feature implementation → Platform or storage`

Views should communicate with the feature that owns the behavior rather than calling platform or persistence code directly.

## Dependency rules

### App may depend on Features

`AppController` may create and connect feature controllers.

Features should not use `AppController` as a global service locator.

### Features may depend on Platform capabilities

The Feature owns the workflow. Platform owns operating-system integration.

For example, Capture may use Speech/Audio and TextDelivery, while Setup may use Capabilities.

### Platform must not own Feature state

A platform component may perform its system operation and return a result.

It must not decide Capture state, History state, Memory state or whether a product workflow should continue.

### Feature UI must not become shared application state

SwiftUI views consume feature state.

Recreating a view must not recreate unrelated product workflows unless that lifecycle is intentionally part of the feature.

### Cross-feature dependencies must be explicit

Features may collaborate when the product flow requires it, but one feature should not reach into another feature's internal mutable state.

Expose the narrow capability or data required by the caller.

## Application composition

`AppController` is the current application composition and coordination boundary.

Conceptually it connects Runtime, Capabilities, Preferences, Capture, History, Dictionary, Memory and Personalization.

Its role is to receive an application-level action, delegate to the owning feature and coordinate cross-feature results when necessary.

If logic can be described entirely as part of Capture, Dictionary, Memory, History or another feature, it normally belongs there rather than in `AppController`.

## Application state

Application-visible state is separated by responsibility.

### AppRuntimeController

Owns frequently changing live runtime presentation state such as current Capture phase and progressive transcript.

### AppCapabilityController

Owns capability and bootstrap presentation state such as setup requirements, bootstrap state, capability availability and the prepared Speech backend.

### AppPreferencesController

Owns application preference values used by the UI.

Side effects caused by preference changes are coordinated with the appropriate owning subsystem.

## Control Center ownership

Morie separates the always-running voice-input runtime from the occasional Control Center UI at the **process boundary**.

The resident Morie process owns the menu bar, global shortcut, live Capture workflow, Speech, refinement, delivery, background learning and runtime maintenance. It does not construct the Control Center SwiftUI/AppKit window hierarchy.

Opening the Control Center launches a new instance of the same signed Morie application with the Control Center process role. The launcher uses the native `NSWorkspace.OpenConfiguration` new-instance capability rather than an additional helper executable or third-party process manager. Reusing the same application identity preserves the existing macOS permission identity, Keychain access, UserDefaults domain and application data locations without introducing a second product bundle.

The Control Center process:

- owns the Control Center `Window`, `NavigationSplitView`, sidebar and routed page hierarchy;
- opens the existing SwiftData-backed product data for presentation and explicit user edits;
- does not recover interrupted Captures, prune audio, install the global shortcut, prepare Speech, start Memory learning or run other resident-runtime bootstrap work;
- proxies runtime-only actions such as starting a Capture, re-enabling runtime bootstrap and factory reset back to the resident process;
- notifies the resident process after persisted configuration changes so its in-memory runtime configuration is refreshed;
- terminates when the Control Center window closes.

Process termination is the memory ownership boundary for SwiftUI/AppKit/CoreUI/font/language-service allocations warmed by Control Center presentation. Do not attempt to make the resident runtime purge framework-owned UI caches with `malloc` tricks, artificial cleanup loops or page-specific memory workarounds.

Within the Control Center process, the UI still has one persistent window-level presentation owner.

`MorieControlCenter` owns exactly one persistent `NavigationSplitView` and one persistent detail `NavigationStack`. A Control Center session owns only state that must survive route changes, such as the selected destination, sidebar visibility and cross-route selections.

`ControlCenterRouteHost` only resolves the selected route into page content. Every route is rendered inside the same persistent `ControlCenterDetailHost`; the router must not replace the right-side root with different ScrollView/Form/workspace containers.

The persistent detail host owns the primary navigation title and stable navigation shell. Route-specific toolbar intent belongs to the routed page that owns the behavior. Pages use Apple-native `.searchable(..., placement: .toolbar)`, `.toolbar`, `ToolbarItem`, `ToolbarItemGroup` and `ToolbarSpacer` directly; the router/host must not mirror route business logic or translate custom toolbar configuration arrays. Search/filter/action state remains page or Control Center presentation state and is shared through normal SwiftUI bindings. Secondary pushed destinations may contribute their own native title/actions.

Overview, Dictionary, Personal Memory, Settings and Permissions share the same `ControlCenterScrollableContent` geometry and the same 24-point outer content inset. Overview metrics live in a dedicated page state rather than `ControlCenterSession`, so asynchronous metric refreshes do not invalidate the window-level shell or toolbar. They must not introduce route-specific outer widths or an alternate top-level Form margin model. History and Diagnostics are full-size internal workspaces, but their split-view minimum widths must remain subordinate to the outer NavigationSplitView and must never squeeze the sidebar below its supported width range.

Routed feature views own their feature-specific presentation state and actions; they must not create replacement Control Center navigation shells or move unrelated feature state into the resident `AppController`.

Control Center presentation data follows the Control Center process/window lifecycle.

- Overview never scans Capture history when the window opens. Capture usage metrics are persisted incrementally with Capture persistence and Overview reads only the small aggregate snapshot.
- History owns a presentation-only `CaptureHistoryController` and `ModelContext` created for the Control Center session. The first page is bounded, further records load on demand, and the list/context/player are released when History is left. Closing the window additionally terminates the entire presentation process.
- Diagnostics writes runtime logs to disk regardless of UI visibility, but its in-memory Entry collection exists only while the Diagnostics page is visible.
- Search, filters, selections and page snapshots belong to `ControlCenterPresentationState`.
- Runtime Dictionary/Memory state remains conceptually separate from Control Center presentation state because the resident Capture pipeline can use those domains while no Control Center process exists.

Do not attach History/Diagnostics/Overview presentation collections to a resident application-lifetime owner.
## Core input flow

The primary interactive flow is:

Global shortcut / Capture action
→ AppController
→ CaptureSessionController
→ SpeechPipeline
→ recognized text
→ Dictionary / deterministic preparation
→ CapturePersonalizer
→ InputRefiner
→ final text
→ TextInjector
→ current target application

Persistence participates at explicit points through:

`CaptureSessionController → CaptureStore / CapturePersistenceWriter`

The Capture feature owns the complete interaction. Lower-level components do not control the overall Capture lifecycle.

## Capture ownership

`CaptureSessionController` owns an active Capture.

It owns the relationship between Capture identity, recording, Speech, finish/cancellation, refinement, delivery and terminal state.

Speech does not own the Capture. Refinement does not own the Capture. Delivery does not own the Capture.

They perform operations requested by the Capture workflow and return results.

## Speech flow

Speech currently sits inside the Capture feature:

`CaptureSessionController → SpeechPipeline → Apple Speech / Audio → transcript + source audio`

`SpeechPipeline` owns recognition and audio-session behavior.

The caller owns what happens to the recognition result.

## Refinement flow

Refinement is separate from recognition:

recognized text
→ Capture preparation
→ bounded Dictionary / Memory / other context
→ InputRefiner
→ final text

`InputRefiner` owns interaction with the selected language model.

The rest of the Capture pipeline consumes a refinement result without owning provider-specific model behavior.

## Delivery flow

Text delivery is a Platform capability:

`Capture → final text → TextInjector → macOS clipboard/input events → target application`

`TextInjector` returns delivery success or failure.

It does not update Capture, History or Memory directly.

## Persistence flow

Capture runtime state and durable Capture data are separate.

`live Capture state → persistence snapshot → CapturePersistenceWriter / CaptureStore → SwiftData`

Live runtime processing should not share mutable SwiftData model objects across asynchronous boundaries.

Persistence receives explicit data from the owning Feature.

## History flow

History operates on persisted Capture data:

`CaptureStore → CaptureHistoryController → History UI`

History may start explicit operations such as re-recognition, but it does not become the owner of the current live Capture.

## Dictionary flow

Dictionary is an independent Feature.

`DictionaryStore → Speech hints / refinement context / deterministic correction`

Capture consumes Dictionary output. Capture does not own Dictionary storage, and Dictionary does not own Capture.

## Personal Memory flow

Memory has two separate directions.

Memory as context:

`MemoryStore → MemoryContextRetriever → bounded relevant context → Capture refinement`

Memory learning:

`completed Capture → MemoryLearningController → MemoryLearner → MemoryStore`

Memory learning is not part of the direct input-delivery chain.

## Post-insertion learning

Optional learning after delivery is owned separately from Capture:

`successful Morie insertion → PostInsertionLearningController → bounded observation → Dictionary / ExpressionProfile`

The Capture may start this process. It does not remain responsible for the learning workflow afterward.

## Primary and secondary flows

The primary interactive flow is:

`Capture → Speech → Refinement → Delivery`

Secondary flows include History persistence, Memory learning, post-insertion learning, maintenance and diagnostics.

Secondary flows may consume results from the primary flow. They must not become required owners of the active Capture.

## State ownership map

| State / responsibility | Owner |
| --- | --- |
| Application composition | `AppController` |
| Live application runtime state | `AppRuntimeController` |
| Capability/bootstrap state | `AppCapabilityController` |
| User preference state | `AppPreferencesController` |
| Active voice interaction | `CaptureSessionController` |
| Speech/audio recognition session | `SpeechPipeline` |
| Refinement execution | refinement layer / `InputRefiner` |
| Cross-application text delivery | `TextInjector` |
| Capture durable data | `CaptureStore` |
| Ordered Capture writes | `CapturePersistenceWriter` |
| History interaction | `CaptureHistoryController` |
| Dictionary data | `DictionaryStore` |
| Personal Memory data | `MemoryStore` |
| Memory background learning | `MemoryLearningController` |
| Post-insertion observation | `PostInsertionLearningController` |
| Diagnostics | `Diagnostics` |

When adding behavior, start by identifying its owner.

If no existing owner fits, determine whether the new responsibility represents a real new feature or platform boundary before creating another global controller.

## Adding new code

Use this decision path:

- Product behavior → `Features/`
- macOS / Apple / external-system integration → `Platform/`
- application-wide composition or coordination → `App/`
- genuinely shared infrastructure without product ownership → `Support/`
- bundled static resource → `Resources/`

Within `Features/`, place the code with the feature that owns the behavior.

Do not place code based only on which existing object is easiest to access.

Place it based on ownership.

## Structural invariants

The following relationships should remain easy to see:

- App coordinates Features.
- Features own product behavior.
- Platform owns system integration.
- Feature-owned stores own durable feature data.
- UI consumes state and sends actions.
- Lower-level capabilities return results to their owner.
- Background flows consume primary-flow output rather than owning primary flow.

If a change makes these relationships unclear, reconsider where the responsibility belongs.

## Keeping this document current

Update `ARCHITECTURE.md` when the actual project structure changes in a way that affects directory ownership, major component ownership, dependency direction, primary or secondary runtime flows, state ownership or where future code should be placed.

Do not use this document for task history, implementation notes, product requirements, testing procedures or deprecated architecture.

It is the current map of the Morie codebase.
