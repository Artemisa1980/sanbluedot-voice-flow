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

## Ahead

### 6 — Application-context awareness and tone adaptation

Detect the frontmost application and adapt the tone profile automatically: casual in
Slack and Messages, formal and structured in Mail and Docs, literal in a terminal or an
IDE. The station window already tracks the target application, so the input exists.

Open question before building: a tone profile changes the words that reach the document,
so it needs the same treatment R3b gave translation — an explicitly selected,
visible mode rather than a silent switch the speaker cannot see.

### 8 — Phonetic dictionary and cleaner prompt biasing

Extend the Gate 3 term store (`vocabulary.local.txt`) into structured JSON carrying
phonetic aliases, and bias both the Whisper prompt and the cleaner prompts with it, to
improve recognition of `sanblueᵈᵒᵗ`, proper names and custom jargon.

Measure before adopting: the vocabulary prompt already suppresses the engine's own
punctuation, which cost punctuation F1 34.8% against 93.8% until it was found. Any
richer prompt is measured on the fixed corpus, punctuation included, before it ships.

### 9 — Morphing floating HUD and in-flight mode toggle

Cycle modes — `[CLEAN]`, `[ES➔EN]`, `[NOTES]`, `[ACTION]` — from the HUD with a hotkey,
without opening the station window, and animate the capsule between rest, live meter,
and mode confirmation.

This is also the answer to an open defect: voice actions are currently parsed on every
dictation, so a sentence that begins like an instruction is executed instead of pasted.
An `[ACTION]` mode makes that an explicit choice.

### 10 — Live latency and speed badge

Partly delivered: the telemetry bar already shows the measured recognition and cleanup
seconds and the measured speaking rate, under R9. What remains is surfacing the same
figures in the floating HUD, where the speaker actually looks, and only ever as
measurements.
