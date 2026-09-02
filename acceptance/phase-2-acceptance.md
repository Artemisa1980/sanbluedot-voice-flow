# Phase 2 Acceptance Runbook

## Purpose

Close Gate 2 with reproducible evidence from the owner's Mac and voice. The run measures 20 global Fn/Globe recordings, clipboard delivery in Notes, Safari, and VS Code, release-to-result latency, and word error rate against a fixed local corpus.

## Completion

Gate 2 passed on 2026-08-28:

- 20/20 ordered recordings completed without a crash or stuck state;
- Notes, Safari, and VS Code received clipboard output;
- release-to-result latency after warm-up was 1.90 seconds p50 and 2.27 seconds p95;
- raw WER was 25.6% and cleaned WER was 26.9%;
- no cleanup fallback occurred.

The private report at `~/Library/Application Support/sanblue.voiceflow/phase2-report.local.md` is the detailed evidence. The baseline shows that mixed English-Spanish recognition needs improvement and that the current local cleaner does not improve aggregate WER.

## Private artifacts

The corpus and results contain user speech data and stay outside the project under `~/Library/Application Support/sanblue.voiceflow/`:

- `phase2-corpus.local.json` — the fixed 20-item reference corpus;
- `phase2-results.local.jsonl` — raw, personalized, and final output plus latency;
- `phase2-results.local-audio/NNN.wav` — the recording behind each numbered result;
- `phase2-report.local.md` — the generated acceptance report.

Ordinary launches create no persistent audio and keep the existing
delete-after-processing behavior. The opt-in acceptance run is the single exception:
it keeps each recording so a later configuration can be replayed against identical
audio instead of a fresh performance. Recording again would change the speaker along
with the setting, leaving no way to attribute a difference to the change. The audio
stays on this Mac, sits outside the project, is ignored by version control, and is
deleted by removing that `phase2-results.local-audio` directory. Acceptance logging
enables no cloud processing.

Replay a saved run under a different configuration with `scripts/replay.py`, which
reports mean raw, personalized, and final WER plus engine latency for the settings given.

## Run

1. Quit every running VoiceFlow instance.
2. Build the signed app with `scripts/build-macos-app.sh`.
3. Start the opt-in run with `scripts/start-phase2-acceptance.sh`.
4. Record corpus items 1–8 into Notes, 9–14 into Safari, and 15–20 into VS Code.
5. Keep the assigned prompts visible in the target application so no application switching is required while recording.
6. For each item, hold Fn/Globe, read the exact prompt naturally, release Fn/Globe,
   and wait for the short completion sound. The menu-bar icon also shows a check mark
   and VoiceFlow reports `Acceptance N saved`. Only then press Command+V; pasting
   sooner returns the previous clipboard value.
7. Paste the result only once in the matching result field.
8. Stop if the saved number does not advance exactly once, a prompt is forgotten, a recording is partial, or the app becomes stuck. Archive the run as a pilot rather than retrying within the fixed sequence.
9. After item 20, confirm that clipboard paste succeeded in all three applications.

The results file is append-only so an interrupted run can resume at the next number. Move the existing local results file to a dated backup before intentionally starting a new run.

Recording 1 counts toward the 20-recording stability and accuracy checks but serves as the warm-up for latency. The report calculates p50 and p95 from recordings 2–20.

## Report

After all 20 items and manual delivery checks pass, generate the private report:

```bash
python3 scripts/phase2_report.py \
  --confirmed-app Notes \
  --confirmed-app Safari \
  --confirmed-app "VS Code"
```

Run `md-gardener` on the generated local report, review p50, p95, raw, personalized,
and final WER, safe fallbacks, and per-sample failures, then update `relay-log.md`.
Gate 2 closes only if all 20 recordings complete without a crash or stuck recording
state and clipboard delivery is confirmed in all target applications.
