# Deployment

This document defines how Morie is built, signed, packaged and released.

Testing requirements belong in `TESTING.md`. Development workflow belongs in `DEVELOPMENT.md`. Product behavior belongs in `PRODUCT.md`.

## Deployment scope

For the macOS application, deployment is:

Build → Sign → Package → Verify → Distribute

A successful compile is not a distributable release.

## Build configurations

Use `Debug` for development and local debugging and `Release` for packaged artifacts and release validation.

Do not distribute Debug builds as releases.

## Local development build

Normal development should use Xcode with the developer's configured Apple Development Team.

The development build should preserve the application identity and entitlements required for realistic macOS permission behavior.

Do not replace the normal signed development application with an unsigned validation build when testing microphone, Speech permissions, Accessibility, Keychain or other TCC-protected capabilities.

Unsigned builds may be used for compile-only validation.

## Build isolation

Command-line validation builds should use isolated DerivedData.

Do not write temporary validation artifacts over the application currently being run or debugged from Xcode.

## Application identity

Before producing a distributable artifact, verify bundle identifier, Development Team, application version, build number, entitlements, privacy usage descriptions, signing identity and Release configuration.

Changes to application identity may affect macOS permissions and Keychain access and should be treated as deployment changes.

## Versioning

Maintain `MARKETING_VERSION` as the user-visible version and `CURRENT_PROJECT_VERSION` as the build number.

Do not change versions incidentally as part of unrelated development.

## Signing

Runtime-test and release artifacts must be signed appropriately for their purpose.

Typical identities are Apple Development for development builds, Developer ID Application for direct distribution, and the applicable Apple distribution identity for Mac App Store distribution.

Never commit signing certificates, private keys or exported identities.

## Entitlements

Entitlements are part of the shipped application contract.

Before packaging, verify the final artifact contains only the entitlements actually required by Morie.

Do not add placeholder entitlements for future features.

## Packaging

Package the built `.app` without modifying its internal contents after final signing.

For a ZIP artifact, sign the app, verify the signature, archive it, then generate the checksum.

Do not sign an artifact and then mutate files inside the application bundle.

## Artifact verification

Before distributing an artifact, verify the expected version, bundle identifier, architecture, code signature, entitlements, launch behavior and package integrity.

For downloadable artifacts, generate a checksum such as SHA-256 for the exact file being distributed.

## Internal test artifacts

Internal testing artifacts may use a different signing path from public releases.

For example, CI may create an ad-hoc signed artifact for controlled testing.

Such an artifact is test-only. It is not evidence that Developer ID signing, notarization or production distribution works.

## Direct distribution

If Morie is distributed directly outside the Mac App Store, the release path is:

Release build → Developer ID signing → package → notarization → staple when applicable → verification → distribution.

Exact commands and export procedures should match current Apple tooling at the time the release process is implemented.

Do not commit guessed or placeholder signing procedures.

## Mac App Store distribution

If Morie is distributed through the Mac App Store, document the final App Store-specific process once that path is selected.

Account for sandbox requirements, entitlements, provisioning, archive/export, App Store Connect and review requirements.

Do not maintain a speculative App Store pipeline before it is needed.

## Notarization

Directly distributed public builds should use Apple's current notarization process when required.

Notarization credentials belong in secure developer or CI credential storage and must never appear in repository files, documentation or build logs.

## CI artifacts

CI may produce compile results, test results, packaged test artifacts, checksums and signature verification output.

CI artifacts should identify the source commit they were built from.

## Release artifact

A release should have one clearly identifiable final artifact.

Record at least version, build number, source commit, distribution channel and artifact checksum when applicable.

Do not create multiple differently built artifacts with the same version/build identity.

## Release validation

Validate the packaged artifact itself, not only the application launched from Xcode.

The final signed/package candidate should be installed and checked in the same form users will receive it.

Behavioral validation requirements are defined in `TESTING.md`.

Deployment validation additionally confirms that signing did not break capabilities, packaging did not remove resources, entitlements are present, application identity is correct and the installed artifact launches normally.

## Clean-machine check

Before a public release, validate the final artifact on a supported Mac that is not relying on the active Xcode development environment.

This helps expose issues involving missing bundled resources, signing, permissions, Gatekeeper, notarization and developer-machine-only state.

## Credentials and secrets

Never commit certificates, signing private keys, Apple account passwords, App Store Connect private keys, API secrets, provisioning secrets, external model API keys or future server credentials.

Use Keychain, Xcode-managed signing, Apple-supported credential mechanisms and CI secret storage as appropriate.

Logs must not expose secrets.

## Cloud capabilities

Deployment configuration for Apple cloud capabilities belongs here only when it affects entitlements, container identifiers, signing, environment configuration or production promotion.

Product synchronization behavior belongs elsewhere.

Do not invent iCloud or CloudKit container identifiers. Only document identifiers that actually exist in the configured Apple Developer environment.

## Release process

A normal release follows this order:

1. Select the exact source revision.
2. Set version and build number.
3. Build Release.
4. Sign with the intended distribution identity.
5. Verify entitlements and signature.
6. Package the final artifact.
7. Notarize when required.
8. Verify the packaged artifact.
9. Run required release validation from `TESTING.md`.
10. Generate checksum where applicable.
11. Publish the exact validated artifact.
12. Record the released version and source revision.

Do not rebuild a release after validation and publish the new unvalidated artifact under the same version.

## Release rule

**Build once for the release candidate, validate that exact artifact, and distribute that exact artifact.**
