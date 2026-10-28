# sanblueᵈᵒᵗ VoiceFlow Product Framework

## Authority

This file is the normative product and acceptance specification. `proposal.md` owns implementation order, and live code owns mechanical behavior. The owner decides product scope and permissions.

## Objective

Provide personal, low-friction dictation on macOS. A configurable push-to-talk shortcut captures speech, understands Spanish, English, and ordinary switching between them, applies the selected cleanup mode, and returns text safely to the user's current workflow.

## Required behavior

### R1 — Capture

- Recording starts once the shortcut has been held past a configurable delay, and stops
  on release. A touch shorter than the delay opens no microphone and produces no
  recording: the default trigger sits where a hand rests, and a brush against it used to
  record a dictation of nothing. The refusal is reported rather than silent.
- A recording in progress can be taken back. The audio is deleted rather than
  transcribed, nothing is pasted, and no history entry is written.
- The default macOS trigger is the Fn/Globe key alone: hold to record and release to
  process. This single-button behavior is an explicit owner decision.
- The trigger remains configurable. Other modifier keys alone are rejected to avoid
  collisions with ordinary keyboard use.
- The default Windows trigger is right Ctrl alone. The Windows adapter has no Fn/Globe
  equivalent to bind, so it satisfies the rule above by taking the modifier that collides
  least: right Ctrl types no character on any keyboard layout and, unlike a released Alt,
  opens no menu bar. This is an explicit platform exception to that rule, and Gate 5
  measures the collisions it still carries rather than assuming there are none.
- The application exposes recording, processing, success, and failure states.
- This specification governs the macOS implementation. A second platform is adapted, gated and measured on the machine it targets, and is not specified, audited or planned from here, except where a rule names the Windows adapter explicitly — its trigger above, and the Ollama cleaner the shared engine keeps for it (R6).

### R1b — Desktop companion and HUD

- A persistent, non-activating desktop companion mascot (Microduck) rests unobtrusively on screen in a borderless floating panel (`FloatingHUDPanel`). It never steals keyboard focus or activates over other applications (`canBecomeKey = false`, `canBecomeMain = false`).
- In its idle state, Microduck defaults to a relaxed seated posture (`sittingFront`), swinging its feet rhythmically, gently breathing, and glancing smoothly toward the cursor via distance-decayed eye and head tracking.
- The user can toggle posture between sitting and standing by left-clicking the duck or selecting the posture action in its context menu. Standing posture features walking cycles, hops, and upright resting sway. Posture preference persists across application launches.
- Microduck can be repositioned freely across displays via click-and-drag. Screen position coordinates persist across restarts and clamp safely inside visible screen bounds.
- During active voice capture and processing, a thought-bubble status capsule opens adjacent to Microduck's head to display live VU audio metering, active cleaner model, transcription status, and action feedback.
- Left-clicking the duck toggles posture; right-clicking or Control-clicking opens an Apple HIG-compliant companion context menu providing mode selection, cleaner switching, model choice, speech engine toggle, posture control, station access, and a hide option.
- During system sleep or display lock, animation loops pause automatically to eliminate idle battery consumption.

### R2 — Speech recognition

- Speech recognition works locally by default.
- Automatic detection covers Spanish, English, and mixed-language utterances in the acceptance corpus.
- The language the engine selected is reported alongside the transcript. When the
  engine reports none, the label stays unknown and is never inferred from the text.
- The raw transcript preserves the speech engine's text exactly. The line breaks
  whisper.cpp writes between segments are where it paused, not text the speaker
  dictated, so segments are joined with one space.
- Literal output may apply explicitly confirmed deterministic corrections, but no
  cleanup model changes it; the raw transcript remains separately available.
- The speech backend is replaceable and cannot write directly to the active application.

### R3 — Cleanup modes

1. **Literal:** no cleanup model changes the transcript; explicitly confirmed
   deterministic corrections may be applied as a separate personalization layer.
2. **Conservative:** remove unambiguous fillers, resolve explicit self-corrections only
   when that transformation can be verified safely, add punctuation, and format
   paragraphs without translation or invented content. When the speech engine writes its own
   punctuation (Parakeet), `clean` asks no model: the output guard's fillers are deleted
   by rule and the result faces the same guard. A spoken take-back still goes to the
   selected engine, and ES➔EN and NOTES are unchanged.
3. **Rewrite:** improve tone or structure only after an explicit user action.

**A spoken take-back is resolved as it is dictated.** When a `clean` dictation carries
a take-back cue from `take_back.py` — "borra eso", "me equivoqué", "no, mejor", "perdón",
"scratch that", "sorry" — it runs as a fix first, on every engine with a model. The
model decides what was withdrawn; the fix guard lets it delete and refuses every word
the speaker did not say, and web addresses, file paths, code and numbers stay as
written. When the fix guard refuses, the dictation gets the ordinary cleanup instead of
the bare transcript. A cue only decides that the model is asked, so the list leans
wide; a bare "no" or "digo" stays out because nearly every sentence would then pay for a
second call. A take-back withdraws the words just before it, never the dictation: the fix
guard lets a deletion stand only within eighteen words before a cue or three after it, as one
unbroken run up to the cue, and it
matches from the end, because the corrected version is the one said last. On long
dictations Apple and Ollama erased most of the text in fix mode, and this is what
refuses it. `literal` has no model and never resolves a take-back. The raw
transcript stays in History.

**FIX teaches and fixes; no model rewrites.** FIX on a History row opens the Words
section with what the engine heard in that dictation, editable. The speaker corrects the
words in place; each run of changed words becomes a pair, shown before LEARN confirms
it: a correction applied before any model sees the text, so it guides every engine from
then on. A one-word change is learned with the words around it unless the speaker ticks
that it applies everywhere. The same pairs are applied to that dictation's delivered
text, whole words only, so the row shows the fix and COPY and RE-PASTE hand it over; a
pair whose heard words are not in that text leaves the row as it was, and the speaker is
told. A pair typed in the Words section still needs the second consent for one word, and
LEARN pressed without it says so rather than staying greyed out.

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
**Transform selection was removed on 2026-09-18.** It applied a spoken instruction to
text highlighted in another application, and it was the one mode whose payload the
speaker had not dictated — which is why it carried a captured-size warning, a pasteboard
restore and a refusal when paired with the literal cleaner. macOS 27 ships Writing Tools,
which does that job wherever the speaker types, and a second, worse copy of it is not a
feature. The engine, the selection reader and the capsule's character count went with it.

The product no longer reads the screen. Nothing in it captures text the speaker did not
say. The removal is reversible and the condition is recorded in `docs/proposals/phase-5-proposal.md`
§11b: the owner is measuring Writing Tools against the work transform used to do, and
transform returns only if that measurement finds a gap.

- A mode that rewrites requires a cleaner that can rewrite. Paired with the literal
  cleaner it is refused, because the alternative is a run that returns an ordinary
  dictation under a badge that says otherwise.
- Only `clean` passes through the conservative output guard. Every other mode is
  delivered as the provider returned it, and the guard must never be relaxed to
  accommodate one of them.
- A cleanup replaced by the deterministic transcript says which side refused: the guard
  rejecting text the provider did return, or the provider failing to answer. The two are
  reported identically nowhere, because they call for opposite responses — shorten the
  sentence, or wait and use a local engine. An unspecified failure is attributed to the
  provider, never to the speaker's sentence.
- The selected mode is visible before transmission and named in the announcement.
### R3c — Voice actions & system automation

- Spoken natural language intents (Google, YouTube, GitHub search, app launch, URL navigation) in Spanish or English are parsed deterministically.
- A dictation is examined for a command only in the mode selected for it. Parsing every
  dictation made the decision for the speaker: a sentence that merely opened like an
  instruction was executed instead of written, and nothing on screen said which reading
  the application had taken. The selected mode is the answer, and it is visible before
  the speaker starts talking.
- The mode is changeable without opening the station window, and the surface that
  announces the change is the one visible at the time. The switch is refused while a
  dictation is in flight — from the moment the shortcut is pressed until the result is
  delivered — and the refusal is reported rather than silent. A run keeps the mode it
  was started with and is reported under that mode.
- `actions` is an application mode, not an engine mode. The engine transcribes and cleans
  as usual, and the command is recognized from the text it returns.
- Executed actions suppress auto-paste into the prior application to prevent document pollution.
- Action execution failure falls through to standard dictation paste so user speech is never discarded.
- A dictation in the action mode that matches no intent is reported as such. Falling
  through in silence gives the mode the same visible result as every other mode, so the
  speaker cannot tell a refusal from a failure.
- A spoken application name with no application behind it resolves to that name's website
  when the name is one of an explicit list. The machine is searched first, so an installed
  application always wins, and a name outside the list is refused rather than guessed at.
- The result names what was performed, not what was parsed. An action that opened a site
  in place of an application is never reported as a launch.
- Conversational phrases with non-app keywords are rejected to prevent accidental app launches.

### R3d — Shortcuts

Siri, Spotlight and Shortcuts can hand the engine text to clean, translate or turn into
meeting notes. That text was written, not dictated.

- A shortcut runs only on this Mac. With a cloud engine selected it is refused and says
  why: a shortcut shows nothing on screen, so nothing would say the text is leaving, and
  swapping in a local engine would run one the speaker did not pick.
- Confirmed corrections and snippets do not apply. They repair and expand speech; applied
  to written text they would change words nobody misheard.
- The conservative output guard applies to `clean` exactly as it does to a dictation.
- The product still reads nothing from the screen. A shortcut works on the text it is
  handed, and choosing that text is the speaker's own action.

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
- A correction can be viewed, changed, or deleted. The Words section does all three,
  and adds or removes vocabulary, by asking the engine, which owns both stores. It shows
  which vocabulary terms fit what Whisper reads before it listens and which are stored
  and unread, and whether a pair was learned from a FIX or typed there.
- Personal data has a versioned local schema and is excluded from version control.
- The single portable export carries every local store, and names what it carried. A
  file that promises "every piece" and omits one loses it silently on the machine the
  speaker moved away from, and an export that does not say it took the archived
  sentences is not a decision the speaker made.

### R5b — Voice snippets & spoken macros

- Spoken trigger phrases expand deterministically into predefined multi-line text blocks, URLs, or structured templates.
- Snippet expansion occurs after speech recognition and cleanup/output guard to ensure long URL or template expansions are never rejected by conservative lexical guards.
- Expansion happens in exactly one place. A single non-cascading scan is a property of
  one scan; two implementations reading the same store and running in sequence reproduce
  the cascade the rule forbids, because the second scan matches the payload the first one
  wrote. The engine owns the scan; any other layer delivers its result unchanged.
- A personal store that cannot be read is preserved under a dated name and the loss is
  reported. Treating an unreadable store as an empty one lets the next edit overwrite it.
- Expansion respects word boundaries (`(?<!\w)trigger(?!\w)`) in Spanish and English, operates case-insensitively, and evaluates longest triggers first in a single non-cascading scan.
- Snippet definitions are stored locally in versioned JSON (`snippets.local.json`) with atomic writes and schema validation, completely excluded from version control.
- If cleanup fails, snippets expand over the deterministic fallback transcript so macro invocations succeed even under provider failure.
- An expansion may carry dynamic macros, resolved once at expansion time: `{date}`,
  `{time}`, `{datetime}`, `{year}`, `{month}`, `{day}`, `{uuid}` and `{app}`. The date
  parts are numeric and agree with each other; a weekday name would have to choose a
  language, and choosing English for a Spanish speaker is not a default, it is a defect.
- A macro whose value the engine was not given stays written as itself. An unresolved
  `{app}` is visible in the delivered text; substituting a blank would hide the failure
  in the one place the speaker cannot check it.

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
- Parakeet Ultra is a second local speech backend, chosen in Settings and remembered
  across launches. It runs on the Neural Engine through FluidAudio, reached through a
  helper binary the engine runs, as Apple's cleanup model is; FluidAudio is linked by that
  helper alone. Its tokens are held to the Latin script, which keeps mixed Spanish and
  English mixed and refuses the Cyrillic the unfiltered model wrote on the owner's
  corpus. It reads no vocabulary prompt; confirmed corrections apply after it as they do
  after Whisper. It reports no language, so the label stays unknown. A dictation never
  downloads it: a missing model is reported, and fetching it is a separate run.
- Ollama was the first local cleanup runtime and left the macOS app on 2026-10-01 by the
  owner's decision. Apple's on-device model is the local cleanup engine on this Mac. The
  shared engine keeps Ollama for the Windows adapter, which has no on-device model, by the
  owner's decision of 2026-10-02; the macOS app never offers it.
- Apple's on-device model is a second local cleanup runtime, reached through a helper
  binary the engine runs rather than by moving cleanup into the application: the pipeline,
  the personalization and the output guard stay where this document draws them. It needs
  no credential and no network, so it is not a cloud provider. Like every other cleaner it
  is measured on the fixed corpus through the same guard before it may become a default.
- Cloud cleanup is optional, text-only, and disabled by default.
- Gemini is the first cloud cleanup provider. Gate 4 closed on 2026-08-31; see
  `acceptance/phase-4-acceptance.md`.
- The primary Gemini model is `gemini-3.8-flash`, by owner decision on 2026-10-24, with
  `gemini-4-argon` available as secondary model for deep cleanup, reasoning, and fallback.
  A busy reply on the primary model is retried once inside the budget before walking the
  chain to `gemini-4-argon`, and the plain transcript is delivered if the chain is exhausted.
- A measurement shown in the interface carries the date it was taken. Nothing in the
  application re-measures, so an undated figure would present a photograph as the current
  ranking and recommend a model that may no longer be the one that answers.
- The fallback chain is ordered by measured delivery, not by version. Ordering it by
  version would send a fallback from the most available model straight to the least
  available one.
- A provider failure names only the models this run actually contacted, and says what
  happened to each: at capacity, or out of time. A model the budget check skipped before
  any request left the machine is named as skipped. Reporting an uncontacted model as
  busy is a claim about the provider's availability that the run has no evidence for.
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
- Accepted limit: the vocabulary prompt reaches `whisper-cli` in argv, visible to `ps`
  on this Mac while it runs, because `--prompt` is the binary's only way to take it.

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
- The diagnostic command identifies missing binaries and models without crashing.
- A configured Whisper model is rejected unless it is a readable ggml model file
  whose size can hold the weights its own header describes.
- A real WAV file can travel through literal mode to stdout and clipboard.
- Model cleanup is opt-in and its failure preserves the raw transcript.

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

### Gate 5 — Second platform

Not this specification's gate. It is defined, measured and reported on the machine it
targets, and `acceptance/phase-5-acceptance.md` is its only record here.

### Gate 6 — Pronunciation practice

This gate is independent of Gate 4 and may be closed before it. It depends only on the
local engine and on retained practice audio.

- A practice session records, keeps its audio, and pairs it with the reference text.
- The word-level report names every reference word the engine did not recover.
- Recordings are listable and deletable by the speaker, and ordinary dictation still
  retains no audio.
- Reported differences distinguish engine formatting, such as writing a numeral for a
  spoken number, from words the engine genuinely failed to recover. Formatting
  differences are excluded from the pronunciation signal.

## Non-goals

- Mobile applications, team accounts, analytics, subscription billing, and enterprise controls.
- Continuous acoustic-model training or claims that the speech model retrains itself.
- Automatic provider selection based on opaque quality guesses. Moving to the next
  measured model after an explicit capacity error is not a quality guess, and R6 requires
  it; choosing a provider because one is assumed to write better output remains excluded.
- Screen-wide context collection.
- Unattended command execution without explicit user speech action.
