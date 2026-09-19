# M-034 — External refinement models

## Status

**IN PROGRESS** — 2026-09-20

## Goal

Allow Morie cleanup to use a user-configured OpenAI-compatible Chat Completions endpoint while preserving Apple Foundation Models as the local/default path.

## Scope

- Settings can select Apple local, external API, or automatic fallback.
- External configuration stores Base URL/model in preferences and API key in Keychain.
- Each Capture freezes the selected refinement configuration.
- External refinement uses Apple's `foundation-models-utilities` `ChatCompletionsLanguageModel` adapter instead of a Morie-owned protocol implementation.
- The Xcode project pins the Apple package to revision `2aa12937e30d310687f40fc470ea35495816c9a4`.
- The repository commits the shared Xcode SwiftPM `Package.resolved` so clones/pulls resolve the same package revision.

## Dependency decision

The owner explicitly approved external-model support. Morie needs an OpenAI-compatible language-model adapter that integrates with Apple's Foundation Models `LanguageModelSession` surface. Reimplementing that adapter locally would make Morie responsible for transcript translation, generation options, protocol/API changes and provider error mapping. Apple's own `apple/foundation-models-utilities` package supplies this integration without adding a separate runtime, SDK daemon, binary framework or non-Apple UI stack.

Runtime cost is limited to the Swift package code linked into Morie; network use only occurs when the user selects/configures an external refinement model. Apple-local refinement remains available independently.

## Package-resolution follow-up — 2026-09-20

The first M-034 merge pinned the package revision in `project.pbxproj`, but did not commit Xcode's shared SwiftPM resolution file. A fresh local checkout could therefore show `Missing package product 'FoundationModelsUtilities'` until Xcode resolved the package graph.

The repository now tracks:

`Morie.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`

with the same pinned Apple revision. CI evidence already confirms Xcode 27 resolves that revision and builds the `FoundationModelsUtilities` product.

## Acceptance criteria

- [x] Apple-local refinement remains selectable.
- [x] External OpenAI-compatible refinement configuration is user-controlled.
- [x] API key is stored in Keychain rather than UserDefaults.
- [x] Package revision is pinned in the Xcode project.
- [x] Shared `Package.resolved` is committed for reproducible local resolution.
- [ ] Pulling current `main` on the owner Mac opens without a missing-package-product error.
- [ ] Owner-device external API refinement is validated end to end.
