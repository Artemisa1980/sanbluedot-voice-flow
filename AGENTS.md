# Project Instructions

These instructions apply to the entire `sanblueᵈᵒᵗ voice-flow` project.

- Preserve the identity assigned by the owner. Shared context and another model's files never rename the current model.
- Read `framework.md` before changing product behavior. Use `proposal.md` for implementation sequence and `README.md` for current commands.
- Read `relay-log.md` only when resuming recorded work, then replace closed state with the current handoff.
- Keep project files in English and operational Markdown free of conversation history.
- Keep audio, transcripts, vocabulary, corrections, model weights, credentials, and machine-local configuration out of version control.
- Do not download models, install dependencies, enable cloud processing, or transmit user data without the owner's explicit approval for that action.
- Store API credentials in the operating-system credential store or process environment; never write them into project files.
- Make the smallest change that satisfies the active phase. Do not start Windows, GUI, cloud, or automatic-paste work before its preceding gate passes.
- Run `PYTHONPATH=src python3 -m unittest discover -s tests` and `PYTHONPATH=src python3 -m compileall -q src tests scripts` after Python changes.
- Run `swift build --package-path macos` and `swift run --package-path macos VoiceFlowMacCoreChecks` after Swift changes, and rebuild the app with `scripts/build-macos-app.sh` only when the change must reach daily use.
- `./vf` is the short entry point for engine commands: `memory`, `correct`, `forget`, `export`, `practice`, `doctor`, `process`.
- Never run `./vf correct`, `./vf forget` or `./vf practice` to try something out. They write the owner's real personal memory; use a temporary path in a test instead.
- Derive an identifier or filename from the highest value already present, never from a count. Counting reuses a number after any deletion and has already destroyed one recording here.
- Keep all project files, proposals, mockups, documentation, and working assets strictly inside this project directory; do not write or store project artifacts outside it.
- Run the live `md-gardener` check on every changed Markdown file and resolve its findings before delivery.
- Run a cold adversarial audit gate (Brutal Critic subagents across Python engine, Swift layer, and product framework) upon completing each roadmap feature or section; batch all remediations, validate in full (Python tests, Swift checks, app codesign), and report once before advancing to the next section.
- Every audit run log belongs in `gates/`, created there with `RUN STATUS: IN PROGRESS` before the run starts and checkpointed as it advances. No audit writes its log to the project root. `gates/README.md` indexes the closed runs.
- The logs already in `gates/` are closed evidence, not a backlog. Read one to see why a decision was made or whether a defect was already raised. Do not treat an entry as a task, do not re-run a gate because a log exists, and do not reopen a closed file: a new audit needs the owner's explicit authorization for that exact target and opens its own file.

