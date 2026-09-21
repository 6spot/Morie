# M-034 — External refinement models

## Status

**IN PROGRESS** — 2026-09-21

## Goal

Allow Morie cleanup to use a user-configured OpenAI-compatible Chat Completions endpoint while preserving Apple Foundation Models as the local/default path.

## Current design

- Settings can select Apple local, external API, or automatic fallback.
- External configuration stores endpoint/model in preferences and API key in Keychain.
- Launch and ordinary Settings rendering never read the Keychain credential.
- Each Capture freezes the selected refinement configuration, resolving the API key only when that Capture reaches external-model refinement.
- Apple Foundation Models is used only for the Apple-local path.
- The external path is a small Morie-owned HTTP adapter for the standard OpenAI Chat Completions protocol.
- The configured endpoint owns its gateway/version prefix. Morie normalizes only the terminal `/chat/completions` path and does not invent a `/v1` prefix.
- The generic request contains only `model`, `stream: false`, and system/user `messages`, plus optional Bearer authorization.
- Provider-private session IDs, proprietary thinking flags and other vendor parameters are outside the generic adapter.

## Reference audit — 2026-09-21

The Cloud path was rechecked against current Type4Me and OpenLess implementations after a real provider returned `400 MissingSessionID`.

Type4Me's OpenAI-compatible client constructs `baseURL + /chat/completions` directly with URLSession, Bearer authorization and JSON messages. OpenLess likewise owns the HTTP request directly; its ordinary non-streaming polish path sends `model`, `stream: false`, and `messages`, and its endpoint normalizer preserves the configured gateway/version prefix.

The useful lesson is not to reproduce either project's provider matrix. Morie needs one explicit generic contract. A service that requires a private session header is not fixed by teaching the generic adapter that private protocol.

## FoundationModelsUtilities removal

The first M-034 implementation routed Cloud requests through Apple's `foundation-models-utilities` `ChatCompletionsLanguageModel`. That translated Foundation Models generation/session semantics into an OpenAI-like wire request and added request-shape behavior that Morie did not need for simple cleanup.

After real-device compatibility testing, Morie removed that package from the Cloud path and from the Xcode project. The direct adapter is intentionally small: POST to the normalized `/chat/completions` endpoint, optional Bearer auth, and a standard JSON body containing only model/stream/messages.

This is not a generalized provider SDK. Responses are limited to the standard Chat Completions `choices[0].message.content` shape used by the refinement flow.

## Keychain / controller contract

- `RefinementModelController` owns mode, endpoint/model preferences, Settings feedback and the process-local credential cache.
- Startup loads only non-secret `UserDefaults` metadata.
- The Settings secure field remains blank rather than reading the existing secret.
- Replacing or clearing a key is an explicit user action.
- A persisted key is first read only when a completed Capture actually enters external-model refinement.
- Keychain read failure never blocks Capture; cloud-only refinement keeps saved text, while Automatic mode may fall back to Apple local.

## Diagnostics contract

Cloud failures record only safe transport metadata: HTTP status and bounded provider error type/code/parameter, or network error codes. API keys, Authorization headers, full response bodies and provider messages that may echo user text are never logged.

A provider error such as `MissingSessionID` remains visible as evidence that the configured service requires a non-standard contract; Morie does not silently add the requested private field.

## Acceptance criteria

- [x] Apple-local refinement remains selectable.
- [x] External OpenAI-compatible refinement configuration is user-controlled.
- [x] API key is stored in Keychain rather than UserDefaults.
- [x] App launch and normal Settings construction do not read the API key from Keychain.
- [x] External-model Captures resolve the credential only at the refinement boundary.
- [x] External refinement uses a provider-neutral OpenAI Chat Completions HTTP request.
- [x] Base URL normalization preserves configured gateway/version prefixes and accepts a full Chat Completions URL.
- [x] Generic requests contain no provider-private session/thinking/tool parameters.
- [x] Cloud failure diagnostics expose safe protocol metadata without credentials or user text.
- [ ] Owner-device external API refinement is validated end to end against at least one standard-compatible endpoint.
- [ ] Automatic mode fallback is validated on the owner device.
