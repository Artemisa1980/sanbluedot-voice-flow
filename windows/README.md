# VoiceFlow — Windows Adapter

Tauri v2 desktop adapter over the shared Python engine. The native hub implements
selected design A with Station, Modes, Snippets, Your words and Control. A 330 x 88 capsule
appears while a dictation is in flight and stays up while its result is shown, then
hides. Window focus does not move it: it answers the trigger, not the hub. The original
preview and alternatives B and C remain in `../docs/`.

Station now keeps its overview in one window: signal chain, engine selection, the original
microphone, Andor result console and desktop output. The header places the actual version
beside the owner name; the footer remains visible. Long transcripts scroll inside the
console. History and Snippets shortcuts open their detailed pages in the left navigation.
Modes, Snippets, Your words and Control each use a cream terminal frame with a fixed
title and bottom status row. Snippets has its own form and list; Your words contains
only History, Vocabulary and Corrections.
While recording, native voice level softly pulses the microphone and changes the height
of twelve recent-loudness bars. Silence and capture exit settle them; reduced-motion
settings retain static level lights. Local cleanup runs through Ollama when a model is
chosen in Control; the station reads the service's own inventory and never pulls one.
Gemini stays refused: its Windows credential path does not exist yet.

## Validation state

The adapter compiles on this Windows machine and the development executable builds
offline against the existing lockfile. The Rust suite, the capsule and station
controller suites and the shared Python check all pass. Counts are not written here:
run the suites rather than trusting a number in a file, as `../README.md` requires.
Snippet descriptions are validated and retained through the existing local store.

Gate 5 remains open. Automated checks do not prove real keyboard behavior, microphone
capture, target insertion or packaged daily use. Use `../acceptance/phase-5-acceptance.md`
for the live matrix. No macOS build or signing was performed in this Windows repair slice.

## Current behavior

- Right Ctrl, F8 or F9 is observed with `GetAsyncKeyState` at a 10 ms polling interval.
  These keys still reach Windows. The hold delay defaults to zero and accepts
  `VOICEFLOW_HOLD_DELAY_MS` values from 0 to 3000 unless saved settings exist.
- Release ends capture. A second hold while processing is not queued. Escape requests
  cancellation during a hold. Cancellation preserves the physical key edge and injects
  no key releases. Right Ctrl + Escape can still open Start; F8 and F9 avoid that modifier
  combination. Keyboard and visible-button captures have distinct release ownership.
- WASAPI capture uses the default input device's format through `cpal`, averages channels
  and downsamples into a 16 kHz, 16-bit mono WAV. F32, I16 and U16 inputs are supported.
- The worker creates a temporary WAV name containing process ID and a time-based nonce,
  finalizes capture before invoking Python, and deletes audio after processing or cancellation.
  Stream, sample-write and finalization errors prevent transcription of a damaged recording.
- The engine uses local Whisper and literal cleanup. It receives no clipboard flag.
  Python uses UTF-8 for redirected I/O and is launched without a console window.
- The native delivery layer copies Unicode text. For recognized terminals, it collapses
  whitespace before copying; the actual clipboard payload is the protected version.
- Insertion checks window, process identity, self-target exclusion and held modifiers.
  It rechecks the foreground window immediately before `SendInput`. It never calls
  `SetForegroundWindow` or releases physical modifiers in the paste path.
- A refused insertion leaves the result copied. A failed clipboard write never dispatches
  a paste of old clipboard content. A partial or failed `SendInput` is not reported as pasted.
- `PASTED` means Windows accepted the synthetic input sequence, not that the destination
  application acknowledged consuming the text. Focus checks are snapshots, not a full
  history of every focus transition during processing.
- Speaking rate uses raw transcript words divided by finalized WAV duration. Displayed
  latency covers the complete Python call, not isolated recognition time. Missing values stay absent; successful delivery
  does not light the microphone meter with synthetic activity.
- Errors persist until the next attempt, with the full reason available by hovering the
  capsule. The processing label describes transcription. A missing native event bridge
  reports failure instead of silently presenting the preview as ready.

## Native station

- Hold the microphone dial or Hold to talk button to record. Release to transcribe;
  losing window focus cancels a button-owned hold. Use the configured global key for
  another application's target. The app's own window only receives clipboard delivery.
- The last ten dictations retain original, final and normalized delivery text in memory,
  including clipboard failures. Copy result and Copy original allow recovery. Clearing
  history requires confirmation; closing the app clears the session. No transcript file
  is written by this history feature.
- Your words and Snippets load the engine's existing local stores when their memory
  view is opened or refreshed. Vocabulary is read-only. Corrections and snippets support
  explicit save, edit and confirmed delete. Snippets also retain an optional description.
  Single-word corrections require explicit global-replacement consent. Payloads reach
  Python through stdin; no shell or command-line transcript is used. Memory mutations
  and capture startup are serialized; existing store locks still apply.
- Control saves the shortcut, delay and insertion preference to
  `preferences.local.json` in the OS app configuration directory. Invalid saved settings
  remain intact and produce a warning; defaults apply until the user saves new settings.
- Control also lists installed `ggml-*.bin` speech models with size and header-check
  results. Save settings selects a model for the next dictation. Legacy settings retain
  Base-first resolution; a missing explicit model is never silently replaced. The native
  layer validates the model before opening the microphone and locks its selection through
  processing. Header checks do not prove weight integrity or recognition accuracy.
- Literal is connected. Clean, Translate and Notes remain disabled until text-provider
  integration. No provider, model download or cloud transmission is enabled here.
- Literal, Ollama and Gemini can be selected in the engine strip. Selection updates the
  cleanup node's label, color and readiness indicator, the setup panel, footer and log.
  Ollama and Gemini are pending routes: neither their adapters nor their models or
  credentials are configured. Capture is blocked for those routes, including global
  shortcuts; selecting Literal restores dictation. Selection lasts for the session only.
- LOG contains the last 100 native events with local display times and category filters.
  Entries represent real selections and capture/delivery states. No sample credentials,
  capacity checks or measurements appear. RESULT retains transcript recovery; a new
  dictation opens RESULT automatically. Neither log nor history is saved to disk.
- The hub shows actual recognition seconds and raw-word speaking rate. The capsule
  retains complete-engine-call latency. Missing measurements remain absent.
- Closing the hub exits the app; minimize it to keep global dictation available.
  Close requests are refused while a dictation is in progress.

## Local prerequisites

The verified machine inventory is `../docs/windows-capabilities.local.md`, excluded from
version control. Python, Rust, Cargo, the Tauri CLI, FFmpeg and Whisper Base are present.
The engine diagnostic resolves the binary and validates the Base model header and size.
Ollama is unavailable, so the combined diagnostic reports a missing optional cleanup
service; that does not prevent literal transcription.

Do not run the setup script or install another model automatically. Any new provisioning
needs an explicit target and purpose. Current repair checks require no new installation.

## Commands

From the project root in PowerShell:

```powershell
$env:PYTHONPATH = 'src'
python -m unittest discover -s tests
python -m compileall -q src tests scripts
node --test windows/tests/*.test.cjs
cargo test --locked --offline --manifest-path windows/src-tauri/Cargo.toml
cargo build --locked --offline --manifest-path windows/src-tauri/Cargo.toml
```

The development executable is
`windows/src-tauri/target/debug/sanbluedot-voiceflow-windows.exe`.
The native hub was opened and its connection, settings page and empty session history
were checked. This is a development build in its project folder, not an installed package.
Live microphone and target-delivery acceptance remains open; close older instances first.

Run the engine diagnostic with the configured local payload:

```powershell
$env:PYTHONPATH = 'src'
python -m sanbluedot_voiceflow doctor --whisper-bin models/whisper-cli.exe --whisper-model models/ggml-base.bin
```

## Source map

Future provider integration must connect a verified adapter and model to the worker before
relaxing `Provider::capture_error`. `select_provider` serializes with capture startup and
returns the authoritative snapshot; the browser never declares a provider ready. Add
secure credential setup and explicit cloud consent before dispatching any remote text.
The current worker remains literal-only; changing the UI readiness flag alone is insufficient.

- `src-tauri/src/main.rs`: keyboard observation, audio lifecycle, engine command and window checks.
- `src-tauri/src/delivery.rs`: payload normalization, Unicode clipboard, insertion policy and rate calculation.
- `src-tauri/src/capture.rs`: capture ownership and physical key edges.
- `src-tauri/src/hub.rs`: validated preferences and bounded session state.
- `src-tauri/src/models.rs`: local speech-model inventory and file checks.
- `src-tauri/capabilities/default.json`: native event access; sensitive commands validate the station label in Rust.
- `../src/sanbluedot_voiceflow/desktop.py`: local memory bridge over the existing engine stores.
- `ui/`: capsule and selected A station structure, local font, styles and controllers.
- `tests/*.test.cjs`: dependency-free controller regression checks, outside shipped UI assets.

<div align="center">sanblue<sup>dot</sup></div>
