# Backlog — defects and improvements

The single task list for this project: every known defect with its fix, and every
improvement with the reason it is worth building. `gates/` holds the evidence behind each
row and is never a task list; this file is.

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

- [ ] **D-02 · The vocabulary is full: 226 terms stored, 64 reach Whisper.** Every term
  added after the 600-character budget filled is inert. **Blocked** on the owner choosing
  which terms matter; the Words section already shows read and unread terms.
  **Fix:** reorder or prune the list in Words.
  `memory.py:148` · 2026-09-26

- [x] **D-16 · The Apple cleaner, App Intents, Parakeet helper and Xcode project are not
  in version control.** The working tree's build script needs `generate-xcodeproj.py`,
  which is untracked.
  **Fix:** commit them, after the privacy check `AGENTS.md` requires.
  working tree · 2026-09-26
  Done 2026-10-02 — committed in `96fd83d` after the privacy scan; `session-audit-03`
  found nothing personal in it.

### Medium

- [ ] **D-58 · In ES➔EN a Spanish snippet trigger is translated before it can expand.**
  "te mando mi firma" came back as "I will send my signature".
  **Fix:** expand snippets before a translation, or protect the trigger through it.
  `pipeline.py` · executed 2026-10-02

- [ ] **D-59 · A cleanup that writes the typographic apostrophe `’` is refused whole.**
  The speaker loses the punctuation and receives the raw transcript.
  **Fix:** fold `’` to `'` before the guard compares.
  `output_guard.py:78` `_fold` · `02-engine` 3 · executed 2026-10-02

- [ ] **D-28 · A cleanup that adds `¿` or `¡` is refused whole.**
  **Fix:** treat both as ignorable presentation marks.
  `output_guard.py:68` · 2026-09-26 · executed 2026-10-02

- [ ] **D-60 · "open chrome and search for macbook" searches "for macbook".** The
  alternation matches `search` before `search for`.
  **Fix:** put `search\s+for` before `search`.
  `VoiceAction.swift:175` · `02-core` 2 · executed 2026-10-02

- [ ] **D-61 · A spoken search for "c++" reaches Google as "c  ".** `URLQueryItem` leaves
  `+`, which the site reads as a space.
  **Fix:** encode `+` as `%2B` after building the query.
  `VoiceActionExecutor.swift:43` · `02-app` 11 · executed 2026-10-02

- [ ] **D-62 · One damaged byte in the distillation store blocks `distill clear` and
  `vf export`.** Both end in a `UnicodeDecodeError` traceback; the store cannot be deleted
  by the command R5c promises.
  **Fix:** read with `errors="replace"` and let `clear` delete even when reading fails.
  `distill.py:103` · `02-cli` 2 · executed 2026-10-02

- [ ] **D-63 · The build script deletes the installed app before the new copy is in
  place.** A failed copy or verify leaves no daily app and no backup.
  **Fix:** copy to `.new`, verify, then swap.
  `scripts/build-macos-app.sh:61` · `02-cli` 4 · code 2026-10-02

- [ ] **D-64 · `./vf` runs from the project folder, so a relative path lands in the
  repository.** `./vf export --to backup.json` writes personal data where `.gitignore`
  does not cover it; relative `--from` and `--text-file` report "not found".
  **Fix:** keep the caller's directory and set `PYTHONPATH` to the absolute `src`.
  `vf:4` · `02-cli` 3 · code 2026-10-02

- [ ] **D-65 · Ctrl-C during a practice take strands an unlisted recording.**
  **Fix:** delete the take on any exception, then re-raise.
  `cli.py:470`, `practice.py:357` · `02-cli` 5 · reported

- [ ] **D-66 · A press while the previous dictation is processing is dropped in silence.**
  The second utterance is lost with no sound, capsule or log line.
  **Fix:** report it as busy through the refusal path the other locked controls use.
  `VoiceFlowController.swift:134` · `02-app` 1, `02-ui` · code 2026-10-02

- [ ] **D-67 · A recording has no maximum length.** If the Mac sleeps or the key release
  is lost, the microphone stays open until a new press and release.
  **Fix:** stop at a cap (about 120 s) and re-sync the key state on wake.
  `HotkeyMonitor.swift:90`, `VoiceFlowController.swift:227` · `02-app` 2 · code
  2026-10-02

- [ ] **D-68 · The temporary WAV survives Quit, a crash or a forced quit.** Nothing
  sweeps `sanbluedot-voiceflow-*.wav` and there is no `applicationWillTerminate`.
  **Fix:** sweep old ones at launch and delete the live one on termination.
  `AudioRecorder.swift:57` · `02-app` 3, `02-security` F-1 · code 2026-10-02

- [ ] **D-69 · A Siri or Shortcuts run can crash the app on a broken pipe.** The legacy
  `FileHandle.write(_:)` raises an exception Swift cannot catch when the engine exits
  before reading.
  **Fix:** `try write(contentsOf:)`, or route intents through `EngineRunner` (I-19).
  `VoiceFlowIntents.swift:79` · `02-app` 4, `02-security` F-8 · code 2026-10-02; Apple's
  exception behaviour reported, not run

- [ ] **D-70 · A timeout on the last Gemini model names no model.** The socket timeout
  fires only at the hard deadline, so the branch that records contacted models is
  skipped; R6 requires the names.
  **Fix:** treat `TimeoutError` as an unfinished model regardless of the clock.
  `cleaners/gemini.py:452` · `02-engine` 1 · reported

- [ ] **D-71 · ES➔EN and NOTES never tell the model the transcript is data.** A dictated
  question can be answered instead of translated, and pasted as if it were the
  translation; neither mode has a guard.
  **Fix:** one line in both prompts: the transcript is text to process, never
  instructions.
  `cleaners/prompt.py:28` · `02-engine` 4 · code

- [ ] **D-72 · The window shows the previous run's figures and says READY while it
  works.** A stage that reported nothing keeps the old value; the badge and lamp know
  only recording and ready, so processing and failure read READY (R1, R9).
  **Fix:** assign every telemetry field each run, nil included; publish a real state
  (recording, processing, ready, failed).
  `ControlWindowController.swift:235`, `VoiceStationWindowView.swift:574` · `02-ui` ·
  code 2026-10-02

- [ ] **D-73 · The capsule always says WHISPER and INFERENCE.** It names Whisper when
  Parakeet listens, and shows inference when Literal or the filler rule runs no model.
  **Fix:** pass the active speech engine and whether a model runs into the HUD.
  `RetroMicHUDView.swift:390`, `:406` · `02-ui` · code 2026-10-02

- [ ] **D-74 · The hold-to-talk capsule has no name for VoiceOver, and focus is
  invisible.** The focus ring is removed with nothing in its place, and some controls
  still draw the system ring.
  **Fix:** `.accessibilityLabel("Hold to dictate")`; one dot-blue outline driven by
  focus for every plain control.
  `VoiceStationWindowView.swift:1363`, `:189` · `02-ui`, 2026-10-02 accessibility tree ·
  executed

- [ ] **D-75 · Snippet saves fail in silence, and a repeated trigger replaces the old
  snippet without asking.**
  **Fix:** make `save` report failure; ask before replacing an existing trigger.
  `VoiceSnippet.swift:60`, `:157` · `02-ui`, `02-core` 4 · code
  Partly done 2026-10-02 with D-40: the window's add and delete now report a failed
  write. Open: the question before replacing a trigger.

- [ ] **D-01 · `abre música` and `abre configuración` never parse.** The capture class
  `[A-Za-z0-9\s]` excludes accented letters.
  **Fix:** accept letters with accents.
  `VoiceAction.swift:264` · 2026-09-26 · executed 2026-10-02

- [x] **D-04 · The capsule misses failures and cancels.** `showFailed` never orders the
  panel front; neither it nor `showCancelled` raises `animationGeneration`, and
  `showCancelled` never positions the panel.
  **Fix:** one helper that raises the generation, positions and shows the panel.
  `FloatingHUDController.swift:194`, `:212` · 2026-09-26, `02-app` 9
  Done 2026-10-02 — `showCancelled` and `showFailed` raise the generation, position the
  panel and show it, as `showModeChanged` does; needed so the D-23 refusal is seen ·
  build passes; not yet seen on screen.

- [ ] **D-09 · The meeting-notes example is not valid JSON.** The string is not raw, so
  its `\n` becomes a real line break inside the example.
  **Fix:** a raw string or escaped `\\n`.
  `cleaners/prompt.py:46` · 2026-09-26

- [ ] **D-11 · The last ten dictations live in plain user defaults, outside the export.**
  **Fix:** store them beside the other personal stores and include them in `vf export`.
  `DictationHistory.swift:92` · 2026-09-26

- [ ] **D-17 · The Swift application layer has no test target.** Do not split the target;
  lift one decision at a time into `VoiceFlowMacCore` as its code is touched (I-18).
  `macos/Package.swift` · `findings-audit-01` #7

- [ ] **D-26 · The speaking rate counts delivered words, not spoken ones.** Translations,
  Markdown and snippet expansions inflate it (R9).
  **Fix:** count the words of the raw transcript.
  `AppDelegate.swift:1039` · 2026-09-26

- [ ] **D-27 · A distillation pair stores the wrong input and output.** Raw text before
  corrections, and final text after snippets and macros.
  **Fix:** store the personalized text and the cleaner's output before expansion.
  `cli.py:650`, `pipeline.py:104` · 2026-09-26

- [ ] **D-32 · Long take-backs are left unresolved on local engines.** The fix guard
  refuses deletions far from the cue, so the cue stays in the text. Fix proposed in I-15.
  `pipeline.py`, `output_guard.py` · 2026-09-27, executed

- [ ] **D-42 · Ordinary phrases count as take-back cues.** "sorry for the delay",
  "perdón por la demora", "I mean it" send the dictation to the model in fix mode.
  **Fix:** require the cue at a phrase boundary; measure on real dictations first.
  `take_back.py` `TAKE_BACK_PHRASES` · `01` F-04

### Low

- [ ] **D-76** `uh-huh` becomes `-huh` and `mm-hmm,` becomes `Mm-`. **Fix:** no filler
  match next to a hyphen. `cleaners/fillers.py:13` · executed 2026-10-02
- [ ] **D-77** "open README.md" opens `https://README.md`; the scheme test is
  case-sensitive. **Fix:** compare the scheme case-insensitively and refuse file-like
  names. `VoiceAction.swift:155` · executed 2026-10-02
- [ ] **D-78** "CLOUD TEXT ON · text is sent to Gemini" shows when no key exists and
  nothing is sent. **Fix:** say the key is missing. `FocusHomeView.swift:151` · code
- [ ] **D-79** Labels truncate: "Gemini 3.7 F…" and take-back chips at the reference
  size; chain stages and the SYSTEM filter chip at the minimum width. **Fix:** shorter
  labels or a wider column. Settings, Words, Station · executed 2026-10-02
- [ ] **D-80** The log says "whisper heard" for Parakeet runs. **Fix:** use
  `selectedSpeechEngine.shortName`. `AppDelegate.swift:1109` · `02-app` 8
- [ ] **D-81** Terminal paste flattens line breaks but keeps other control characters.
  **Fix:** drop control characters for terminal targets. `AutoPaste.swift:58` ·
  `02-security` F-2
- [ ] **D-82** The on-screen console shows dictated text, against R7. **Fix:** log counts
  and language, or amend R7 to exempt the on-screen log. `AppDelegate.swift:1105` ·
  `02-security` F-3
- [x] **D-83** `.gitignore` lacks `Modelfile*`, `*.wav`, `*.m4a`, `*.safetensors`,
  `*.onnx`, `*.mlpackage`. **Fix:** add them. `.gitignore` · `02-security` F-4
  Done 2026-10-02 — audio, model and export patterns added · `git check-ignore`
  confirms each; no tracked file matches them.
- [ ] **D-84** Every keychain error reads as "no key", including a locked keychain.
  **Fix:** distinguish found, absent and error. `Keychain.swift:26` · `02-app` 10
- [ ] **D-85** One unreadable history record erases all ten. **Fix:** decode record by
  record. `DictationHistory.swift:151` · `02-core` 6
- [ ] **D-86** The Parakeet helper needs macOS 14; the app declares 13. **Fix:** raise
  the minimum to 14 or hide Parakeet below it. `ParakeetHelper/Package.swift:9` ·
  `02-core` 8
- [ ] **D-87** `distill create` posts the stored pairs to any `--ollama-url`, not only
  this machine; the Words placeholder says "Oyama → Ollama". Ollama stays in the engine
  for Windows (D-121), so the commands stay. **Fix:** accept only a loopback URL, as
  `desktop.py` and `OllamaCleaner` already do; change the placeholder. `distill.py:237`,
  `cli.py:270`, `FocusHomeView.swift` · `02-cli` 12, 2026-10-02
- [ ] **D-88** A failed `--copy` exits 1 after printing the JSON, and the app discards
  the finished dictation. **Fix:** exit 0 with the copy failure on stderr. `cli.py:685` ·
  `02-cli` 7
- [ ] **D-89** A vocabulary term starting with `#` is reported added but never loads.
  **Fix:** refuse it. `memory.py:141` · `02-cli` 6
- [ ] **D-90** The snippet editor takes one line and shows no macros, so a multi-line
  signature cannot be written in the window. **Fix:** a vertical field and a macro hint.
  `VoiceStationWindowView.swift:2212` · `02-ui`, executed 2026-10-02
- [ ] **D-91** A double press on LEARN learns twice and overwrites the success notice.
  **Fix:** disable Words actions until the read-back returns. `AppDelegate.swift:609` ·
  `02-ui`
- [ ] **D-92** The filler rule capitalises a URL after a sentence end, the guard refuses
  it, and the filler stays. **Fix:** capitalise only the first letter and the one after
  a removed filler. `cleaners/fillers.py:48` · executed 2026-10-02
- [ ] **D-93** With Parakeet and a cloud cleaner, a provider failure on a take-back skips
  the model-free filler removal. **Fix:** fall back to the filler rule.
  `pipeline.py:181` · `02-engine` 6
- [ ] **D-94** The Gemini timeout bounds each socket operation, not the whole call.
  **Fix:** document it as per-operation, or bound the call. `cleaners/gemini.py:419` ·
  `02-engine` 8
- [ ] **D-95** Some failures escape as tracebacks: Whisper misses `OSError`, three
  subprocess calls decode strictly, `IncompleteRead` ends the Gemini chain. **Fix:**
  catch them and decode with `errors="replace"`. `whisper_cpp.py:143`,
  `cleaners/gemini.py:442` · `02-engine` 9
- [ ] **D-96** Words counts a term containing ", " as two read terms. **Fix:** count the
  selected terms. `cli.py:326` · `02-cli` 8
- [ ] **D-97** A store entry that fails validation vanishes at the next write, with no
  quarantine. **Fix:** keep a dated copy before rewriting. `memory.py:387`,
  `snippets.py:161` · `02-cli` 9
- [ ] **D-98** `vf forget` prints a traceback on a disk error. **Fix:** catch `OSError`
  like `vf correct`. `cli.py:387` · `02-cli` 10
- [ ] **D-99** `vf export` counts distillation pairs without naming where they live
  (R5c). **Fix:** print the store path. `cli.py:417` · `02-cli` 11
- [ ] **D-100** `cleaner_gate` counts the dot inside `3.5` or `example.com` as
  punctuation, moving the F1 that decides a cleaner's verdict. **Fix:** read only
  trailing marks. `scripts/cleaner_gate.py:73` · `02-cli` 13
- [ ] **D-101** The acceptance launchers refuse when any command line mentions
  `VoiceFlowMac`. **Fix:** `pgrep -x VoiceFlowMac`. `scripts/start-phase2-acceptance.sh:21`
  · `02-cli` 14
- [ ] **D-102** The app ignores the snippet store's schema version and rewrites a newer
  file as version 1. **Fix:** refuse an unknown version. `VoiceSnippet.swift:114` ·
  `02-core` 5
- [ ] **D-103** Two different Gemini medians are shown for the same model and date.
  **Fix:** label each with its run, or show one. `CleanerFacts.swift:46` · `02-core` 9
- [ ] **D-104** The engine watchdog sends SIGTERM only and then waits without limit.
  **Fix:** SIGKILL after the grace period, in a process group. `EngineRunner.swift:315`
  · `02-app` 5
- [ ] **D-105** Escape reports the audio discarded even when deleting it failed.
  **Fix:** pass the failure to the log. `VoiceFlowController.swift:205` · `02-app` 6
- [ ] **D-106** Words runs share a concurrent queue and a failed read leaves the section
  empty with no message. **Fix:** a serial queue and a reported failure.
  `AppDelegate.swift:619` · `02-app` 7
- [ ] **D-107** The OUTPUT lamp is lit before any dictation of the session, because
  History is restored at launch. **Fix:** light it after a delivery this session.
  `VoiceStationWindowView.swift:931` · `02-ui`
- [ ] **D-108** Several small labels sit under the 4.5 contrast the contract requires;
  the HUD's PASTED is about 3.9; the contract's 4.80 for sage on the console does not
  reproduce. **Fix:** raise those opacities to at least 0.75 and correct the contract.
  `VoiceStationWindowView.swift:975`, `RetroMicHUDView.swift:300` · `02-ui`
- [ ] **D-109** The meter's last bars use `rec`; `design-system.md` says `onAir`.
  **Fix:** align one with the other. `VoiceStationWindowView.swift:844` · `02-ui`
- [ ] **D-110** `@MainActor` sits on the `WordsTab` enum instead of the view model.
  **Fix:** move it to the class. `VoiceStationWindowView.swift:206` · `02-ui`
- [ ] **D-111** Settings never shows whether a permission is granted; the three flags
  are never set; four views are dead. **Fix:** feed the flags from `AppDelegate` and show
  them; delete the dead views. `FocusHomeView.swift:909`,
  `VoiceStationWindowView.swift:273` · `02-ui`
- [ ] **D-112** A one-word FIX pair is sent unticked and refused by the engine, where
  the typed form explains first. **Fix:** the same pre-check. `FocusHomeView.swift:386`
  · `02-ui`
- [ ] **D-113** The "you are holding the capsule" refusal shows for hotkey recordings.
  **Fix:** refuse only for button recordings. `FocusHomeView.swift:1085` · `02-ui`
- [ ] **D-114** EDIT on a Words row discards a FIX sentence in progress. **Fix:** refuse
  with a notice while a FIX is open. `FocusHomeView.swift:541` · `02-ui`
- [ ] **D-115** The key and permission buttons refuse in silence during a run.
  **Fix:** the shared refusal notice. `FocusHomeView.swift:1038` · `02-ui`
- [ ] **D-116** The log copy button appears only on hover, so the keyboard and VoiceOver
  cannot reach it. **Fix:** keep it in the accessibility tree.
  `VoiceStationWindowView.swift:2806` · `02-ui`
- [ ] **D-117** A practice WAV staged as `.pending-delete` by an interrupted delete is
  never swept. **Fix:** sweep old `.pending-delete` files too. `practice.py:515` ·
  `02-security` F-6
- [ ] **D-118** The vocabulary prompt travels in argv, visible to `ps`. **Fix:** a file
  or stdin if whisper-cli accepts one, otherwise record it as an accepted limit in R7.
  `whisper_cpp.py:137` · `02-security` F-7
- [ ] **D-119** At the minimum height the control card scrolls and the second row of mode
  tiles sits below its fold; `design-system.md` asks for the 700 floor to rise when a row
  is added. **Fix:** measure the smallest height that shows every row and raise the
  floor. `ControlWindowController.swift:41` · executed 2026-10-02
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
- [ ] **D-06** App Intents read stdout then stderr serially, with no watchdog. **Fix:**
  I-19. `VoiceFlowIntents.swift:88` · 2026-09-26
- [ ] **D-08** RECHECK stays live during a run and only beeps; its handler is empty.
  **Fix:** the shared refusal notice. `ControlWindowController.swift:129` · 2026-09-26
- [ ] **D-10** A failed app launch is reported as done; the launch is asynchronous.
  **Fix:** report from the completion handler. `VoiceActionExecutor.swift:87` · 2026-09-26
- [ ] **D-12** Terminal paste leaves the flattened line on the clipboard, while History
  records the multi-line text. **Fix:** record what was delivered.
  `AutoPaste.swift:58` · 2026-09-26
- [ ] **D-13** The distillation gate compares `"gemini"` instead of
  `CLOUD_CLEANER_NAMES`. **Fix:** use the set. `cli.py:639` · `findings-audit-01` #4
- [ ] **D-14** Stale doc comments from the transform removal, and the
  `_is_ignorable_presentation_mark` docstring. **Fix:** rewrite or delete them.
  `ActivityLog.swift:90`, `AppContext.swift:96`, `output_guard.py:46` · 2026-09-26
- [ ] **D-15** Dead code: `CLEANER_MODES`, `practice.DEFAULT_INDEX`, the `write_modelfile`
  import, the ignored `available:` parameter, `PER_MODEL_TIMEOUT_SECONDS`, and the views
  `statusBadgeView`, `cleanerButtonLabel`, `MiniVUMeterView`, `AppTargetMonitorView`.
  **Fix:** delete. several · 2026-09-26, `02-ui`
- [ ] **D-18** Every Gemini figure is frozen at 2026-08-31. **Blocked** on the owner's
  approval to spend the provider budget on a re-measure. `cleaners/gemini.py:43`
- [ ] **D-21** Unverified whether the station carries every approved preview item
  (scanline, pulse). **Fix:** drive the app against the approved preview. `docs/` ·
  `findings-audit-01` #12
- [ ] **D-24** Selection is shown by colour alone: engine bank, station mode tiles,
  console tabs, filter chips, model and key chips, Settings pills; the three `?` buttons
  are all named "?". **Fix:** `.isSelected` traits and "About <engine>" labels.
  `VoiceStationWindowView.swift:849`, `FocusHomeView.swift:974` · 2026-09-26, `02-ui`
- [ ] **D-30** The distillation store skips an unreadable line in silence. **Fix:**
  quarantine and report, like every other store. `distill.py:113` · 2026-09-26
- [ ] **D-31** Apple's model can hand back the prompt's own example; the guard refuses
  it. A "format only" line was measured and made things worse. **Fix:** none measured
  yet; try a different example set on the corpus. `cleaners/prompt.py` · 2026-09-26
- [ ] **D-41** On a fallback, `personalized_text` carries the snippet expansion, so
  History's CORRECTED layer shows it as a correction. **Fix:** carry the unexpanded text
  in `CleanupFailed`. `cli.py:607`, `:745` · `01` F-03
- [ ] **D-43** The guard accepts case changes that break proper nouns (`March` →
  `march`). **Fix:** refuse lowercasing a capitalised word outside a sentence start.
  `output_guard.py` `_fold` · `01` F-05
- [ ] **D-44** `doctor` checks Whisper only. **Fix:** add the Apple helper, the Parakeet
  helper and model, and `pbcopy`. `doctor.py` · `01` F-06
- [ ] **D-45** The 180 s watchdog no longer covers Whisper plus two cleanups, and losing
  the race discards a finished transcript. **Fix:** raise the watchdog above the stage
  limits. `EngineRunner.swift:139` · `01` F-07
- [ ] **D-46** Each paste may raise the Accessibility prompt when permission is missing.
  **Fix:** prompt only on an explicit request. `AutoPaste.swift:27` · `01` F-08, reported
- [ ] **D-47** Stale since FIX teaches: `clean --mode fix` has no caller in the app,
  `sameWords` is used only by checks, the generator docstring names
  `PingVoiceFlowIntent`, `VoiceFlowShortcuts` says four with three. **Fix:** delete or
  correct. several · `01` F-09
- [ ] **D-49** The seeded log says the Fn/Globe trigger and Whisper are ready before
  anything is checked. **Fix:** one neutral line. `VoiceStationWindowView.swift:311` ·
  `01` F-11
- [ ] **D-50** An executed voice action still replaces the clipboard with the spoken
  command. **Fix:** copy only when no action ran. `VoiceFlowController.swift:279` · `01`
  F-12
- [ ] **D-51** Editing a correction's heard side forgets the old pair before learning
  the new; a failed learn loses it. **Fix:** learn first, then forget.
  `AppDelegate.swift` `onLearnCorrection` · `01` F-13
- [ ] **D-52** A silent recording is reported as "the engine failed with status 1".
  **Fix:** report it as a refusal, like a touch that was too short. `AppDelegate.swift`
  `.failed` · 2026-10-01

### Known limitations — deliberate, with a cost

- **L-01** The guard folds the acute accent but never the tilde, because `ano` and `año`
  are different words. A cleanup that restores one tilde is discarded whole. How often
  the engine drops the tilde on this speaker's Spanish is unmeasured.

## B. Improvements

Each one names why it would make the app better. Ordered by what changes daily use.

- [ ] **I-18 · Lift the dictation state machine into `VoiceFlowMacCore`.** Why: press,
  release, Escape and busy orderings (D-66, D-23) become checkable without opening the
  app; about 6,000 lines of the app layer are reachable by no check today.
- [ ] **I-19 · One engine launcher for App Intents.** Why: reusing `EngineRunner` closes
  D-06 and D-69 with one piece of code instead of two copies.
- [ ] **I-20 · Give the audio level its own observable object.** Why: today the whole
  window re-renders 20 times a second while recording, including the Words diff, which
  costs battery and can stutter the FIX page.
- [ ] **I-21 · Respect Reduce Motion.** Why: the ring, meter and blink run at 30 fps
  whenever the window is visible, whatever the system setting says.
- [ ] **I-22 · Announce refusals to VoiceOver.** Why: the refusal banner is silent text
  that vanishes after 4 s, so a screen-reader user never learns why nothing happened.
- [ ] **I-23 · Undo for deleting a correction or a snippet.** Why: one click deletes
  authored text for good.
- [ ] **I-24 · Keep the clipboard on this Mac.** Why: dictated text written to the
  general pasteboard can reach an iPhone through Universal Clipboard, which R7 does not
  intend. The AppKit option is unverified.
- [ ] **I-25 · Private file modes (0600 files, 0700 folders) for stores, exports and
  practice audio.** Why: an export saved to the Desktop or iCloud is readable by other
  accounts; `~/Library` itself is already 0700.
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
  measurement in `phase-5-proposal.md` §11b.
- [ ] **I-06 · Transcribe an audio file from the window.** Why: `vf process` already does
  it; only the button is missing.
- [ ] **I-08 · Meeting capture from system audio.** Why: competitors have it; large.
- [ ] **I-15 · Resolve long take-backs on local engines.** Why: hand Apple only the
  stretch around the cue, where it measured 9/9; about 0.7 s more, only when a cue is
  spoken. Closes D-32.
- [ ] **I-17 · A personal bilingual cleanup model fine-tuned on the owner's pairs.**
  **Blocked** on enough recorded pairs and approval to download and train.

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
| Python suite | pass on 2026-10-02 — run it rather than trust a count | `PYTHONPATH=src python3 -m unittest discover -s tests` |
| Swift build and checks | pass, 2026-10-02 | `swift build --package-path macos`, `swift run --package-path macos VoiceFlowMacCoreChecks` |
| Installed app | signed, `codesign --verify --deep --strict` passes, bundled engine identical to `src/`, 2026-10-02 | `dist/sanblueᵈᵒᵗ VoiceFlow.app` |
| Local cleanup, fixed corpus | Apple 18/19 accepted, punctuation F1 34.8% → 84.8%, 0.61 s median | `scripts/cleaner_gate.py`, 2026-09-26 |
| Apple cleanup, cold against prewarmed | 2.48 s cold, 1.06 s prewarmed, 0.98 s warm | `VoiceFlowAppleCleaner`, 2026-09-27 |
| Parakeet Ultra, one corpus clip | 0.17–0.50 s engine time | `vf process`, 2026-10-02 |
| Whisper `large-v3-turbo` | 1.84–2.69 s | `whisper-cli`, 2026-09-26 and 2026-10-02 |
| Whisper compute backend | Metal; no Core ML symbols in the installed binary | `otool -L`, `strings` |
| Vocabulary budget | 226 terms stored, 64 reach the prompt, 596 of 600 characters | `build_initial_prompt` |
| Speech variation, 44 kept recordings | loud-to-quiet frame ratio 8.9× minimum; steady synthetic noise 1.1× | 30 ms frames, 95th over 10th percentile, 2026-10-02 |

Neural Engine core count is not reported by `system_profiler` or `ioreg` on this machine
and must not be stated as a figure.

## E. Audit coverage

| Area | Depth |
|---|---|
| Whole working tree after `3d2182b` | Six independent reviews, 2026-10-01 (`gates/full-code-audit-02-*`): Python engine, CLI and stores, Swift core and helpers, Swift app layer, SwiftUI views, security and privacy |
| Interface | Driven in the UI-only preview on 2026-10-02: every section, the minimum and reference sizes, held-back cleanup, a locked run |
| Engine | Driven on real recordings with Parakeet, Whisper, Apple and Literal; snippets in CLEAN and ES➔EN; noise takes; guard and filler cases executed directly |
| Not covered | Live microphone dictation, permissions revoked while running, sleep during a hold, Siri launching the app cold, the Gemini endpoint, `windows/` (excluded by `AGENTS.md`) |

## F. Models and bundles on disk

`AGENTS.md`: what nothing uses is deleted, after the owner hears which item and agrees.
Sizes measured 2026-10-01.

| What | Size | Used by | Status |
|---|---|---|---|
| `models/ggml-large-v3-turbo.bin` | 1.5 GB | Whisper, the default speech engine | In use |
| `models/fluidaudio/parakeet-ultra/` | 614 MB | Parakeet Ultra, Settings › SPEECH | In use |
| ~~`models/ggml-parakeet-tdt-0.6b-v3-q8_0.bin`~~ | 638 MB | Nothing | Moved to the Trash 2026-10-01 |
| ~~`models/ggml-small.bin`~~ | 465 MB | Nothing | Moved to the Trash 2026-10-01 |
| Apple speech assets, es-US and en-US | ~750 MB | Not VoiceFlow; installed by macOS for C-13 | Kept by owner decision, 2026-10-01 |
| ~~`models/fluidaudio/nemotron-multilingual/`~~ | 641 MB | Nothing | Moved to the Trash 2026-10-01 |
| `qwen3:4b` in Ollama | 2.5 GB | Nothing in VoiceFlow | The owner removes it with `ollama rm qwen3:4b` if no other project uses it |
| ~~`dist/previews/`~~ | — | A UI review | Deleted 2026-10-02 |
| `dist/… BACKUP 2026-10-02 urgent-fixes.app` | ~30 MB | Rollback to the build before the 2026-10-02 urgent fixes | Delete once the current build has been used a few days |
| `dist/… BACKUP 2026-10-01 parakeet.app` | ~11 MB | Rollback | Delete once the current build has been used a few days |
| `dist/… BACKUP 2026-10-01 before-ollama-removal.app` | ~30 MB | Rollback to the last build with Ollama | Delete once the current build has been used a few days |
| `macos/ParakeetHelper/.build/` | build cache | Rebuilding the Parakeet helper | Keep |

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
