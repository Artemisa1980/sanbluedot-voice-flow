# Project Proposal: sanblueᵈᵒᵗ VoiceFlow

> **Owner:** private  
> **Status:** Approved for phased implementation  
> **Platforms:** macOS first; Windows after the engine passes its Mac gate  
> **Updated:** 2026-08-31

## Purpose

sanblueᵈᵒᵗ VoiceFlow is a personal push-to-talk dictation application. Holding the Fn/Globe key captures speech by default, local speech recognition transcribes Spanish, English, or a mixture of both, and an optional text model applies conservative cleanup before the result reaches the active application. The trigger remains configurable.

The product is for one user on two known computers. It does not need multi-tenant infrastructure, enterprise administration, mobile clients, or a large model-routing platform.

`framework.md` is the normative product and acceptance specification. This proposal owns the implementation direction and sequence.

## Product principles

1. **Local first:** audio and personal vocabulary remain on the device by default.
2. **Literal before clever:** the raw transcript is always available; cleanup must not change meaning.
3. **Fast path first:** ordinary dictation uses local models. Cloud rewriting is explicit and optional.
4. **One working platform at a time:** the Mac implementation must pass before the Windows adapter begins.
5. **Explicit learning:** corrections enter memory only after the user confirms them.
6. **Replaceable providers:** speech and cleanup models sit behind small interfaces rather than controlling the application architecture.

## Initial architecture

```mermaid
flowchart LR
    Hotkey["Global push-to-talk"] --> Audio["Local audio capture"]
    Audio --> STT["whisper.cpp"]
    Vocabulary["Local vocabulary"] --> STT
    STT --> Raw["Raw transcript"]
    Raw --> Corrections["Confirmed corrections"]
    Corrections --> Personalized["Personalized transcript"]
    Personalized --> Mode{"Output mode"}
    Mode -->|Literal| Guard["Safety and output guard"]
    Mode -->|Local cleanup| Ollama["Ollama + Qwen3 4B"]
    Mode -->|Explicit cloud| Cloud["Provider adapter"]
    Ollama --> Guard
    Cloud --> Guard
    Guard --> Output["Clipboard or active application"]
```

### Model responsibilities

| Layer | Initial choice | Responsibility |
|---|---|---|
| Speech recognition | `whisper.cpp` | Local transcription and automatic language detection |
| Local text cleanup | Ollama with `qwen3:4b` | Punctuation, filler removal, and conservative formatting |
| Cloud cleanup | Gemini with `gemini-3.5-flash` | Optional higher-quality cleanup; text only; Gate 4 closed 2026-08-31 |

Cloud model IDs are configuration, not permanent architecture. Gemini is the selected
first cloud provider and `gemini-3.5-flash` is the configured default, with 3.6 and 3.7
selectable and used as automatic fallbacks. Which model is default follows measured
delivery, not the version number. Groq is only a possible later
comparison: adding it requires new explicit authorization and the same privacy,
fallback, output-guard, corpus-quality, latency, and cost evidence. No Anthropic or
OpenAI connector is current planned work. Every provider must implement the same small
cleanup contract.

## Personalization

The application improves through controlled local state:

- a vocabulary list for names, acronyms, academic terms, and brand words;
- confirmed pairs of misheard text and intended text;
- output preferences for literal, conservative, and rewrite modes;
- optional application-specific formatting preferences.

This is prompt and correction memory, not continuous acoustic-model training. Silent collection of surrounding screen content, keystrokes, or unconfirmed edits is outside scope.

## Privacy and safety

- Audio stays local unless a future mode clearly states otherwise before capture.
- Cloud providers receive text only in the initial design.
- API keys belong in the operating-system credential store, never project files.
- The raw transcript remains recoverable when cleanup fails.
- Terminal output defaults to clipboard delivery. Automatic paste requires a later explicit safety decision.
- A focus change during processing must not send text to an unintended application.

## Delivery sequence

| Phase | Deliverable | Gate |
|---|---|---|
| 0 | Proposal, framework, governance, and repository-safe scaffold | Markdown and structural checks pass |
| 1 | File-to-text engine: WAV → `whisper.cpp` → literal/local cleanup → stdout or clipboard | Automated tests pass; real bilingual sample set is transcribed |
| 2 | macOS live capture and push-to-talk | Hold/release works across the agreed Mac applications |
| 3 | Confirmed vocabulary and correction memory | Repeated test terms improve without regressions |
| 4 | One optional cloud cleanup provider | No audio leaves the device; failure returns to the local path |
| 5 | Menu-bar interface and settings | Packaged Mac app passes the acceptance matrix |
| 6 | Windows platform adapter | Same engine contract passes on the named Windows computer |

**These phase numbers are not the gate numbers in `framework.md`, and the two must not
be read as one sequence.** Phase 6 here is Windows; Gate 6 there is pronunciation
practice, while Windows is Gate 5. When they disagree, `framework.md` governs, because
it is the normative specification.

## Pronunciation practice

Added 2026-08-29 as `framework.md` R8 and Gate 6, outside the phase sequence above and
independent of cloud and Windows work. A mis-transcription against a text the speaker
chose is acoustic evidence about the speaker, and the engine already produces it for
free. The application reports which words it failed to recover and keeps the recording
to replay; it assigns no score and states no phonetic diagnosis, because teaching
belongs to the separate English tutor that reads these results. This is the same
principle as the rest of the product: surface evidence, never invent judgement.

## First implementation slice

The first code slice is deliberately small:

- a Python 3.11+ engine package;
- a `whisper.cpp` command adapter;
- literal and Ollama cleanup adapters;
- a pipeline that preserves the raw transcript;
- cross-platform clipboard output;
- a diagnostic command;
- unit tests with no downloaded model required.

Live microphone capture, the global shortcut, cloud APIs, persistent personal memory, automatic paste, and the graphical shell begin only after this slice passes.

## Success measures

The Mac gate uses the owner's M3 Pro, 18 GB computer and a controlled sample set containing Spanish, English, mixed-language speech, names, numbers, URLs, and technical vocabulary.

- All automated engine tests pass.
- The raw field never changes the transcript returned by the speech engine; literal
  final output differs only through explicitly confirmed deterministic corrections.
- A cleanup failure returns an actionable error without destroying the raw transcript.
- Twenty short recordings complete without a crash.
- Release-to-result latency is measured at p50 and p95 after warm-up; the first benchmark establishes the release target rather than inventing one.
- Accuracy is reported separately from latency using a fixed reference transcript.
- Clipboard delivery succeeds in the agreed test applications; terminal auto-paste is not part of this gate.

## Current constraints

- The development Mac now has `whisper.cpp`, Ollama, `qwen3:4b`, Whisper Small, and
  large-v3-turbo provisioned and verified locally. They remain external dependencies and
  are not bundled with the source tree.
- The native Phase 2 runner is built and signed locally. It opens a visible control window,
  remains available from the Dock and menu bar, and supports both one large hold button
  and Fn/Globe. Its automated checks pass, the stable macOS permissions are approved,
  and Gate 2 passed 20/20 ordered global hold/release recordings without a crash or stuck
  state. Clipboard delivery passed in Notes, Safari, and VS Code.
- The private Phase 2 baseline records 1.90-second p50 latency, 2.27-second p95 latency,
  25.6% raw WER, and 26.9% cleaned WER. The local cleaner did not improve aggregate
  accuracy. Later fixed-audio replay points to English, not mixed speech, as the main
  remaining recognition weakness; the cleaner remains opt-in until separately accepted.
- The Windows machine is named, which closes Gate 5's first condition. Lenovo IdeaPad 1
  15IAU7 (`82QD`), Windows 11 Home 25H2, build `10.0.26200.9278`, x64: Intel Core
  i3-1215U with AVX2, 6 cores and 8 threads; 7.73 GiB usable RAM; Intel UHD integrated
  graphics and no NVIDIA GPU; 1920 × 1080; 67.6 GiB free on `C:`. Verified 2026-09-04.
- Its target applications for the gate are Notepad, VS Code and a browser text field.
- That machine carries the tools and not the payload. Python 3.13, Git, Node, VS Code,
  WebView2, MSVC Build Tools 2019 and the Windows SDK are installed; Rust, the Tauri CLI,
  `whisper-cli.exe` and the model weights are not, and the last two are excluded from
  version control by design. They are provisioned there, not shipped from here.
- Its transcription budget is not this Mac's. `large-v3-turbo` is the default because it
  was measured on an M3 Pro. On integrated graphics with 8 GiB the first measurement is
  `ggml-small`, and which model becomes the Windows default follows what that machine
  reports rather than what this one did.
- Windows work continues on that machine, not from the Mac: a copy of this project plus
  Claude Code running there can build and test the adapter in place, which is what the
  gate requires. The Python engine is unchanged and shared; only the platform shell —
  global hotkey, capture, paste, window — is new.
- macOS microphone and Accessibility permissions require visible user consent.

## Noted for later — Shortcuts, Xcode, and local intent parsing

Recorded 2026-09-16. Not scheduled, not authorized, and not part of the interface work
in progress. It is written here so the reasoning is not lost, not because it is next.

**Siri cannot be the transcriber.** `NOT VERIFIED`: no Apple documentation was opened for
this. The claim is that Apple exposes no way for an application to receive what Siri
heard, which would make this a platform limit before a privacy one. Check it against
Apple's developer documentation before the note is acted on. The owner stated
on 2026-09-16 that Siri reaching Apple's servers is acceptable to her, which removes the
objection to using Siri as a trigger but changes nothing about the limit above. If a Siri
path is ever added, `README.md` and R2/R7 stop being true as written and must be
corrected in the same change; the claim that speech never leaves the machine is not a
slogan to keep once a path contradicts it.

**Shortcuts can be the hands.** The useful direction is the opposite one: the engine
transcribes locally, the intent is resolved locally, and the result invokes a Shortcut,
which already carries a large library of system actions. Nothing is spoken to Apple, and
the Mac still does the work. This replaces neither `VoiceAction.swift` nor the paste
path; it is a third delivery target beside clipboard and keystroke.

**A local model could replace the regex intent parser.** `VoiceAction.swift` matches
fixed patterns and has already failed on ordinary Spanish — an accented application name
cannot be parsed at all, because the capture class is `[A-Za-z0-9\s]`. A local Ollama
model would read intent in either language without a pattern list. R3c currently requires
spoken intents to be parsed *deterministically*, so this is a framework decision before it
is an implementation: a model is not deterministic, and the requirement would have to say
what replaces that guarantee.

**The packaging blocks App Intents, and this is unverified.** `macos/Package.swift` builds
a plain SPM executable and `scripts/build-macos-app.sh` assembles the bundle by hand. App
Intents rely on metadata that Xcode's build system generates and embeds; without it the
actions exist in code and the system never sees them. Migrating to an Xcode target, or
reproducing that step in the script, is the open question. The cheap test is one trivial
intent through the current packaging, before any of the above is designed.
