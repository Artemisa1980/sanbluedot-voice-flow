# sanblueᵈᵒᵗ VoiceFlow — Windows Native Platform Adapter

Technical specification and build instructions for the Windows platform runner (Gate 5), built on Tauri v2 and Rust Win32 APIs with a lightweight retro HTML/CSS capsule HUD.

## Status

**This adapter has never been compiled.** It was written and audited on the Mac, where
neither the Rust toolchain nor the Windows SDK is installed, so every statement below
describes what the source says and not what a build proved. Gate 5 is open: `framework.md`
requires the Windows machine and its target applications to be named, and the adapter to
be built and measured on that machine. The first task there is `cargo tauri dev`, and the
first defects will be compilation errors.

## Architecture

The Windows adapter provides a native desktop interface for the shared Python engine (`src/sanbluedot_voiceflow`):

- **Push-to-Talk Trigger:** Right Alt key (`AltGr` / `VK_RMENU`) detected via a global keyboard listener. The microphone opens 500 ms after the press and not before, so a key that is really being typed opens no device and writes no file (R1). Set `VOICEFLOW_HOLD_DELAY_MS` to change it, up to 3000. A hold released before that is reported as `TOO SHORT`, which is not the same state as the take-back below.
- **Trigger collision:** `AltGr` is the key a Spanish layout uses for `@`, `\` and `~`. The arming delay is what keeps ordinary typing out of the microphone, so it is the one value to re-measure on the target machine before this trigger is accepted.
- **Cancellation:** Pressing Escape while recording cancels capture, deletes temporary audio, and suppresses auto-paste without writing history (R1).
- **Audio Capture:** WASAPI input stream via `cpal` recording 16 kHz 16-bit mono PCM via `hound`, streaming real-time normalized RMS amplitude to the retro HUD VU meter.
- **Floating HUD:** 330 × 88 px transparent, borderless, always-on-top window with 18px continuous corner radius adhering to `design-system.md` and `HUDLayout.swift`. Includes `sanblueᵈᵒᵗ` brand lockup, 12-bar LED VU meter, and vintage ribbon microphone artwork.
- **Auto-Paste:** Win32 `SendInput` (`Ctrl + V`) following target window verification via `GetForegroundWindow`. If focus changed between press and release, paste is suppressed and text remains on clipboard.
- **Terminal Guard:** Target processes identified as terminal emulators (`windowsterminal.exe`, `cmd.exe`, `powershell.exe`, `alacritty.exe`, `wezterm.exe`) enforce single-line flattening per R4.
- **Privacy & Storage:** Temporary recordings are written to `%TEMP%\voiceflow_recording.wav` and deleted immediately upon transcription completion or cancellation.

## Directory Structure

```
windows/
├── setup-windows.ps1        # Automated environment setup script
├── README.md                # This specification and instruction manual
├── ui/                      # Static retro HUD interface (No Node.js/npm required)
│   ├── index.html           # 330 × 88 capsule structure with brand lockup and 12-bar meter
│   ├── style.css            # sanblueᵈᵒᵗ visual design tokens
│   └── app.js               # Tauri event listener and VU meter controller
└── src-tauri/               # Native Rust backend
    ├── Cargo.toml           # Win32, audio, and Tauri v2 dependencies
    ├── build.rs             # Tauri v2 build script
    ├── tauri.conf.json      # Transparent window & tray configuration
    └── src/
        └── main.rs          # Hotkey, audio recording, focus guard, and engine invocation
```

## Setup Instructions

### 1. Prerequisites

Measured against the target machine on 2026-09-04. What it already has: Windows 11 Home
25H2 x64, the WebView2 Runtime, Python 3.13, Git, Node, MSVC Build Tools 2019 with the
Windows SDK 10.0.19041, and FFmpeg.

What it does not have, and what each is for:

| Missing | Needed for | Install |
|---|---|---|
| Rust and Cargo | The Rust backend of this adapter | `winget install Rustlang.Rustup` |
| Tauri CLI v2 | `cargo tauri` is a Cargo subcommand and is not part of Cargo | `cargo install tauri-cli --version "^2.0"` |
| `whisper-cli.exe` | The engine invokes the whisper.cpp binary. FFmpeg's own `whisper` filter is a different interface and does not satisfy it | A prebuilt whisper.cpp Windows x64 release, placed at `models\whisper-cli.exe` |
| A GGML model | `models/` is excluded from version control, so no weights arrive with a clone | Copy `ggml-small.bin` (465 MB) first. `ggml-large-v3-turbo.bin` is 1.5 GB and is the macOS default because it was measured on an M3 Pro, not here |

Ollama is not installed on that machine, so local cleanup is unavailable until one is.
There is no macOS keychain either: the engine reads the process environment first, so a
cloud key reaches it as `VOICEFLOW_GEMINI_API_KEY`. It never belongs in a file, a script
or a committed configuration.

`acceptance/phase-5-acceptance.md` is the gate runbook and records what must be measured
here.

### 2. Environment Setup

Run the automated PowerShell setup script from the `windows/` directory:

```powershell
powershell -ExecutionPolicy Bypass -File .\setup-windows.ps1
```

This script verifies prerequisites, installs Python engine dependencies in editable mode, runs unit tests, and validates the local environment.

### 3. Run Verification Tests

Confirm that engine unit tests pass on the Windows machine before running the adapter:

```powershell
$env:PYTHONPATH = "src"
python -m unittest discover -s tests
```

### 4. Development & Build

Run the Tauri application in development mode:

```powershell
cd windows
cargo tauri dev
```

Build the release executable:

```powershell
cd windows
cargo tauri build
```

The output executable is generated at `src-tauri/target/release/sanbluedot-voiceflow-windows.exe`.
