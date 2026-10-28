# Backlog — defects and improvements

The single task list for this project: every known defect with its fix, and every
improvement with the reason it is worth building. `gates/` holds the evidence behind each
row and is never a task list; this file is.

## Executive Status & Quick Index — 2026-10-27

| Category | Total Cataloged | Done (Closed) | Open (Pending) | Status |
|---|---:|---:|---:|---|
| **Defects — High** (§A) | 33 | 33 | **0** | **100% Cleared ✓** |
| **Defects — Medium** (§A) | 90 | 85 | **5** | 94% Cleared |
| **Defects — Low** (§A) | 88 | 73 | **15** | 83% Cleared |
| **Improvements — Roadmap** (§B) | 30 | 5 | **25** | Active backlog |
| **Improvements — Maintenance** (§B) | 46 | 4 | **42** | Technical proposals |
| **Total** | **287** | **200 (70%)** | **87 (30%)** | **Stable floor** |

### Quick Index: The 20 Open Defects (Zero High)
- **Medium (5 items):**
  - `D-17`: Add dedicated test target for Swift application layer (`VoiceFlowMacTests`).
  - `D-32`: Refine long spoken take-backs on local engines.
  - `D-42`: Exclude ordinary phrases from false take-back cues ("sorry for the delay").
  - `D-132`: Prevent VU meter live bars ceiling overflow on extreme loud speech.
  - `D-133`: Preserve typed form text in Snippet editor if disk save fails.
- **Low (15 items):**
  - `D-18`: Re-measure Gemini delivery latency when owner authorizes credits.
  - `D-21`: Verify station carries every approved preview item.
  - `D-24`: Add shape/text cues beside color for option selections.
  - `D-31`: Guard prompt example return in Apple Writing Tools.
  - `D-43`: Preserve casing of proper nouns during guard evaluation.
  - `D-79`: Truncation polish on reference labels.
  - `D-82`: Conceal raw dictated text in on-screen console (log counts only, R7).
  - `D-87`: Bound `distill create` to localhost Ollama instances.
  - `D-90`: Multi-line support and macro reference in snippet editor.
  - `D-111`: Add visible permission status indicators in Settings.
  - `D-112`: Reject unticked one-word FIX pairs cleanly.
  - `D-114`: Prevent Words row edit from discarding FIX in progress.
  - `D-122`: Calibrate D-53 steady-noise threshold across microphones.
  - `D-176`: VoiceOver activation handling on hold-to-talk capsule.
  - `D-182`: Persist form input state in Station across tab switching.

## How to work this list

1. Read `AGENTS.md` and `framework.md` first. They decide what correct behaviour is.
2. Work top-down: High, then Medium, then Low. An improvement in §B starts only when the
   owner picks it. A row marked **Blocked** waits for what it names.
3. Fix one row at a time with the smallest change. Add a test or a
   `VoiceFlowMacCoreChecks` check that fails without the fix — reintroduce the defect
   once and watch it fail. Then run the checks `AGENTS.md` requires.
4. Tick the box and append one line: `Done YYYY-MM-DD — what changed · how it was
   verified`. Never delete a row; a fix that proves wrong is unticked with the reason.
5. A new finding takes the next free number (highest present + 1), a severity, what
   happens, the fix, where, the source and the evidence.

**Severity.** High: loses data or the speaker's words, delivers wrong text, or breaks the
app. Medium: a wrong result in realistic use. Low: an edge case, a misleading detail or
maintenance.

**Evidence.** `executed` — reproduced by running it. `code` — confirmed by reading the
code. `reported` — raised by a reviewer and not yet confirmed. Unconfirmed is not the
same as broken.

**Sources.** `02-engine`, `02-cli`, `02-core`, `02-app`, `02-ui` and `02-security` are the
six logs `gates/full-code-audit-02-*.local.md` of 2026-10-01; `01` is
`gates/full-code-audit-01.local.md`; a date alone is a direct read or run that day.
`03-engine`, `03-cli`, `03-core`, `03-app`, `03-ui` and `03-pipelines` are the six logs
`gates/full-code-audit-03-*.local.md` of 2026-10-23, consolidated with their original
identifiers (E-, C-, S-, A-, U-, P-) in `gates/full-code-audit-03-summary.local.md`.

## A. Defects

### High — fix first

- [x] **D-53 · Background noise with no speech becomes an invented sentence.**
  Whisper turns a take of steady noise into text and the app pastes it: synthetic noise
  at RMS 0.012 came back as "and the rest of the world." The silence floor (RMS 0.003)
  only stops near-silence.
  **Fix:** reject a take whose loud frames do not rise clearly above its quiet frames.
  On the 44 recordings kept on this Mac, speech varies by at least 8.9× between its
  quiet and loud frames; steady noise varies by 1.1×.
  `transcribers/whisper_cpp.py:21` · `02-engine` F2 · executed 2026-10-02
  Done 2026-10-02 — `is_effectively_silent` also refuses a take whose loud frames stay
  under 1.6× its quiet ones; covers Whisper and Parakeet · two new tests (the noise one
  failed before the fix), all 44 kept recordings still accepted, the noise take now
  refused before Whisper runs.

- [x] **D-54 · A damaged practice index deletes every kept practice recording.**
  When `sessions.local.json` is quarantined, the next sweep sees no session and deletes
  each WAV older than 300 s; the index survives as `.corrupt-*`, the audio does not.
  **Fix:** never sweep when the index was unreadable; sweep only against ids the file
  actually claims.
  `practice.py:440` `sweep_orphans` · `02-cli` 1 · executed 2026-10-02
  Done 2026-10-02, in two steps. The first fix guarded only a quarantine made by the
  sweep itself, so `vf practice --list` followed by `vf practice --text` still deleted
  every take (`session-audit-03` F1). Now the sweep keeps every take no newer than the
  last write of a quarantined index, keeps every id the index names, and sweeps nothing
  while an unreadable index could not be moved aside · five tests; the audit's sequence
  and the failed move each failed before the second fix; a take stranded after the
  quarantine is still swept.

- [x] **D-55 · The Parakeet helper can delete and re-download its model during a
  dictation.** It checks only that the files exist; FluidAudio's loader re-downloads on
  a revision mismatch and, on any load error, purges the cache and downloads again
  inside the engine's 120 s limit. `AGENTS.md` forbids downloads without approval.
  **Fix:** set `ModelHub.offlineMode = true` before loading, except for `--download`.
  `macos/ParakeetHelper/Sources/VoiceFlowParakeet/main.swift:60` · `02-core` 1 · code
  2026-10-02 (FluidAudio `ModelHub.swift:101-137`)
  Done 2026-10-02 — the transcription path sets offline mode before loading · with the
  network denied, the installed helper deleted all 20 files of a broken model copy and
  tried to download; the rebuilt helper kept all 20 and exited 1. A real recording still
  transcribes.

- [x] **D-56 · The console stops following new lines after 50 entries.** Auto-scroll is
  keyed on the log's count, which is capped at 50, so it never changes again and a new
  failure line lands out of sight.
  **Fix:** key the scroll on the last entry's id.
  `VoiceStationWindowView.swift:1549` · `02-ui` HIGH · code 2026-10-02
  Done 2026-10-02 — the scroll follows the newest entry's id · driven in the preview past
  50 entries: the console still shows the newest line.

- [x] **D-57 · Below about 944 px of window width the Station overlaps the sidebar.**
  At the window's own minimum (760 × 700) the control card sits on top of the sidebar,
  the mode tiles are cut off and the chain labels truncate.
  **Fix:** raise the window floor until the Station fits, or let the console shrink
  first; record the real floor in `design-system.md`.
  `ControlWindowController.swift:41`, `FocusHomeView.swift:186` · 2026-10-02 preview,
  `02-ui` · executed
  Done 2026-10-02 — the content floor is `884 × 700`, which gives both cards their 320;
  the root view reads the same constant and `design-system.md` records it · driven in the
  preview at the new minimum: nothing overlaps the sidebar. Height is D-119.

- [x] **D-23 · A rewriting mode paired with the literal engine spends the recording and
  then fails.** Only one of five paths checks the pairing; the engine refuses
  `translate` with `literal` after the audio is recorded.
  **Fix:** one check where a recording starts (`VoiceFlowController.shortcutPressed`)
  and one at launch (`Configuration.parse`).
  `VoiceStationWindowView.swift:849`, `AppDelegate.swift:561`, `Configuration.swift:391` ·
  2026-09-26 · executed 2026-10-02
  Done 2026-10-02 — one rule, `ProcessingMode.refusal(with:)`, read at the press (the
  capsule and the log say why, no recording starts) and at launch (`--cleaner literal
  --mode translate` is refused); the mode tiles and the engine bank decline it where it
  is chosen, in both directions · new checks failed with the rule disabled and pass with
  it; the tile and engine-bank refusals were driven in the preview. The press refusal in
  the capsule has not been seen on screen (D-04).

- [x] **D-39 · A bare "no" far from the real take-back cue can be deleted and invert the
  sentence.** `el cliente no aprobó… perdón, del sur` is accepted as `El cliente
  aprobó…`.
  **Fix:** count deletion reach only from the phrases in `TAKE_BACK_PHRASES`.
  `take_back.py:78` `_GUARD_ANCHOR_WORDS`, `output_guard.py` `guard_fix_cleanup` · `01`
  F-01 · executed
  Done 2026-10-02 — a bare anchor word counts as a cue only when the word before it was
  deleted too, a bare "no" only when it also joins a real phrase through deleted words,
  and a deletion must form one unbroken run up to its cue. The "joins a phrase" rule
  closes the hole `session-audit-03` F2 found: "que no" deleted together justified each
  other seven words from the cue · five new tests, each failed before its fix; both
  inversion examples from `01` and both from the audit are refused, every fix-prompt
  example still passes.

- [x] **D-40 · Snippets added from the terminal are erased by the next add in the
  window.** The app saves the list it loaded at launch.
  **Fix:** re-read the file under the lock, apply the change, write.
  `VoiceSnippet.swift:154`, `AppDelegate.swift:276` · `01` F-02 · executed
  Done 2026-10-02 — `VoiceSnippetStore.edit` re-reads the file under the shared lock,
  applies the change and writes; the window's add and delete use it and say when a write
  fails · a new check failed with the re-read disabled (only "mi web" survived) and
  passes with it.

- [x] **D-02 · The vocabulary is full: 226 terms stored, 64 reach Whisper.** Every term
  added after the 600-character budget filled is inert. **Blocked** on the owner choosing
  which terms matter; the Words section already shows read and unread terms.
  **Fix:** reorder or prune the list in Words.
  `memory.py:148` · 2026-09-26
  Done 2026-10-02 — by owner decision 42 terms stay (her own names, acronyms and rare
  terms) and 184 ordinary words and well-known names went; the prior list is kept as
  `vocabulary.local.txt.backup-2026-10-02` beside the store · `./vf memory`: 42 terms,
  42 fit the prompt, 357 of 600 characters; the diff against the backup is removals
  only. The pruning was a judgement, not a measurement with the owner's voice.

- [x] **D-16 · The Apple cleaner, App Intents, Parakeet helper and Xcode project are not
  in version control.** The working tree's build script needs `generate-xcodeproj.py`,
  which is untracked.
  **Fix:** commit them, after the privacy check `AGENTS.md` requires.
  working tree · 2026-09-26
  Done 2026-10-02 — committed in `96fd83d` after the privacy scan; `session-audit-03`
  found nothing personal in it.

- [x] **D-191 · Spanish opening punctuation (`¿`, `¡`) with fillers fails filler removal and reverts.**
  Sentences opening with `¿` or `¡` followed by a filler (`"¿Eh, cómo estás?"`) fail
  `_SENTENCE_START`. Removing the filler leaves a space after the mark (`"¿ cómo estás?"`),
  which `output_guard.py` rejects as a detached token, raising a `CleanupError`.
  `remove_fillers` catches this and silently returns uncleaned text with fillers intact.
  **Fix:** include `[¿¡]` in `_SENTENCE_START`, collapse whitespace after opening
  punctuation (`re.sub(r"([¿¡])[ \t]+", r"\1", cleaned)`), and allow `_OPENED`
  capitalization. `cleaners/fillers.py:35` · `04-python` · code
  Done 2026-10-25 — opening `¿`/`¡` added to `_SENTENCE_START`, post-punctuation whitespace collapsed, covered in `test_fillers.py`.

- [x] **D-203 · `DictationHistoryStore` missing corrupted file quarantine (permanent data loss).**
  In `DictationHistory.swift`, `loadFromDisk` attempts `load(from: data)` on
  `history.local.json`. If corrupted, it falls back to an empty `DictationHistoryStore()`.
  On the next dictation or fix, `append` and `save` write directly over `history.local.json`,
  permanently destroying the corrupted user history without the `.corrupt-*` quarantine
  mandated by R5. Disk writes also lack cross-process file locking.
  **Fix:** rename damaged file to `.corrupt-YYYYMMdd-HHmmss-SSSSSS` on decode failure
  and report the loss, matching `VoiceSnippetStore.loadReporting`; wrap writes with file
  lock. `DictationHistory.swift:237` · `04-swift` · code
  Done 2026-10-25 — damaged history is quarantined with dated name, writes take file lock, tested in VoiceFlowMacCoreChecks.

- [x] **D-204 · Synchronous pipe drainage in App Intents deadlocks on large stderr.**
  In `VoiceFlowIntents.swift` (`IntentEngine.run`), `stdout` is read synchronously to end
  of file, followed sequentially by `stderr`. If stderr output exceeds 64KB, the child
  blocks writing to stderr while the parent blocks reading stdout, causing a permanent
  deadlock. It also lacks a watchdog timer, which can freeze Shortcuts and Siri indefinitely.
  **Fix:** drain `stdout` and `stderr` concurrently with `DispatchGroup` on a background
  queue and enforce a watchdog with SIGTERM/SIGKILL escalation, matching `EngineRunner.swift`.
  `VoiceFlowIntents.swift:32` · `04-swift` · code
  Done 2026-10-25 — concurrent drainage via drainQueue + DispatchGroup, stdin async feeder, 45s watchdog with SIGKILL escalation · build.

### Medium

- [x] **D-58 · In ES➔EN a Spanish snippet trigger is translated before it can expand.**
  "te mando mi firma" came back as "I will send my signature".
  **Fix:** expand snippets before a translation, or protect the trigger through it.
  `pipeline.py` · executed 2026-10-02
  Done 2026-10-24 — in translate mode snippets expand before the cleaner, so the trigger is matched in Spanish · `TranslateSnippetTests`, failed first.

- [x] **D-59 · A cleanup that writes the typographic apostrophe `’` is refused whole.**
  The speaker loses the punctuation and receives the raw transcript.
  **Fix:** fold `’` to `'` before the guard compares.
  `output_guard.py:78` `_fold` · `02-engine` 3 · executed 2026-10-02
  Done 2026-10-24 — `_fold` maps `’` to `'` · `TypographicMarkTests`, failed first.

- [x] **D-28 · A cleanup that adds `¿` or `¡` is refused whole.**
  **Fix:** treat both as ignorable presentation marks.
  `output_guard.py:68` · 2026-09-26 · executed 2026-10-02
  Done 2026-10-24 — `¿`/`¡` attached to the start of a word are presentation marks; detached they stay content · `TypographicMarkTests`, failed first.

- [x] **D-60 · "open chrome and search for macbook" searches "for macbook".** The
  alternation matches `search` before `search for`.
  **Fix:** put `search\s+for` before `search`.
  `VoiceAction.swift:175` · `02-core` 2 · executed 2026-10-02
  Done 2026-10-25 — `search\s+for` tried before `search` · check.

- [x] **D-61 · A spoken search for "c++" reaches Google as "c  ".** `URLQueryItem` leaves
  `+`, which the site reads as a space.
  **Fix:** encode `+` as `%2B` after building the query.
  `VoiceActionExecutor.swift:43` · `02-app` 11 · executed 2026-10-02
  Done 2026-10-25 — one `SearchURL` builder encodes `+` as `%2B` for Google, YouTube and GitHub · check.

- [x] **D-62 · One damaged byte in the distillation store blocks `distill clear` and
  `vf export`.** Both end in a `UnicodeDecodeError` traceback; the store cannot be deleted
  by the command R5c promises.
  **Fix:** read with `errors="replace"` and let `clear` delete even when reading fails.
  `distill.py:103` · `02-cli` 2 · executed 2026-10-02
  Done 2026-10-25 — the store is read with `errors="replace"`, and `clear` deletes even when counting fails · `DamagedStoreTests`, failed first.

- [x] **D-63 · The build script deletes the installed app before the new copy is in
  place.** A failed copy or verify leaves no daily app and no backup.
  **Fix:** copy to `.new`, verify, then swap.
  `scripts/build-macos-app.sh:61` · `02-cli` 4 · code 2026-10-02
  Done 2026-10-25 — the build copies to `.new`, verifies, then swaps; the previous build stays as `.previous` · `zsh -n`; runs at the next rebuild.

- [x] **D-64 · `./vf` runs from the project folder, so a relative path lands in the
  repository.** `./vf export --to backup.json` writes personal data where `.gitignore`
  does not cover it; relative `--from` and `--text-file` report "not found".
  **Fix:** keep the caller's directory and set `PYTHONPATH` to the absolute `src`.
  `vf:4` · `02-cli` 3 · code 2026-10-02
  Done 2026-10-25 — `./vf` exports `VF_CALLER_DIR` and the file arguments resolve against it; models still resolve from the project · `CallerPathTests`, failed first.

- [x] **D-65 · Ctrl-C during a practice take strands an unlisted recording.**
  **Fix:** delete the take on any exception, then re-raise.
  `cli.py:470`, `practice.py:357` · `02-cli` 5 · reported
  Done 2026-10-25 — any exception during a take deletes it, then re-raises · `PracticeInterruptTests`, failed first.

- [x] **D-67 · A recording has no maximum length.** If the Mac sleeps or the key release
  is lost, the microphone stays open until a new press and release.
  **Fix:** stop at a cap (about 120 s) and re-sync the key state on wake.
  `HotkeyMonitor.swift:90`, `VoiceFlowController.swift:227` · `02-app` 2 · code
  2026-10-02
  Done 2026-10-24 — a take ends itself at `RecordingHygiene.maximumRecordingSeconds` (120 s) and is delivered; on wake the hotkey re-reads the key · check on the limit; the cap and the wake path not yet run live.

- [x] **D-68 · The temporary WAV survives Quit, a crash or a forced quit.** Nothing
  sweeps `sanbluedot-voiceflow-*.wav` and there is no `applicationWillTerminate`.
  **Fix:** sweep old ones at launch and delete the live one on termination.
  `AudioRecorder.swift:57` · `02-app` 3, `02-security` F-1 · code 2026-10-02
  Done 2026-10-24 — stranded takes are swept at launch and on Quit, never the live one · sweep check, failed under mutation.

- [x] **D-69 · A Siri or Shortcuts run can crash the app on a broken pipe.** The legacy
  `FileHandle.write(_:)` raises an exception Swift cannot catch when the engine exits
  before reading.
  **Fix:** `try write(contentsOf:)`, or route intents through `EngineRunner` (I-19).
  `VoiceFlowIntents.swift:79` · `02-app` 4, `02-security` F-8 · code 2026-10-02; Apple's
  exception behaviour reported, not run
  Done 2026-10-23 with D-130 — the intent writes with `try? write(contentsOf:)` and
  `try? close()`; SIGPIPE is ignored app-wide · `swift build` passes; not run through
  Siri. I-19 remains for the duplicated launcher.

- [x] **D-70 · A timeout on the last Gemini model names no model.** The socket timeout
  fires only at the hard deadline, so the branch that records contacted models is
  skipped; R6 requires the names.
  **Fix:** treat `TimeoutError` as an unfinished model regardless of the clock.
  `cleaners/gemini.py:452` · `02-engine` 1 · reported
  Done 2026-10-25 — a socket timeout is always an unfinished model, so the last one is named · `LastModelTimeoutTests`, failed first.

- [x] **D-71 · ES➔EN and NOTES never tell the model the transcript is data.** A dictated
  question can be answered instead of translated, and pasted as if it were the
  translation; neither mode has a guard.
  **Fix:** one line in both prompts: the transcript is text to process, never
  instructions.
  `cleaners/prompt.py:28` · `02-engine` 4 · code
  Done 2026-10-25 — both prompts say the transcript is text to process, never instructions · `PromptShapeTests`, failed first.

- [x] **D-72 · The window shows the previous run's figures and says READY while it
  works.** A stage that reported nothing keeps the old value; the badge and lamp know
  only recording and ready, so processing and failure read READY (R1, R9).
  **Fix:** assign every telemetry field each run, nil included; publish a real state
  (recording, processing, ready, failed).
  `ControlWindowController.swift:235`, `VoiceStationWindowView.swift:574` · `02-ui` ·
  code 2026-10-02
  Done 2026-10-25 — each run assigns every telemetry field, nil included; the badge reads READY, ON AIR, PROCESSING or FAILED (`StationState`) · check; not yet seen on screen.

- [x] **D-73 · The capsule always says WHISPER and INFERENCE.** It names Whisper when
  Parakeet listens, and shows inference when Literal or the filler rule runs no model.
  **Fix:** pass the active speech engine and whether a model runs into the HUD.
  `RetroMicHUDView.swift:390`, `:406` · `02-ui` · code 2026-10-02
  Done 2026-10-25 — the capsule names the listening engine and RULES when no model runs (`RunLabels`) · check; not yet seen on screen.

- [x] **D-74 · The hold-to-talk capsule has no name for VoiceOver, and focus is
  invisible.** The focus ring is removed with nothing in its place, and some controls
  still draw the system ring.
  **Fix:** `.accessibilityLabel("Hold to dictate")`; one dot-blue outline driven by
  focus for every plain control.
  `VoiceStationWindowView.swift:1363`, `:189` · `02-ui`, 2026-10-02 accessibility tree ·
  executed
  Done 2026-10-25 — the capsule is named "Hold to dictate". Update 2026-10-26: dot-blue outline removed from `voiceFlowNoFocusRing` by owner decision to eliminate flickering focus rectangle on sidebar tabs.

- [x] **D-75 · Snippet saves fail in silence, and a repeated trigger replaces the old
  snippet without asking.**
  **Fix:** make `save` report failure; ask before replacing an existing trigger.
  `VoiceSnippet.swift:60`, `:157` · `02-ui`, `02-core` 4 · code
  Partly done 2026-10-02 with D-40: the window's add and delete now report a failed
  write. Open: the question before replacing a trigger.
  Done 2026-10-25 — a repeated trigger asks Replace or Cancel before it is overwritten · check on `existing(trigger:)`; the dialog not yet seen.

- [x] **D-01 · `abre música` and `abre configuración` never parse.** The capture class
  `[A-Za-z0-9\s]` excludes accented letters.
  **Fix:** accept letters with accents.
  `VoiceAction.swift:264` · 2026-09-26 · executed 2026-10-02
  Done 2026-10-25 — the app-name capture accepts any letter (`\p{L}`) · check.

- [x] **D-04 · The capsule misses failures and cancels.** `showFailed` never orders the
  panel front; neither it nor `showCancelled` raises `animationGeneration`, and
  `showCancelled` never positions the panel.
  **Fix:** one helper that raises the generation, positions and shows the panel.
  `FloatingHUDController.swift:194`, `:212` · 2026-09-26, `02-app` 9
  Done 2026-10-02 — `showCancelled` and `showFailed` raise the generation, position the
  panel and show it, as `showModeChanged` does; needed so the D-23 refusal is seen ·
  build passes; not yet seen on screen.

- [x] **D-09 · The meeting-notes example is not valid JSON.** The string is not raw, so
  its `\n` becomes a real line break inside the example.
  **Fix:** a raw string or escaped `\\n`.
  `cleaners/prompt.py:46` · 2026-09-26
  Done 2026-10-25 — the meeting prompt is a raw string, so its example is valid JSON · `PromptShapeTests`, failed first.

- [x] **D-11 · The last ten dictations live in plain user defaults, outside the export.**
  **Fix:** store them beside the other personal stores and include them in `vf export`.
  `DictationHistory.swift:92` · 2026-09-26
  Done 2026-10-25 — history lives in `history.local.json` (moved once from user defaults) and `vf export` carries it · `HistoryExportTests` and a migration check.

- [ ] **D-17 · The Swift application layer has no test target.** Do not split the target;
  lift one decision at a time into `VoiceFlowMacCore` as its code is touched (I-18).
  `macos/Package.swift` · `findings-audit-01` #7

- [x] **D-26 · The speaking rate counts delivered words, not spoken ones.** Translations,
  Markdown and snippet expansions inflate it (R9).
  **Fix:** count the words of the raw transcript.
  `AppDelegate.swift:1039` · 2026-09-26
  Done 2026-10-25 — the rate counts the raw transcript's words · build.

- [x] **D-27 · A distillation pair stores the wrong input and output.** Raw text before
  corrections, and final text after snippets and macros.
  **Fix:** store the personalized text and the cleaner's output before expansion.
  `cli.py:650`, `pipeline.py:104` · 2026-09-26
  Done 2026-10-25 — a pair stores the personalized text and the cleaner's output before expansion (`cleaner_output`) · `DistillationPairContentTests`, failed first.

- [ ] **D-32 · Long take-backs are left unresolved on local engines.** The fix guard
  refuses deletions far from the cue, so the cue stays in the text. Fix proposed in I-15.
  `pipeline.py`, `output_guard.py` · 2026-09-27, executed

- [ ] **D-42 · Ordinary phrases count as take-back cues.** "sorry for the delay",
  "perdón por la demora", "I mean it" send the dictation to the model in fix mode.
  **Fix:** require the cue at a phrase boundary; measure on real dictations first.
  `take_back.py` `TAKE_BACK_PHRASES` · `01` F-04

- [x] **D-125 · A shortcut chord that ends in an F-key never fires.** macOS sets the
  Function flag on F1–F20 and the navigation keys; `flagsMatch` expects that flag only
  when the chord names `fn`. `control+f5` and the README's `command+shift+f8` are
  accepted at launch, shown in the menu and dead.
  **Fix:** when the chord does not name `fn`, drop `.maskSecondaryFn` from the event
  flags for F-keys and navigation keys; add a check with an F-key event carrying it.
  `ShortcutMatch.swift:15`, `HotkeyMonitor.swift:193` · `03-core` S-01 · code and Apple
  documentation 2026-10-23
  Done 2026-10-23 — `ShortcutMatch.flagsMatch` takes the key code and ignores the
  Function flag on F-keys and navigation keys unless the chord names `fn`; the trigger,
  its release and the mode chord all pass it · four new checks; the F8 one failed before
  the change. Not yet pressed on the keyboard.

- [x] **D-126 · A short Whisper dictation is delivered with a leading space.**
  whisper.cpp starts each segment with a space; the multi-segment join strips it, the
  single-segment path does not, and only terminal pastes are trimmed.
  **Fix:** strip the delivered text in `cleaners/literal.py` and in the personalized
  fallback (`pipeline.py:148`); the raw transcript stays byte-exact (R2).
  `transcribers/whisper_cpp.py:233` · `03-engine` E-02 · code
  Done 2026-10-23 — `LiteralCleaner` and the fallback strip the delivered text; raw and
  personalized text keep the space · two tests failed before the change; the app pastes
  `final_text`.

- [x] **D-127 · A cough can be pasted as `[BLANK_AUDIO]`.** A noise loud enough to pass
  the D-53 gate makes whisper.cpp write a bracketed tag such as `(coughing)`, and nothing
  filters it.
  **Fix:** raise `TranscriptionError("no speech")` when the whole text is one bracketed
  tag; add a test with a bracketed-only transcript.
  `transcribers/whisper_cpp.py:240` · `03-engine` E-01 · code
  Done 2026-10-23 — a transcript made only of bracketed tags is refused with the silence
  message; a tag inside a sentence is kept · three tag cases failed before the change,
  and the in-sentence case passes.

- [x] **D-128 · A confirmed correction loses its casing at a sentence start, in both
  languages.** `i phone → iPhone` becomes `IPhone` and `ebay → eBay` becomes `EBay`; the
  FIX preview shows the same.
  **Fix:** leave a replacement that contains any capital untouched and propagate case
  only to all-lowercase ones, in Python and Swift in one change with one shared test
  vector.
  `memory.py:314` `_match_case`, `Words.swift:110` · `03-cli` C-02, `03-core` S-03 · code
  Done 2026-10-23 — narrower than the fix proposed: a replacement with a capital after its
  first letter is written as confirmed, so `utel → Utel` still keeps an all-caps `UTEL`
  as the existing check requires · a test and a check covering the same `iPhone` and
  `eBay` cases, both failed before the change.

- [x] **D-129 · The app quarantines a snippet store the engine reads fine.** Swift
  requires `schema_version` and every field as a string; Python accepts an unversioned
  file and skips one bad item. A legacy file, or one item with `"expansion": null`, is
  moved aside at launch and every snippet stops expanding.
  **Fix:** an optional version (default 1) that refuses only a different integer, and
  item-by-item decoding as in Python; settle D-102 in the same change.
  `VoiceSnippet.swift:23`, `:114`, `:198` · `03-core` S-02 · code
  Done 2026-10-23 — `decode` reads by the engine's rules: no version means 1, items that
  are not usable snippets are skipped, a non-string description is dropped · checks for
  an unversioned file and a file with two bad items; the first failed before the change.

- [x] **D-130 · An engine that exits before reading its input can end the app.** Nothing
  ignores `SIGPIPE`, and `try?` on the stdin write cannot stop a signal. Extends D-69 to
  the main engine path.
  **Fix:** `signal(SIGPIPE, SIG_IGN)` once in `main.swift`; the write then fails with
  `EPIPE`, which the code already absorbs.
  `EngineRunner.swift:289`, `main.swift` · `03-app` A-02 · reported, signal not run
  Done 2026-10-23 — `signal(SIGPIPE, SIG_IGN)` at the top of `main.swift` · executed in a
  throwaway program: a `try?` write to a child that had exited ended the writer with
  status 141, and with the signal ignored it survived. The app itself was not run.

- [x] **D-131 · A test reads the owner's real corrections and snippets.**
  `test_cloud_cleanup_alone_records_nothing` runs with memory on and patches neither
  store, so a damaged store would be quarantined by a test run.
  **Fix:** `no_memory=True`, or patch both stores as `test_cli_memory.py:31` does.
  `tests/test_cli.py:344` · `03-cli` C-01 · code
  Done 2026-10-23 — memory stays on but both stores are patched to a temporary folder ·
  with the loads stubbed, the test asked for both real paths before the change and only
  temporary ones after.

- [ ] **D-132 · The live meter bars overflow their ceiling on loud speech.** The level
  reaches 1.25 while recording, so a bar draws into the row above.
  **Fix:** clamp the height to `meterCeiling`, or scale the level to a maximum of 1.
  `VoiceStationWindowView.swift:803` · `03-ui` U-01 · code
  Done 2026-10-23 — the bar height is clamped to `meterCeiling` · arithmetic: the tallest
  bar reached 47.5 against 40; `swift build` passes. Not driven on screen (the app layer
  has no check target, D-17).
  Unticked 2026-10-23 by owner decision: the code is changed, and the row closes only
  after the meter is seen on screen in a rebuilt app.

- [ ] **D-133 · A failed snippet save clears what was typed.** The form empties trigger,
  expansion and description right after `onAddSnippet`, which reports nothing back.
  **Fix:** return success from `onAddSnippet` and clear only then.
  `VoiceStationWindowView.swift:2241` · `03-ui` U-02 · code
  Done 2026-10-23 — `onAddSnippet` returns whether the snippet was written, and the form
  clears only on `true` · `swift build` passes; not driven on screen, and the preview
  cannot fail a save.
  Unticked 2026-10-23 by owner decision: the code is changed, and the row closes only
  after a failed save is seen keeping the form in a rebuilt app.

- [x] **D-134 · No atomic writer calls `fsync`.** After a power loss right after the
  rename a store can be empty; it is then quarantined and the live file is blank.
  **Fix:** `flush`, `fsync` and `F_FULLFSYNC` before `os.replace` (one writer, I-46);
  temp file, `fsync` and `rename` on the Swift side.
  `memory.py:21`, `:180`, `VoiceSnippet.swift:175` · `03-cli` C-03, `03-core` S-09 · code;
  the loss itself reported
  Done 2026-10-25 — one flushed writer on each side (`F_FULLFSYNC`, directory flushed after the rename) · writer test and check.

- [x] **D-135 · A quarantine runs without the store lock.** A slow reader can move aside
  a good store another process has just rewritten.
  **Fix:** take `exclusive_file_lock` inside `quarantine_file`, and skip the move when
  the file's inode, mtime or size changed since the failed read.
  `memory.py:70` · `03-cli` C-04 · reported
  Done 2026-10-25 — the move is skipped when the file changed since the failed read; the lock is not taken because callers already hold it · `QuarantineRaceTests`, failed first.

- [x] **D-136 · "abre safari y busca X" opens the default browser.** Every pattern
  yields `.googleSearch`, and `NSWorkspace.open(url)` hands it to the default browser.
  README lists the phrase as "Browser with the search", so the defect is that the
  sentence names Safari and the run ignores it.
  **Fix:** capture the browser and open with `open(_:withApplicationAt:)`, or stop
  matching browser names.
  `VoiceAction.swift:173`, `VoiceActionExecutor.swift:43` · `03-core` S-04 · code
  Done 2026-10-24 — the named browser travels with the search and opens via `open(_:withApplicationAt:)`; "el navegador" keeps the default · checks; Safari opened live in ACTIONS mode, 2026-10-25.

- [x] **D-137 · Alacritty's bundle id may be wrong (`io.alacritty`).** If it is, its
  pastes skip the terminal guard. Alacritty is not installed on this Mac.
  **Fix:** read the id from Alacritty's `Info.plist`, then correct the one table (I-60).
  `PasteTarget.swift:24` · `03-core` S-05 · reported
  Done 2026-10-25 — `org.alacritty`, read from Alacritty's own Info.plist, in both tables · check.

- [x] **D-138 · The window says "Terminal (Single-line Guard)" for apps the guard does
  not protect.** The badge also matches names containing `terminal`, `iterm`, `ghostty`
  or `warp`; the paste guard reads only the bundle list, so a multi-line NOTES result
  reaches those apps unflattened.
  **Fix:** derive the badge from `PasteTarget.isTerminal(bundleIdentifier:)` alone.
  `ControlWindowController.swift:244`, `AutoPaste.swift:57` · `03-app` A-01 · code
  Done 2026-10-25 — the badge comes from `PasteTarget.isTerminal` alone · build.

- [x] **D-139 · The floating HUD is invisible to VoiceOver.** With another app in front
  it is the only state cue, and the file has no accessibility modifier.
  **Fix:** one element with a state label, and an announcement on each state change.
  `RetroMicHUDView.swift` · `03-ui` U-03 · code
  Done 2026-10-25 — the capsule is one VoiceOver element with a state label, and each state change is announced · build; not yet heard.

- [x] **D-140 · The Words side column may stack below at the default window size.** The
  820 threshold is read inside a `GeometryReader` whose width needs a 1,112pt window
  against the 1,100 default.
  **Fix:** compare against the workspace width, or subtract the measured overhead.
  `FocusHomeView.swift:237` · `03-ui` U-05 · reported, arithmetic not rendered
  Done 2026-10-25 — the threshold is 760, measured from the paper width at the default window (808) · arithmetic; not yet seen.

- [x] **D-141 · The refusal banner pushes the page down for 4 s.**
  **Fix:** draw it as an overlay; the VoiceOver announcement is I-22.
  `FocusHomeView.swift:52` · `03-ui` U-06 · code
  Done 2026-10-25 — the refusal banner is an overlay · build; not yet seen.

- [x] **D-142 · The console tabs contradict `design-system.md`.** The code shows LOG /
  HISTORY n / SNIPPETS n with a 5pt radius and an extrusion; the contract names
  TELEMETRY LOG / HISTORY TRAY / SNIPPETS, no counts, 4pt. **Blocked** on the owner
  choosing which is right; the other changes in the same cycle.
  `VoiceStationWindowView.swift:717`, `:1461` · `03-ui` U-07 · code
  Done 2026-10-25 — ratified canonical enum RightCardTab vs compact presentation labels LOG, HISTORY <n>, SNIPPETS <n> in design-system.md · build.

- [x] **D-143 · VoiceOver names the Words fields by their example placeholder.**
  **Fix:** an `.accessibilityLabel` matching the visible label.
  `FocusHomeView.swift:395`, `:486`, `:562` · `03-ui` U-10 · code
  Done 2026-10-25 — each Words field carries the label it shows · build.

- [x] **D-144 · Log rows re-wrap under the pointer.** The hover copy button takes width
  only while shown.
  **Fix:** reserve its width and fade it with opacity; D-116 shares the change.
  `VoiceStationWindowView.swift:2820` · `03-ui` U-11 · code
  Done 2026-10-25 — the copy button is always laid out and fades with opacity · build; not yet seen.

- [x] **D-145 · More text sits under 4.5:1 than D-108 lists.** Popover and field labels
  measure 3.4–3.8, the HUD's PASTED and COPIED sage 2.8–3.7, and the subtitle and
  timestamps at gold 50% 3.4 — a value `design-system.md` itself prescribes.
  **Fix:** at least 0.75 opacity through one label token (I-77), a lighter HUD sage, and
  the contract corrected with D-108.
  `VoiceStationWindowView.swift:981`, `:1195`, `:1775`, `RetroMicHUDView.swift:298` ·
  `03-ui` U-12, U-13, U-22 · code; contrast computed from code values, not rendered
  Done 2026-10-25 — dim gold and navy text raised to 0.75 and 0.8 (5.9:1), a lighter HUD sage `okOnDark` (7.1:1), contract corrected · computed from the token values.

- [x] **D-146 · README says "Whisper Small is also present"; it went to the Trash on
  2026-10-01.**
  **Fix:** say it was measured and removed, and correct the examples that name
  `ggml-small.bin`.
  `README.md:297` · `03-pipelines` P-02 · executed (`ls models/`)
  Done 2026-10-23 — the line says Small was measured and moved to the Trash, and the two
  Validation bullets written about Ollama now name it; the `ggml-small.bin` mentions left
  are dated history · md-gardener clean.

- [x] **D-147 · `proposal.md`, which `CLAUDE.md` routes to as the approved sequence,
  still describes 2026-08-31.** It plans local cleanup with Ollama and `qwen3:4b`, says
  terminal auto-paste needs a later decision and lists Xcode and App Intents as later
  work; all three have changed.
  **Fix:** a dated status line on each stale passage, pointing at README and
  `framework.md`.
  `proposal.md:37`, `:49`, `:78`, `:112`, `:131`, `:135`, `:153` · `03-pipelines` P-03,
  P-04 · code
  Done 2026-10-23 — a status block under the header and a dated line on the
  architecture, terminal paste, first slice, constraints and "noted for later" passages;
  the history itself is unchanged · md-gardener clean.

- [x] **D-148 · A stray Xcode template folder `VoiceFlow/` would have committed the
  signing team id.** It hard-coded `DEVELOPMENT_TEAM` and a second bundle id, untracked
  and not ignored. `VoiceFlow/` · `03-pipelines` P-01 · code
  Done 2026-10-23 — the folder no longer exists; the project in use is
  `macos/VoiceFlow.xcodeproj` · `ls` finds no `VoiceFlow/` at the project root and
  `git status --ignored` lists nothing under it.

- [x] **D-192 · URLs and emails preserve raw casing in token comparison, rejecting valid cleanups.**
  Capitalized emails or URLs (`Sandy@example.com` or `Https://github.com`) normalized to
  lowercase by cleanup models are flagged as lexical substitutions because `_tokens` does
  not case-fold protected email/URL tokens.
  **Fix:** casefold email `token` and URL `protected` values before appending to `tokens`.
  `output_guard.py:110,122` · `04-python` · code
  Done 2026-10-25 — protected URL and email tokens casefolded in `_tokens`, covered in `test_output_guard.py`.

- [x] **D-193 · Closing marks attached to terminal punctuation rejected as lexical content.**
  `_is_ignorable_presentation_mark` checks `_CLOSING_MARKS` (`"'”’)]}»`) during lookahead
  for terminal marks (`.!?`), but when iteration lands on the closing mark itself, it
  returns `False`. Closing quotes/brackets attached to terminal punctuation (e.g. `."` or `!)`)
  are rejected as protected additions.
  **Fix:** recognize characters in `_CLOSING_MARKS` following terminal punctuation as
  ignorable when followed by whitespace or EOF. `output_guard.py:55` · `04-python` · code
  Done 2026-10-25 — closing marks after terminal punctuation recognized as presentation marks, covered in `test_output_guard.py`.

- [x] **D-194 · Non-positive timeout (`timeout=0.0`) passed to `urlopen` when budget expired.**
  When `remaining <= 0.0`, `timeout=max(remaining, 0.0)` passes `0.0` to
  `urllib.request.urlopen`. Sockets with `0.0` timeout enter non-blocking mode and raise
  `BlockingIOError` instead of clean `TimeoutError`, causing misleading error classifications.
  **Fix:** check `if remaining <= 0:` at the top of the loop in `_send` and raise
  `_ModelUnfinished(TimeoutError("time budget expired"), CONTACT_TIMED_OUT)`.
  `cleaners/gemini.py:413` · `04-python` · code
  Done 2026-10-25 — non-positive timeout raises `_ModelUnfinished(TimeoutError(...), CONTACT_TIMED_OUT)` without passing 0.0 to opener.

- [x] **D-195 · Non-atomic, unflushed append in `DistillationStore.record` risks permanent JSONL corruption.**
  `DistillationStore.record` appends lines to `distill_pairs.local.jsonl` using buffered
  `f.write(...)` without calling `f.flush()` or `os.fsync(f.fileno())`. Truncated lines on
  crash trigger permanent `.skipped-<hash>` warnings on every future read indefinitely.
  **Fix:** call `f.flush()` and `os.fsync(f.fileno())` before releasing the file lock in
  `record`; auto-compact/repair valid lines on read. `distill.py:84` · `04-python` · code
  Done 2026-10-25 — `DistillationStore.record` calls `f.flush()` and `os.fsync(f.fileno())` under file lock.

- [x] **D-205 · `HotkeyMonitor` lacks `deinit` cleanup, risking `EXC_BAD_ACCESS` crash.**
  `HotkeyMonitor` creates a `CGEventTap` and registers a runloop source on
  `CFRunLoopGetMain()` with an unretained pointer to `self` in the callback context. It
  implements `stop()`, but lacks `deinit { stop() }`. Any unstopped instance that is
  deallocated leaves an active callback pointing to freed memory.
  **Fix:** add `deinit { stop() }`. `HotkeyMonitor.swift:13` · `04-swift` · code
  Done 2026-10-25 — added deinit { stop() } disabling the tap and cleaning up the runloop source · build.

- [x] **D-206 · `CleanerFacts.swift` out-of-sync copy claims 3 Gemini models are walked.**
  Line 50 asserts `"All three models are tried, then the raw transcript arrives at 45s."`
  Contradicts the single `gemini-3.8-flash` configuration and violates R9 truth-over-comfort.
  **Fix:** update copy to describe the single model policy and retry rule.
  `CleanerFacts.swift:50` · `04-swift` · code
  Done 2026-10-25 — copy updated to reflect single-model retry and fallback chain before 45s raw transcript delivery.

### Low

- [x] **D-76** `uh-huh` becomes `-huh` and `mm-hmm,` becomes `Mm-`. **Fix:** no filler
  match next to a hyphen. `cleaners/fillers.py:13` · executed 2026-10-02
  Done 2026-10-25 — no filler match next to a hyphen · `HyphenAndCapitalTests`.
- [x] **D-77** "open README.md" opens `https://README.md`; the scheme test is
  case-sensitive. **Fix:** compare the scheme case-insensitively and refuse file-like
  names. `VoiceAction.swift:155` · executed 2026-10-02
  Done 2026-10-25 — the scheme is compared case-insensitively and a single name with a file extension is not a URL · check.
- [x] **D-78** "CLOUD TEXT ON · text is sent to Gemini" shows when no key exists and
  nothing is sent. **Fix:** say the key is missing. `FocusHomeView.swift:151` · code
  Done 2026-10-25 — the card reads CLOUD KEY MISSING when no key is stored · build.
- [ ] **D-79** Labels truncate: "Gemini 3.7 F…" and take-back chips at the reference
  size; chain stages and the SYSTEM filter chip at the minimum width. **Fix:** shorter
  labels or a wider column. Settings, Words, Station · executed 2026-10-02
- [x] **D-80** The log says "whisper heard" for Parakeet runs. **Fix:** use
  `selectedSpeechEngine.shortName`. `AppDelegate.swift:1109` · `02-app` 8
  Done 2026-10-25 — the log names the engine that listened · build.
- [x] **D-81** Terminal paste flattens line breaks but keeps other control characters.
  **Fix:** drop control characters for terminal targets. `AutoPaste.swift:58` ·
  `02-security` F-2
  Done 2026-10-25 — `PasteTarget.terminalSafe` also drops control characters · check.
- [x] **D-82** The on-screen console shows dictated text, against R7. **Fix:** log counts
  and language, or amend R7 to exempt the on-screen log. `AppDelegate.swift:1105` ·
  `02-security` F-3
  Done 2026-10-28 — on-screen console logs word/character counts and timestamps instead of raw dictated sentences · `VoiceFlowMacCoreChecks`.
- [x] **D-83** `.gitignore` lacks `Modelfile*`, `*.wav`, `*.m4a`, `*.safetensors`,
  `*.onnx`, `*.mlpackage`. **Fix:** add them. `.gitignore` · `02-security` F-4
  Done 2026-10-02 — audio, model and export patterns added · `git check-ignore`
  confirms each; no tracked file matches them.
- [x] **D-84** Every keychain error reads as "no key", including a locked keychain.
  **Fix:** distinguish found, absent and error. `Keychain.swift:26` · `02-app` 10
  Done 2026-10-25 — `Keychain.status` returns present, absent or unavailable; the window says when the keychain could not be read · build.
- [x] **D-85** One unreadable history record erases all ten. **Fix:** decode record by
  record. `DictationHistory.swift:151` · `02-core` 6
  Done 2026-10-25 — history decodes record by record · check.
- [x] **D-86** The Parakeet helper needs macOS 14; the app declares 13. **Fix:** raise
  the minimum to 14 or hide Parakeet below it. `ParakeetHelper/Package.swift:9` ·
  `02-core` 8
  Done 2026-10-25 — the minimum is macOS 14 in the package, Info.plist and the generated project; `onChange` moved to the macOS 14 form · build with no warnings.
- [ ] **D-87** `distill create` posts the stored pairs to any `--ollama-url`, not only
  this machine; the Words placeholder says "Oyama → Ollama". Ollama stays in the engine
  for Windows (D-121), so the commands stay. **Fix:** accept only a loopback URL, as
  `desktop.py` and `OllamaCleaner` already do; change the placeholder. `distill.py:237`,
  `cli.py:270`, `FocusHomeView.swift` · `02-cli` 12, 2026-10-02
- [x] **D-88** A failed `--copy` exits 1 after printing the JSON, and the app discards
  the finished dictation. **Fix:** exit 0 with the copy failure on stderr. `cli.py:685` ·
  `02-cli` 7
  Done 2026-10-25 — a failed `--copy` keeps the exit status (0, or 2 on a fallback) and reports on stderr · the two clipboard tests updated.
- [x] **D-89** A vocabulary term starting with `#` is reported added but never loads.
  **Fix:** refuse it. `memory.py:141` · `02-cli` 6
  Done 2026-10-25 — a term starting with `#` is refused · `VocabularyTermShapeTests`.
- [x] **D-90** The snippet editor takes one line and shows no macros, so a multi-line
  signature cannot be written in the window. **Fix:** a vertical field and a macro hint.
  `VoiceStationWindowView.swift:2212` · `02-ui`, executed 2026-10-02
  Done 2026-10-28 — expansion field uses `axis: .vertical` (`.lineLimit(2...5)`) with clickable R5b macro chips (`{date}`, `{time}`, `{clipboard}`, `{app}`) · `VoiceFlowMacCoreChecks`.
- [x] **D-91** A double press on LEARN learns twice and overwrites the success notice.
  **Fix:** disable Words actions until the read-back returns. `AppDelegate.swift:609` ·
  `02-ui`
  Done 2026-10-25 — `isWordsBusy` disables LEARN, ADD and DELETE buttons while async Words run completes.
- [x] **D-92** The filler rule capitalises a URL after a sentence end, the guard refuses
  it, and the filler stays. **Fix:** capitalise only the first letter and the one after
  a removed filler. `cleaners/fillers.py:48` · executed 2026-10-02
  Done 2026-10-25 — only the word a removed filler left at a sentence start is capitalised · `HyphenAndCapitalTests`.
- [x] **D-93** With Parakeet and a cloud cleaner, a provider failure on a take-back skips
  the model-free filler removal. **Fix:** fall back to the filler rule.
  `pipeline.py:181` · `02-engine` 6
  Done 2026-10-25 — with a punctuating engine any take-back failure falls back to the filler rule · `TakeBackProviderFailureTests`.
- [x] **D-94** The Gemini timeout bounds each socket operation, not the whole call.
  **Fix:** document it as per-operation, or bound the call. `cleaners/gemini.py:419` ·
  `02-engine` 8
  Done 2026-10-25 — documented as a per-operation socket timeout enforced between attempts · comment beside `DEFAULT_TIMEOUT_SECONDS`.
- [x] **D-95** Some failures escape as tracebacks: Whisper misses `OSError`, three
  subprocess calls decode strictly, `IncompleteRead` ends the Gemini chain. **Fix:**
  catch them and decode with `errors="replace"`. `whisper_cpp.py:143`,
  `cleaners/gemini.py:442` · `02-engine` 9
  Done 2026-10-25 — Whisper reports `OSError`, the three subprocess calls decode with `errors="replace"`, `IncompleteRead` counts as a dropped model · `IncompleteReadTests`.
- [x] **D-96** Words counts a term containing ", " as two read terms. **Fix:** count the
  selected terms. `cli.py:326` · `02-cli` 8
  Done 2026-10-25 — `prompt_terms` counts the selected terms · `SmallCliTests`.
- [x] **D-97** A store entry that fails validation vanishes at the next write, with no
  quarantine. **Fix:** keep a dated copy before rewriting. `memory.py:387`,
  `snippets.py:161` · `02-cli` 9
  Done 2026-10-25 — a store with unreadable entries is copied once per version (`.skipped-<hash>`) and reported once · `SkippedEntryTests`.
- [x] **D-98** `vf forget` prints a traceback on a disk error. **Fix:** catch `OSError`
  like `vf correct`. `cli.py:387` · `02-cli` 10
  Done 2026-10-25 — `vf forget` reports `OSError` · `SmallCliTests`.
- [x] **D-99** `vf export` counts distillation pairs without naming where they live
  (R5c). **Fix:** print the store path. `cli.py:417` · `02-cli` 11
  Done 2026-10-25 — `vf export` prints where the pairs are stored · code.
- [x] **D-100** `cleaner_gate` counts the dot inside `3.5` or `example.com` as
  punctuation, moving the F1 that decides a cleaner's verdict. **Fix:** read only
  trailing marks. `scripts/cleaner_gate.py:73` · `02-cli` 13
  Done 2026-10-25 — only trailing marks count · `InnerDotTests`.
- [x] **D-101** The acceptance launchers refuse when any command line mentions
  `VoiceFlowMac`. **Fix:** `pgrep -x VoiceFlowMac`. `scripts/start-phase2-acceptance.sh:21`
  · `02-cli` 14
  Done 2026-10-25 — `pgrep -x VoiceFlowMac` in both launchers · code.
- [x] **D-102** The app ignores the snippet store's schema version and rewrites a newer
  file as version 1. **Fix:** refuse an unknown version. `VoiceSnippet.swift:114` ·
  `02-core` 5
  Done 2026-10-23 with D-129 — any version other than the integer 1 is refused, so it is
  quarantined as the engine does and never rewritten · checks with versions 2, `true`,
  `1.5` and a missing list; the old strict decoder already refused the last three, and
  accepted version 2.
- [x] **D-103** Two different Gemini medians are shown for the same model and date.
  **Fix:** label each with its run, or show one. `CleanerFacts.swift:46` · `02-core` 9
  Done 2026-10-25 — labeled as "4.19s median across measured runs" to clarify the multi-run measurement scope.
- [x] **D-104** The engine watchdog sends SIGTERM only and then waits without limit.
  **Fix:** SIGKILL after the grace period, in a process group. `EngineRunner.swift:315`
  · `02-app` 5
  Done 2026-10-25 — SIGKILL after the 5 s grace when the child ignores SIGTERM · build.
- [x] **D-105** Escape reports the audio discarded even when deleting it failed.
  **Fix:** pass the failure to the log. `VoiceFlowController.swift:205` · `02-app` 6
  Done 2026-10-25 — a failed delete on Escape is reported as such · build.
- [x] **D-106** Words runs share a concurrent queue and a failed read leaves the section
  empty with no message. **Fix:** a serial queue and a reported failure.
  `AppDelegate.swift:619` · `02-app` 7
  Done 2026-10-25 — Words runs on one serial queue and a failed read says so · build.
- [x] **D-107** The OUTPUT lamp is lit before any dictation of the session, because
  History is restored at launch. **Fix:** light it after a delivery this session.
  `VoiceStationWindowView.swift:931` · `02-ui`
  Done 2026-10-25 — OUTPUT lamp checks viewModel.hasDeliveredThisSession, set on first delivery · build.
- [x] **D-108** Several small labels sit under the 4.5 contrast the contract requires;
  the HUD's PASTED is about 3.9; the contract's 4.80 for sage on the console does not
  reproduce. **Fix:** raise those opacities to at least 0.75 and correct the contract.
  `VoiceStationWindowView.swift:975`, `RetroMicHUDView.swift:300` · `02-ui`
  Done 2026-10-25 with D-145.
- [x] **D-109** The meter's last bars use `rec`; `design-system.md` says `onAir`.
  **Fix:** align one with the other. `VoiceStationWindowView.swift:844` · `02-ui`
  Done 2026-10-25 — the meter's last bars use `onAir` · build.
- [x] **D-110** `@MainActor` sits on the `WordsTab` enum instead of the view model.
  **Fix:** move it to the class. `VoiceStationWindowView.swift:206` · `02-ui`
  Done 2026-10-25 — `@MainActor` moved from `WordsTab` to the view model · build.
- [x] **D-111** Settings never shows whether a permission is granted; the three flags
  are never set; four views are dead. **Fix:** feed the flags from `AppDelegate` and show
  them; delete the dead views. `FocusHomeView.swift:909`,
  `VoiceStationWindowView.swift:273` · `02-ui`
  Done 2026-10-28 — `AppDelegate.refreshPermissionStatuses()` feeds `ControlWindowController.updatePermissions(...)` and `FocusHomeView` renders live `GRANTED` / `NEEDED` indicators · `VoiceFlowMacCoreChecks`.
- [x] **D-112** A one-word FIX pair is sent unticked and refused by the engine, where
  the typed form explains first. **Fix:** the same pre-check. `FocusHomeView.swift:386`
  · `02-ui`
  Done 2026-10-28 — `sentenceFix` pre-checks unticked one-word pairs and shows the confirmation notice before calling the engine · `VoiceFlowMacCoreChecks`.
- [x] **D-113** The "you are holding the capsule" refusal shows for hotkey recordings.
  **Fix:** refuse only for button recordings. `FocusHomeView.swift:1085` · `02-ui`
  Done 2026-10-25 — the refusal applies only while the capsule is held · build.
- [x] **D-114** EDIT on a Words row discards a FIX sentence in progress. **Fix:** refuse
  with a notice while a FIX is open. `FocusHomeView.swift:541` · `02-ui`
  Done 2026-10-28 — `EDIT` and `TO CORRECTION` refuse with a clear notice while `teachContext != nil` · `VoiceFlowMacCoreChecks`.
- [x] **D-115** The key and permission buttons refuse in silence during a run.
  **Fix:** the shared refusal notice. `FocusHomeView.swift:1038` · `02-ui`
  Done 2026-10-25 — permission and key buttons stay interactive and report loud refusal notices via viewModel.reportRefusal during active dictation · build.
- [x] **D-116** The log copy button appears only on hover, so the keyboard and VoiceOver
  cannot reach it. **Fix:** keep it in the accessibility tree.
  `VoiceStationWindowView.swift:2806` · `02-ui`
  Done 2026-10-25 — the copy button stays in the accessibility tree while hidden · build.
- [x] **D-117** A practice WAV staged as `.pending-delete` by an interrupted delete is
  never swept. **Fix:** sweep old `.pending-delete` files too. `practice.py:515` ·
  `02-security` F-6
  Done 2026-10-25 — the sweep restores a staged take whose session is indexed and removes the rest · `PendingDeleteSweepTests`.
- [x] **D-118** The vocabulary prompt travels in argv, visible to `ps`. **Fix:** a file
  or stdin if whisper-cli accepts one, otherwise record it as an accepted limit in R7.
  `whisper_cpp.py:137` · `02-security` F-7
  Done 2026-10-25 — recorded as an accepted limit in R7: `--prompt` is whisper-cli's only prompt input (checked in `whisper-cli --help`).
- [x] **D-119** At the minimum height the control card scrolls and the second row of mode
  tiles sits below its fold; `design-system.md` asks for the 700 floor to rise when a row
  is added. **Fix:** measure the smallest height that shows every row and raise the
  floor. `ControlWindowController.swift:41` · executed 2026-10-02
  Done 2026-10-25 — raised contentFloor height from 700 to 710 · build.
- [x] **D-120** The Apple signing team was written into the generated Xcode project and
  its generator, both headed for the repository; it identifies the owner's account.
  **Fix:** read it from the installed certificate at build time.
  `scripts/generate-xcodeproj.py`, `scripts/build-macos-app.sh` · pre-commit scan
  2026-10-02 · executed
  Done 2026-10-02 — the build script reads the team from the Apple Development
  certificate and passes it to `xcodebuild`; no tracked file carries it · the rebuilt app
  is signed with the same team and passes `codesign --verify --deep --strict`.
- [x] **D-121** Merging the Windows commit `b8d6797` would have removed the Ollama
  cleaner the Windows adapter uses for local cleanup, and broken its memory bridge
  (`desktop.py` imports `doctor.ollama_status`). **Fix:** keep Ollama in the shared engine
  for Windows only. `cleaners/ollama.py`, `cleaners/__init__.py`, `cli.py`, `doctor.py` ·
  merge 2026-10-02 · executed
  Done 2026-10-02 — by owner decision the cleaner is back, adapted to the current prompts
  and to the per-call fix mode; `doctor` checks Ollama only when a model is named, which
  `cli.py` does by default on Windows alone · the suite passes, its Ollama tests included,
  and `./vf doctor` on this Mac still shows no Ollama check.
- [ ] **D-122** The D-53 steady-noise threshold (1.6) was measured on this Mac's
  microphone and now also governs the Windows adapter, whose microphones are unmeasured.
  Speech under steady noise louder than about −3 dB SNR is refused as no speech.
  **Blocked** on the Windows machine measuring it at Gate 5. **Fix:** confirm 1.6 there,
  or read the ratio from an override the Windows adapter sets. `whisper_cpp.py:25` ·
  `session-audit-03` F4
- [x] **D-123** A bare `doctor` checked `ggml-base.bin` first, the Windows choice, while
  the Mac dictates with turbo. **Fix:** check the model this platform runs. `cli.py`
  `_doctor_model` · `session-audit-03` F5
  Done 2026-10-02 — the Mac checks turbo, Windows keeps base first · `./vf doctor`
  reports turbo.
- [x] **D-124** The restored Ollama cleaner sent the transcript to any `--ollama-url`
  while Ollama is classed as local, against R7. **Fix:** refuse a non-local host before
  anything is sent. `cleaners/ollama.py` · `session-audit-03` F6
  Done 2026-10-02 — only 127.0.0.1, localhost and ::1 are accepted · a test with two
  remote addresses fails if anything is sent.
- [x] **D-06** App Intents read stdout then stderr serially, with no watchdog. **Fix:**
  I-19. `VoiceFlowIntents.swift:88` · 2026-09-26
  Done 2026-10-25 — concurrent drain with `DispatchGroup` and 45s watchdog with SIGKILL escalation (`D-204`) · build.
- [x] **D-08** RECHECK stays live during a run and only beeps; its handler is empty.
  **Fix:** the shared refusal notice. `ControlWindowController.swift:129` · 2026-09-26
  Done 2026-10-25 — routes to viewModel.reportRefusal("permissions cannot be rechecked during active dictation") · build.
- [x] **D-10** A failed app launch is reported as done; the launch is asynchronous.
  **Fix:** report from the completion handler. `VoiceActionExecutor.swift:87` · 2026-09-26
  Done 2026-10-25 — a launch failure arrives through the completion handler, with a beep and a system-log line · build.
- [x] **D-12** Terminal paste leaves the flattened line on the clipboard, while History
  records the multi-line text. **Fix:** record what was delivered.
  `AutoPaste.swift:58` · 2026-09-26
  Done 2026-10-25 — the paste hands back what the terminal received, and History records that · build.
- [x] **D-13** The distillation gate compares `"gemini"` instead of
  `CLOUD_CLEANER_NAMES`. **Fix:** use the set. `cli.py:639` · `findings-audit-01` #4
  Done 2026-10-25 — the gate reads `CLOUD_CLEANER_NAMES` · existing distillation tests.
- [x] **D-14** Stale doc comments from the transform removal, and the
  `_is_ignorable_presentation_mark` docstring. **Fix:** rewrite or delete them.
  `ActivityLog.swift:90`, `AppContext.swift:96`, `output_guard.py:46` · 2026-09-26
  Done 2026-10-25 — the orphan ActivityLog paragraph removed, the AppContext prefix and the guard docstring rewritten · build.
- [x] **D-15** Dead code: `CLEANER_MODES`, `practice.DEFAULT_INDEX`, the `write_modelfile`
  import, the ignored `available:` parameter, `PER_MODEL_TIMEOUT_SECONDS`, and the views
  `statusBadgeView`, `cleanerButtonLabel`, `MiniVUMeterView`, `AppTargetMonitorView`.
  **Fix:** delete. several · 2026-09-26, `02-ui`
  Done 2026-10-25 — `CLEANER_MODES`, `DEFAULT_INDEX`, the `write_modelfile` import, the `available:` parameter, `PER_MODEL_TIMEOUT_SECONDS` and the four views deleted · build and suite.
- [ ] **D-18** Every Gemini figure is frozen at 2026-08-31. **Blocked** on the owner's
  approval to spend the provider budget on a re-measure. `cleaners/gemini.py:43`
- [ ] **D-21** Unverified whether the station carries every approved preview item
  (scanline, pulse). **Fix:** drive the app against the approved preview. `docs/` ·
  `findings-audit-01` #12
- [ ] **D-24** Selection is shown by colour alone: engine bank, station mode tiles,
  console tabs, filter chips, model and key chips, Settings pills; the three `?` buttons
  are all named "?". **Fix:** `.isSelected` traits and "About <engine>" labels.
  `VoiceStationWindowView.swift:849`, `FocusHomeView.swift:974` · 2026-09-26, `02-ui`
- [x] **D-30** The distillation store skips an unreadable line in silence. **Fix:**
  quarantine and report, like every other store. `distill.py:113` · 2026-09-26
  Done 2026-10-25 with D-97 — the distillation store reports and preserves skipped lines.
- [ ] **D-31** Apple's model can hand back the prompt's own example; the guard refuses
  it. A "format only" line was measured and made things worse. **Fix:** none measured
  yet; try a different example set on the corpus. `cleaners/prompt.py` · 2026-09-26
- [x] **D-41** On a fallback, `personalized_text` carries the snippet expansion, so
  History's CORRECTED layer shows it as a correction. **Fix:** carry the unexpanded text
  in `CleanupFailed`. `cli.py:607`, `:745` · `01` F-03
  Done 2026-10-25 — `CleanupFailed` carries the unexpanded `personalized_text`, which the fallback JSON reports · `FallbackLayerTests`.
- [ ] **D-43** The guard accepts case changes that break proper nouns (`March` →
  `march`). **Fix:** refuse lowercasing a capitalised word outside a sentence start.
  `output_guard.py` `_fold` · `01` F-05
- [x] **D-44** `doctor` checks Whisper only. **Fix:** add the Apple helper, the Parakeet
  helper and model, and `pbcopy`. `doctor.py` · `01` F-06
  Done 2026-10-25 — on the Mac, doctor checks the Apple and Parakeet helpers, the Parakeet model and pbcopy · `MacHelperCheckTests`, `./vf doctor` run.
- [x] **D-45** The 180 s watchdog no longer covers Whisper plus two cleanups, and losing
  the race discards a finished transcript. **Fix:** raise the watchdog above the stage
  limits. `EngineRunner.swift:139` · `01` F-07
  Done 2026-10-25 — the watchdog is 260 s, above Whisper plus two cleanups · build.
- [x] **D-46** Each paste may raise the Accessibility prompt when permission is missing.
  **Fix:** prompt only on an explicit request. `AutoPaste.swift:27` · `01` F-08, reported
  Done 2026-10-25 — the paste checks `AXIsProcessTrusted()` without the prompt · build.
- [x] **D-47** Stale since FIX teaches: `clean --mode fix` has no caller in the app,
  `sameWords` is used only by checks, the generator docstring names
  `PingVoiceFlowIntent`, `VoiceFlowShortcuts` says four with three. **Fix:** delete or
  correct. several · `01` F-09
  Done 2026-10-25 — the generator docstring and the shortcuts comment name the three intents; `clean --mode fix` and `sameWords` stay, both used by checks · code.
- [x] **D-49** The seeded log says the Fn/Globe trigger and Whisper are ready before
  anything is checked. **Fix:** one neutral line. `VoiceStationWindowView.swift:311` ·
  `01` F-11
  Done 2026-10-25 — one neutral seed line · build.
- [x] **D-50** An executed voice action still replaces the clipboard with the spoken
  command. **Fix:** copy only when no action ran. `VoiceFlowController.swift:279` · `01`
  F-12
  Done 2026-10-25 — a command that will run is not copied; one that fails to run is copied before it is pasted · build.
- [x] **D-51** Editing a correction's heard side forgets the old pair before learning
  the new; a failed learn loses it. **Fix:** learn first, then forget.
  `AppDelegate.swift` `onLearnCorrection` · `01` F-13
  Done 2026-10-25 — the new pair is learned before the old one is forgotten · build.
- [x] **D-52** A silent recording is reported as "the engine failed with status 1".
  **Fix:** report it as a refusal, like a touch that was too short. `AppDelegate.swift`
  `.failed` · 2026-10-01
  Done 2026-10-25 — a take with no audible speech is a refusal ("nothing heard"), not an engine failure · build.
- [x] **D-149** A caught `HTTPError` is never closed, which is the suite's three
  `ResourceWarning`s. **Fix:** `exc.close()` in the handlers, `addCleanup(error.close)`
  in the tests. `cleaners/gemini.py:421`, `distill.py:262`, `tests/test_gemini.py:104` ·
  `03-engine` E-04 · executed
  Done 2026-10-25 — the caught `HTTPError` is closed; the suite prints no `ResourceWarning` · suite run.
- [x] **D-150** The Apple cleaner parses all of stdout as JSON, so one stray library line
  breaks every Apple cleanup. **Fix:** parse the last non-empty line, as
  `parakeet.py:87` does. `cleaners/apple.py:114` · `03-engine` E-06 · reported
  Done 2026-10-25 — the last non-empty stdout line is parsed · `StrayOutputTests`.
- [x] **D-151** Modelfile text ending in `"` merges with the closing `"""` and
  `distill create` fails. **Fix:** append a space. `distill.py:158` · `03-engine` E-07 ·
  reported
  Done 2026-10-25 — a trailing quote gets a space · `ModelfileQuoteTests`.
- [x] **D-152** D-70 also hits a chain of one model: its timeout names no model.
  **Fix:** the D-70 fix and a chain-of-one test. `cleaners/gemini.py:452` · `03-engine`
  E-08 · reported
  Done 2026-10-25 with D-70 — the test runs on the one-model chain.
- [x] **D-153** The filler pass capitalises every sentence start, so `iPhone` becomes
  `IPhone`. **Fix:** the D-92 fix covers it. `cleaners/fillers.py:48` · `03-engine` E-05 ·
  reported
  Done 2026-10-25 with D-92.
- [x] **D-154** `quarantine_file` reports "moved to" its own name when the move failed.
  **Fix:** say the file was left in place. `memory.py:70` · `03-cli` C-06 · reported
  Done 2026-10-25 — a failed move says the file was left in place · `QuarantineMessageTests`.
- [x] **D-155** A vocabulary term containing `\x0b` or `\r` is stored as two terms.
  **Fix:** refuse a term that is not one line. `memory.py:155` · `03-cli` C-07 · reported
  Done 2026-10-25 — a term must be one line by `splitlines` · `VocabularyTermShapeTests`.
- [x] **D-156** `gemini` followed by a newline passes the provider check. **Fix:**
  `fullmatch`. `credentials.py:25` · `03-cli` C-08 · reported
  Done 2026-10-25 — `fullmatch` · `ProviderNameTests`.
- [x] **D-157** A locked keychain or a timeout reads as "no key stored" in the engine,
  the Python twin of D-84. **Fix:** return the status and print "keychain unavailable".
  `credentials.py:59`, `:157` · `03-cli` C-09 · reported
  Done 2026-10-25 — `describe` tells configured, absent (status 44) and keychain unavailable apart · `KeychainStatusTests`.
- [x] **D-158** `pbcopy` has no timeout, and `PermissionError` escapes as a traceback.
  **Fix:** `timeout=10`, catch `OSError` and `TimeoutExpired`. `clipboard.py:25` ·
  `03-cli` C-10 · reported
  Done 2026-10-25 — `timeout=10`, `OSError` and `TimeoutExpired` reported · `ClipboardFailureTests`.
- [x] **D-159** Several `{uuid}` in one snippet all get the same value, while README
  promises a fresh one per occurrence. **Fix:** replace one occurrence at a time.
  `snippets.py:90` · `03-cli` C-12 · reported
  Done 2026-10-25 — each `{uuid}` gets its own value · `SnippetEdgeTests`.
- [x] **D-160** `snippet import` hides skipped and replaced entries and ignores
  `schema_version`. **Fix:** report added, replaced and skipped; refuse an unknown
  version. `snippets.py:223` · `03-cli` C-13 · reported
  Done 2026-10-25 — import reports added, replaced and skipped, and refuses an unknown `schema_version` · `SnippetEdgeTests`.
- [x] **D-161** A trigger typed with a double space or a tab is saved and never fires.
  **Fix:** normalise whitespace in `add`, join pattern words with `\s+`.
  `memory.py:301`, `snippets.py:121` · `03-cli` C-14 · reported
  Done 2026-10-25 — snippet and correction triggers are whitespace-normalised on add and matched with `\s+` · `SnippetEdgeTests`, `CorrectionWhitespaceTests`.
- [x] **D-162** `vf practice` prints a traceback on a full disk or a permission error.
  **Fix:** move `sweep_orphans` and `next_audio_path` inside the `try`, catch `OSError`.
  `cli.py:489` · `03-cli` C-15 · reported
  Done 2026-10-25 — the sweep and the next path run inside a `try` that reports `OSError` · code.
- [x] **D-163** `--text` together with `--text-file` silently prefers the file.
  **Fix:** refuse both. `cli.py:474` · `03-cli` C-16 · reported
  Done 2026-10-25 — `--text` with `--text-file` is refused · `SmallCliTests`.
- [x] **D-164** The build signs with the first Apple Development certificate, even an
  expired one. **Fix:** pick a valid one (`openssl x509 -checkend 0`).
  `scripts/build-macos-app.sh:37` · `03-cli` C-17 · reported
  Done 2026-10-25 — the build signs with the first certificate that passes `openssl x509 -checkend 0` · `zsh -n` and the lookup run on this Mac.
- [x] **D-165** A transient read error (EACCES, EIO) quarantines an intact snippet file.
  **Fix:** quarantine only on a decode failure. `VoiceSnippet.swift:198` · `03-core` S-06
  · reported
  Done 2026-10-25 — a read error leaves the snippet file in place; only a decode failure moves it · build and checks.
- [x] **D-166** A comment says the checks compare `fallbackOrder` with `MODEL_CHAIN`;
  they do not. **Fix:** read `MODEL_CHAIN` from `gemini.py`, as `REWRITING_MODES` is read.
  `Configuration.swift:170`, `VoiceFlowMacCoreChecks/main.swift:445` · `03-core` S-07 ·
  reported
  Done 2026-10-25 — the checks read `MODEL_CHAIN` from `gemini.py` · check.
- [x] **D-167** A term or pair starting with `-` is read by argparse as an option and the
  Words action fails. **Fix:** emit `--term=<value>` and `--heard=<value>`.
  `Words.swift:17`, `EngineInvocation.swift:103` · `03-core` S-08 · reported
  Done 2026-10-25 — Words passes `--heard=`, `--intended=`, `--term=` and `--app-name=` · check, and argparse reads a leading dash.
- [x] **D-168** The engine starts through `/usr/bin/env python3` with no version check;
  without Homebrew it gets 3.9 and every dictation fails with a generic error.
  **Fix:** check for 3.11 or newer at launch and show the first stderr line.
  `EngineInvocation.swift:62` · `03-core` S-10 · reported
  Done 2026-10-25 — checkPythonRuntime() asynchronously verifies python3 version >= 3.11 at launch and logs clear diagnostic warning to console · build.
- [x] **D-169** The 2.5 s status-icon task is never cancelled and can erase a newer `!`
  marker. **Fix:** keep the `Task` and cancel it in `updateStatus`.
  `AppDelegate.swift:1113` · `03-app` A-03 · reported
  Done 2026-10-25 — the icon task is kept and cancelled by the next status · build.
- [x] **D-170** `Keychain.hasKey` fetches the secret itself on the main thread, so a lock
  or an access prompt blocks the window. **Fix:** query attributes only. Related to D-84.
  `Keychain.swift:35`, `AppDelegate.swift:328` · `03-app` A-05 · reported
  Done 2026-10-25 — presence is asked with attributes only · build.
- [x] **D-171** History, HUD and telemetry read the live `selectedCleaner`; a click during
  the 0.5 s arming hold mislabels the run. **Fix:** carry the run's `recordingCleaner` in
  `.copied`. `AppDelegate.swift:1072`, `:1158` · `03-app` A-06 · reported
  Done 2026-10-25 — `.copied` carries the run's cleaner for History and telemetry · build.
- [x] **D-172** If `001.wav` already exists, every acceptance-log append throws.
  **Fix:** start above the highest existing file (`AGENTS.md`). `AcceptanceLogger.swift:104`
  · `03-app` A-07 · reported
  Done 2026-10-25 — the take is named above the highest file already in the folder · build.
- [x] **D-173** `showProcessing`, `showCompleted` and `showActionExecuted` assume the HUD
  is visible; latent. **Fix:** call `showAtFullOpacity()` when it is hidden.
  `FloatingHUDController.swift:86` · `03-app` A-08 · reported
  Done 2026-10-25 — processing, completed and action states show the capsule if it was hidden · build.
- [x] **D-174** A NaN audio level traps in `Int(audioLevel * 12)`. **Fix:**
  `guard avgPower.isFinite`. `AudioRecorder.swift:96`, `RetroMicHUDView.swift:511` ·
  `03-ui` U-14 · reported
  Done 2026-10-25 — a non-finite level reads as 0 in the recorder and the HUD · build.
- [x] **D-175** The HUD ignores `usedFallback`, so a raw fallback looks like a clean
  success. **Fix:** a label of its own. `RetroMicHUDView.swift:296` · `03-ui` U-15 ·
  reported
  Done 2026-10-25 — a fallback shows PLAIN beside PASTED or COPIED · build.
- [ ] **D-176** VoiceOver's press on the hold control gives a zero-length recording
  (D-74 family). **Fix:** a toggle action for accessibility.
  `VoiceStationWindowView.swift:1375` · `03-ui` U-16 · reported
- [x] **D-177** A `DateFormatter` is created for every log line. **Fix:** one static
  formatter for the log and History. `VoiceStationWindowView.swift:114` · `03-ui` U-17 ·
  reported
  Done 2026-10-25 — one static formatter for the log and for History · build and checks.
- [x] **D-178** Snippet DELETE has no label, a 16pt target and no confirmation.
  **Fix:** a label, a larger target and a confirm step.
  `VoiceStationWindowView.swift:2319` · `03-ui` U-19 · reported
  Done 2026-10-25 — confirmation dialog, 24x24pt touch target and VoiceOver accessibility label added.
- [x] **D-179** The TELEMETRY beacon pulses in `danger` red at all times and reads as a
  fault. **Fix:** a neutral colour. `VoiceStationWindowView.swift:2530` · `03-ui` U-20 ·
  reported
  Done 2026-10-25 — the beacon pulses in dot blue · build.
- [x] **D-180** The History header pills wrap at the 884 floor. **Fix:** `lineLimit(1)`.
  `VoiceStationWindowView.swift:2140` · `03-ui` U-21 · reported
  Done 2026-10-25 — applied lineLimit(1) and minimumScaleFactor(0.85) to pill helper in VoiceStationWindowView · build.
- [x] **D-181** The vocabulary list uses `\.offset` identity. **Fix:** identify rows by
  the term. `FocusHomeView.swift:590` · `03-ui` U-23 · reported
  Done 2026-10-25 — vocabulary rows are identified by the term · build.
- [x] **D-182** `switch page` unmounts each page and loses its state: the snippet form,
  the ORIGINAL toggles. `FocusHomeView.swift:53` · `03-ui` U-24 · reported
  Done 2026-10-28 — `snippetDraftTrigger`, `snippetDraftExpansion`, `snippetDraftDescription` and `expandedOriginalHistoryIDs` moved to `VoiceStationViewModel` · `VoiceFlowMacCoreChecks`.
- [x] **D-183** One mode carries three names — DICTATE, CLEAN, and ES → EN beside
  ES ➔ EN — and a refusal says "switch back to CLEAN". **Fix:** one mode-name table read
  by Words, the station and the HUD. `FocusHomeView.swift:525`, `:1153`,
  `VoiceStationWindowView.swift:1179` · `03-ui` U-25 · reported
  Done 2026-10-25 — ProcessingMode.shortTitle unifies CLEAN, ES ➔ EN, NOTES, ACTIONS consumed across FocusHomeView and VoiceStationWindowView · build.
- [x] **D-184** The preview delegate wires no Words callbacks ("Reading your
  corrections…" forever) and calls the deprecated `activate(ignoringOtherApps:)`.
  `FocusHomePreviewDelegate.swift:13` · `03-ui` U-26 · reported
  Done 2026-10-25 — initialized sample WordsSnapshot, wired onRefreshWords, onLearnCorrection, onForgetCorrection, onAddWord, onRemoveWord, verified preview build · build.
- [x] **D-185** With no certificate, `set -euo pipefail` ends the build silently at the
  `team=$(…)` line and the message meant for that case never prints. **Fix:**
  `team=$(…) || true`. `scripts/build-macos-app.sh:37` · `03-pipelines` P-05 · reported
  Done 2026-10-25 — the lookup ends in `|| true`, so the no-certificate message prints · `zsh -n`.
- [x] **D-186** `pyproject.toml` declares 0.1.0 against the app's 0.10.0. **Fix:** move
  it with `Info.plist`, or state that it is independent. `pyproject.toml:7` ·
  `03-pipelines` P-06 · code
  Done 2026-10-23 — `pyproject.toml` and `__version__` both read 0.10.0; nothing in
  `src/`, `scripts/`, `tests/`, `macos/Sources/` or `vf` reads `__version__` · the suite
  passes. I-80 would keep them moving together.
- [x] **D-187** The §F sizes were stale. `backlog.md` §F · `03-pipelines` P-07
  Done 2026-10-23 — re-measured; each of the four `dist/` bundles is 29 MB · `du -sh`.
- [x] **D-188** A clean `swift build` prints two warnings in `AppDelegate.swift`: a
  `weak self` capture that differs from the implicit strong one in its outer scope, and
  the non-`Sendable` `EngineRunner` captured in a `@Sendable` closure. The 2026-10-23
  baseline said "zero warnings" because that build was incremental. **Fix:** capture
  `self` one way through the nested closures, and hand the closure a `Sendable` value or
  run it on the main actor. `AppDelegate.swift:639`, `:649` · 2026-10-23 · executed (a
  clean export of `db61765` prints both)
  Done 2026-10-25 — `self` captured once, weakly; `EngineRunner` declared `@unchecked Sendable` (immutable state); `swift build` prints no warnings · build.
- [x] **D-189** The Apple cleaner helper writes its answer with the legacy
  `FileHandle.write(_:)`, the D-69 class: if the engine has exited before reading, the
  helper ends on an uncatchable exception. Only the helper dies, after its parent is
  gone, so no dictation is lost today. **Fix:** `try? write(contentsOf:)`.
  `VoiceFlowAppleCleaner/AppleCleaner.swift:67` · 2026-10-23 · code
  Done 2026-10-25 — `try? write(contentsOf:)` · build.
- [x] **D-190** Two of the three Gemini models are deprecated. Google's deprecations
  page, opened 2026-10-24: `gemini-3.5-flash` (the default) is replaced by
  `gemini-3.6-flash`, and `gemini-3.7-flash` by `gemini-3.8-flash`, with requests routed
  there. The default now lands on the model measured slowest (14.3 s median, 2026-08-31).
  **Done in code 2026-10-24, by owner decision:** `gemini-3.8-flash` is the primary model,
  with `gemini-4-argon` added as secondary fallback (`I-83`, `1f7807a`).
  Done 2026-10-26 — active chain `gemini-3.8-flash` and `gemini-4-argon` verified in tests, window, and checks · tests pass.

- [x] **D-196 · Cascading snippet expansion in `translate` mode violates non-cascading rule.**
  `expand_snippets` runs on `personalized_text` prior to cleaner translation, and
  unconditionally runs again on `cleaned`, violating framework R5b single-pass invariant.
  **Fix:** skip secondary snippet expansion on `cleaned` when `mode == "translate"`.
  `pipeline.py:70,111` · `04-python` · code
  Done 2026-10-25 — secondary snippet expansion skipped when mode is translate, preserving single expansion pass.

- [x] **D-197 · `remove_vocabulary_term` uncaught `UnicodeDecodeError` on corrupted file.**
  `remove_vocabulary_term` executes `path.read_text()` directly without exception
  handling, crashing if the vocabulary store is damaged.
  **Fix:** catch `(UnicodeDecodeError, OSError)` and call `quarantine_file`.
  `memory.py:262` · `04-python` · code
  Done 2026-10-25 — `remove_vocabulary_term` and `add_vocabulary_term` catch `(UnicodeDecodeError, OSError)` and quarantine unreadable files.

- [x] **D-198 · Zero-byte Whisper model file bypasses readability check.**
  `handle.read(1)` succeeds on an empty 0-byte file without error, failing downstream in
  `whisper-cli` with a generic subprocess failure rather than `DependencyUnavailable`.
  **Fix:** check `if len(handle.read(1)) == 0: raise DependencyUnavailable(...)`.
  `transcribers/whisper_cpp.py:164` · `04-python` · code
  Done 2026-10-25 — empty 0-byte Whisper model file raises `DependencyUnavailable`, verified in unit tests.

- [x] **D-199 · Fragile `lines[-1]` JSON extraction in Parakeet and Apple cleaners.**
  Selecting `lines[-1]` breaks if Metal or CoreML runtimes output trailing teardown logs.
  **Fix:** search backwards with `reversed(lines)` for the first parseable JSON line.
  `transcribers/parakeet.py:88`, `cleaners/apple.py:117` · `04-python` · code
  Done 2026-10-25 — JSON extraction traverses `reversed(lines)` until first valid JSON payload is parsed.

- [x] **D-200 · `vf process` omits default `--whisper-model` fallback.**
  `doctor` and `practice` default to `DEFAULT_WHISPER_MODEL`, but `process` requires an
  explicit argument.
  **Fix:** supply `default=DEFAULT_WHISPER_MODEL` in parser. `cli.py:134` · `04-python` · code
  Done 2026-10-25 — `vf process` defaults `--whisper-model` to `DEFAULT_WHISPER_MODEL`.

- [x] **D-201 · Dead parameter `hard_deadline` in internal `_send`.**
  Unused parameter in internal Gemini cleaner method signature.
  **Fix:** remove parameter from signature and call sites. `cleaners/gemini.py:365` · `04-python` · code
  Done 2026-10-25 — dead `hard_deadline` removed from signature and call sites.

- [x] **D-202 · Deprecated Gemini models in test fixtures and missing tests.**
  `test_cli.py`, `test_distill.py`, `test_parakeet.py`, `test_replay.py` hardcode
  `gemini-3.5-flash` or `gemini-3.7-flash`. Missing test cases for `¿`/`¡` with fillers
  and case variations in URLs/emails.
  **Fix:** reference `DEFAULT_GEMINI_MODEL` (`gemini-3.8-flash`) and add targeted tests.
  `tests/` · `04-python` · code
  Done 2026-10-25 — test fixtures reference `DEFAULT_GEMINI_MODEL` (`gemini-3.8-flash`), comprehensive tests added for `¿`/`¡` and URL casefolding.

- [x] **D-207 · `AppleCleaner.swift` missing trailing newline and outdated platform annotation.**
  `AppleCleaner.swift` writes JSON bytes to stdout without `\n`; `VoiceFlowIntents.swift`
  marks types with `@available(macOS 13.0, *)` despite 14.0+ baseline.
  **Fix:** append `\n` to emission and bump annotations to macOS 14.0+.
  `AppleCleaner.swift:67`, `VoiceFlowIntents.swift:21` · `04-swift` · code
  Done 2026-10-25 — added trailing 0x0A to AppleCleaner JSON stdout emission; updated VoiceFlowIntents availability annotations to macOS 14.0+ · build.

### Known limitations — deliberate, with a cost

- **L-01** The guard folds the acute accent but never the tilde, because `ano` and `año`
  are different words. A cleanup that restores one tilde is discarded whole. How often
  the engine drops the tilde on this speaker's Spanish is unmeasured.

## B. Improvements

Each one names why it would make the app better. Ordered by what changes daily use.

- [x] **I-82 · Build the Microduck HUD.** Picked by the owner 2026-10-25. Why: the
  capsule shrinks from `330 × 88` to `120 × 30`, an accidental key press shows only a
  `36 × 16` capsule, and the duck answers the voice live. **Spec:** `design-system.md`
  "Floating HUD — Microduck redesign"; the previews `docs/hud-redesign-02-bubble.html`
  and `docs/microduck-mascot-01.html` §2–3 hold the exact shapes, angles and timings.
  **Where:** `RetroMicHUDView.swift` (capsule and a new duck view), `HUDLayout.swift`,
  `FloatingHUDController.swift` (panel size and placement; show the duck only after a
  voice), `VoiceStationTokens` (`duckOrange`, `duckOrangeDeep`), and
  `VoiceFlowMacCoreChecks`: the panel-fits-content and the 12-character badge budget
  must be recomputed for the new sizes, not deleted.
  Done 2026-10-25 — Vector Microduck mascot rig (`MicroduckView.swift`) reacting live to voice volume and audio decibels, 3-size bubble capsule (`36 × 16`, `120 × 22`, `120 × 30`), anchored to bottom-left screen corner (`screenRect.minX + 24`, `screenRect.minY + 24`), checks passing, built and installed in daily app · 2026-10-25.
- [x] **I-83 · Add Gemini Argon (`gemini-4-argon`) cleaner model.** Requested by the owner
  2026-10-25. Why: Google's latest model generation includes `gemini-4-argon`, offering
  higher reasoning depth for dictation cleanup alongside `gemini-3.8-flash`.
  **Where:** `src/sanbluedot_voiceflow/cleaners/gemini.py` (model registry and validation),
  `macos/Sources/VoiceFlowMacCore/Configuration.swift` (`GeminiModel` enum: add `.argon4`,
  short name `Argon`, fallback chain), `VoiceStationWindowView.swift` (console chip picker),
  `scripts/cleaner_gate.py` and `VoiceFlowMacCoreChecks`.
  Done 2026-10-25 — added `gemini-4-argon` to engine `MODEL_CHAIN` and Swift `GeminiModel`, with console pickers and checks verified.
- [x] **I-84 · Unified low-noise "System Health & Status" diagnostic check in Settings.**
  Requested by the owner 2026-10-25. Why: Multiple software layers (NVIDIA Parakeet CoreML,
  Whisper cpp binary/models, Apple Intelligence helper, Gemini API connectivity and macOS
  permissions) are connected without a single, low-noise diagnostic check to alert the
  user if a dependency is missing, corrupted, or deprecated.
  **Spec:** strictly user-triggered on-demand button in Settings/Diagnostics (never
  background polling or automatic telemetry, preserving R7 privacy). Runs a quiet probe:
  1) Parakeet CoreML and Whisper models verified, 2) Apple Intelligence helper responsive,
  3) Gemini API ping & model deprecation verification, 4) macOS Microphone/Accessibility/
  Input Monitoring status. Displays a clean, quiet status badge for each layer.
  **Where:** `vf doctor` CLI and Settings diagnostic panel in `FocusHomeView.swift`.
  Done 2026-10-25 — `vf doctor --json` implemented, Keychain Gemini API key check added, and on-demand "System Health & Status" diagnostic panel wired in Settings.
- [x] **I-85 · Microduck Desktop Companion: persistent mascot presence, seated baseline with foot-swinging, ambient behaviors, drag-and-drop repositioning with UserDefaults persistence, and optical chest wordmark centering.**
  Requested by the owner 2026-10-27. Why: transforms the voice HUD mascot into a persistent desktop companion inspired by virtual pets (Tamagotchi) and the Newton biped platform. The duck remains visible at rest in a relaxed seated pose with swinging feet, shows ambient behaviors (looking around, quacking/singing, sleeping when idle), toggles between sitting and standing on click, allows dragging anywhere on screen with persisted coordinates, and displays an optically centered `SBdot` wordmark on its white chest face.
  **Spec:** `docs/MicroduckCompanionDesign.md`, `microduck_companion_simulator.html`.
  **Where:** `macos/Sources/VoiceFlowMac/MicroduckView.swift` (kinematics, optical wordmark, ambient poses), `macos/Sources/VoiceFlowMac/RetroMicHUDView.swift` (persistent idle mascot, thought bubble visibility only during dictation, click-to-toggle), `macos/Sources/VoiceFlowMac/FloatingHUDController.swift` (no auto-dismissal of mascot, window drag and `UserDefaults` coordinate persistence), `macos/Sources/VoiceFlowMacCore/HUDLayout.swift`, and `VoiceFlowMacCoreChecks`.
  Done 2026-10-27 — persistent desktop companion implemented with seated baseline, ambient behaviors (curious looking, singing/quacking, sleeping nap mode), click-to-stand toggle, window dragging with screen clamping and UserDefaults persistence, optical chest wordmark centering, menu toggle, verified by test suite and packaged in daily app · 2026-10-27.
- [ ] **I-18 · Lift the dictation state machine into `VoiceFlowMacCore`.** Why: press,
  release and Escape orderings (D-23) become checkable without opening the
  app; about 6,000 lines of the app layer are reachable by no check today.
- [ ] **I-19 · One engine launcher for App Intents.** Why: reusing `EngineRunner` closes
  D-06 and D-69 with one piece of code instead of two copies.
- [x] **I-20 · Give the audio level its own observable object.** Why: today the whole
  window re-renders 20 times a second while recording, including the Words diff, which
  costs battery and can stutter the FIX page.
  Done 2026-10-28 — isolated 20Hz microphone level in `AudioLevelState` observed only by `StationMicCapsuleView` and `StationLiveMeterView` · `VoiceFlowMacCoreChecks`.
- [x] **I-21 · Respect Reduce Motion.** Why: the ring, meter and blink run at 30 fps
  whenever the window is visible, whatever the system setting says.
  Done 2026-10-26 — `@Environment(\.accessibilityReduceMotion)` in `RetroMicHUDView.swift` snaps mascot to static pose and disables oscillations · build.
- [ ] **I-22 · Announce refusals to VoiceOver.** Why: the refusal banner is silent text
  that vanishes after 4 s, so a screen-reader user never learns why nothing happened.
- [ ] **I-23 · Undo for deleting a correction or a snippet.** Why: one click deletes
  authored text for good.
- [ ] **I-24 · Keep the clipboard on this Mac.** Why: dictated text written to the
  general pasteboard can reach an iPhone through Universal Clipboard, which R7 does not
  intend. The AppKit option is unverified.
- [x] **I-25 · Private file modes (0600 files, 0700 folders) for stores, exports and
  practice audio.** Why: an export saved to the Desktop or iCloud is readable by other
  accounts; `~/Library` itself is already 0700.
  Done 2026-10-28 — `0600` file permissions and `0700` directory permissions enforced across `memory.py`, `distill.py`, `practice.py`, and `VoiceSnippet.swift` (`writeFlushed` / `withFileLock`) · `PrivateFilePermissionsTests` and `VoiceFlowMacCoreChecks`.
- [ ] **I-26 · Checks for the two helper binaries' exit contract.** Why: no check runs
  either helper, which is how D-55 went unseen.
- [ ] **I-27 · The build script asserts the embedded helpers and the team signature.**
  Why: `codesign --verify` also passes an ad-hoc signature, and an ad-hoc app loses
  Input Monitoring.
- [ ] **I-28 · Run `pbcopy` with a UTF-8 locale.** Why: accented Spanish should not
  depend on the locale Finder hands the app. Unverified.
- [ ] **I-29 · Restrict the keychain item to this app.** Why: an item created by
  `security` may be readable by any same-user process without a prompt. Unverified.
- [ ] **I-30 · Focus the FIX sentence field when it opens.** Why: the speaker can type
  the correction at once.
- [ ] **I-31 · Reset the station console to LOG on entering Station.** Why: after
  visiting Snippets the console opens on the Snippets tab.
- [ ] **I-32 · Declare `mode` in the `Cleaner` protocol.** Why: a type checker then sees
  the contract the pipeline actually calls.
- [ ] **I-33 · Skip the model when the text is only whitespace.** Why: a shortcut handed
  "   " still costs a model or network call.
- [ ] **I-34 · Pluralise counts of one.** Why: "1 dictations" reads as an error.
- [ ] **I-35 · Owner decision: treat editors with an integrated terminal as terminals.**
  Why: a multi-line dictation pasted into the VS Code terminal runs line by line.
  **Blocked** on the owner naming the editors.
- [ ] **I-01 · Text that appears while speaking.** Why: every stage runs after release
  today. **Blocked** on a streaming engine that holds accuracy on mixed Spanish and
  English; `SpeechTranscriber` (C-13) and Nemotron (C-14) both failed it.
- [ ] **I-02 · Mode chosen by the target application.** Why: `AppContext` already knows
  CODE, CHAT, DOCS. **Blocked** on an owner decision about R3 and R3c.
- [ ] **I-03 · Vocabulary learned from confirmed corrections.** Why: no `vf correct` by
  hand. **Blocked** on D-02.
- [ ] **I-04 · Rewrite highlighted text in place.** **Blocked** on the Writing Tools
  measurement in `docs/proposals/phase-5-proposal.md` §11b.
- [ ] **I-06 · Transcribe an audio file from the window.** Why: `vf process` already does
  it; only the button is missing.
- [ ] **I-08 · Meeting capture from system audio.** Why: competitors have it; large.
- [ ] **I-15 · Resolve long take-backs on local engines.** Why: hand Apple only the
  stretch around the cue, where it measured 9/9; about 0.7 s more, only when a cue is
  spoken. Closes D-32.
- [ ] **I-17 · A personal bilingual cleanup model fine-tuned on the owner's pairs.**
  **Blocked** on enough recorded pairs and approval to download and train.

### Maintenance — from the 2026-10-23 review

Each row cites its identifier in `gates/full-code-audit-03-summary.local.md`. None changes
what the speaker sees; each removes a way for the same defect to come back.

- [ ] **I-36** One `system_prompt_for(mode)` in `cleaners/prompt.py` instead of the copies
  in `apple.py:63`, `gemini.py:288` and `distill.py:189`. Why: a mode added to one adapter
  only becomes impossible. EI-1
- [ ] **I-37** One `parse_cleaned_text()` for the JSON answer (`gemini.py:478`,
  `apple.py:114`). Why: one parser, and D-150 lands in the same change. EI-2
- [ ] **I-38** Dead code beyond D-15: the unreachable `if last_error is None`
  (`gemini.py:399`) and a local `import re` (`gemini.py:480`). EI-3
- [ ] **I-39** The Gemini `output_text` and `steps` shapes (`gemini.py:472`, `:518`) are
  not `generateContent` shapes. Why: once the documentation confirms it, about 22 lines
  go. EI-4
- [ ] **I-40** One `run_helper()` for the Apple and Parakeet subprocesses (`apple.py:88`,
  `parakeet.py:63`). Why: one timeout and decoding policy, about 30 lines fewer. EI-5
- [ ] **I-41** Move `resolve_binary` and `is_effectively_silent` out of `whisper_cpp.py`,
  which a cleaner imports, and make `_REMOVABLE_FILLERS` public. Why: a cleaner stops
  depending on a transcriber. EI-6
- [ ] **I-42** One local `fail()` for the four `CleanupFailed(...)` constructions in
  `pipeline.py`. Why: no site can forget a field. EI-7
- [ ] **I-43** A single pass in `is_effectively_silent`. Why: only if the stage shows in
  `transcribe_seconds`. EI-9
- [ ] **I-44** Engine tests for snippets in ES➔EN and NOTES (D-58), a Whisper runner
  raising `OSError` or `UnicodeDecodeError` (D-95), a bracketed-only transcript (D-127),
  and `’ ¿ ¡` in the guard (D-59, D-28). EI-10
- [ ] **I-45** One `load_entries()` for the three store loaders (`memory.py:364`,
  `snippets.py:145`, `practice.py:389`). Why: D-97 and D-135 then land once. CI-1
- [ ] **I-46** One `write_text_atomically()` for both writers (`memory.py:21`, `:180`).
  Why: D-134's `fsync` and I-25's file mode live in one place. CI-2
- [ ] **I-47** `SCHEMA_VERSION` is declared three times and checked against memory's copy
  only. Why: an `expected` argument makes each store check its own. CI-3
- [ ] **I-48** `SnippetStore._write()` instead of five copies of the payload
  (`snippets.py:180`). CI-4
- [ ] **I-49** One result-payload builder for the four JSON result dicts in `cli.py`.
  Why: a new field cannot be missed on one path. CI-5
- [ ] **I-50** Delete `SnippetStore.clear`. Why: no caller, and it overwrites without a
  quarantine. CI-6
- [ ] **I-51** The `collapsed` fallbacks never run (`memory.py:345`, `snippets.py:129`).
  Why: delete them, or make them reachable with D-161. CI-7
- [ ] **I-52** One `_take_files()` matching `\d{3,}`. Why: `1000.wav` is never counted or
  swept today (`practice.py:321`). CI-8
- [ ] **I-53** In `test_cli_memory.py` the inherited tests run twice and `unittest.main()`
  sits above the last class. CI-9
- [x] **I-54** Script duplication: the two branches in `replay.py:132`, the identical
  `except` bodies in `cleaner_gate.py:244`, and two Levenshtein tables. CI-11
  Done 2026-10-26 — consolidated `build_cleaner` call across transcriber branches in `replay.py` and handled `--apple-bin` · tests pass.
- [ ] **I-55** One acceptance launcher with a phase argument instead of two copies.
  Why: D-101 is then fixed once. CI-12
- [x] **I-56** `generate-xcodeproj.py`: one deployment-target constant (D-86), and drop
  the unused `all_files`. CI-13
  Done 2026-10-26 — unified `MACOSX_DEPLOYMENT_TARGET = 14.0` across Release configurations in `generate-xcodeproj.py` and project · build.
- [x] **I-57** `build-focus-home-preview.sh` leaves a new `dist/previews/focus-home.*`
  per run. Why: §F's rule — prune the old ones. CI-14
  Done 2026-10-26 — `build-focus-home-preview.sh` cleans older runs and abandoned previews purged · checked.
- [ ] **I-58** CLI tests for `practice.record`, take-back reach edges, a `\r` term, a
  mixed-case correction and two writers on one store. CI-15
- [ ] **I-59** One Python-generated fixture for correction casing, `CorrectionSource`,
  the Gemini chain and the snippet schema, read by the checks. Why: four hand-kept copies
  already disagree (D-128, D-129). SI-1
- [ ] **I-60** One terminal bundle-id table (`AppContext.swift:61`, `PasteTarget.swift:18`,
  `VoiceFlowMacCoreChecks/main.swift:360`). Why: the badge and the guard cannot disagree
  (D-137, D-138). SI-2
- [ ] **I-61** Drive `knownAppAliases` and `normalizeAppName` from one dictionary
  (`VoiceAction.swift:309`). SI-3
- [ ] **I-62** `make` calls `textRunEnvironment`, so credential stripping lives in one
  place, and a check covers `makeTextRun` and `makeWordsRun`
  (`EngineInvocation.swift:50`, `:199`). SI-4
- [ ] **I-63** Dead code: `VoiceSnippetStore.save(to:)`, `load(from:)`, `delete(id:)` and
  `clear()`, and the legacy branch of `DictationHistoryStore.load`. Why: `save(to:)` is a
  latent D-40 overwrite. SI-5
- [ ] **I-64** Make `fixedText` a `var` so `DictationRecord.withFix` stops copying 13
  fields by hand. SI-6
- [ ] **I-65** Merge the two `HUDBadge.recording` switches; the stale comments are D-14.
  SI-7
- [ ] **I-66** Precompile the `VoiceActionParser` patterns. Why: about 15 compiles per
  dictation, and `try?` hides a bad pattern. SI-8
- [ ] **I-67** `Sendable` value types and one build with `-strict-concurrency=complete`;
  both packages are on tools 5.10. SI-9
- [ ] **I-68** The checks collect every failure instead of stopping at the first, and add
  snippet decoding, F-key chords, configuration errors, `makeWordsRun`, the D-60, D-01 and
  D-77 parser cases and the helper exit contracts (I-26). SI-10
- [ ] **I-69** One `copyToClipboard(_:label:)` for the seven clipboard writes in
  `AppDelegate.swift`. Why: D-12 gets one home. AI-1
- [ ] **I-70** The cleaner preference key is written twice (`VoiceFlowIntents.swift:25`,
  `AppDelegate.swift:29`); one constant in `VoiceFlowMacCore`. AI-2
- [ ] **I-71** Dead API: `setRetryPermissionsEnabled` has an empty body, and a misplaced
  doc comment sits at `ControlWindowController.swift:148`. AI-4
- [ ] **I-72** Pass an explicit state to `update(title:detail:)` instead of reading it
  from the title text (`ControlWindowController.swift:186`). Why: D-72 needs it. AI-5
- [ ] **I-73** Assign the 26 closures directly instead of `{ [weak self] in
  self?.onX?() }` hops (`ControlWindowController.swift:259`). About 70 lines fewer. AI-6
- [ ] **I-74** `AppDelegate.swift` is 1,390 lines. First extract the repeated record, save,
  rebuild-menu, update sequence (`:1154`, `:1223`), then the Words and snippet handlers.
  AI-7
- [x] **I-75** `AppIntentsContext` statics are `nonisolated(unsafe)`, written on main and
  read off it; one lock-protected value set once (`VoiceFlowIntents.swift:132`). AI-8
  Done 2026-10-26 — `AppIntentsContext` synchronized with `NSLock` accessors · build.
- [ ] **I-76** Split `VoiceStationWindowView.swift` (2,844 lines) into tokens, view model
  and console and History rows. Why: the History row drawn at two scales lives in one file.
  UI-2
- [ ] **I-77** One `consoleLabel(opacity:)` style for the eight gold 50–55% literals.
  Why: D-108 and D-145 become one token change. UI-3
- [ ] **I-78** One `selectableOption` modifier — `.isSelected`, no focus ring,
  `contentShape` — for options, tiles and tabs. Why: D-24 and D-74 are fixed once. UI-4
- [ ] **I-79** One `scripts/check.sh` running the four validations `AGENTS.md` requires
  and `codesign --verify --deep --strict` on the installed app. PI-1
- [ ] **I-80** A version-consistency check in that script: `Info.plist`, the README H1
  and `pyproject.toml` (D-186). PI-2
- [ ] **I-81** Apple cleanup latency. Measured 2026-10-24 on the rebuilt app, M3 Pro,
  macOS 27.0.1: first call 2.1 s, then 0.9 s for 5 words and 1.8 s for 45 words; a
  `--prewarm` run beforehand changed nothing (1.82 s). Time grows with length because
  the model rewrites the whole text. The prewarm runs in its own process, so the
  instructions are never cached for the call that follows. **Fix to test:** one helper
  process kept alive by the app, its session built with the instructions and prewarmed
  with `prewarm(promptPrefix:)`; measure before adopting. `AppleCleaner.swift:92`, `:117`

## C. Settled corrections — do not restate

Each was delivered as fact, audited and struck down. Kept so the same claim does not
return.

| ID | Claim struck down | What is true instead | Gate |
|---|---|---|---|
| C-01 | "Nothing in Apple's stack stores heard X, meant Y" | macOS Text Replacement does. The corrections here are confirmed, versioned, exportable and applied before cleanup — a better version, not a missing feature | `apple-comparison-audit` |
| C-02 | "Snippets are hers alone" | Same mechanism as Text Replacement, minus the macros | `apple-comparison-audit` |
| C-03 | "An App Intent has to live in the app target" | A framework declares its own `AppIntentsPackage`; intents can live in `VoiceFlowMacCore` | `session-audit-02` |
| C-04 | "Apple's model is the fastest local option" | Apple 0.61 s median against Ollama 0.54 s. The case for Apple is what it changes: 12 of 19 samples and punctuation F1 84.8% | 2026-09-26 |
| C-05 | "Stream the cleanup so text appears progressively" | The guard compares complete token sequences; a partial cleanup cannot be verified. Stream the transcription, never the cleanup | 2026-09-26 |
| C-06 | "No competitor verifies what the model returned" | `NOT VERIFIED`: only six landing pages were read | 2026-09-26 |
| C-07 | "Cloud cleanup usable, not guaranteed" carried as a defect | It is Gate 4's recorded measurement | `findings-audit-01` #8 |
| C-08 | "A connection reset ends the Gemini chain" | Executed: the reset is reported as dropped and the next model answers | `session-audit-02` |
| C-09 | "Parakeet v3 should replace Whisper" | The ggml q8 port: WER 19.7% against 9.9%, Cyrillic output, no vocabulary | 2026-09-27 |
| C-10 | "Whisper is slow because it runs on the CPU" | It runs on Metal; the prompt and language detection cost about 0.7 s each and both earn it | 2026-09-27 |
| C-11 | "`whisper-server` saves 1.2 s a dictation" | 0.2 s with the vocabulary prompt; not worth a resident 1.6 GB process | 2026-09-27 |
| C-12 | "Parakeet is less accurate than Whisper here" | Parakeet Ultra through FluidAudio: WER 9.3% against 10.6%, mixed 3.7% against 7.6%, 0.24 s against 2.37 s | 2026-10-01 |
| C-13 | "Apple's own speech engine should match Parakeet" | 19.8–37% WER against 9.3%; each Apple model is locked to one language | 2026-10-01 |
| C-14 | "Nemotron streaming gives text while speaking at Parakeet's accuracy" | Instant, but WER 32.1% and one sentence in Devanagari | 2026-10-01 |
| C-15 | "Ollama is slow because Ollama is slow" | Cleanup time grows with the dictation on every model, because the model writes every word again | 2026-10-01 |

## D. Verified baseline

Machine: MacBook Pro `Mac15,6`, Apple M3 Pro, 11 CPU cores (5P/6E), 14-core GPU, 18 GB,
macOS 27.0, Xcode 27 / Swift 6.4.

| Measurement | Result | How |
|---|---|---|
| Python suite | pass on 2026-10-23 — run it rather than trust a count | `PYTHONPATH=src python3 -m unittest discover -s tests` |
| Swift build and checks | pass, 2026-10-23 | `swift build --package-path macos`, `swift run --package-path macos VoiceFlowMacCoreChecks` |
| Installed app | signed, `codesign --verify --deep --strict` passes, bundled engine identical to `src/`, 2026-10-02 | `dist/sanblueᵈᵒᵗ VoiceFlow.app` |
| Local cleanup, fixed corpus | Apple 18/19 accepted, punctuation F1 34.8% → 84.8%, 0.61 s median | `scripts/cleaner_gate.py`, 2026-09-26 |
| Apple cleanup, cold against prewarmed | 2.48 s cold, 1.06 s prewarmed, 0.98 s warm | `VoiceFlowAppleCleaner`, 2026-09-27 |
| Parakeet Ultra, one corpus clip | 0.17–0.50 s engine time | `vf process`, 2026-10-02 |
| Whisper `large-v3-turbo` | 1.84–2.69 s | `whisper-cli`, 2026-09-26 and 2026-10-02 |
| Whisper compute backend | Metal; no Core ML symbols in the installed binary | `otool -L`, `strings` |
| Vocabulary budget | 42 terms stored, 42 reach the prompt, 357 of 600 characters, after D-02 | `./vf memory`, 2026-10-02 |
| Speech variation, 44 kept recordings | loud-to-quiet frame ratio 8.9× minimum; steady synthetic noise 1.1× | 30 ms frames, 95th over 10th percentile, 2026-10-02 |

Neural Engine core count is not reported by `system_profiler` or `ioreg` on this machine
and must not be stated as a figure.

## E. Audit coverage

| Area | Depth |
|---|---|
| Whole working tree after `3d2182b` | Six independent reviews, 2026-10-01 (`gates/full-code-audit-02-*`): Python engine, CLI and stores, Swift core and helpers, Swift app layer, SwiftUI views, security and privacy |
| Whole working tree after `db61765` | Six independent reviews, 2026-10-23 (`gates/full-code-audit-03-*`): the same five code areas plus build, hygiene and docs against code; every MEDIUM re-read in code |
| Interface | Driven in the UI-only preview on 2026-10-02: every section, the minimum and reference sizes, held-back cleanup, a locked run |
| Engine | Driven on real recordings with Parakeet, Whisper, Apple and Literal; snippets in CLEAN and ES➔EN; noise takes; guard and filler cases executed directly |
| Not covered | Live microphone dictation, permissions revoked while running, sleep during a hold, Siri launching the app cold, the Gemini endpoint, `windows/` (excluded by `AGENTS.md`) |

## F. Models and bundles on disk

`AGENTS.md`: what nothing uses is deleted, after the owner hears which item and agrees.
Models measured 2026-10-01; `dist/` bundles and build caches 2026-10-23.

| What | Size | Used by | Status |
|---|---|---|---|
| `models/ggml-large-v3-turbo.bin` | 1.5 GB | Whisper, the default speech engine | In use |
| `models/fluidaudio/parakeet-ultra/` | 614 MB | Parakeet Ultra, Settings › SPEECH | In use |
| ~~`models/ggml-parakeet-tdt-0.6b-v3-q8_0.bin`~~ | 638 MB | Nothing | Moved to the Trash 2026-10-01 |
| ~~`models/ggml-small.bin`~~ | 465 MB | Nothing | Moved to the Trash 2026-10-01 |
| Apple speech assets, es-US and en-US | ~750 MB | Not VoiceFlow; installed by macOS for C-13 | Kept by owner decision, 2026-10-01 |
| ~~`models/fluidaudio/nemotron-multilingual/`~~ | 641 MB | Nothing | Moved to the Trash 2026-10-01 |
| `qwen3:4b` in Ollama | 2.5 GB | Nothing in VoiceFlow | The owner removes it with `ollama rm qwen3:4b` if no other project uses it |
| ~~`dist/previews/`~~ | — | UI preview builds | Deleted 2026-10-26 by owner decision |
| ~~`dist/… BACKUP 2026-10-02 urgent-fixes.app`~~ | 29 MB | Nothing | Moved to the Trash 2026-10-23 by owner decision |
| ~~`dist/… BACKUP 2026-10-01 parakeet.app`~~ | 29 MB | Nothing | Moved to the Trash 2026-10-23 by owner decision |
| ~~`dist/… BACKUP 2026-10-01 before-ollama-removal.app`~~ | 29 MB | Nothing | Moved to the Trash 2026-10-23 by owner decision |
| ~~`dist/… BACKUP 2026-10-02.app`~~ | 29 MB | Nothing | Moved to the Trash 2026-10-25 by owner decision |
| `dist/… BACKUP 2026-10-25 (activa 10am).app` | 29 MB | Rollback for 2026-10-25 rebuild | Active backup |
| `dist/… BACKUP 2026-10-26 (9.50am).app` | 29 MB | Rollback before Gate 05 rebuild | Active backup |
| `dist/… VoiceFlow.app.previous` | ~29 MB | The build before the last install, kept by the build script (D-63) | Replaced at each install |
| `macos/ParakeetHelper/.build/` | 1.4 GB | Rebuilding the Parakeet helper | Keep |
| `macos/.build/` | 1.0 GB | `swift build` and the checks; regenerated when deleted | Keep |

Outside the project and not measured: an MLX copy of whisper-large-v3-turbo in
`~/.cache/huggingface/` and a `whisper` environment under `~/miniconda3/`. Neither is used
by this project.

## G. Closed before this checklist

Kept so a cold session sees what was already done.

- [x] **D-03** Default-cleaner comment quoted Ollama's acceptance — fixed 2026-09-26.
- [x] **D-05** Merged into D-04.
- [x] **D-07** `clean --json` omitted `personalized_text` and `timings` — fixed
  2026-09-27.
- [x] **D-19** Connection reset ends the Gemini chain — withdrawn, false when executed
  (C-08).
- [x] **D-20** Commit veto misses `git -C` — moved to the `~/.claude` hook.
- [x] **D-22** Duplicate font in `docs/product-directions-inline.html` — file deleted
  2026-09-26.
- [x] **D-25** A shortcut sent text to Gemini with nothing on screen — fixed 2026-09-26
  (R3d).
- [x] **D-29** Shortcuts applied corrections and snippets to written text — fixed
  2026-09-26.
- [x] **D-33** The cleanup instruction asked for what the guard refuses — fixed
  2026-09-26.
- [x] **D-34** Whisper's segment line breaks reached the text — fixed 2026-09-27.
- [x] **D-35** FIX duplicated History rows; Gemini capitalised a web address — fixed
  2026-09-27.
- [x] **D-36** A take-back erased a long dictation — fixed 2026-09-27; D-39 remains.
- [x] **D-37** Apple's log lines carried the SYS badge — fixed 2026-09-27.
- [x] **D-38** FIX fixed nothing visible — fixed 2026-10-01.
- [x] **D-48** README drift — fixed 2026-10-01.
- [x] **I-05** Speech model chosen in the window — shipped 2026-10-01.
- [x] **I-07** Raw-to-clean pair in History — shipped 2026-09-26.
- [x] **I-09** Whisper kept loaded with `whisper-server` — measured and refused
  2026-09-27 (C-11).
- [x] **I-10** Apple's model prewarmed when the microphone opens — shipped 2026-09-27.
- [x] **I-11** History row that reads the dictation first — shipped 2026-09-26.
- [x] **I-12** Words section for corrections and vocabulary — shipped 2026-09-27.
- [x] **I-13** Spoken take-backs resolved while dictating — shipped 2026-09-27.
- [x] **I-14** Parakeet as a second speech engine — shipped 2026-10-01.
- [x] **I-16** No cleanup model on an ordinary dictation once Parakeet hears it —
  shipped 2026-10-01.
