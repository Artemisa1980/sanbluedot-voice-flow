# gates — cold-audit run logs

Every cold audit of this project writes its run log here, and only here. A run log is
created in this directory with `RUN STATUS: IN PROGRESS` before the audit begins, is
checkpointed as the run advances, and stays here when the run closes.

Every run log in this directory has a row here, including a run that was blocked or
stopped before it audited anything. An unindexed log cannot be told apart from a lost one.

**The row states what the log says, and is written after the log closes.** A row was
once filled in from what was expected — "NOT RUN" against a gate that had in fact
completed with a FAIL — and the index then concealed a real finding from anyone who
trusted it instead of opening the file.

**These are closed runs, not open work.** Their findings were remediated by the author
in the same work cycle. Read one to learn why a decision was made or whether a defect
was already raised; never treat an entry as a task, and never re-run a gate because a
log exists. A new audit requires the owner's explicit authorization for that exact target,
and it opens a new file rather than reopening one of these.

Run logs are personal working evidence, so every one of them is named `*.local.md` and
excluded from version control. `session-edits-gate-01` was renamed on 2026-09-01 to hold
that rule; only this index is meant to be shared.

The `LOG PATH:` line inside each file records where that run wrote at the time. Six of
these logs were written in the project root and moved here on 2026-09-01; their contents
were not edited, because rewriting an audit's own record of itself would damage the
evidence.

## Runs

| Log | Date | Target | Outcome |
|---|---|---|---|
| `audit-run-log.local.md` | 2026-08-29 | Phases 1–2 engine and Swift sources | COMPLETE · findings remediated |
| `phase3-code-audit.local.md` | 2026-08-29 | Gate 3 correction-memory code | COMPLETE · findings remediated |
| `phase3-direction-audit.local.md` | 2026-08-29 | Gate 3 product direction | COMPLETE · findings remediated |
| `audit-code-bugs.local.md` | 2026-08-31 | `src/` and `macos/Sources/` logic bugs | COMPLETE · 3 of 4 fixed; the "Every Gemini model is at capacity" message remains open |
| `audit-app-test.local.md` | 2026-08-31 | Build, test suites, CLI and packaged app | COMPLETE |
| `audit-edits.local.md` | 2026-08-31 | Files changed that session | STOPPED before auditing — the invocation lacked the literal authorization and target lines the contract requires. Kept as the record of that boundary |
| `session-edits-gate-01.local.md` | 2026-08-31 | Session documentation and assets | COMPLETE |
| `audit-distill-engine-gate.local.md` | 2026-09-01 | Feature 5 distillation and Python cleaners | COMPLETE · F-01 to F-09 remediated |
| `audit-swift-terminal-gate.local.md` | 2026-09-01 | Terminal auto-paste and Swift app layer | COMPLETE · 2 critical, 3 defects remediated |
| `audit-framework-quality-gate.local.md` | 2026-09-01 | Framework, roadmap, relay and design system | COMPLETE · 5 findings remediated |
| `audit-engine-timings-gate.local.md` | 2026-09-01 | Python engine stage timings and opt-in distillation | COMPLETE · FAIL on `export_jsonl` data loss; remediated with a refusal and two tests |
| `audit-station-redesign-gate.local.md` | 2026-09-01 | Station redesign and visual contract conformance | COMPLETE · 7 findings, 6 remediated, 1 rejected by the owner and recorded in the contract |
| `audit-python-pipeline-gate.local.md` | 2026-09-02 | Feature 9 close-out · Python snippets and pipeline engine | COMPLETE · FAIL on double snippet expansion and a snippet-store data-loss path; both remediated |
| `audit-swift-ui-gate.local.md` | 2026-09-02 | Feature 9 close-out · Swift app layer and UI | COMPLETE · CONDITIONAL PASS · 3 findings remediated |
| `audit-framework-governance-gate.local.md` | 2026-09-02 | Feature 9 close-out · framework, roadmap and governance | COMPLETE · CONDITIONAL PASS · 2 defects and 3 notes remediated |
| `audit-session2-python-gate.local.md` | 2026-09-02 | Session close · Python engine, practice, export | COMPLETE · FAIL · 1 critical and 2 defects remediated |
| `audit-session2-swift-ui-gate.local.md` | 2026-09-02 | Session close · Swift app layer and interface | COMPLETE · FAIL · 1 critical and 4 defects remediated |
| `audit-session2-docs-gate.local.md` | 2026-09-02 | Session close · framework, design system, acceptance | COMPLETE · FAIL · 2 blocking and 3 non-blocking findings remediated |
