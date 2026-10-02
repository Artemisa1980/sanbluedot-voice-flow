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

## Trigger

Right Ctrl, decided 2026-09-04, before the adapter was compiled for the first time.

The adapter was written against AltGr. On this machine's Spanish layout AltGr is the key
that types `@`, `\` and `~`, so ordinary typing pressed the trigger. The arming delay kept
the microphone shut on a tap, but two things survived it: the capsule announced
`TOO SHORT` at every one of those characters, and a hold long enough to reach for the
second key would have opened the device. On the en-US profile the same physical key is a
plain right Alt, whose release focuses the menu bar of a Win32 window — where the
auto-paste would then land.

Right Ctrl types no character on any layout and Ctrl alone opens no menu, so the collision
class is smaller. It is not zero: rows 2 and 3 below measure it rather than assume it.

The adapter watches the trigger; it does not take it. `GetAsyncKeyState` is polled every
10 ms on a thread of its own, and every key it reads reaches Windows unchanged. An
earlier build consumed the press and the release with `rdev::grab`; the poll replaced
that trigger, and the trade the grab carried went with it.

What the poll keeps: right Ctrl still works as a modifier, so `Ctrl+C` taken with the
right hand copies instead of typing a bare `c`, and left Ctrl was never affected either
way. What the poll costs: the key state the shell reads is set while the trigger is
held, so a held right Ctrl turns the mouse wheel into zoom and a click into a
Ctrl-click, and Windows still answers `Ctrl+Escape` with the Start menu. F8 and F9
carry neither cost. Row 3 measures them rather than assuming them.

`framework.md` R1 rejects modifier keys alone as triggers. Windows exposes no Fn/Globe
equivalent to bind, so this platform meets that rule by choosing the modifier that
collides least. The exception is recorded in R1 and is settled here by measurement.

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
| 1 | Engine tests on Windows | `python -m unittest discover -s tests` with `PYTHONPATH=src` | **PASS** · 2026-09-04 · 298 tests, 296 passed and 2 skipped, after F-W1 and F-W2 were fixed |
| 2 | Trigger | Right Ctrl held past the arming delay opens the microphone; a shorter press opens nothing and is reported as `TOO SHORT`; Escape cancels and deletes the audio | |
| 3 | Trigger collision | `Ctrl+C` and `Ctrl+V` taken with the right hand write no audio file and still perform their shortcut, because the poll consumes nothing. Also recorded: whether a held right Ctrl turns the mouse wheel into zoom and a click into a Ctrl-click, and whether `Ctrl+Escape` opens Start. Measured on the Spanish and en-US profiles, in Notepad and in a terminal | |
| 4 | Capture | 16 kHz mono WAV written and deleted after the run, at a length the clock accounts for | **PASS** · 2026-09-04 · 406 240 samples = 25.39 s written for 25.46 s of open microphone; deleted after the run. The 0.07 s shortfall is the stream's start latency, not drift — see the reading below |
| 5 | Transcription | Spanish, English and mixed utterances, with the model named and its latency recorded | |
| 6 | Clipboard | Text reaches the clipboard on every run, including when paste is suppressed | |
| 7 | Insertion | Auto-paste into Notepad, VS Code and a browser field; focus changed between press and release suppresses it | |
| 8 | Insertion limits | A terminal target receives single-line text; an elevated window is expected to refuse a non-elevated injection, and the refusal is reported rather than silent | |
| 9 | Permissions | Microphone consent requested and granted; the refusal path is visible | |
| 10 | Packaging | `cargo tauri build` produces an x64 executable, and it runs from its installed location | |
| 11 | Latency | Release-to-result p50 and p95 on this CPU, with the model named | |
| 12 | Model decision | `ggml-small` against `ggml-large-v3-turbo` on this machine: latency and accuracy, then the default | |

## Row 1 — engine tests, 2026-09-04

`python -m unittest discover -s tests` with `PYTHONPATH=src`, Python 3.13.15, run from the
project root on the target machine. 297 tests in 1.2 s: 295 pass, 1 fails, 1 errors. The
package was not installed first; `PYTHONPATH=src` is what the gate specifies and the engine
imports from it.

Both defects are in `src/sanbluedot_voiceflow/transcribers/whisper_cpp.py`, and both are the
same class: file permissions checked the POSIX way on a platform that does not answer those
questions. These are the only two `os.access` call sites in the engine.

**F-W1 · `whisper_cpp.py:78` — the executability guard is inert on Windows.**
`resolve_binary` accepts an explicit path when `candidate.is_file() and os.access(candidate,
os.X_OK)`. On Windows `os.access(path, os.X_OK)` answers true for any existing file, whatever
it contains, so the guard admits a file that cannot be executed.
`BinaryResolutionTests.test_explicit_binary_must_be_executable` writes a text file named
`whisper-cli` and expects `None`; it receives the path.

**F-W2 · `whisper_cpp.py:112` — the readability guard is inert on Windows.**
`transcribe` raises `DependencyUnavailable` when `not os.access(self.model_path, os.R_OK)`.
`WhisperCppTranscriberTests.test_unreadable_model_raises_dependency_unavailable` makes the
model unreadable with `chmod(0o000)`, which Windows does not honour for the file's owner, so
the guard passes, execution continues into `subprocess.run`, and the run dies on the fake
binary with `OSError: [WinError 193] %1 is not a valid Win32 application`.

That `OSError` carries a third fact worth stating on its own: on Windows an invalid binary
escapes as a raw `OSError` rather than as the engine's own `DependencyUnavailable`, so the
failure a speaker would see is a stack trace rather than a named refusal. Fixing F-W1 closes
the route that produced it here, because a file without an executable extension no longer
resolves. A binary that carries the extension and is still not a valid image would raise the
same `OSError`; that path is open and is not part of row 1.

### Remediation, same day

`is_executable_file()` was added to `whisper_cpp.py` and `resolve_binary` now calls it:
POSIX keeps `os.access(path, os.X_OK)`, Windows compares the suffix against `PATHEXT`. The
model check no longer asks `os.access`; it opens the file and reads one byte, which is the
question it was trying to ask and the only portable way to ask it. The `not readable`
message is unchanged, so its assertion still holds.

The tests carried the same POSIX assumption in their fixtures. Eleven of them built a
stand-in binary named `whisper-cli` and made it executable with `chmod`, which Windows does
not honour, so they now build `BINARY_NAME` — `whisper-cli.exe` on Windows. Two tests
measure a mechanism the platform does not have and are skipped there rather than weakened:
`chmod` cannot remove execute permission on Windows, and it cannot deny the owner read
access. A Windows-only test covers what `PATHEXT` decides.

`python -m compileall -q src tests scripts` is clean and the suite is `OK`: 298 tests, 296
passed, 2 skipped. The change is in the shared engine, so it reaches macOS as well; the
POSIX branch of both guards is the behavior that was already there.

## First compile, 2026-09-04

Rust 1.98.1, Cargo 1.98.1, `tauri-cli` 2.11.4, all installed on the target machine that day.
`cargo check` in `windows/src-tauri`. The adapter had never been compiled anywhere, and the
first run produced four defects. It now compiles with no errors and no warnings.

**C-01 · `tauri-build` stopped on a missing `icons/icon.ico`.** The adapter shipped no icon
set and declared none. `cargo tauri icon assets/voiceflow-app-icon.png` generated one from
the 1024 × 1024 brand asset the macOS app already uses. The Android and iOS sets it also
writes were deleted: this adapter targets Windows, and those platforms are not in the
framework.

**C-02 · `main.rs:234` called `and_value_str()` on the wrong type.** `Value::get` returns
`Option<&Value>` and the trait is implemented on `Value`, so the call was
`.and_then(JsonValueExt::and_value_str)`.

**C-03 · `main.rs:288` built a `StreamConfig` without `buffer_size`.** `cpal` 0.15 requires
the field; it is `BufferSize::Default`.

**C-04 · the audio layer could not cross a thread, and the design depended on it.**
`cpal::Stream` is neither `Send` nor `Sync` on any platform. `AudioRecorder` held the stream
and was shared as `Arc<Mutex<AudioRecorder>>`, which the arming timer moved into
`std::thread::spawn` — a bound the type can never satisfy. This is a design defect rather
than a slip, and the fix is the shape `cpal` requires: one thread owns the stream and the
writer for the life of the process, and the rest of the program addresses it through an
`mpsc` channel. `Stop` is acknowledged rather than fired and forgotten, because the caller
hands the file to the engine as soon as it returns and the WAV header must already be
written.

C-04 changes when the microphone can fail to open: the arming thread now waits for the audio
thread's answer instead of holding a lock. Row 2 measures that path.

## First run, 2026-09-04

Compiling was not running. Three more defects stood between a binary that built and an
application that did anything, and each was found by instrumenting the path rather than by
reading it.

**C-05 · the adapter had no `capabilities/` directory, so the interface was inert.** Tauri v2
grants a webview nothing until a capability file says otherwise. `window.__TAURI__.event` was
therefore absent, `app.js` took its standalone-preview branch, and the capsule painted READY
once and never moved again — through recordings, refusals and errors alike. It looked like a
trigger that did nothing. `capabilities/default.json` grants `core:default` to the `main`
window, and the capsule now reports `ERROR` and `TERMINAL` where it reported nothing.

**C-06 · the microphone was asked for a format no device on this machine offers.** The stream
was built against a hardcoded `StreamConfig` of 1 channel at 16 kHz. WASAPI in shared mode
hands out the format the device already runs at and refuses anything else, so every arming
ended in `Failed to build audio stream: The requested stream configuration is not supported by
the device.` This machine's Realtek input runs at **48 000 Hz, 2 channels, F32**. The stream
now takes the device's own `default_input_config()` and the conversion to the 16 kHz mono WAV
whisper.cpp requires happens on the way to the file: channels averaged per frame, then a box
filter over each output period. The measurement in row 4 is that conversion checked against
the clock.

**C-07 · `rdev::listen`'s error was discarded by `let _ =`.** A listener that fails to install
and a trigger that is never pressed produced the same silence. The refusal was reported
from that build; the listener was later replaced by the poll described under Trigger.

Two facts about this machine that cost time and belong here. First, the adapter must be
launched from the owner's own terminal: a global keyboard hook installed from a sandboxed
shell receives no input, and the same instrumentation that printed nothing there printed every
key when she ran it. Second, the trigger, the capture and the interface were each proved
separately, in that order; before C-05 was found the capsule could not report what the other
two were doing.

## Review of the first holds, 2026-09-04

Four short holds were run from the owner's terminal and their instrumentation read back
against the code. The capture instrumentation printed:

```text
0 samples = 0.00 s of audio, microphone open 0.07 s, ratio 0.000
7040 samples = 0.44 s of audio, microphone open 0.50 s, ratio 0.872
6880 samples = 0.43 s of audio, microphone open 0.49 s, ratio 0.879
```

**The ratio is length-dependent and the shortfall is constant.** Against row 4's 25.46 s
hold the four readings lose 0.07, 0.06, 0.06 and 0.07 s of audio. A conversion that drifted
would lose a share of the take; this loses the same 60 to 70 ms whatever the take. That is
the interval between `stream.play()` returning, where the clock starts, and WASAPI
delivering its first buffer. The conversion does not drift, and a ratio of 0.87 on a half-
second hold is the same healthy machine as 0.997 on a long one. The consequence that does
belong to the product: the first 60 to 70 ms after the microphone opens carries no audio,
which sits inside the 500 ms arming delay a speaker already waits out. The third reading is
the floor of that — a release 70 ms after the arming point writes a WAV of zero samples,
which the engine's silence guard names as no audible speech rather than passing to whisper.

Two defects were found by this review rather than by a failed run, and both are fixed.

**C-08 · the downsampler applied a gain that wobbled, at every rate but this machine's.**
`Downsampler::push` reset `sum` to zero on emitting a sample but carried the fractional
remainder in the same counter it divided by, so each average after the first divided a whole
number of frames by a larger number. At 48 kHz `frames_per_sample` is exactly 3.0, the
remainder is always zero, and the defect is invisible — which is why the first run did not
show it. At 44.1 kHz a constant full-scale input came out as `1.000 0.925 0.860 0.804 0.672`
repeating: a gain wobble reaching −3.5 dB every four samples, a 4 kHz tone the microphone
never heard, inside the band whisper listens to. The counter is now two: `summed` counts the
frames the average divides by, `phase` carries the remainder. A unit test drives a constant
input through 16 000, 44 100, 48 000 and 96 000 Hz and asserts a constant output at the right
length; against the old divisor it fails at 44 100 Hz with 21 879 against 32 767.

**C-09 · a second hold taken during transcription was lost and reported as too short.**
`IS_RECORDING` was documented as the flag that keeps a second hold from starting while the
first is still being transcribed, and it was cleared at the release instead — before the
engine ran. A hold started in that window was therefore accepted by the hook and queued, and
the worker, reaching it only after the first dictation finished, found the release already in
the channel and answered `TOO SHORT` however long the key had been held. No microphone
opened. The flag is now `DICTATION_IN_FLIGHT`, cleared at the end of the whole dictation, and
a hold arriving inside that window is refused at the hook. Escape moved to its own flag,
`TRIGGER_HELD`, which spans the press to the release and nothing after, so Escape is taken
out of the input stream only while it means cancel and is left alone during transcription.

A refused hold is silent: the capsule is showing `PROCESSING`, which is the honest answer,
but the speaker gets no separate acknowledgement that the second hold was declined. Row 2
records what that feels like in use.

`cargo test` passes and `cargo check` is clean, with no warnings.

## Gate criteria

Gate 5 closes when rows 1 through 11 are recorded with results and none of them is a
failure the product accepts. Row 12 is a decision this machine makes for itself; the
Mac's default does not carry over.

R9 governs every figure written into this file: it is the measurement of the run it
describes, it carries its date, or it is not written.
