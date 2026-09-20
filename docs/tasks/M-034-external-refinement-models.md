# M-034 — External refinement models

## Status

**IN PROGRESS** — 2026-09-20

## Goal

Allow Morie cleanup to use a user-configured OpenAI-compatible Chat Completions endpoint while preserving Apple Foundation Models as the local/default path.

## Scope

- Settings can select Apple local, external API, or automatic fallback.
- External configuration stores Base URL/model in preferences and API key in Keychain.
- Launch and ordinary Settings rendering never read the Keychain credential.
- Each Capture freezes the selected refinement configuration, resolving the API key only when that Capture is actually configured to use an external model.
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

## Keychain / controller follow-up — 2026-09-20

The first external-model implementation loaded the API key unconditionally from `AppController.init()`. On launch that called `SecItemCopyMatching` for `me.morie.mac.refinement-cloud`, so macOS could present a Keychain access dialog even when Morie was using Apple-local refinement.

The corrected ownership is:

- `RefinementModelController` owns refinement mode, endpoint/model preferences, Settings feedback and the process-local credential cache.
- `AppController` remains the application/session orchestrator and no longer owns external-model form state.
- Startup loads only non-secret `UserDefaults` metadata.
- The Settings secure field is intentionally blank rather than reading the existing secret; leaving it blank preserves the existing Keychain item.
- Replacing or clearing a key is an explicit user action.
- A persisted key is first read only when a Capture that can use the external model starts; that resolved value is frozen into the per-Capture runtime configuration and cached for the rest of the process.
- Keychain read failure never blocks Capture; cloud-only refinement may keep the original text, while Automatic mode retains its normal Apple-local fallback.

This preserves the M-032 per-Capture settings snapshot while removing Keychain from the application launch path.

## Acceptance criteria

- [x] Apple-local refinement remains selectable.
- [x] External OpenAI-compatible refinement configuration is user-controlled.
- [x] API key is stored in Keychain rather than UserDefaults.
- [x] App launch and normal Settings construction do not read the API key from Keychain.
- [x] External-model Captures resolve and freeze the credential only when needed.
- [x] Refinement-model settings ownership is extracted from AppController.
- [x] Package revision is pinned in the Xcode project.
- [x] Shared `Package.resolved` is committed for reproducible local resolution.
- [ ] Pulling current `main` on the owner Mac opens without a missing-package-product error.
- [ ] Relaunching the owner build does not present a Keychain dialog before external-model use.
- [ ] Owner-device external API refinement is validated end to end.
