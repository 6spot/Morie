# M-020 — Source Tree Organization

## Status

**IN PROGRESS** — 2026-09-19

Implementation is on `m-020/source-tree-organization` in [PR #19](https://github.com/6spot/Morie/pull/19). Source/test relocation and Xcode project updates are implemented; the macOS 27 compile gate remains pending.

## Why

Morie has grown from an early single-directory prototype into several stable product areas: Capture, Memory, Dictionary, Personalization, Setup, app composition, platform integration and diagnostics. Keeping all product Swift files and all tests flat makes ownership harder to see and increases the chance that future work expands `AppController` or mixes unrelated responsibilities merely because files are adjacent.

This task makes those existing boundaries visible without introducing package/module complexity or changing runtime behavior.

## Scope

Included:

- organize product sources into `App/`, `Features/`, `Platform/`, `Support/` and `Resources/`;
- group Capture History beneath Capture;
- organize tests by the same feature/support ownership;
- update the existing explicit `PBXGroup` hierarchy and physical file paths;
- preserve source/test target membership;
- update architecture/task documentation.

Explicitly excluded:

- extracting `AppController` responsibilities;
- adding `CaptureSessionController` or other new runtime types;
- splitting Swift packages/modules/targets;
- changing public/internal access control;
- changing persistence schemas, file locations, UI, behavior or dependencies;
- converting the project to filesystem-synchronized Xcode groups.

## Acceptance criteria

- [x] Product Swift files are physically grouped by existing ownership boundaries.
- [x] Tests mirror feature/support ownership.
- [x] `Morie.entitlements` remains at `Morie/Morie.entitlements`.
- [x] Existing source and test build-file membership IDs are preserved.
- [x] Xcode uses explicit nested `PBXGroup` paths matching the filesystem.
- [x] No application Swift source content changes as part of the move.
- [x] Architecture documentation describes the new layout and confirms it is not a module/package split.
- [ ] macOS 27 product compile gate passes.
- [ ] Relevant test target compiles/runs without path regressions.

## Subtasks / progress

- [x] Create GitHub Issue #18 and task branch.
- [x] Define feature-first ownership boundaries from the current codebase.
- [x] Move product files and localized resource.
- [x] Move tests into matching ownership directories.
- [x] Rebuild Xcode group hierarchy without changing target membership.
- [x] Update `docs/architecture.md`.
- [x] Update `docs/tasks.md`.
- [x] Open pull request #19.
- [ ] Run and record CI.
- [ ] Record final validation evidence and close the task when checks pass.

## Implementation notes

The product still has one `Morie` app target and one `MorieTests` target. Existing PBX file/build references are retained; only their owning groups and filesystem paths change.

The directory boundaries are:

- `App/`: composition, top-level app/controller and management shell;
- `Features/`: Capture, Memory, Dictionary, Personalization and Setup;
- `Platform/`: Apple/macOS capabilities, global input, text delivery and CloudKit settings;
- `Support/`: diagnostics and cross-cutting support;
- `Resources/`: localized resources.

`SpeechPipeline` stays with Capture because its current lifecycle is owned by the capture flow. No reusable Speech module is created speculatively.

The next architecture step, if separately approved, is to reduce `AppController` by extracting the capture-session state machine. That is intentionally not mixed into this relocation task.

## Validation

Structural checks performed during the repository update:

- every old moved path existed on the base `main` tree;
- no destination path existed before the move;
- moved files reuse their existing Git blobs, ensuring source contents are unchanged;
- product/test `PBXBuildFile` and `PBXSourcesBuildPhase` entries are unchanged;
- nested Xcode groups resolve the new physical directories;
- entitlement build setting remains `Morie/Morie.entitlements`.

Pending:

- GitHub macOS 27 compile workflow;
- test-target validation on Xcode/macOS 27.

No real-device microphone, TCC, Apple Intelligence, focus or injection validation is required because this task intentionally changes no runtime behavior.

## Known issues / blockers

No product blocker is known. Completion depends on compile/test validation after the pull request is opened.

## Follow-up

Create a separate architecture task for `AppController` reduction, beginning with the capture-session state machine. Do not combine that change with this source-tree move.

Do not extract `MorieCore` or another shared Swift package until iOS or another real consumer creates reuse/ownership pressure.

## References

- GitHub Issue: [#18](https://github.com/6spot/Morie/issues/18)
- Pull request: [#19](https://github.com/6spot/Morie/pull/19)
- [Architecture](../architecture.md)
- [Product and architecture baseline](../product-architecture-baseline.md)
- [Development guide](../development.md)
