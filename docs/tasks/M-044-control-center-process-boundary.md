# M-044 — Control Center process isolation experiment

## Status

**BLOCKED** — superseded by M-045

Implementation evidence: draft PR #106.

## Outcome

M-044 tested whether isolating Control Center presentation in a separate process would allow the always-running voice runtime to return near its cold memory baseline after the UI closes.

Owner-device validation confirmed the process-isolation premise: after the separate presentation process terminated, the resident runtime returned near the desired low physical-footprint baseline.

However, the experimental implementation made the voice runtime the product-facing `Morie` process and made the Control Center a helper. That product ownership direction is not accepted.

## Superseded by M-045

M-045 keeps `Morie.app` as the primary GUI application and moves Hotkey / Capture / Speech / refinement / persistence into a background `Morie Runtime` agent.

PR #106 remains a draft reference for the memory investigation and process-isolation evidence. It must not be merged as the final architecture.
