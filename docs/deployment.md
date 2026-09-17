# Deployment & Release Guide

Morie is a native macOS application. In V0 there is no Morie backend deployment. "Deployment" currently means building, signing, packaging, installing, and eventually distributing the macOS app.

## Current release stage

Phase 0 is pre-release development. Do not publish a user-facing release until the core input loop and compatibility matrix are validated on supported hardware.

## Supported runtime baseline

- macOS 27+
- Apple Intelligence-capable Mac
- Apple Intelligence enabled and required local model availability satisfied
- supported Speech locale/assets
- required macOS permissions granted

Older systems are not supported through compatibility runtimes or legacy Speech fallbacks.

## Build configurations

The Xcode project currently provides `Debug` and `Release` configurations.

Current target settings include:

- deployment target: macOS 27.0;
- generated Info.plist;
- menu-bar-only app behavior (`LSUIElement`);
- hardened runtime;
- automatic code signing;
- microphone and Speech usage descriptions.

Before a distributable build, verify the signing team, bundle identifier, entitlements, version/build numbers, and release identity in Xcode.

## Local development deployment

For Phase 0 testing:

1. open `Morie.xcodeproj`;
2. select the Morie target;
3. configure a valid Development Team;
4. run directly from Xcode on a supported Mac;
5. grant required Microphone, Speech Recognition, and Accessibility permissions;
6. execute the validation matrix in [`validation.md`](./validation.md).

This is the preferred deployment path while the input foundation is still changing.

## Release build

Once Phase 0 is release-worthy:

1. update `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` intentionally;
2. confirm Release uses the expected bundle identifier/team;
3. review entitlements and privacy usage descriptions;
4. archive using the current stable Xcode;
5. sign with the appropriate Developer ID / distribution identity for the chosen distribution channel;
6. notarize when distributing outside the Mac App Store;
7. staple notarization where applicable;
8. install the packaged artifact on a clean supported Mac and rerun the critical smoke/permission flow;
9. record the tested artifact/version in the release notes and task documentation.

Exact signing/export commands should be added only after the distribution channel is selected, rather than committing placeholder credentials or assumptions.

## Future App Store vs direct distribution

The repository does not yet lock Morie to one macOS distribution channel.

When that decision is made, document:

- sandbox requirements and how they affect Accessibility/global input;
- entitlements;
- App Store review implications;
- Developer ID/notarization path if distributed directly;
- update mechanism if direct distribution is used.

Do not introduce an updater framework before the distribution strategy requires it.

## CloudKit deployment — Phase 1

Phase 1 will add the actual iCloud/CloudKit environment. At that point this guide must include:

- iCloud container identifier;
- required entitlements;
- Development vs Production CloudKit environment handling;
- schema/container initialization and promotion procedure;
- compatibility/migration rules for persisted Capture data;
- release validation for cross-device synchronization.

Do not hard-code fake container identifiers or declare CloudKit ready before the actual Apple Developer configuration exists.

## Secrets and credentials

Never commit:

- signing certificates/private keys;
- provisioning secrets;
- Apple account credentials;
- App Store Connect API private keys;
- cloud/server secrets if a future backend is introduced.

Use Apple/Xcode-supported credential storage and CI secret facilities when automation is introduced.

## CI/CD direction

CI is not required to prove Phase 0's device behavior, because microphone, Accessibility, frontmost-app focus, and cross-application injection require real macOS validation.

When CI is introduced, it should at minimum perform what can be automated safely:

- project build/compile checks;
- unit tests;
- static checks;
- archive verification where credentials/environment permit.

Real-device compatibility validation remains a distinct release gate.

## Release gate

A build is not releasable merely because Xcode compiles it. At minimum the current task's required validation, documentation updates, signing/package verification, and known-issue review must all be complete.