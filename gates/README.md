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
| `audit-evolution-python-gate.local.md` | 2026-09-03 | Competitive evolution · Python engine and tests | STOPPED before auditing — the launch packet named no gate and the report lacked `GATE STATUS: IN PROGRESS`. Nothing was opened and no verdict applies |
| `audit-evolution-swift-gate.local.md` | 2026-09-03 | Competitive evolution · Swift application layer | STOPPED before auditing — same two launch defects. Nothing was opened and no verdict applies |
| `audit-evolution-docs-gate.local.md` | 2026-09-03 | Competitive evolution · framework, design system, governance | STOPPED before auditing — same two launch defects. Nothing was opened and no verdict applies |
| `evolution-python-gate-01.local.md` | 2026-09-03 | Competitive evolution · Python engine and tests | COMPLETE · CONDITIONAL PASS · unguarded stdin read and an untested Gemini transform branch |
| `evolution-swift-gate-01.local.md` | 2026-09-03 | Competitive evolution · Swift application layer | COMPLETE · FAIL · `positionPanel()` resized the redesigned capsule back to `295 × 74`, clipping it by 17pt on every show |
| `evolution-docs-gate-01.local.md` | 2026-09-03 | Competitive evolution · framework, visual contract and governance | COMPLETE · FAIL · the same panel-size contradiction, a wrong vintage-mic state rule, and two unsupported claims in the relay |
| `windows-scaffold-gate-01.local.md` | 2026-09-03 | Windows platform adapter scaffolding | COMPLETE · FAIL · 9 blocking errors remediated by author |
| `focus-home-gate-01.local.md` | 2026-09-08 | Focus Home shell, engine boundaries and product contract | CANCELLED 2026-09-17 · the independent reports it waited for never arrived, so it audited nothing and carries no verdict |
| `focus-home-gate-02.local.md` | 2026-09-17 | Focus Home shell, second run | COMPLETE · findings remediated; the shell's missing tests (W5) reported and left open |
| `findings-audit-01.local.md` | 2026-09-17 | The 12 findings recorded in the relay: are they real, and is each remediation safe | COMPLETE · CONDITIONAL PASS · 10 of 12 confirmed, 1 misclassified, 1 unverified, 1 remediation rejected as unsafe |
| `session-audit-02.local.md` | 2026-09-18 | Every change of the 2026-09-18 session plus the proposed Siri/Xcode plan | COMPLETE · CONDITIONAL PASS · all changes validated; one behaviour risk, one guard limitation, one plan claim corrected against Apple's documentation |
| `apple-comparison-audit.local.md` | 2026-09-18 | The spoken comparison of macOS 27 and Siri AI against VoiceFlow | COMPLETE · FAIL · one headline differentiator false, two claims sourced from a search summary and delivered as Apple's own |
| `full-code-audit-01.local.md` | 2026-09-27 | Whole macOS code base, working tree after `3d2182b` | COMPLETE · FAIL · 3 errors (fix guard deletes a distant negation, app save erases CLI snippets, fallback mislabels personalized text), 11 weaknesses and risks; 19 backlog defects still present |
| `full-code-audit-02-python-engine.local.md` | 2026-10-01 | Whole-app review · Python pipeline, guards, cleaners, transcribers | COMPLETE · FIT WITH FIXES · 10 new (4 MEDIUM: last Gemini model timeout names no model, typographic apostrophe refused, Whisper non-speech output unfiltered, transform prompts lack a data boundary); D-39 still open |
| `full-code-audit-02-python-cli-stores.local.md` | 2026-10-01 | Whole-app review · CLI, personal stores, tooling, build scripts | COMPLETE · FIT WITH FIXES · 1 HIGH (practice recordings deleted after an index quarantine), 4 MEDIUM, 9 LOW |
| `full-code-audit-02-swift-core.local.md` | 2026-10-01 | Whole-app review · `VoiceFlowMacCore`, Apple and Parakeet helpers, bundle metadata | COMPLETE · FIT WITH FIXES · 1 HIGH (Parakeet helper can download or purge the model during a dictation), D-40 still open, 1 MEDIUM (`search for` query) |
| `full-code-audit-02-swift-app-logic.local.md` | 2026-10-01 | Whole-app review · Swift application layer | COMPLETE · FIT WITH FIXES · 4 MEDIUM (busy press dropped silently, unbounded recording, temp WAV survives Quit, App Intents pipe-write crash), 7 LOW |
| `full-code-audit-02-swift-ui.local.md` | 2026-10-01 | Whole-app review · SwiftUI views against `design-system.md` | COMPLETE · FIT WITH FIXES · 1 HIGH (console stops following the log at 50 entries), 8 MEDIUM, 14 LOW; D-23, D-24 and D-49 still open |
| `full-code-audit-02-security-privacy.local.md` | 2026-10-01 | Whole-app review · security and privacy across layers | COMPLETE · FIT WITH FIXES · no secret leak; 1 MEDIUM (temp WAV survives a quit or crash), 7 LOW |
| `session-audit-03.local.md` | 2026-10-02 | Commit `96fd83d`, the merge with `b8d6797` and the git state before push | COMPLETE · FAIL · D-54 only half fixed (F1, blocking), a `word + no` hole in the D-39 guard (F2), 8 lower findings; no personal data found; all remediated by the author the same day |
| `full-code-audit-03-python-engine.local.md` | 2026-10-23 | Whole-app analysis · Python pipeline, guards, cleaners, transcribers | COMPLETE · FIT WITH FIXES · 0 HIGH, 3 MEDIUM (1 Windows-only), 5 LOW |
| `full-code-audit-03-python-cli-stores.local.md` | 2026-10-23 | Whole-app analysis · CLI, personal stores, scripts, tests | COMPLETE · FIT WITH FIXES · 0 HIGH, 5 MEDIUM (1 Windows-only), 12 LOW |
| `full-code-audit-03-swift-core.local.md` | 2026-10-23 | Whole-app analysis · `VoiceFlowMacCore`, helpers, bundle metadata | COMPLETE · FIT WITH FIXES · 0 HIGH, 5 MEDIUM, 5 LOW |
| `full-code-audit-03-swift-app-logic.local.md` | 2026-10-23 | Whole-app analysis · Swift application layer | COMPLETE after two API-limit resumes · FIT WITH FIXES · 0 HIGH, 3 MEDIUM (1 is open I-35), 6 LOW |
| `full-code-audit-03-swift-ui.local.md` | 2026-10-23 | Whole-app analysis · SwiftUI views against `design-system.md` | COMPLETE · FIT WITH FIXES · 0 HIGH, 13 MEDIUM, 14 LOW |
| `full-code-audit-03-pipelines-crosscutting.local.md` | 2026-10-23 | Whole-app analysis · build, security, repository hygiene, docs versus code | COMPLETE · FIT WITH FIXES · 0 HIGH, 5 MEDIUM, 3 LOW |
| `full-code-audit-03-summary.local.md` | 2026-10-23 | Consolidation of the six logs above, every MEDIUM re-checked in code | COMPLETE · FIT WITH FIXES · 29 MEDIUM, 45 LOW, 2 Windows-only, 53 improvements; analysis only, nothing remediated yet |
| `full-code-audit-04-python.local.md` | 2026-10-25 | Whole-app review · Python pipeline, cleaners, transcribers, CLI, stores, tests | COMPLETE · 1 HIGH, 4 MEDIUM, 7 LOW |
| `full-code-audit-04-swift.local.md` | 2026-10-25 | Whole-app review · Swift core, app logic, concurrency, helpers, UI views | COMPLETE · 1 CRITICAL, 1 HIGH, 2 MEDIUM, 1 LOW |
| `full-code-audit-04-summary.local.md` | 2026-10-25 | Consolidation of the two logs above across Python and Swift | COMPLETE · CONDITIONAL PASS · 17 findings assigned D-191 to D-207 |
| `full-code-audit-05-python.local.md` | 2026-10-26 | Whole-app review · Python pipeline, cleaners, fallback chains, CLI, stores, tests | COMPLETE · CONDITIONAL PASS · 1 framework defect, 4 weaknesses/risks |
| `full-code-audit-05-swift-systems.local.md` | 2026-10-26 | Whole-app review · Swift lifecycle, pipes, concurrency, App Intents, watchdog | COMPLETE · CONDITIONAL PASS · 1 safety R3c, 3 concurrency/stability, 1 hygiene |
| `full-code-audit-05-swift-ui.local.md` | 2026-10-26 | Whole-app review · Microduck HUD, RetroMicHUDView, FocusHome, design-system | COMPLETE · FAIL · 1 error (disconnected voice gate/dead minimal capsule), 1 framework defect, 2 risks, 7 weaknesses, 1 preference |
| `full-code-audit-05-pipelines-build.local.md` | 2026-10-26 | Whole-app review · build scripts, codesign, SPM, CoreChecks, replay | COMPLETE · CONDITIONAL PASS · 2 errors (cleaner gate exit 0 on failure, replay missing --apple-bin), 1 framework defect, 6 weaknesses, 1 preference |
| `full-code-audit-05-governance-walkthrough.local.md` | 2026-10-26 | Whole-app review · model navigability, WalkthroughHierarchy, CLAUDE/AGENTS discovery | COMPLETE · CONDITIONAL PASS · 5 weaknesses (walkthrough accuracy, routing gap in CLAUDE/AGENTS, signature guide path, framework R6) |
| `full-code-audit-05-summary.local.md` | 2026-10-26 | Consolidation of the five logs above across app, code, UI, pipelines, and governance | COMPLETE · FAIL · 37 findings (3 errors, 3 framework defects, 6 risks, 23 weaknesses, 2 preferences) |
