# Phase 5 Acceptance Runbook — Windows Platform Adapter

## Purpose

Close Gate 5 of the `sanblueᵈᵒᵗ VoiceFlow` product framework with evidence produced on
the Windows machine itself. Gate 5 asks for four things: the machine and its target
applications named, the same engine tests passing there, and shortcut, capture,
clipboard, insertion limits, packaging and permissions verified on that machine.

**Status: OPEN.** The first condition is closed below. Everything after it is measured on
the target machine and nowhere else — this file is the runbook until it is also the
report.

---

## Target machine

Verified 2026-09-04.

| Item | Value |
|---|---|
| Computer | Lenovo IdeaPad 1 15IAU7, model `82QD` |
| Operating system | Windows 11 Home 25H2, build `10.0.26200.9278`, x64 |
| CPU | Intel Core i3-1215U · 6 cores / 8 threads · AVX2, AVX, FMA, SSE4.1 |
| Memory | 7.73 GiB usable |
| Graphics | Intel UHD integrated, no NVIDIA GPU, no CUDA |
| Display | 1920 × 1080 at 60 Hz |
| Free disk | 67.6 GiB on `C:` (NTFS) |
| Locale | `en-US` system locale, English and Latin-American Spanish input profiles |
| Long paths | Enabled |

The registry still reports the legacy string `Windows 10 Home` in one field. Version and
build APIs identify the installation; that string does not.

## Target applications

Notepad, VS Code, and a text field in a browser. These are the three the gate measures.
Any application added here is added by name before the run, never by inference during it.

## Prerequisites on that machine

Present already: Python 3.13.15, Git 2.55, Node 22.23, VS Code, Chrome, Edge WebView2
Runtime, MSVC Build Tools 2019 (16.11) with the Windows SDK 10.0.19041, FFmpeg 8.1.1,
WinGet, Scoop and Chocolatey.

Missing, and required before the adapter can build or transcribe:

| Item | Why | How |
|---|---|---|
| Rust and Cargo | The adapter is Tauri v2 over a Rust backend | `winget install Rustlang.Rustup` |
| Tauri CLI v2 | `cargo tauri` is a subcommand, not part of Cargo | `cargo install tauri-cli --version "^2.0"` |
| `whisper-cli.exe` | The engine invokes the whisper.cpp binary. FFmpeg's `whisper` filter is a different interface and does not satisfy it | A prebuilt whisper.cpp Windows x64 release, placed at `models\whisper-cli.exe` |
| A model file | `models/` is excluded from version control, so no weights arrive with the repository | Copy `ggml-small.bin` (465 MB) first; `ggml-large-v3-turbo.bin` is 1.5 GB |

Two capabilities the Mac has and this machine does not:

- **No Ollama**, so local cleanup is unavailable until one is installed. Literal mode and
  the cloud provider are what remain.
- **No macOS keychain.** `credentials.py` reads the process environment first and falls
  back to the keychain, so on Windows the cloud key arrives as
  `VOICEFLOW_GEMINI_API_KEY` in the environment. A Credential Manager or DPAPI store is
  the Windows equivalent and is not implemented yet; until it is, the key never belongs
  in a file, a script or a committed configuration.

## Procedure

1. Copy the repository to the machine, and the model file separately — it does not travel
   with the repository.
2. Run `windows\setup-windows.ps1`. It verifies the prerequisites above, installs the
   engine, and runs the engine tests. It stops on a test failure.
3. Record the engine test result. This is Gate 5's second condition and it is pass or
   fail, not a judgement.
4. Build and run the adapter: `cd windows` then `cargo tauri dev`. **Expect compilation
   errors on the first attempt.** The adapter was written and audited on a Mac with
   neither the Rust toolchain nor the Windows SDK, so nothing in it has been compiled.
   Fix them there and record what they were.
5. Measure and record each row of the evidence table below, on this machine, with the
   model actually used.

## Evidence to record

| # | What | How it is measured | Result |
|---|---|---|---|
| 1 | Engine tests on Windows | `python -m unittest discover -s tests` with `PYTHONPATH=src` | |
| 2 | Trigger | AltGr held past the arming delay opens the microphone; a shorter press opens nothing and is reported as `TOO SHORT`; Escape cancels and deletes the audio | |
| 3 | Trigger collision | Typing `@`, `\` and `~` on the Spanish layout does not open the microphone | |
| 4 | Capture | 16 kHz mono WAV written and deleted after the run | |
| 5 | Transcription | Spanish, English and mixed utterances, with the model named and its latency recorded | |
| 6 | Clipboard | Text reaches the clipboard on every run, including when paste is suppressed | |
| 7 | Insertion | Auto-paste into Notepad, VS Code and a browser field; focus changed between press and release suppresses it | |
| 8 | Insertion limits | A terminal target receives single-line text; an elevated window is expected to refuse a non-elevated injection, and the refusal is reported rather than silent | |
| 9 | Permissions | Microphone consent requested and granted; the refusal path is visible | |
| 10 | Packaging | `cargo tauri build` produces an x64 executable, and it runs from its installed location | |
| 11 | Latency | Release-to-result p50 and p95 on this CPU, with the model named | |
| 12 | Model decision | `ggml-small` against `ggml-large-v3-turbo` on this machine: latency and accuracy, then the default | |

## Gate criteria

Gate 5 closes when rows 1 through 11 are recorded with results and none of them is a
failure the product accepts. Row 12 is a decision this machine makes for itself; the
Mac's default does not carry over.

R9 governs every figure written into this file: it is the measurement of the run it
describes, it carries its date, or it is not written.
