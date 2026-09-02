# sanblueᵈᵒᵗ VoiceFlow Product Framework

## Authority

This file is the normative product and acceptance specification. `proposal.md` owns implementation order, and live code owns mechanical behavior. The owner decides product scope and permissions.

## Objective

Provide personal, low-friction dictation on macOS and Windows. A configurable push-to-talk shortcut captures speech, understands Spanish, English, and ordinary switching between them, applies the selected cleanup mode, and returns text safely to the user's current workflow.

## Required behavior

### R1 — Capture

- Recording starts on shortcut press and stops on release.
- The default macOS trigger is the Fn/Globe key alone: hold to record and release to
  process. This single-button behavior is an explicit owner decision.
- The trigger remains configurable. Other modifier keys alone are rejected to avoid
  collisions with ordinary keyboard use.
- The application exposes recording, processing, success, and failure states.
- The first implementation target is macOS; Windows uses a platform adapter after the Mac gate.

### R2 — Speech recognition

- Speech recognition works locally by default.
- Automatic detection covers Spanish, English, and mixed-language utterances in the acceptance corpus.
- The language the engine selected is reported alongside the transcript. When the
  engine reports none, the label stays unknown and is never inferred from the text.
- The raw transcript preserves the speech engine's text exactly.
- Literal output may apply explicitly confirmed deterministic corrections, but no
  cleanup model changes it; the raw transcript remains separately available.
- The speech backend is replaceable and cannot write directly to the active application.

### R3 — Cleanup modes

1. **Literal:** no cleanup model changes the transcript; explicitly confirmed
   deterministic corrections may be applied as a separate personalization layer.
2. **Conservative:** remove unambiguous fillers, resolve explicit self-corrections only
   when that transformation can be verified safely, add punctuation, and format
   paragraphs without translation or invented content.
3. **Rewrite:** improve tone or structure only after an explicit user action.

The raw transcript remains available for every mode. Cleanup failure must not erase it.

### R3b — Transformation modes

Translation and meeting structuring are not cleanup. They are asked to change the text,
so the conservative output guard cannot apply to them: a guard that rejects substitution
would reject every correct translation. They are therefore separate, explicitly selected
modes, and the distinction is normative rather than cosmetic.

1. **Translate (ES → EN):** turns Spanish or mixed speech into idiomatic professional US
   English. Proper names, technical terms, URLs, file paths, numbers, and currencies are
   preserved.
2. **Meeting notes:** structures spoken dictation into Markdown summary bullets and a
   `- [ ]` action-item checklist, keeping the speaker's language.

- Only `clean` passes through the conservative output guard. Every other mode is
  delivered as the provider returned it, and the guard must never be relaxed to
  accommodate one of them.
- The selected mode is visible before transmission and named in the announcement.
### R3c — Voice actions & system automation

- Spoken natural language intents (Google, YouTube, GitHub search, app launch, URL navigation) in Spanish or English are parsed deterministically.
- Executed actions suppress auto-paste into the prior application to prevent document pollution.
- Action execution failure falls through to standard dictation paste so user speech is never discarded.
- Conversational phrases with non-app keywords are rejected to prevent accidental app launches.

### R4 — Output

- Clipboard delivery is the safe baseline on both platforms.
- Active-application insertion is a separate platform capability with a clipboard fallback.
- A recorded target application is invalid after focus changes.
- Terminals receive automatic paste insertion following the owner's explicit approval on 2026-09-01, protected by an automatic single-line prompt flattening guard in `AutoPaste` to prevent premature command execution.
- Unidentifiable applications (missing or empty bundle identifier) and VoiceFlow's own window remain strictly clipboard-only. The owner adds or removes identifiers by name; nothing is added by inference.
- The result reported to the speaker states what happened. Permission, the target
  application, and event creation are all decided before the interface claims a paste,
  so "pasted" is never shown for text that only reached the clipboard.

### R5 — Personalization

- Personalization uses a local vocabulary and explicitly confirmed correction pairs.
- Unconfirmed edits, surrounding screen content, and arbitrary keystrokes are not learning signals.
- A correction can be viewed, changed, or deleted.
- Personal data has a versioned local schema and is excluded from version control.

### R5b — Voice snippets & spoken macros

- Spoken trigger phrases expand deterministically into predefined multi-line text blocks, URLs, or structured templates.
- Snippet expansion occurs after speech recognition and cleanup/output guard to ensure long URL or template expansions are never rejected by conservative lexical guards.
- Expansion respects word boundaries (`(?<!\w)trigger(?!\w)`) in Spanish and English, operates case-insensitively, and evaluates longest triggers first in a single non-cascading scan.
- Snippet definitions are stored locally in versioned JSON (`snippets.local.json`) with atomic writes and schema validation, completely excluded from version control.
- If cleanup fails, snippets expand over the deterministic fallback transcript so macro invocations succeed even under provider failure.

### R5c — Distillation pairs

A distillation pair is the speaker's own sentence stored twice: as the engine heard it
and as the cloud provider rewrote it. Keeping it is a privacy decision, so it is made
explicitly and never inferred from the choice of provider.

- Recording is off by default. Selecting a cloud cleaner is consent to clean one
  dictation, never consent to archive every sentence.
- The engine records a pair only when that run was explicitly asked to, and the
  application sends that request only while the speaker has the setting turned on.
- Pairs stay local, are excluded from version control, and leave the device only
  through an explicit export.
- The store is deletable in one command, and its location is named wherever its
  contents are counted.
- A failure to record is reported. A store the speaker believes is filling and is not
  would make the resulting dataset a claim nobody can trust.

### R6 — Model providers

- `whisper.cpp` is the first local speech backend.
- Ollama is the first local cleanup runtime; `qwen3:4b` is the initial candidate.
- Cloud cleanup is optional, text-only, and disabled by default.
- Gemini is the first cloud cleanup provider. Gate 4 closed on 2026-08-31; see
  `acceptance/phase-4-acceptance.md`.
- The configured default is `gemini-3.5-flash`: the model that answers, not the highest
  version. Any change to it is a measurement, never an inference from the version number.
  Interleaved on 2026-08-31 with the same request shape and identical output quality on
  cleanup, translation and meeting notes: 3.5 delivered 5 of 6 at a 2.3-second median,
  3.6 delivered 4 of 6 at 14.3 seconds, 3.7 delivered 3 of 6 at 12.5 seconds.
- The fallback chain is ordered by measured delivery, not by version. Ordering it by
  version would send a fallback from the most available model straight to the least
  available one.
- Failures are HTTP 503 `UNAVAILABLE`, returned as "this model is currently experiencing
  high demand". The project is billed, the same status reaches every model, and it
  persists without the response schema and at a small token budget, so it is Google
  capacity and not this project's request, key, or tier.
- A provider timeout is a product decision, not a constant to guess. It is set above the
  slowest reply measured against the live endpoint, and it bounds the whole call rather
  than each attempt, so recovering from a transient failure never doubles the wait
  before the fallback arrives.
- A transient server status (500, 502, 503, 504) is provider capacity, not a rejected
  request, and is retried once inside that same budget. Any other status fails
  immediately: a rejected key or a malformed request is never sent twice.
- When a provider offers several measured models, the speaker picks one and the
  application walks the rest on a capacity error, inside the same budget. No single
  model may spend the whole budget: without a per-model share, one busy model exhausts
  the wait and the healthy ones are never reached.
- Falling back is an availability decision, never a quality one. A model joins the chain
  only after it is measured on the same request shape and produces equivalent output, so
  moving down the chain never trades accuracy for a reply.
- The interface names the model that answered, not the model that was asked for. A
  fallback the speaker cannot see is a silent change to what produced their words.
- The chosen model persists across launches. The application is opened from the Finder
  with no arguments, so a preference that lives only in launch configuration is no
  preference at all.
- Every cloud provider implements the same cleanup interface, and the application works
  when none is configured. A later provider, including Groq, requires new explicit
  authorization and must pass the same Gate 4 evidence.
- Provider selection, model identifier, timeout, and fallback policy are configuration rather than branching product logic.

### R7 — Privacy and credentials

- Audio remains local in the initial product.
- No cloud request occurs without a visible cloud mode.
- Secrets never enter source files, Markdown, logs, test fixtures, or personal-memory files.
- Diagnostic logs exclude audio and dictated content by default.
- Local user data supports deletion and export.

### R8 — Pronunciation practice

A mis-transcription against a known text is acoustic evidence about the speaker, not
only about the engine. Practice mode exposes that evidence; it does not grade speech.

- Practice mode is entered explicitly and is never the default. Ordinary dictation
  continues to delete every recording.
- A practice session pairs one recording with the reference text the speaker read.
- The session reports, at word level, which reference words the engine did not
  recover and what it produced instead.
- The recording is kept so the speaker can listen to it, and can be listed and
  deleted by the speaker.
- The application reports what the engine heard. It assigns no score, level or
  verdict on pronunciation, and states no phonetic diagnosis. Teaching belongs to the
  separate English tutor, which reads these results.
- Practice audio never leaves the device under this requirement. Sending it to a
  provider that can assess pronunciation is a separate decision under R6 and R7.

### R9 — Reported measurements

The product's evidence discipline applies to its own interface. A number shown as a
measurement is one, or it is not shown.

- A latency, rate, or diagnostic figure displayed anywhere in the interface comes from
  the run being displayed. The engine reports the seconds each stage spent; the
  interface may report those and nothing else.
- A stage that reported no measurement leaves its indicator empty. A placeholder is
  indistinguishable from a reading and is therefore never displayed.
- Before the first dictation of a session, a diagnostics surface shows no figures.
- A speaking rate is words over the time the speaker spoke. Words over processing time
  measures the machine and must not carry a speech-rate label.
- A displayed figure is never clamped into a plausible range: a rate outside the
  expected band is evidence, not a defect to hide.

## Architecture boundaries

```text
platform input -> audio source -> transcriber -> raw transcript
raw transcript -> confirmed corrections -> personalized transcript
personalized transcript -> cleaner -> output guard -> snippet expander -> clipboard / inserter
personalized transcript -----------^ (fallback) ---> snippet expander -> clipboard / inserter
```

- Platform input and insertion contain operating-system behavior.
- Transcribers only convert audio to text.
- Cleaners only transform provided text.
- The pipeline coordinates components and retains raw, personalized, and final text.
- Conservative cleanup output is rejected if it invents, reorders, substitutes, or
  deletes non-filler lexical content; rejection returns the deterministic personalized
  transcript.
- User memory supplies bounded context but cannot invoke providers itself.

## Phase gates

### Gate 1 — File-to-text engine

- Unit tests and compilation checks pass.
- The diagnostic command identifies missing binaries, models, and Ollama without crashing.
- A configured Whisper model is rejected unless it is a readable ggml model file
  whose size can hold the weights its own header describes.
- A real WAV file can travel through literal mode to stdout and clipboard.
- Ollama cleanup is opt-in and its failure preserves the raw transcript.

### Gate 2 — macOS push-to-talk

- Press-and-hold recording works after the required macOS permissions are granted.
- Twenty short recordings finish without a crash or stuck recording state.
- Notes, one supported browser, and VS Code receive clipboard output successfully.
- Measured p50 and p95 latency and transcript error results are recorded against the fixed corpus.

### Gate 3 — Personalization

- The acceptance vocabulary includes UTEL, Gim, sanblueᵈᵒᵗ, and selected technical terms.
- Confirmed correction pairs improve their target cases and do not alter unrelated literal output.
- The user can inspect and delete stored corrections.

### Gate 4 — Cloud cleanup

- Only transcript text and bounded preferences leave the device.
- The interface indicates the selected provider before transmission.
- Timeout, provider error, or missing credentials return to the configured local behavior.
- Provider usage is measurable and can be disabled completely.
- The provider passes the fixed recorded corpus through the same output guard as the
  local cleaner, and its delivered text is no further from the reference than the
  engine transcript it replaced.

### Gate 5 — Windows

- The Windows machine and target applications are named before implementation.
- The same engine tests pass on Windows.
- Shortcut, capture, clipboard, insertion limits, packaging, and permissions are verified on that machine.

### Gate 6 — Pronunciation practice

This gate is independent of Gates 4 and 5 and may be closed before either. It depends
only on the local engine and on retained practice audio.

- A practice session records, keeps its audio, and pairs it with the reference text.
- The word-level report names every reference word the engine did not recover.
- Recordings are listable and deletable by the speaker, and ordinary dictation still
  retains no audio.
- Reported differences distinguish engine formatting, such as writing a numeral for a
  spoken number, from words the engine genuinely failed to recover. Formatting
  differences are excluded from the pronunciation signal.

## Non-goals before Gate 5

- Mobile applications, team accounts, analytics, subscription billing, and enterprise controls.
- Continuous acoustic-model training or claims that the speech model retrains itself.
- Automatic provider selection based on opaque quality guesses. Moving to the next
  measured model after an explicit capacity error is not a quality guess, and R6 requires
  it; choosing a provider because one is assumed to write better output remains excluded.
- Screen-wide context collection.
- Unattended command execution without explicit user speech action.
