# M-019 — Optional iCloud sync and backup foundation

## Status

- **State:** IN PROGRESS
- **Last updated:** 2026-09-19
- **Branch:** `feature/m-019-icloud-opt-in`
- **Depends on:** M-003 durable Capture, M-004 Memory, M-011 Dictionary, M-018 Expression Profile
- **Issue / PR:** —

## Why

The owner explicitly does not want a local automatic-backup subsystem. The intended long-term protection and multi-device path is the user's own iCloud/CloudKit private database, enabled only by an explicit user setting.

Morie already keeps its core user state in SwiftData. Apple's current SwiftData configuration can either disable managed CloudKit with `.none` or enable managed private CloudKit using the primary iCloud container from the signed app entitlements with `.automatic`. This gives Morie an Apple-native sync/backup path without a Morie backend.

## Scope

- Add a default-off **使用 iCloud 同步与备份** setting.
- Check the current user's CloudKit account before accepting an enable request.
- Configure the production SwiftData store at launch with:
  - `.none` when iCloud is off;
  - `.automatic` when iCloud is on.
- Apply storage-mode changes on the next app launch.
- Keep in-memory tests and explicit/custom storage URLs CloudKit-free.
- If an enabled CloudKit store fails to open, retry the current schema locally and show an iCloud error instead of blocking input.
- Synchronize SwiftData-backed History text/provenance, user Dictionary, Personal Memory and Expression Profile once the signed app has a real CloudKit capability/container.
- Keep original audio files local.
- Keep iCloud optional; no Device Only product fork and no Morie backend.

## Explicit non-goals

- No local automatic backup.
- No copy-before-upgrade or legacy-development-data preservation.
- No invented/fake iCloud container identifier.
- No raw audio upload in this slice.
- No iOS UI or iPhone development.
- No custom CloudKit record engine while SwiftData managed CloudKit is sufficient.
- No compatibility adapter for superseded development schemas.

## Acceptance criteria

1. iCloud sync defaults off.
2. Enabling first verifies that CloudKit reports an available account; an unavailable account does not silently enable the setting.
3. A launch with the setting off creates the production SwiftData configuration with CloudKit disabled.
4. A launch with the setting on requests SwiftData managed CloudKit using the primary entitled container.
5. In-memory and explicit-URL stores never enable CloudKit, even if their caller passes the flag.
6. Changing the setting clearly reports that the active ModelContainer changes on the next launch.
7. A requested CloudKit configuration failure falls back to local current-schema persistence so voice input remains usable.
8. Original recording files remain local and are never uploaded by this storage configuration.
9. The repository contains no placeholder container ID.
10. Hosted macOS 27 compilation/tests pass.
11. Actual synchronization remains blocked until the real Apple Developer/Xcode iCloud capability and container are configured and validated with a signed app.

## Progress

- [x] Add opt-in iCloud settings/account-state model.
- [x] Select `.none` vs `.automatic` managed CloudKit at production store launch.
- [x] Keep isolated/test stores CloudKit-free.
- [x] Add safe local fallback if the requested CloudKit-backed store cannot initialize.
- [x] Add native Settings toggle, state and recheck UI.
- [x] Document that original audio remains local.
- [x] Preserve the no-local-backup/no-development-migration decision.
- [ ] Pass hosted macOS 27 CI.
- [ ] Configure the real Apple Developer iCloud/CloudKit capability and primary container.
- [ ] Validate private-database synchronization and conflict/deletion behavior on signed builds and multiple devices.

## Architecture decision

M-019 uses SwiftData's managed CloudKit integration rather than immediately introducing a repository-owned `CKSyncEngine` record protocol.

Reasons:

- the current canonical data already lives in SwiftData;
- SwiftData can explicitly use `.none` or managed private CloudKit;
- the user wants an Apple-native private sync/backup path, not a Morie server;
- custom CloudKit serialization, zone/change-token storage and conflict handling would duplicate framework behavior before a concrete gap is observed.

If real validation later exposes a requirement SwiftData managed CloudKit cannot satisfy, stop and document that gap before replacing it with a custom sync engine.

## Storage boundary

Cloud-backed SwiftData currently contains the same current-schema models used locally:

- `CaptureRecord` — History text and processing/delivery provenance;
- `DictionaryEntry` — user-maintained/correction-confirmed words;
- `MemoryRecord`, `MemoryAnalysisRecord`, `MemoryLearningBlock`;
- `ExpressionProfileRecord`.

The source-audio M4A files are separate filesystem artifacts under `CaptureAudio`. They are not part of the SwiftData CloudKit configuration and stay local.

## Capability / container blocker

No CloudKit container identifier is hard-coded in the repository. SwiftData `.automatic` discovers the primary container from signed app entitlements.

Runtime acceptance therefore requires the real project owner/developer team to configure the iCloud/CloudKit capability and container in Xcode/Apple Developer. Until then:

- the code can compile;
- the toggle can report account/capability failure;
- hosted CI cannot establish real CloudKit synchronization.

## Apple references

- SwiftData: Syncing model data across a person's devices
- `ModelConfiguration.CloudKitDatabase.automatic`
- `ModelConfiguration.CloudKitDatabase.none`
- CloudKit `CKContainer.accountStatus()`
- CloudKit private database semantics
