# Phase 3 Acceptance Runbook

## Purpose

Close Gate 3 with reproducible evidence that confirmed correction pairs improve the
cases they target and damage nothing else. `framework.md` states the three criteria;
this runbook supplies the measurement for the one that needs recorded speech.

Recording once and replaying is what makes the result attributable. Re-recording after
adding a pair would change the speaker along with the setting, so any difference could
be either. The saved audio removes that ambiguity.

## Completion

Gate 3 passed on 2026-08-29. All 18 items were recorded once and replayed twice
against identical audio, with the correction table as the only variable.

| Category | Corrections off | Corrections on |
|---|---:|---:|
| Term, 13 items | 7.5% | **4.1%** |
| Control, 5 items | 0.0% | **0.0%** |
| All 18 | 5.4% | 2.9% |

The vocabulary carries the named terms, and corrections list and delete through
`./vf memory` and `./vf forget`, so the first and third criteria hold outright.

Five pairs were confirmed, every one an acronym or a name with no ordinary meaning of
its own: `ies -> IESS`, `srai 1 -> SRI`, `bes -> BIESS`, `sun blue dog -> sanblueᵈᵒᵗ`,
and `jin -> Gim`, the owner's name for the Gemini model. `./vf memory` lists the live
table, which is the authority; this record is a snapshot of the run.

Three further mishearings were **refused** rather than converted into pairs. `a -> y`
would rewrite one of the most common words in Spanish. `envíe -> envié` collapses two
real verb forms. `deferring -> deferred` overwrites a word the speaker genuinely uses.
A pair is earned by a term that has no other life in the speaker's writing; a lower
number bought with an ordinary word is a corrupted table, not a passed gate.

**Read the second criterion narrowly.** Both halves of it came out the only way they
could, and calling that strong evidence would be self-deception.

The five pairs were written *after* reading these same recordings' errors, then
measured on those same recordings. Term error falling was arithmetic once those exact
failures were patched. It shows the mechanism applies confirmed pairs correctly. It
shows nothing about speech the pairs have not already seen.

The control set could not have detected collateral damage either: none of the pairs'
heard strings occurs in any of the five control sentences, so 0.0% before and after was
guaranteed by construction, not observed.

What actually supports "does not alter unrelated literal output" is the unit suite,
which applies the real confirmed pairs to sentences that *do* contain their heard
strings inside longer words — `especies`, `series`, `bebes`, `besos`, `jinete` — and
requires them to survive untouched. That test can fail. The corpus one could not.

**What would close the gap:** record a second set using the same terms in different
sentences, with the five pairs already confirmed, and replay it without adding
anything. Improvement there would be held-out evidence rather than a demonstration.

## Corpus design

Eighteen items live in `~/Library/Application Support/sanblue.voiceflow/phase3-corpus.local.json`.

- **Thirteen `Term` items** carry the vocabulary Gate 3 names: UTEL, Gim, sanblueᵈᵒᵗ,
  IESS, BIESS, SRI, RUC, FODA, PyME, aguinaldo, antigüedad, KPI, GitHub and the
  accounting terms. These are where a correction pair is allowed to help.
- **Five `Control` items** contain no special vocabulary at all. They exist to catch
  collateral damage. A pair that fixes its target and breaks ordinary speech fails the
  gate.

## Run

1. Quit every running VoiceFlow instance.
2. Build the signed app with `scripts/build-macos-app.sh`.
3. Start the run with `scripts/start-phase3-acceptance.sh`.
4. Read items 1 through 18 in order into Notes, holding Fn/Globe for each and waiting
   for the completion sound before pasting.
5. Stop if the saved number does not advance exactly once, or a reading is partial.
   Archive the attempt with a dated name and start again rather than retrying inside
   the sequence.

The recordings are kept, so this is the only time the corpus must be spoken.

## Measure

Establish the baseline with corrections disabled:

```bash
python3 scripts/replay.py --whisper-model models/ggml-large-v3-turbo.bin \
  --corpus ~/Library/Application\ Support/sanblue.voiceflow/phase3-corpus.local.json \
  --results ~/Library/Application\ Support/sanblue.voiceflow/phase3-results.local.jsonl \
  --no-corrections --require-complete --label "phase 3 baseline"
```

Read the per-item output and find the `Term` items whose vocabulary the engine did not
recover. Confirm one pair for each, using the exact text the engine produced:

```bash
./vf correct --heard "lo que escribió" --intended "lo que dijiste"
```

Only a term the engine reliably mishears earns a pair. A pair whose `heard` side is an
ordinary word the speaker also uses in its own right is rejected, because the table
rewrites that word everywhere and forever. `change`, `decision` and `views` are
ordinary words; `IESS` misheard as `yes` is not.

Then replay the identical audio with corrections enabled and compare:

```bash
python3 scripts/replay.py --whisper-model models/ggml-large-v3-turbo.bin \
  --corpus ~/Library/Application\ Support/sanblue.voiceflow/phase3-corpus.local.json \
  --results ~/Library/Application\ Support/sanblue.voiceflow/phase3-results.local.jsonl \
  --require-complete --label "phase 3 with corrections"
```

## Pass criteria

Gate 3 closes only when all three hold:

1. The vocabulary includes UTEL, Gim, sanblueᵈᵒᵗ and the selected technical terms.
   Verify with `./vf memory`.
2. Mean personalized WER over the `Term` items falls between the two replays, and mean
   personalized WER over the `Control` items does not rise at all. An unchanged control
   set is the evidence that pairs do not alter unrelated output.
3. Stored corrections can be listed and deleted. Verify with `./vf memory` and
   `./vf forget --heard "…"`.

Record the two WER figures per category and the pairs added, then update `relay-log.md`.
A gate that improves the targets while moving a control item is a failed gate, not a
partial one: remove the offending pair and measure again.

## Known limit

Eighteen items with five controls cannot detect a rare interaction, and each category
carries few samples. The run proves that the mechanism works and that the specific
confirmed pairs are safe. It does not prove that every future pair will be.
