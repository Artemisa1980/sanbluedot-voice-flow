# sanblueᵈᵒᵗ VoiceFlow

Personal, local-first push-to-talk dictation for macOS and Windows. **Gates 1 to 4 are
closed. Automatic paste ships, and since 2026-09-01 it reaches terminal emulators too,
under a single-line flattening guard; applications that report no bundle identifier, and
VoiceFlow's own window, stay on clipboard delivery. Windows and pronunciation practice
remain open gates.**

## Current slice

The Python engine can:

- inspect local dependencies with `doctor`;
- transcribe an existing audio file through a configured `whisper.cpp` binary;
- return the literal transcript or clean it through a local Ollama model;
- print the result or copy it to the operating-system clipboard;
- retain raw engine text, deterministic personalization, and final output separately;
- report the language the engine detected, or leave it unknown when the engine
  reported none;
- expand confirmed voice snippets into their full text after cleanup;
- report, in `--json`, the seconds speech recognition and cleanup each spent, or `null`
  when a stage did not run.

The native macOS runner can:

- open a visible control window and remain available from the Dock and menu bar;
- record through one large hold-to-talk button;
- capture the microphone while a configurable global shortcut is held;
- send the recording through the local Python engine on release;
- expose ready, recording, processing, copied, and failure states;
- show a floating retro microphone HUD with a live VU meter, the active mode, and the
  result, without taking focus from the application being dictated into;
- copy the deterministic personalized transcript by default;
- paste at the active cursor when Accessibility is granted, re-checking the focused
  application immediately before the keystroke is posted rather than when the paste was
  requested. Terminal emulators receive the text flattened to a single line so a
  dictation cannot execute itself; an application that reports no bundle identifier, and
  VoiceFlow's own window, stay on clipboard delivery;
- transform instead of clean when asked: `translate` turns Spanish speech into
  professional English, `meeting` structures it into Markdown bullets and `- [ ]`
  action items, and `transform` applies what you say to the text you highlighted in
  another application. Only `clean` passes the conservative output guard;
- name the application the text is going to, on the capsule, when it recognizes it —
  `ON AIR • VSCODE`, `PASTED ➔ TERMINAL`. Detection only: what you say is never rewritten
  because of where it is going;
- copy the personalized transcript when opt-in local cleanup fails, while retaining raw;
- delete each temporary recording after processing;
- apply the confirmed local vocabulary, correction memory, and voice snippets;
- execute a spoken action instead of pasting when the dictation is one — a web search,
  a URL, or opening an application — and paste the dictation normally when that action
  fails, so speech is never discarded;
- keep the last ten dictations in a menu-bar tray for re-copying or re-pasting;
- show, in the station window, only telemetry it measured: the recognition and cleanup
  seconds the engine reported for that dictation, and words over the time actually
  spoken. Before the first dictation those indicators are empty;
- let the speaker pick literal, local, or Gemini cleanup in the window, and store
  that provider's API key in the macOS keychain;
- let the speaker pick the Gemini model — 3.7, 3.6 or 3.5 — with each button showing its
  measured delivery, remember that choice across launches, and walk the remaining models
  automatically when Google reports capacity, naming the model that answered in the HUD
  and the activity log;
- reject cleanup that invents, reorders, substitutes, or deletes non-filler content;
- opt into a private acceptance log that keeps raw, personalized, and final output,
  release-to-result latency, and the recording behind each numbered result.

A settings interface and Windows integration are later gated phases.

## Personal memory

Local files under `~/Library/Application Support/sanblue.voiceflow/` personalize
recognition without training anything. `vocabulary.local.txt` lists terms in priority
order, and `corrections.local.json` holds confirmed `heard -> intended` pairs applied
with whole-word matching so a pair never rewrites unrelated text. Two more stores live
beside them: `snippets.local.json` for voice snippets, and `distill_pairs.local.jsonl`,
which stays empty unless distillation recording is switched on.

```bash
./vf memory
./vf correct --heard "meditation" --intended "dictation" --allow-global
./vf forget --heard "meditation"
./vf export --to ~/Desktop/voiceflow-memory.json
```

`export` satisfies R7 by writing every local store into one portable file — vocabulary,
confirmed corrections, practice history, voice snippets and distillation pairs — which is
how this memory reaches the second computer. Snippets and pairs were missing from it
while it claimed to carry everything, so a move lost both without a word.

It prints a count per section, because the pairs are the sentences you spoke and an
export that carries them without saying so is not a choice you made. Audio is excluded;
copy recordings deliberately or not at all.

`./vf` is a thin wrapper that sets `PYTHONPATH` and runs the module from the project
root, so the same commands also work as `PYTHONPATH=src python3 -m sanbluedot_voiceflow …`.

Both layers apply by default. Replaying one fixed 20-recording audio set showed the
vocabulary prompt helping every model tested, taking large-v3-turbo
from 13.5% to 10.1% mean WER for about 40 milliseconds. Disable it with
`--no-vocab-prompt`, or disable both layers with `--no-memory`. The measured gain is
partly specific to that corpus, whose references contain vocabulary terms; general
speech should expect less.

A single-word correction can rewrite that word everywhere, so `correct` requires the
additional `--allow-global` confirmation. Multi-word triggers do not require it.

## Voice snippets

A spoken trigger expands into a full block of text: a signature, a link, a template.
Expansion runs after cleanup and after the output guard, so a multi-line block or a long
URL is never rejected as invented content.

It runs as one non-cascading scan, so an expansion can never trigger another snippet —
and that holds because expansion happens in exactly one place, the engine's
`snippets.py`. The app once ran a second scan of its own over the text the engine
returned, and that pass matched the *payload* of the first expansion: a `firma` snippet
whose body says "mi linkedin" came back with the link substituted. The macOS app now
delivers the engine's `final_text` unchanged and only edits the store.

```bash
./vf snippet add --trigger "mi linkedin" --expansion "https://www.linkedin.com/in/..."
./vf snippet list
./vf snippet delete --trigger "mi linkedin"
./vf snippet export --to ~/Desktop/snippets.json
./vf snippet import --from ~/Desktop/snippets.json
```

Triggers match on word boundaries in Spanish and English, case-insensitively, longest
first. The store is versioned JSON written atomically and excluded from version control.

An expansion may carry macros, resolved when it expands:

| Macro | Resolves to |
|---|---|
| `{date}` `{time}` `{datetime}` | `2026-09-03`, `10:15`, `2026-09-03 10:15` |
| `{year}` `{month}` `{day}` | `2026`, `09`, `03` — all numeric, all the same date |
| `{uuid}` | a fresh identifier per occurrence |
| `{app}` | the frontmost application, e.g. `VS Code` |

`{app}` is left written as `{app}` when the engine was run without `--app-name`, so an
unresolved macro is visible in the text instead of arriving as a blank you would not
notice. `{day}` is the day of the month: it returned an English weekday name until
2026-09-03, which put "Thursday" inside Spanish templates regardless of the language
being spoken.

## Transform a selection

Highlight text anywhere, hold the trigger in `transform` mode, and say what to do with
it: "hazlo más formal", "resume esto en tres puntos", "make it bullet points". The
speech is the instruction and the highlighted text is the material; the result replaces
the selection through the usual paste.

The selection is read at the moment you press, while the other window still has focus,
and it is handed to the engine on standard input rather than as a command-line argument
— `ps -ww -ax` prints arguments in full to every process you run, and your screen
content does not belong there. Reading it uses a synthetic copy, so whatever was on the
clipboard is captured first and put back afterwards, including images and files.

While the recording is still cancellable, the capsule states how much it captured —
`⚡ LIVE · 412 CHARS · WHISPER` — in dot blue, or in the on-air red past two thousand
characters. Every other mode sends what you just said, which you can check by
remembering it; this one sends what was on screen, and the size is what tells you it
took the sentence you highlighted and not the whole file. Escape still cancels.

Transform needs a cleaner that can rewrite text. With `literal` it is refused rather
than run: the pairing produced an ordinary dictation while the capsule said `TRANSFORM`.
With `ollama` nothing leaves the Mac at all.

```bash
printf '%s' "$SELECTED" | ./vf process take.wav --whisper-model models/ggml-small.bin \
  --cleaner gemini --mode transform --context-text-stdin
```

## Voice actions

When a dictation is an instruction rather than text — "busca en google …", "abre
Notas", "ir a github.com" — the app performs it instead of pasting: a Google, YouTube or
GitHub search, a URL, or launching an application. Queries are encoded with
`URLComponents`, so delimiters in speech cannot corrupt the address.

An executed action suppresses the paste into the application behind VoiceFlow, so a
document is never polluted by the command that opened a browser. If the action fails,
the dictation is pasted normally, so speech is never lost. Conversational phrases that
merely start with "abre" or "open" are rejected rather than treated as an app name.

Only the `ACTION` mode looks for a command. Every other mode writes what was said, so a
sentence that merely opens like an instruction is dictated rather than executed. When
`ACTION` recognizes nothing, it says so — the capsule shows `NO CMD` and the activity log
names the sentence it dictated instead. Silence there made the mode look broken.

A spoken name with no application behind it opens that name's website. This Mac is
searched first, so `abre spotify` opens Spotify and `abre youtube` opens youtube.com,
which used to fail because there is no `YouTube.app`. The interface names what actually
happened, so a site opened in place of an application is never reported as a launch. The
list covers the everyday web properties — YouTube, Gmail, Drive, GitHub, LinkedIn,
WhatsApp, Instagram, Facebook, Netflix, ChatGPT, Claude, Canva, Notion, Figma — and a
name outside it is still refused rather than guessed at.

These phrasings are recognized:

| Say | Result |
|---|---|
| `abre notas` · `abre spotify` · `abre la calculadora` | Launches the application |
| `abre youtube` · `abre gmail` · `abre github` | Opens the site, when no such app exists |
| `busca en youtube <query>` · `search youtube for <query>` | YouTube search |
| `busca en google <query>` · `googlea <query>` | Google search |
| `busca en github <query>` | GitHub search |
| `abre safari y busca <query>` | Browser with the search |
| `ir a apple.com` · `open github.com` | Opens the address |

`abre youtube y busca lofi` is not one of them: an application name is a name, not a
sentence, and a phrase of more than three words that matches no known application is
rejected as conversation.

## Switching mode

Four modes decide what happens to a dictation: `CLEAN` writes it, `ES➔EN` translates it,
`NOTES` structures it, and `ACTION` runs it as a spoken command. Press `⌃⌥M` anywhere to
advance to the next one; the floating capsule names the new mode and shows the other
three, so the station window does not have to be open. The same choice sits in the
menu bar under **Mode**, and in the window's mode switch.

The chord is configurable, and cannot be the push-to-talk trigger:

```bash
open -n 'dist/sanblueᵈᵒᵗ VoiceFlow.app' --args \
  --mode-shortcut control+option+p
```

A mode change applies to the next dictation. Pressing the chord while the engine is
still working is ignored and logged, because that run already received its mode.

## Recent dictations

The menu bar keeps the last ten dictations — raw, personalized and final text, latency,
provider, and whether the text was pasted or copied — so a thought is not lost when the
clipboard is overwritten. Each entry can be copied, re-pasted, or cleared; the list
persists across launches in this app's user defaults and holds ten items at most.

## Distillation pairs

Off by default, and deliberately so: a pair is the sentence you spoke, kept twice — as
the engine heard it and as Gemini rewrote it — so that a local model can later be taught
that same transformation. Choosing a cloud provider cleans one dictation; it is not
consent to archive every sentence.

Turn it on for the app in the menu bar under **Keep Distillation Pairs**, or for one
engine run with `--distill`. Nothing is stored while it is off.

```bash
./vf distill list                       # counts, modes, and the file's location
./vf distill export --to ~/Desktop/pairs.jsonl
./vf distill clear --yes                # deletes every pair and the file itself
./vf distill modelfile --base-model qwen2.5:3b --out Modelfile
./vf distill create --name sanblue-voiceflow
```

`modelfile` and `create` build a local Ollama model from the pairs collected so far.
Neither has been measured against the fixed corpus yet, so treat the distilled model as
an experiment rather than a replacement for the measured cleaners.

## Pronunciation practice

Reading a known text and seeing which words the engine failed to recover turns a
mis-transcription into acoustic evidence about the speaker. Requires `ffmpeg`.

```bash
./vf practice --text "The tests run without changes"
./vf practice --text-file ~/Documents/passage.txt
./vf practice --list
./vf practice --delete 3
```

The take is recorded until Enter, kept so it can be replayed, and compared word by
word. Engine formatting is separated from missed words: a spoken number written as a
numeral, lost spacing, and a dropped Spanish written accent are reported as formatting,
never as pronunciation. A take that recovers no reference word is discarded as failed
rather than presented as a result, because near-silence makes the engine invent text.

Practice deliberately runs without the vocabulary prompt. Biasing the engine toward
known terms would flatter the result, and the point is to hear how the speech lands on
its own. VoiceFlow reports what the engine heard and assigns no score; the separate
English tutor reads these results and teaches.

## Verified local setup

The development Mac passed the engine checks on 2026-08-29 with:

- Python 3.14.7;
- `whisper.cpp` 1.9.2;
- Whisper large-v3-turbo, 1.5 GB, at `models/ggml-large-v3-turbo.bin`;
- Ollama 0.33.0 with `qwen3:4b`, approximately 2.5 GB.

Whisper Small and large-v3 are also present and kept for comparison. Replaying one
fixed 20-recording set put turbo ahead of both: 10.1% mean WER against 14.8% for Small
and 15.1% for large-v3, at 1.98 seconds of engine time against 0.80 and 3.02. Model
files remain local and are ignored by version control.

## Run from source

Requirements for the current automated checks: Python 3.11 or newer. The test suite does not require downloaded models.

```bash
PYTHONPATH=src python3 -m unittest discover -s tests -v
PYTHONPATH=src python3 -m compileall -q src tests scripts
PYTHONPATH=src python3 -m sanbluedot_voiceflow doctor
```

Build and check the native macOS runner:

```bash
swift build --package-path macos
swift run --package-path macos VoiceFlowMacCoreChecks
./scripts/build-macos-app.sh
```

The packaging script uses an installed Apple Development identity so macOS permissions
remain attached to VoiceFlow across rebuilds. It fails instead of silently reverting to
an unstable ad-hoc identity. Each build starts from an empty staging bundle, embeds the
Python engine under signed Resources without bytecode caches, signs it, and performs a
strict signature verification both before and after installation. The only entitlement
is hardened-runtime audio input for local microphone capture.

This is a signed daily-use development build, not a standalone redistributable package.
It still expects `python3`, `whisper-cli`, and the local Whisper model to exist on this
Mac; the default model remains under the project beside `dist/`. Moving the app away
from that layout requires launching it with an explicit `--project-root` or
`--whisper-model` path.

On this Mac, run the complete diagnostic with:

```bash
PYTHONPATH=src python3 -m sanbluedot_voiceflow doctor \
  --whisper-model models/ggml-large-v3-turbo.bin
```

`doctor` reads the model's ggml header instead of only checking that the path exists, so
an empty file, a downloaded error page and an interrupted download are named before a
recording is lost to them. The reported size floor comes from the file's own header. It
is a format and size check: a file truncated above that floor, or corrupted in place,
still passes, and proving the weights bit-perfect would need a recorded hash baseline
this project does not keep.

The `--json` output of `process` carries the detected language in its `language` field.
Automatic mode recovers the label whisper.cpp reports on its error stream; a forced
`--language en` or `--language es` reports that choice. The field is `null` when the
engine announced no language.

Measure what a cleanup model changes, on the fixed recorded corpus:

```bash
PYTHONPATH=src python3 scripts/cleaner_gate.py \
  --whisper-model models/ggml-large-v3-turbo.bin \
  --cleaner ollama
```

Each sample is transcribed once and every cleaner is then run on that identical
transcript, so only the cleaner varies. The candidate faces the real output guard, and
the report separates what cleanup did to the words from what it did to the punctuation,
which word error rate strips away before comparing. Any cloud provider implements the
same `clean(text, language_hint)` contract and faces this same corpus and guard.

Process a WAV file after `whisper-cli` and a compatible model are available:

```bash
PYTHONPATH=src python3 -m sanbluedot_voiceflow process sample.wav \
  --whisper-model /absolute/path/to/model.bin \
  --cleaner literal
```

Use local Ollama cleanup and copy the result:

```bash
PYTHONPATH=src python3 -m sanbluedot_voiceflow process sample.wav \
  --whisper-model /absolute/path/to/model.bin \
  --cleaner ollama \
  --ollama-model qwen3:4b \
  --copy
```

## Cloud cleanup with Gemini

Cloud cleanup is off until it is chosen. The app window carries a provider list —
literal, local Ollama, or Gemini — and the choice takes effect on the next recording,
never mid-dictation. Selecting Gemini without a key changes nothing except a warning:
dictation keeps working on this Mac.

The key is stored in the macOS keychain, on this device only, and never in a project
file, a preference, or a log. Add it in the app with **Set API key…**: the secure field
accepts standard Command+V and also has an explicit **Paste** button. Alternatively,
add it from a terminal:

```bash
./vf provider set-key gemini    # prompts; the key never appears in the command
./vf provider status gemini     # says whether a key exists, never what it is
./vf provider forget gemini
```

The app reads that same keychain item and passes the key to the engine in the child
process environment, which is why dictation never raises a keychain prompt. A terminal
run with no app around reads the item directly.

What leaves the device is the transcript text and a language hint. Audio never does.
Before each request the engine prints which provider and model are about to receive the
text. A timeout, a refused key, a provider error or a missing key all return the
deterministic local transcript, so a cloud failure costs the cleanup and nothing else.
Gemini 3.7 Flash runs with `thinking_level: low` for this narrow latency-sensitive task,
omits its deprecated temperature setting, and sends `store: false` because VoiceFlow
does not use the Interactions API's server-side conversation state.

```bash
PYTHONPATH=src python3 -m sanbluedot_voiceflow process sample.wav \
  --whisper-model models/ggml-large-v3-turbo.bin \
  --cleaner gemini
```

Gemini output faces the same output guard and the same fixed-corpus gate as the local
cleaner, so it is accepted on measured evidence rather than on reputation:

```bash
PYTHONPATH=src python3 scripts/cleaner_gate.py \
  --whisper-model models/ggml-large-v3-turbo.bin \
  --cleaner gemini
```

## Use the macOS push-to-talk app

Open the locally built app:

```bash
open 'dist/sanblueᵈᵒᵗ VoiceFlow.app'
```

The app starts in literal mode. Opt into local Ollama cleanup explicitly:

```bash
open -n 'dist/sanblueᵈᵒᵗ VoiceFlow.app' --args --cleaner ollama
```

On first launch, grant **Microphone** access to `sanblueᵈᵒᵗ VoiceFlow`. The visible
hold-to-talk button works with that permission alone. Grant **Input Monitoring** in macOS
System Settings only to enable the global Fn/Globe trigger. Choose **Retry Permissions**
from the window or the `VF` menu after changing permissions. The window includes an
**Open Input Monitoring Settings** button for this one-time setup.

The station window reopens where it was left, at the same size, and falls back to the
centre of the screen only when the remembered frame lands on a display that is no longer
attached.

The window provides one large hold-to-talk button. The default global control is the
single `Fn/Globe` key:

1. Hold the visible button or `Fn/Globe` while speaking. The microphone opens half a
   second after the press, so a hand brushing the key records nothing. Tune it with
   `--hold-delay SECONDS`, up to 3.
2. Press `Escape` while recording to take it back: the audio is deleted, nothing is
   pasted, and no history entry is written. The capsule shows `ESC ✕` at the end of the
   meter row while that is available.
3. Release it to transcribe the recording locally. If Gemini is selected, only the
   resulting transcript text and language hint leave the Mac for cleanup.
4. Wait for the menu-bar icon to show a check mark.
5. Paste the copied text with `Command+V` in the intended application.

Launch a separate instance with a different supported shortcut when needed:

```bash
open -n 'dist/sanblueᵈᵒᵗ VoiceFlow.app' --args \
  --shortcut command+shift+f8
```

`Fn/Globe` is the only modifier accepted by itself. Configured combinations may use
`command`, `control`, `option`, `shift`, or `fn` plus a letter, `Space`, `Escape`, or
`F1` through `F20`. The mode switch (`--mode-shortcut`) takes the same combinations but
never a modifier alone: it is tapped, not held.

## Run the Phase 2 acceptance matrix

The fixed 20-item run, private artifact locations, application assignments, and report
command are defined in `acceptance/phase-2-acceptance.md`. Build the current signed app, quit any
older VoiceFlow instance, then start or resume the opt-in run:

```bash
./scripts/build-macos-app.sh
./scripts/start-phase2-acceptance.sh
```

The normal app launch does not record transcripts. Acceptance artifacts stay outside the
project under `~/Library/Application Support/sanblue.voiceflow/`.

## Project map

Start here when arriving cold: `AGENTS.md` for the rules that bind any model working
in this project, then `framework.md` for what the product must do, then this file for
what currently works. `relay-log.md` holds the resumable state and is read only when
continuing recorded work.

- `AGENTS.md` — project rules: privacy, version control, required checks.
- `CLAUDE.md` — routing adapter into the shared workspace contract.
- `framework.md` — normative behavior and acceptance gates.
- `proposal.md` — product direction and delivery sequence.
- `src/sanbluedot_voiceflow/` — engine implementation.
- `src/sanbluedot_voiceflow/output_guard.py` — deterministic conservative-cleanup guard.
- `src/sanbluedot_voiceflow/snippets.py` — voice snippet store and expansion.
- `src/sanbluedot_voiceflow/distill.py` — opt-in distillation pairs and Modelfile build.
- `macos/` — native menu-bar runner and dependency-free checks.
- `macos/Sources/VoiceFlowMacCore/PasteTarget.swift` — which applications may receive a keystroke.
- `macos/Sources/VoiceFlowMacCore/VoiceAction.swift` — spoken-intent parsing.
- `windows/` — Windows platform adapter scaffold: written and audited, never compiled.
- `scripts/build-macos-app.sh` — stable local `.app` packaging and Apple Development signing.
- `acceptance/` — one runbook and report per framework gate; `acceptance/README.md` indexes them.
- `docs/` — HTML previews of interface surfaces, built from the `design-system.md` tokens.
- `gates/` — cold-audit run logs, closed evidence; `gates/README.md` indexes them.
- `scripts/start-phase2-acceptance.sh` — opt-in private acceptance launcher.
- `scripts/start-phase3-acceptance.sh` — Gate 3 acceptance launcher.
- `scripts/phase2_report.py` — private latency and word-error report generator.
- `scripts/replay.py` — replay a saved run's audio under a different configuration.
- `vf` — short wrapper for the engine commands.
- `tests/` — dependency-free unit tests.
- `relay-log.md` — current resumable handoff; read only when resuming work.

## Private data

Do not place recordings, transcripts, vocabulary, corrections, API keys, local configuration, model weights, or packaged builds in the repository. The `.gitignore` records the expected local paths and file classes.

## Validation status

- The Python unit tests pass and all Python sources compile. Run them rather than
  trusting a count written here.
- Station telemetry is measured, not assumed. The engine reports the seconds speech
  recognition and cleanup each spent in its `--json` `timings` field, the window shows
  those figures and leaves an indicator empty when a stage reported none, and the rate
  is words over the seconds actually spoken. Until 2026-09-01 the bar displayed a fixed
  180 ms recognition latency, a seeded 1.24 s and 220 WPM before any dictation, and a
  rate clamped into a plausible band; none of those were measurements.
- Distillation recording is off unless it is switched on, in the menu bar or with
  `--distill`, and `VoiceFlowMacCoreChecks` asserts that an ordinary run and a cloud run
  without that setting both reach the engine without the flag.
- The Swift runner builds, its configuration checks pass, and the signed `.app` launches.
- A bundled JFK WAV sample passed through Whisper literal and Ollama cleanup modes.
- A synthetic Spanish-English sample preserved both languages through the complete local pipeline.
- The owner approved macOS permissions and passed the first live global Fn/Globe recording.
- Gate 2 passed with 20/20 ordered recordings, no crash or stuck recording state, and
  clipboard delivery confirmed in Notes, Safari, and VS Code.
- The acceptance run of 2026-08-29 kept its audio, so every comparison below replays
  identical recordings and is repeatable to the decimal.
- Model comparison, vocabulary prompt on: large-v3-turbo 10.1% mean WER at 1.98 seconds
  of engine time, Whisper Small 14.8% at 0.80 seconds, large-v3 15.1% at 3.02 seconds.
- Accuracy splits sharply by category, which corrects the long-standing claim that
  mixed speech is the weakness. With turbo: Spanish 0.0% over four samples, numbers
  0.0%, mixed 7.6% over six, English 13.8% over the original four, technical terms 18.8%, and a
  single URL at 50.0%. Spanish measured 0.0% on these four samples; English carries the
  largest repeatable category error. Per-category counts are small, so treat the ordering
  as indicative rather than conclusive.
- Recording quality is a minor factor. The recordings measure about 21.8 dB
  signal-to-noise, and injecting matching noise into clean synthetic speech costs only
  2.4 points, so the current evidence points to accent rather than the microphone as the
  larger contributor to residual English error.
- Forcing a language loses to automatic detection: 19.3% for English and 33.2% for
  Spanish against 10.1%.
- Engine tuning changed nothing. Thread counts of 5, 8 and 11 are indistinguishable
  because the encoder runs on the GPU, and the default beam size beats 1, 3 and 8.
- Gate 3 passed on 2026-08-29. Replaying one fixed 18-item set with the correction
  table as the only variable moved Term error from 7.5% to 4.1% while the five Control
  items stayed at 0.0%. Five acronym and proper-noun pairs were confirmed; three
  mishearings of ordinary words were refused rather than patched. Read that result
  narrowly: the pairs were derived from the same recordings they were measured on, and
  no Control sentence contains any pair's heard string, so neither number could have
  come out otherwise. The evidence that pairs leave unrelated text alone is the unit
  suite, which applies the real confirmed pairs to sentences that do contain them
  inside longer words.
- The model change bought nothing where it matters most. Per category, turbo beats or
  ties Small everywhere, but English measures 18.5% on both over the three English
  recordings that survive; the 13.8% above covers four, including the one destroyed by
  the logger defect, which turbo transcribed perfectly. The gains are in Spanish,
  numbers and clipboard text.
- A logger defect destroyed one Phase 2 recording before it was fixed: both acceptance
  runs wrote to a shared `audio` folder, so the second overwrote the first. Each run
  now keeps its own folder, and the Phase 2 set replays with its remaining 19 items.
- The detected language now survives to the caller. Processing a WAV in automatic mode
  against `ggml-small.bin` returns `"language": "en"` where the field was previously
  `null`; the label came from whisper.cpp, not from inspecting the text.
- `doctor` passes both provisioned models with their layer count, mel bands and size,
  and rejects a 100 kB head of `ggml-small.bin` as truncated against a 20.0 MB floor
  derived from that same header.
- The local cleaner was measured on 37 recorded samples across both corpora and does
  not earn being on by default. It changed one sample, adding one correct punctuation
  mark; the output guard refused three of its attempts because it tried to insert words;
  every other accepted result was identical to the engine transcript, for about 0.6
  seconds per dictation. Verdicts: CONDITIONAL on the Phase 2 corpus, PASS on Phase 3 on
  the strength of that single mark.
- The vocabulary prompt suppresses the engine's punctuation, which every earlier word
  error rate measurement was blind to because that metric strips punctuation before
  comparing. Replaying the same 19 recordings, the prompt on yields 3.6 marks per 100
  words and 3 periods; the prompt off yields 16.2 marks per 100 words and 17 periods,
  against 17.7 per 100 words in the reference. Punctuation F1 on recovered words moves
  from 34.8% to 93.8%. The prompt is a comma-separated list carrying no sentence
  punctuation of its own, and Whisper follows the style it is given.
- A paid Gemini key is stored in the macOS keychain. On 2026-08-30 the key successfully
  authorized the model catalog and listed Gemini 3.7 Flash.
- `gemini-3.7-flash` does return inference. The earlier "no response" reading was partly
  a client-side ceiling: successful replies arrived at 21.3, 24.1 and 34.6 seconds
  against a 20-second timeout, so healthy replies were being cancelled on arrival. The
  timeout is now 45 seconds bounding the whole call, and one transient status is retried
  inside that same budget.
- The default is `gemini-3.5-flash`, the model that answers rather than the highest
  version. Three candidates were measured interleaved on 2026-08-31, same minutes, same
  request shape, with identical output quality on cleanup, translation and meeting notes:

  | Model | Delivered | Median |
  |---|---|---|
  | `gemini-3.5-flash` | 5/6 | 2.3 s |
  | `gemini-3.6-flash` | 4/6 | 14.3 s |
  | `gemini-3.7-flash` | 3/6 | 12.5 s |

- Every failure is HTTP 503 `UNAVAILABLE`: "this model is currently experiencing high
  demand". It is Google capacity, not this project. The billing account is active and
  charged, the same status reaches every model including the 2.5 generation, and it
  persists with the response schema removed and at a 256-token budget.
- Provider capacity swung widely across that session, including a window where every
  model timed out at 45 seconds. The number that matters is not latency but that the
  fallback holds: every failure returned the deterministic personalized transcript with
  no crash and no loss.
- The model chain closes most of that gap. Choosing `gemini-3.7-flash`, the busiest
  model, delivered 0 of 5 before the chain existed and **4 of 4 after**, in 23.8 to 28.2
  seconds, answered by 3.6 three times and by 3.5 once.
- With `gemini-3.5-flash` as the default the cost disappears: **5 of 6 delivered, 4.19
  second median**, worst success 7.29 seconds, because no slice is spent on a busy model
  before reaching one that answers. The single failure exhausted all three models and
  returned the local transcript at 45 seconds.
- Each model gets at most 15 seconds of the 45-second budget, except the last, which may
  use whatever remains. Without that cap a busy 3.7 consumed all 45 seconds and 3.5 was
  never reached, which was observed before the cap was added.
- Treat the 3.18-second Gate 4 median as the measurement of its own day. Re-measure both
  models before trusting any latency figure here.
- The Swift core checks assert that the key reaches the engine only through the
  environment, only for a cloud cleaner, never as a command argument, and never when it
  is empty.
- A recording with no audible speech is rejected before the engine runs. Near-silence
  otherwise makes whisper.cpp invent text, and with the vocabulary prompt loaded it
  invents terms from that prompt straight onto the clipboard.
- The local cleaner is still unevaluated. It altered no word in 20 results, and the
  metric normalizes away the punctuation it adds, so this corpus cannot judge it. It is
  now opt-in, and a deterministic guard rejects lexical invention, reordering,
  substitution, and non-filler deletion before clipboard delivery.
