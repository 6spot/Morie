# Development

This document defines the engineering rules for developing Morie.

Product behavior belongs in `PRODUCT.md`. System structure belongs in `ARCHITECTURE.md`. UI rules belong in `DESIGN.md`. Testing belongs in `TESTING.md`. Build and release belong in `DEPLOYMENT.md`.

## Development baseline

Morie is an Apple-platform product under active development.

Target the current supported Apple platform and current Apple APIs. The project does not need to preserve unfinished internal designs, temporary implementations, development data formats or obsolete architecture unless explicitly required.

When an existing implementation is wrong, change, replace or remove it. Do not add compatibility code merely to preserve development-stage behavior.

## Understand before changing

Inspect the actual implementation before making a change.

Trace the relevant runtime path far enough to understand where the behavior begins, which component owns it, what state is involved, where the observed problem is introduced, and whether existing code is already compensating for it.

Logs, screenshots, symptoms and previous discussions are evidence, not substitutes for inspecting the code.

## Fix the owning layer

Fix a problem where it belongs.

Do not compensate for one layer's defect by adding behavior to unrelated layers.

If speech recognition is wrong, investigate recognition. If refinement is wrong, investigate refinement. If persistence is wrong, investigate storage. If UI state is wrong, investigate state ownership and UI lifecycle. If input delivery is wrong, investigate delivery.

A workaround in another layer is acceptable only when the underlying platform constraint makes it necessary and the reason is understood.

## Avoid patch accumulation

Do not solve problems by continuously adding special cases, fallback branches, duplicate validation, duplicated state, arbitrary timing delays, retries without a known failure model, compatibility paths or one-off application handling.

When several mechanisms are compensating for the same problem, reconsider the design.

Prefer replacing an incorrect mechanism over wrapping it in additional logic.

## Keep one source of truth

Every piece of mutable application state should have a clear owner.

Persistent storage, runtime state, UI state, derived values and caches must have clearly different responsibilities.

A cache is not a second source of truth. A UI representation is not a second source of truth.

When ownership is unclear, resolve ownership before adding synchronization logic.

## Keep responsibilities focused

Components should have understandable responsibilities.

Application-level coordination should coordinate systems rather than absorb their internal implementation.

Do not move unrelated behavior into a large controller simply because that controller is easy to access.

Create an abstraction when a real responsibility or boundary exists. Remove abstractions that no longer represent a useful boundary.

## Code and model responsibilities

Morie uses deterministic software and language models.

Program code owns deterministic behavior such as lifecycle, state, permissions, capabilities, persistence, protocol validity, resource ownership, cancellation, network failures, timeouts and data integrity.

Language models own semantic language decisions such as understanding corrections, removing filler, resolving repetition, organizing spoken expression, paragraphing and preserving intended meaning.

Do not reproduce semantic understanding through increasingly complex hard-coded text rules.

Output should not be considered invalid merely because it is significantly shorter, longer, reorganized or contains words that do not exactly match transcript tokens.

Programmatic validation should protect deterministic boundaries. Semantic quality should be improved through the model, prompt, context or model interaction.

## Trust the selected mechanism

Once a responsibility has been assigned to a mechanism, allow that mechanism to perform its job.

Do not add another independent implementation behind it merely because the first mechanism might theoretically fail.

Fallbacks should exist only for understood and meaningful failure modes.

## Build for current requirements

Do not design infrastructure for hypothetical future requirements.

Avoid speculative provider systems, plugin architectures, compatibility layers, migration frameworks, generalized routing, cross-platform abstractions, fallback hierarchies and extension points.

When a future requirement actually appears, redesign the relevant boundary then.

## Apple-native UI is mandatory

For any user-facing UI work, `docs/DESIGN.md` is an engineering constraint, not optional visual guidance.

Before changing a view, identify the existing global pattern for its hierarchy and responsibility.

Implementation **must** reuse the shared design system and Apple-native platform behavior before considering custom UI.

Developers and agents **must not**:

- create a local replacement for an existing global shell, title, toolbar, search, layout or interaction pattern;
- recreate behavior already provided by SwiftUI/AppKit;
- introduce one-off geometry, spacing, materials or control styling merely to distinguish one feature;
- preserve an incorrect custom mechanism merely because it already exists.

If the global/native solution cannot satisfy a concrete requirement, identify the missing capability first. A custom implementation must be minimal and must be documented as an explicit design or architecture exception before it becomes an accepted pattern.

For non-UI platform functionality, prefer current Apple frameworks and straightforward Swift implementations over recreating platform behavior.

## External dependencies

Every external dependency must solve a concrete problem.

Before introducing one, determine what requirement it solves, why the existing platform or project code is insufficient, its runtime and binary cost, maintenance cost, privacy and security implications, and whether it creates additional services, runtimes or packaging requirements.

Do not introduce dependencies merely for convenience.

## Reference projects

Type4Me and OpenLess are reference implementations, not Morie specifications.

Use them to understand solved problems, failure modes and implementation experience.

The workflow is:

Morie requirement → current Morie implementation → relevant reference implementation → extracted lesson → Morie solution

Do not inherit unrelated architecture, dependencies, compatibility code or provider machinery.

## Replace instead of preserve

When a new implementation replaces an old implementation, remove the obsolete path.

Do not keep both versions indefinitely as a precaution.

Remove obsolete services, state, feature flags, validators, fallback paths, configuration, compatibility code, unused abstractions and commented-out implementations.

## Debug with evidence

Do not guess at runtime problems.

For crashes, memory growth, high CPU usage, redraws, delayed execution, leaked resources, concurrency problems or unstable behavior, observe the system first using appropriate logging, diagnostics or profiling.

Then fix the cause.

Temporary diagnostic instrumentation should be clearly distinguishable from the final solution.

## Concurrency

Use Swift Concurrency when it matches the problem.

Ownership and lifetime of asynchronous work must remain explicit. Cancellation must leave the owning component in a valid state and release resources that are no longer needed.

Do not create detached or long-lived tasks without a clear owner. Do not hide concurrency problems by moving work onto arbitrary dispatch queues.

## Error handling

Handle errors according to their meaning.

Expected conditions should not automatically become user-facing failures. User-facing errors should normally represent conditions the user can understand or act on.

Do not silently swallow failures that can cause data loss or leave the application invalid. Do not hide persistent failures behind unlimited retries or fallback chains.

## Data during development

Morie is under active development.

Do not introduce schema migrations or compatibility systems solely to preserve disposable development formats unless explicitly required.

At the same time, never silently destroy existing user data. Any destructive development reset must be intentional and explicit.

## Keep changes focused

A change should solve the requested problem completely without becoming an excuse to redesign unrelated systems.

Related cleanup is appropriate when it removes code made obsolete by the change or is required to establish the correct design.

## Development workflow

For normal development:

1. Read the relevant current documentation. For any UI task, `docs/DESIGN.md` is mandatory.
2. For UI changes, identify the existing global Apple-native pattern for the target hierarchy before writing code.
3. Inspect the current implementation.
4. Reproduce or understand the existing behavior.
5. Identify the owning layer and root cause.
6. Check relevant reference implementations when useful.
7. Choose the simplest coherent solution.
8. Implement the change.
9. Remove mechanisms made obsolete by the change.
10. Validate the affected behavior according to `TESTING.md`.
11. Update documentation when current behavior or design changed.
12. Review the final diff before committing or merging.

## Git workflow

Work should normally be isolated from `main` until the change is ready.

Keep commits and branches focused on a coherent change. Do not discard unrelated work or rewrite shared history unless explicitly required.

Before merging, review the complete diff and ensure temporary debugging code, obsolete implementation and accidental files are not included.

## Development principle

When multiple solutions are possible, prefer the one that is simpler to understand, has clearer ownership, introduces less state, solves the general problem, relies on fewer assumptions, and is easier to change or remove later.

Do not make Morie more complicated to protect an implementation that should instead be corrected.
