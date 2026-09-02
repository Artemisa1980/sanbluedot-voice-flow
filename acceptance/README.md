# acceptance — gate runbooks and reports

One file per framework gate: how the gate was measured, and what the measurement
returned. `framework.md` states the criteria a gate must satisfy; a file here supplies
the procedure and the recorded result for the criteria that need real speech, a real
machine, or a real provider.

A gate closes here, not in a chat and not in the relay. When Gate 5 or Gate 6 closes,
its runbook and report are written in this directory under the same name pattern.

These are not audits. Cold-audit run logs live in `gates/`; an acceptance file is the
author's own reproducible measurement of a gate the product must pass.

The runbooks stay usable after their gate closes: every comparison in `README.md` under
"Validation status" replays the corpora they define, so a later change can be measured
against the same recordings rather than against a fresh, incomparable set.

## Gates

| File | Gate | State |
|---|---|---|
| `phase-2-acceptance.md` | Gate 2 — macOS push-to-talk: 20 recordings, latency, word error rate, clipboard delivery | PASS 2026-08-29 |
| `phase-3-acceptance.md` | Gate 3 — correction memory, with control items that must not move | PASS 2026-08-29 |
| `phase-4-acceptance.md` | Gate 4 — cloud cleanup: privacy boundary, fallback, output guard, corpus quality | PASS 2026-08-31 |

Gate 5 (Windows) has no file yet: the Windows machine is still unnamed. Gate 6
(pronunciation practice) is implemented and untested against a live session, so it has
no acceptance record either.
