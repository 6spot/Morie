# M-030 — macOS Logic Test Gate

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#48](https://github.com/6spot/Morie/issues/48)

## Goal

Make the existing `MorieTests` suite an actual CI gate. Product compilation remains necessary, but deterministic Capture/History/Dictionary/Memory/Personalization regressions must also execute automatically rather than existing only as test source.

## Design

Morie keeps two separate hosted checks:

```text
macOS 27 CI
├─ Xcode 27 compile
│  └─ Release Morie product target
└─ MorieTests
   └─ Debug standalone logic-test scheme
```

The test target remains deliberately independent of the signed menu-bar application. It does not launch Morie or request TCC permissions.

A committed shared `MorieTests` scheme makes the command deterministic in CI and locally:

```bash
xcodebuild \
  -project Morie.xcodeproj \
  -scheme MorieTests \
  -configuration Debug \
  -sdk macosx27.0 \
  -destination "platform=macOS" \
  -derivedDataPath "$validation_dir" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

The workflow also watches `MorieTests/**`, so a test-only regression or coverage change cannot bypass CI.

## Hosted-test boundary

Included in hosted CI:

- SwiftData Capture persistence and revision/tombstone ordering;
- History query/recovery logic;
- synthetic audio/no-speech classification and file preservation;
- Dictionary/correction rules;
- cleanup/refinement validation;
- Memory/personalization deterministic tests;
- permission-controller logic with injected authorization behavior.

Still owner-device/runtime only:

- real microphone and Speech asset behavior;
- Apple Intelligence semantic quality;
- TCC state and Accessibility trust;
- physical Fn/global hotkey behavior;
- current-focus clipboard/paste delivery in real apps;
- HUD/Liquid Glass rendering and sound feel;
- latency, CPU, memory and energy measurements.

## Acceptance criteria

- [x] A shared `MorieTests` scheme is committed.
- [x] `.github/workflows/macos-27-ci.yml` has a real `xcodebuild ... test` job.
- [x] Test-only changes under `MorieTests/**` trigger the workflow.
- [x] Existing Release product compile remains a separate job.
- [x] No external testing dependency is introduced.
- [ ] GitHub Actions executes the new test job successfully on the PR head.

## Validation

The final hosted result is intentionally left open until the PR workflow executes. A passing compile job alone is not sufficient to close M-030.
