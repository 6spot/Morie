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
5. complete **使用引导与权限**, explicitly authorize Microphone/Speech/Accessibility, then choose **开始使用**;
6. execute the validation matrix in [`validation.md`](./validation.md).

This remains the preferred path for debugging because Xcode exposes runtime diagnostics directly.

## GitHub test artifact

The `macOS 27 Build` GitHub Actions workflow also produces an installable Phase 0 test artifact for owner/device testing.

The workflow:

1. builds the `Release` configuration on GitHub's `xcode-27` runner;
2. performs ad-hoc code signing (`codesign --sign -`);
3. verifies the resulting app with `codesign --verify --deep --strict`;
4. packages `Morie.app` as `Morie-macOS27-test.zip`;
5. writes `Morie-macOS27-test.zip.sha256`;
6. uploads both files as a GitHub Actions artifact retained for 14 days.

This artifact is intentionally **not Developer ID signed and not notarized**. It is for internal Phase 0 validation, not public distribution.

To test it:

1. download the latest successful `Morie-macOS27-test-*` Actions artifact;
2. extract the artifact archive, then extract `Morie-macOS27-test.zip`;
3. move `Morie.app` to `/Applications` if desired;
4. open Morie, complete **使用引导与权限** through its explicit native authorization actions, then choose **开始使用**;
5. if Gatekeeper blocks the ad-hoc test build because it is not notarized, use the normal macOS Privacy & Security **Open Anyway** flow. For development-only troubleshooting, the downloaded app's quarantine attribute may also be removed explicitly before launching;
6. execute the Phase 0 checks in [`validation.md`](./validation.md).

Do not treat successful installation of this artifact as release-signing validation.

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

## Language and setup packaging

Keep `CFBundleDevelopmentRegion = zh-Hans` and the bundled `zh-Hans.lproj/InfoPlist.strings` in both Debug and Release artifacts. Privacy descriptions must match the Chinese setup page. A packaged first launch must inspect requirements without automatically prompting, and all Settings entry points must open the native Command-comma Settings scene. Validate these using the signed test artifact; unsigned compile output must not replace the owner's installed app.

## CloudKit deployment — later cross-device milestone

On 2026-09-18, the owner corrected the delivery order: complete the single-Mac input/dictionary/Memory loop before cross-device sync. CloudKit is outside the current milestone, not a prerequisite for local persistence or task completion. Apple Developer enrollment/container setup is also not ready; do not request it until an actual cross-device milestone is scheduled.

The intended storage is each user's own iCloud private database within Morie's app container. The developer team provisions the app's CloudKit capability and container once. End users use their own iCloud accounts and do not need developer accounts. Morie operates no shared cloud backend in V0.

That later milestone will add the actual iCloud/CloudKit environment. At that point this guide must include:

- iCloud container identifier;
- required entitlements;
- Development vs Production CloudKit environment handling;
- schema/container initialization and promotion procedure;
- current Capture schema and conflict/deletion semantics;
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

CI can verify buildability and package structure, but it cannot prove Phase 0's device behavior because microphone, Accessibility, frontmost-app focus, and cross-application injection require real macOS validation.

The current macOS 27 CI performs:

- Xcode 27 / macOS 27 SDK build checks;
- Release test packaging;
- ad-hoc signature verification;
- SHA-256 generation;
- GitHub Actions artifact upload.

Real-device compatibility validation remains a distinct release gate.

## Release gate

A build is not releasable merely because Xcode compiles it. At minimum the current task's required validation, documentation updates, signing/package verification, and known-issue review must all be complete.
