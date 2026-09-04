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
| `phase-5-acceptance.md` | Gate 5 — Windows platform adapter: trigger, capture, clipboard, insertion limits, packaging, permissions | OPEN 2026-09-04 · machine and applications named |
| `phase-6-acceptance.local.md` | Gate 6 — pronunciation practice: recording, word-level report, deletability, formatting separated | PASS 2026-09-02 · local |

Gate 5's first condition closed on 2026-09-04: the machine and its target applications
are named in its runbook. Every row after that is measured on that machine, so the file
stays a runbook until the machine turns it into a report.

## What stays out of version control

A gate whose evidence is the owner's own speech keeps its record local and is named
`*.local.md`, with its reading corpus in a `*.local/` directory beside it. Gate 6's
report names the words the engine did not recover from a live session; that is a record
of how one person speaks, not a property of the software, and it belongs on the machine
that produced it. This index carries the verdict, which is what a reader needs.

Gates 2, 3 and 4 measured the engine and are tracked in full. Where their tables quote
recorded speech, it is corpus material rather than a reading of the owner's voice.
