# Phase 5 Roadmap — capability features

Phase 5 delivered the floating HUD and auto-paste, then a sequence of capability
features on top of them. This file owns what is still ahead. What already shipped is
described where it is used: behavior in `framework.md`, commands in `README.md`, visual
tokens in `design-system.md`.

`proposal.md` owns the overall delivery direction; this file is the feature queue inside
Phase 5, and `framework.md` governs when the two disagree.

## Delivered

The HUD specification that opened this file was built and is now the shipped surface,
so it lives in the code and in `design-system.md` rather than here. The original
reference mockup is kept at `assets/retro-mic-ui-mockup.jpg`.

| # | Feature | Where it lives now |
|---|---|---|
| — | Floating retro HUD and auto-paste | `RetroMicHUDView.swift`, `FloatingHUDController.swift`, `AutoPaste.swift` · R4 |
| 1 | Live voice translation, Spanish to professional English | R3b · `cleaners/prompt.py` |
| 2 | Meeting notes and action-item structuring | R3b · `cleaners/prompt.py` |
| 3 | Voice actions and system automation | R3c · `VoiceAction.swift`, `VoiceActionExecutor.swift` |
| 4 | Recent-dictation menu-bar tray | `DictationHistory.swift` · README |
| 5 | Gemini-to-Ollama distillation, opt-in | R5c · `distill.py` · `./vf distill` |
| 7 | Voice snippets and spoken macros | R5b · `snippets.py`, `VoiceSnippet.swift` · `./vf snippet` |
| 9 | Morphing HUD and in-flight mode toggle | R3c · `RetroMicHUDView.swift`, `HotkeyMonitor.swift` · README |
| 6 | Application-context awareness, detection only | `AppContext.swift` · `HUDBadge` · `design-system.md` |
| 10 | Latency and speed badge in the floating HUD | R9 · `RetroMicHUDView.swift` telemetry strip |

## Ahead

### 6b — Tone adaptation from the detected application · CLOSED, will not be built

Detection shipped; adaptation will not. The frontmost application is resolved and named
on the capsule, and nothing about it changes the words. That is the finished state.

The open question this entry carried was already answered by R3b: a tone profile rewrites
the document, so it belongs to an explicitly selected, visible mode rather than to a
silent switch keyed off whichever window happened to be in front. `transform` was that mode; it was removed on 2026-09-18 because macOS 27's Writing Tools
does the same job wherever the speaker types. Tone profiles keyed off the frontmost
window remain the wrong shape either way: five silent behaviours in place of one
deliberate choice.

Reopen this only if speaking the instruction proves to be the friction in daily use.

### 11b — Transform selection, removed and reversible

Removed on 2026-09-18, by the owner's decision, after macOS 27 shipped Writing Tools.
The whole surface went: the screen-selection reader, the capsule's captured-character
count, the pasteboard restore, the transform prompt, the App Intent and six tests. The
application no longer reads the screen at all.

**The condition to bring it back is one measurement the owner is running herself:** use
Apple's Writing Tools for the work transform used to do, on real text, in Spanish and in
mixed speech. If it does the job, this entry closes for good. If it does not — if it
misses the mixed-language case, or rewrites more than was asked and gives no way to
refuse the result — transform returns.

What returning costs: the mode, its prompt, the selection reader and the pasteboard
restore come back from the 2026-09-18 state, and R3b in `framework.md` is rewritten
rather than reverted, because the reason for having it would then be a measured gap in
Writing Tools rather than the absence of an alternative. The captured-size warning is
not optional in that case: a payload the speaker did not dictate is the one she cannot
check by remembering it.

### 8 — Phonetic dictionary and cleaner prompt biasing

Extend the Gate 3 term store (`vocabulary.local.txt`) into structured JSON carrying
phonetic aliases, and bias both the Whisper prompt and the cleaner prompts with it, to
improve recognition of `sanblueᵈᵒᵗ`, proper names and custom jargon.

Measure before adopting: the vocabulary prompt already suppresses the engine's own
punctuation, which cost punctuation F1 34.8% against 93.8% until it was found. Any
richer prompt is measured on the fixed corpus, punctuation included, before it ships.

### 8b — If the whisper prompt is ever enriched again

A fixed list of bilingual priming terms was added to `build_initial_prompt` and removed
in the same session. Measured against the real store it never reached whisper: 226
personal terms then filled 596 of the 600 characters (42 terms, 357 characters since D-02), the priming was appended after
them, and every term was cut. The prompt was byte-identical with the feature on and off,
and the two tests covering it used two-term fixtures, which is why the budget never bound
them and the feature read as working.

The condition this entry already stated still holds and is now the reason it was pulled
rather than fixed: making it effective means prepending, which changes what the engine
hears, and any richer prompt is measured on the fixed corpus with punctuation before it
ships. `scripts/replay.py` must exercise the same prompt the application does, or the
corpus measures something the speaker never runs.

