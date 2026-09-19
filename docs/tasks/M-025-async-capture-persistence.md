# M-025 — Asynchronous Capture Persistence

## Status

**IN PROGRESS** — 2026-09-19

Issue: [#26](https://github.com/6spot/Morie/issues/26)  
Pull request: [#27](https://github.com/6spot/Morie/pull/27)

## Goal

Keep History persistence out of Morie's normal voice-input latency budget. Once an intentional Capture has a durable recovery shell, recognition, cleanup and current-app delivery should advance from live state without waiting for SwiftData I/O.

## Product invariant

The initial Capture shell is still synchronous and required before Speech starts:

\`\`\`text
captureID + createdAt + deliveryMode + audio destination
                         ↓
                    durable shell
                         ↓
                      Speech
\`\`\`

After that boundary, normal current-app input is delivery-first:

\`\`\`text
Speech final
  ├──────────────→ async recognized/audio snapshot
  ↓
cleanup
  ├──────────────→ async final/provenance snapshot
  ↓
paste dispatch
  ↓
success / Ready
  ├──────────────→ async delivered snapshot
  └── after persistence flush → dependent Memory learning
\`\`\`

\`captureOnly\` is intentionally different: History is the requested destination, so the newest final snapshot must be durable before Morie reports **已保存**.

## Scope

Included:

- add \`CapturePersistenceWriter\` with its own SwiftData context;
- copy live model data into Sendable value snapshots before crossing actors;
- assign monotonically increasing per-Capture revisions;
- reject stale revisions in the writer;
- claim a cancellation tombstone revision before deletion I/O;
- disable \`CaptureStore\` main-context autosave;
- remove post-shell \`ModelContext.save()\` from progressive recognition, recognition completion, refinement and terminal current-app state;
- read active Capture state from the in-memory active record instead of refetching it during cleanup;
- explicit \`flushPersistence(for:)\` for save-first/dependent work;
- defer automatic Memory completion until the delivered snapshot has flushed;
- add finish→Speech-final, finish→refinement-final and finish→paste-dispatched latency logs;
- update persistence/refinement tests for the new invariant.

Excluded:

- changing Apple Speech, cleanup prompts or delivery mechanics;
- weakening the initial Capture-first recovery shell;
- dropping source-audio recovery;
- adding a database/queue dependency;
- making iCloud required;
- moving History retry/delete/settings operations off their existing non-hot paths.

## Acceptance criteria

- [x] The initial Capture shell is still saved before Speech starts.
- [x] Progressive transcript callbacks never call \`ModelContext.save()\` on the live/main actor.
- [x] Recognition completion and refinement metadata queue snapshots rather than awaiting a History save.
- [x] Active current-app refinement reads its already-owned live Capture instead of fetching it from SwiftData.
- [x] Paste dispatch occurs before any final History flush is awaited.
- [x] Current-app success/Ready is not gated by final History persistence.
- [x] Delivery-dependent Memory learning starts only after a background flush.
- [x] \`captureOnly\` flushes final History state before **已保存**.
- [x] Stale snapshot revisions cannot overwrite a newer state.
- [x] A cancellation tombstone prevents older queued writes from resurrecting the Capture.
- [x] Main-context autosave is disabled so live mutation cannot implicitly write to disk.
- [x] Input/persistence latency diagnostics are emitted.
- [ ] Updated Capture/Personalization tests compile and pass.
- [x] Final macOS 27 Release product compile passes.
- [ ] Owner-device timing confirms History activity does not materially increase finish→paste latency.

## Validation

GitHub Actions `macOS 27 CI` run #72 passed the final code head (`7e20c7930aeca8616e5d45fd3379be34820ad6ff`) as a Release product compile on Xcode 27/macOS 27.

A static hot-path check also confirms that `updateRecognizedText`, `completeRecognition` and the live refinement path no longer contain `container.mainContext.save()`. The remaining synchronous main-context saves are the initial recovery shell plus History retry/delete, audio-retention maintenance and startup recovery operations outside normal finish-to-paste delivery.

Product compile runs on Xcode 27/macOS 27 after implementation heads.

Added logic coverage includes:

- applying revision 2 before revision 1 keeps revision 2;
- a revision-3 cancellation tombstone rejects a later revision-2 persist;
- explicit \`flushPersistence\` makes the latest delivered state visible from a fresh SwiftData context;
- capture-only tests flush before releasing active ownership;
- refinement tests no longer assert that durable History state must precede model execution.

The repository's standard CI still builds the product target rather than executing the logic test target, so test execution and owner-device timing remain open until separately run.

## Latency evidence

\`InputLatency\` records:

- finish → Speech final;
- finish → refinement final;
- finish → paste dispatched.

\`CapturePersistence\` records per snapshot:

- queue wait in milliseconds;
- SwiftData write duration;
- revision and lifecycle.

This allows device validation to distinguish model/Speech time from History I/O instead of attributing the whole finish delay to one stage.

## Recovery semantics

If a background derived-state save fails, current-app delivery is not retroactively failed. The initial shell, source audio, and any earlier successful checkpoint remain available to startup recovery. A newer full snapshot can repair an earlier failed async write because snapshots are self-contained rather than deltas.

Explicit cancellation is stronger: the writer records the tombstone revision before attempting deletion, so a stale queued snapshot cannot revive the cancelled record even when deletion itself reports an I/O failure.

## Follow-up

Do not move the initial Capture shell to fire-and-forget persistence unless a different recovery design is explicitly approved.

Do not make every feature asynchronous merely for symmetry. This task is specifically about protecting the latency-sensitive input path.
