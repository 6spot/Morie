# Testing

This document defines how Morie changes are validated.

Task-specific test cases and historical validation results do not belong here.

## Testing goal

Testing should answer:

**Did this change behave correctly in the environment where that behavior actually exists?**

Compilation is not runtime validation. Unit tests are not system validation. Offscreen UI rendering is not interaction validation. Real-device testing is not a replacement for deterministic tests.

Use the smallest set of tests that can actually prove the changed behavior.

## Validation levels

Morie uses four validation levels:

1. Compile.
2. Automated tests.
3. Targeted runtime validation.
4. Real-device acceptance when required.

Not every change requires every level. The affected behavior determines the required level.

## Compile validation

Code changes must compile with the current supported Xcode and SDK.

Compile validation catches syntax errors, type errors, concurrency errors, unavailable APIs, target configuration problems, dependency resolution problems and accidental project-file breakage.

Compile success proves only that the code can be built.

## Automated tests

Deterministic product logic should be covered by automated tests where practical.

Good candidates include state transitions, persistence behavior, ordering, cancellation, stale-result rejection, parsing, filtering, deterministic correction, lifecycle logic, data transformations and error handling.

Automated tests should use temporary or in-memory data and must not depend on the user's real Morie data.

## Test the owning layer

Tests should live with the behavior they validate.

Capture code belongs with Capture tests, Dictionary with Dictionary tests, Memory with Memory tests, Personalization with Personalization tests, and Setup with Setup tests.

Do not test one subsystem indirectly through an unrelated subsystem when the owning layer can be tested directly.

## Runtime validation

Some behavior requires running Morie.

Examples include application lifecycle, SwiftUI/AppKit interaction, navigation, real persistence lifecycle, window behavior, asynchronous coordination and integration between multiple features.

Runtime validation should reproduce the real user path affected by the change and its immediate neighboring boundaries.

## Real-device acceptance

Behavior depending on macOS hardware or protected system services must be validated on a supported real Mac.

Examples include microphone capture, Apple Speech, Apple Intelligence / Foundation Models, Accessibility, global keyboard events, clipboard and synthetic input, focus behavior across applications, permission prompts, Keychain behavior, iCloud / CloudKit, native visual materials, VoiceOver, performance and energy behavior.

Mocks, unit tests, compilation, previews or offscreen rendering cannot establish these behaviors.

## Semantic model validation

Language-model behavior cannot be proven solely through deterministic tests.

Changes affecting refinement quality, meaning preservation, paragraphing, correction, Memory extraction, semantic retrieval or model prompts require representative real-model evaluation.

Validate both expected transformations and unwanted transformations.

## Refinement evaluation

When refinement behavior changes, include representative cases such as short input, long natural speech, fillers, repetition, self-correction, uncertainty, questions, instructions, lists, Chinese, English, mixed language, names, technical terms, numbers, dates, negation and code/path/URL content where relevant.

Check especially for invented information, changed meaning, lost information, changed tone, unnecessary rewriting and incorrect structure.

Prompt examples are test material, not hard-coded validators.

## UI validation

UI changes should be validated at the level affected by the change.

Check layout, resizing, navigation, state transitions, selection, scrolling, keyboard behavior, light/dark appearance and accessibility when relevant.

A screenshot can prove visual layout. It cannot prove focus, keyboard navigation, window activation, accessibility, interaction timing or native material behavior.

## Cross-application input validation

Changes affecting text delivery must be validated against representative application types, such as a native macOS text field, browser field, Electron application, code editor and terminal where applicable.

Validate current-focus targeting, paste, multiline text, selected-text replacement, repeated input, clipboard restoration, no unexpected activation and no leaked synthetic input.

A failure in one application should first be reproduced and understood before introducing application-specific handling.

## Persistence validation

Changes to persisted data must validate both writing and reading.

When relevant, test a cold reopen: write → close → reopen → read.

Do not assume that successfully creating data in one process proves it can be read after a cold launch.

Persistence tests must use isolated data and never modify the user's active History or Memory.

## Concurrency and cancellation

Changes involving asynchronous work must test relevant interruption paths.

Typical cases include start → finish, start → cancel, start → failure, start → new operation, and an old task completing after replacement.

Verify stale results are ignored, cancellation releases owned resources, no late result mutates newer state, no duplicate completion occurs and no background task becomes orphaned.

## Failure-path testing

Important failure behavior should be tested explicitly.

Examples include unavailable capability, permission denied, Speech failure, model failure, persistence failure, delivery failure, cancellation and unavailable external service.

A successful happy path does not prove failure recovery.

## Regression testing

When fixing a reproducible defect:

1. Reproduce the defect.
2. Identify the owning layer.
3. Create deterministic regression coverage when possible.
4. Implement the fix.
5. Verify the original reproduction no longer fails.

A regression test should reproduce the underlying failure condition, not merely assert the implementation chosen to fix it.

## Performance validation

Performance should be measured when a change can materially affect launch, memory, CPU, energy, input latency, model latency, audio lifetime or background activity.

Use real measurement rather than subjective impressions when investigating performance problems.

## Test isolation

Automated and diagnostic testing must not unexpectedly modify the user's active History, Dictionary, Personal Memory, clipboard, Keychain, permissions, recordings or external documents.

Use temporary directories, temporary stores, in-memory stores, injected dependencies and disposable test documents where appropriate.

## Testing external services

Tests must not depend on a real paid or user-configured external model when deterministic behavior can be injected.

Use injected or fake boundaries for request construction, response handling, cancellation, network failure, invalid responses and persistence behavior.

Use the real external model only when validating actual model behavior or integration that cannot otherwise be established.

Never expose secrets in test logs or fixtures.

## Evidence

A test result should make clear what was tested, what environment was used when relevant, what passed, what failed and what was not tested.

Do not claim runtime behavior from compilation alone, real-model quality from mocked output, native interaction correctness from an offscreen render or permission behavior from a fake permission service.

State the limit of the evidence.

## Change-based validation

Validation should follow the affected boundary.

- Pure deterministic logic: automated tests.
- Swift/project configuration: compile + relevant tests.
- Persistence: tests + cold reopen when relevant.
- UI layout: compile + targeted UI/runtime check.
- Speech/microphone: automated boundaries + real-device check.
- Model prompt/semantic behavior: automated integration + real-model examples.
- Clipboard/focus/Accessibility: real-device cross-app check.
- Performance regression: reproduce + profile + measure.

Do not require unrelated validation merely because it exists elsewhere in the application.

## Before merging

Before merging a change:

1. Compile the affected target.
2. Run relevant automated tests.
3. Validate affected runtime behavior.
4. Perform real-device acceptance when the changed behavior requires it.
5. Check important failure and cancellation paths.
6. Review what remains unverified.
7. Do not report an unperformed check as passed.

If a required validation cannot be performed, record that limitation explicitly.

## Testing principle

**Use evidence appropriate to the behavior being changed.**

A test only proves what its environment is capable of observing.
