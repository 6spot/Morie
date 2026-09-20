# Development Diagnostics

Morie treats development observability as infrastructure rather than temporary
print statements. A single voice Capture should be reconstructable end-to-end
from one diagnostic log by searching its eight-character Capture ID.

## Activation

Verbose development tracing is enabled only when the process is running with
Swift's debug-assert configuration. Release builds keep the normal bounded,
privacy-preserving diagnostics and do not emit `Dev/*` raw-text events.

The Overview page shows the stamped version, build, Git commit, branch and build
configuration. Debug builds also expose the runtime-only Application Context
inspector.

## Local privacy boundary

Development logs may contain:

- user speech/transcript text;
- current-app selected/focused/nearby Accessibility text;
- extracted vocabulary and Speech contextual strings;
- Memory notes supplied to local deterministic guards;
- refinement and Memory model prompts and generated output;
- bounded post-insertion edits.

Development logs must never contain:

- API keys or authorization headers;
- Keychain credential contents;
- passwords or secure text field contents;
- unrelated clipboard contents.

Secure Event Input and AX secure text fields continue to suppress Application
Context collection before any debug text can be emitted.

Do not publish a development log without reviewing/redacting it first.

## Capture trace coverage

Every relevant `Dev/*` event carries `Capture XXXXXXXX` when a Capture ID is
available.

### Environment and configuration

- `Dev/Environment`: version/build/commit/branch/configuration, OS, locale,
  process and executable identity.
- `Dev/Capture`: delivery mode, target app/PID, frozen feature flags and model
  mode.
- `Dev/CloudConfig` / `Dev/Keychain`: endpoint/model configuration and
  credential access lifecycle. Credential contents are never logged.

### Audio and Speech

- `Dev/Audio`: microphone identity, requested capture format, duration and
  meaningful-audio outcome.
- `Dev/SpeechContext`: exact contextual strings actually applied to Apple
  Speech, including late Application Context updates and saved-audio retry
  context.
- `Dev/SpeechLive`: throttled progressive transcript snapshots.
- `Dev/Speech`: live final, accurate retry, preferred recognition source and
  preferred final text.

### Application Context

- `Dev/AX`: trust/secure-input state, focused AX role/subrole, PID validation
  and traversal-budget usage.
- `Dev/ApplicationContext`: bounded selected/focused/nearby raw text.
- `Dev/Vocabulary`: every candidate's source, quality/rank decision,
  de-duplication and final selected set.
- the Overview inspector shows the latest context and hint provenance in memory
  only.

### Refinement and personalization

- `Dev/RefinementInput`: recognized/prepared text, Dictionary candidates,
  confirmed corrections, Memory matches and expression directives.
- `Dev/RefinementMemory`: matched Memory notes for local debugging only.
- `Dev/RefinementPrompt`: effective instructions and model payload.
- `Dev/RefinementModel`: backend choice, cloud host/model, token budgets and
  safe error types.
- `Dev/RefinementRunner`: model-task ownership/busy/cancellation lifecycle.
- `Dev/RefinementOutput`: generated and accepted text plus edits.
- `Dev/RefinementGuard` / `Dev/RefinementGuardDetail`: exact deterministic
  rejection rule and supporting fact/leak/script/expansion evidence.

### Memory learning and post-insertion learning

- `Dev/MemoryLearning`: source, active/blocked context, model suggestions and
  failures.
- `Dev/MemoryPrompt` / `Dev/MemoryModel`: effective local-model prompt,
  token budget and raw structured observations.
- `Dev/MemoryAdmission`: grounding, de-duplication and learned/ignored/conflict
  decisions.
- `Dev/PostInsertion`: bounded inserted text, anchor state, observed edits,
  dictionary-correction candidates and expression-sample recording.

### Delivery and completion

- `Dev/Delivery`: exact text being delivered and actual destination app/PID.
- `Dev/Capture`: terminal success and end-to-end elapsed time.
- normal `InputLatency`, `CapturePersistence` and `Memory` categories remain
  the source of detailed timing, durability and process-memory measurements.

## Working with a trace

1. Open **控制面板 → 诊断**.
2. Search for the eight-character Capture ID shown in History or the Overview
   Application Context inspector.
3. Use **复制当前筛选** to copy only that Capture's trace.
4. For cross-Capture startup issues, search `Dev/Environment`,
   `Dev/CloudConfig`, `Capability` or `Memory` instead.

The local diagnostic file remains at
`~/Library/Logs/Morie/morie-debug.log`. Development builds keep a larger
bounded log window so one complete trace is less likely to be rotated away.
