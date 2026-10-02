// sanblueᵈᵒᵗ VoiceFlow — Windows Native Platform Adapter (Tauri v2)
// Gate 5 Implementation: Push-to-Talk, Audio Capture, and Win32 Auto-Paste

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod capture;
mod delivery;
mod hub;
mod models;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use hound::{WavSpec, WavWriter};
use std::path::PathBuf;
use std::sync::mpsc;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tauri::{Emitter, Manager};

#[cfg(windows)]
use windows::Win32::Foundation::{CloseHandle, HWND};
#[cfg(windows)]
use windows::Win32::System::ProcessStatus::GetProcessImageFileNameW;
#[cfg(windows)]
use windows::Win32::System::Threading::{OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION};
#[cfg(windows)]
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS,
    KEYEVENTF_KEYUP, VIRTUAL_KEY, VK_CONTROL, VK_ESCAPE, VK_LWIN, VK_MENU, VK_RCONTROL, VK_RWIN,
    VK_SHIFT,
};
#[cfg(windows)]
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

static CAPTURE: Mutex<capture::Gate> = Mutex::new(capture::Gate::new());

struct Runtime {
    triggers: mpsc::Sender<Trigger>,
    snapshot: Mutex<hub::Snapshot>,
    preferences_path: PathBuf,
    history_path: PathBuf,
}

/// Keep the session's transcripts so they are still there after a restart.
///
/// These are the owner's own words, so the file is local, carries the `.local.json`
/// suffix version control already excludes, and is deleted outright when the history is
/// cleared rather than left behind emptied.
fn persist_history(runtime: &Runtime) {
    let entries = {
        let state = runtime.snapshot.lock().unwrap();
        state.history.clone()
    };
    if entries.is_empty() {
        let _ = std::fs::remove_file(&runtime.history_path);
        return;
    }
    let Some(parent) = runtime.history_path.parent() else { return };
    if std::fs::create_dir_all(parent).is_err() {
        return;
    }
    let Ok(bytes) = serde_json::to_vec_pretty(&entries) else { return };
    // Written aside and renamed: a partial write must not replace a good history.
    let temporary = parent.join(format!(".history-{}.tmp", std::process::id()));
    if std::fs::write(&temporary, bytes).is_ok() {
        if std::fs::rename(&temporary, &runtime.history_path).is_err() {
            let _ = std::fs::remove_file(&temporary);
        }
    } else {
        let _ = std::fs::remove_file(&temporary);
    }
}

fn publish_hub(app: &tauri::AppHandle) {
    let runtime = app.state::<Runtime>();
    let snapshot = {
        let mut state = runtime.snapshot.lock().unwrap();
        state.revision += 1;
        state.clone()
    };
    let _ = app.emit_to("station", "hub:state", snapshot);
}

fn publish_mode(app: &tauri::AppHandle, payload: ModePayload) {
    {
        let runtime = app.state::<Runtime>();
        let mut state = runtime.snapshot.lock().unwrap();
        state.status = payload.mode.clone();
        state.error = payload.error.clone();
        let (category, tag, message) = match payload.mode.as_str() {
            "arming" => (
                "capture",
                "MIC",
                "Hold detected; waiting to open the microphone.",
            ),
            "recording" => (
                "capture",
                "MIC",
                "Microphone opened. Release to transcribe.",
            ),
            "processing" => ("capture", "WHISPER", "Transcribing locally with Whisper."),
            "completed" if payload.did_auto_paste => (
                "system",
                "SYS",
                "Text copied; Windows accepted the paste input.",
            ),
            "completed" => ("system", "SYS", "Text copied to the clipboard."),
            "cancelled" => (
                "capture",
                "MIC",
                "Recording cancelled; no transcript created.",
            ),
            "too_short" => (
                "capture",
                "WARN",
                "Hold too short; microphone stayed closed.",
            ),
            "refused" => (
                "capture",
                "WARN",
                payload
                    .error
                    .as_deref()
                    .unwrap_or("The trigger was refused before the microphone opened."),
            ),
            "failed" => (
                "error",
                "ERROR",
                payload.error.as_deref().unwrap_or("Dictation failed."),
            ),
            "not_configured" => (
                "system",
                "SYS",
                "Provider setup required; microphone remains closed.",
            ),
            "ready" => ("system", "SYS", "Ready for local dictation."),
            _ => ("system", "SYS", payload.mode.as_str()),
        };
        state.note(category, tag, message);
    }
    let _ = app.emit("hud:mode", payload);
    publish_hub(app);
}

fn request_press(app: &tauri::AppHandle, source: capture::Source) -> Result<(), String> {
    // The provider and the model are settled before the capture lock is taken. Both read
    // the file system, and every station command waits on that lock, so holding it across
    // a canonicalize and a header read stalls the interface on each press.
    let unavailable = app.state::<Runtime>().snapshot.lock().unwrap().capture_error();
    if let Some(error) = unavailable {
        emit_mode_with_error(app, "refused", Some(error.clone()));
        return Err(error);
    }
    let selected = app.state::<Runtime>().snapshot.lock().unwrap().preferences.speech_model.clone();
    let directory = resolve_project_root().join("models");
    let name = models::selected_name(&directory, selected.as_deref());
    if let Err(error) = models::validate(&directory, &name) {
        emit_mode_with_error(app, "refused", Some(error.clone()));
        return Err(error);
    }

    let mut gate = CAPTURE.lock().map_err(|_| "Capture is unavailable.")?;
    if !gate.press(source) {
        return Err("A dictation is already in progress.".into());
    }
    app.state::<Runtime>().snapshot.lock().unwrap().model = name;
    emit_mode(app, "arming");
    if app
        .state::<Runtime>()
        .triggers
        .send(Trigger::Pressed)
        .is_err()
    {
        gate.finish();
        return Err("The capture worker is unavailable.".into());
    }
    Ok(())
}

fn request_release(app: &tauri::AppHandle, source: capture::Source) -> Result<(), String> {
    let mut gate = CAPTURE.lock().map_err(|_| "Capture is unavailable.")?;
    if gate.release(source) {
        app.state::<Runtime>()
            .triggers
            .send(Trigger::Released)
            .map_err(|_| "The capture worker is unavailable.")?;
    }
    Ok(())
}

fn request_cancel(app: &tauri::AppHandle) -> Result<(), String> {
    let mut gate = CAPTURE.lock().map_err(|_| "Capture is unavailable.")?;
    if gate.cancel() {
        app.state::<Runtime>()
            .triggers
            .send(Trigger::Cancelled)
            .map_err(|_| "The capture worker is unavailable.")?;
    }
    Ok(())
}

const DEFAULT_HOLD_DELAY_MS: u64 = 0;

/// R1: Instant push-to-talk by default (0 ms), configurable up to 3000 ms via VOICEFLOW_HOLD_DELAY_MS.
fn hold_delay() -> Duration {
    let millis = std::env::var("VOICEFLOW_HOLD_DELAY_MS")
        .ok()
        .and_then(|value| value.parse::<u64>().ok())
        .filter(|millis| *millis <= 3_000)
        .unwrap_or(DEFAULT_HOLD_DELAY_MS);
    Duration::from_millis(millis)
}

#[derive(serde::Serialize, Clone)]
struct ModePayload {
    mode: String,
    context: Option<String>,
    wpm: Option<u32>,
    latency: Option<f64>,
    cleaner: Option<String>,
    did_auto_paste: bool,
    unrecognized_command: bool,
    error: Option<String>,
}

#[derive(Clone, Debug)]
struct TargetWindowInfo {
    #[cfg(windows)]
    hwnd: HWND,
    name: String,
    process_name: String,
    is_terminal: bool,
    process_id: u32,
    identified: bool,
}

fn get_active_window_info() -> TargetWindowInfo {
    #[cfg(windows)]
    unsafe {
        let hwnd: HWND = GetForegroundWindow();
        if hwnd.0.is_null() {
            return TargetWindowInfo {
                hwnd,
                name: "DESKTOP".to_string(),
                process_name: String::new(),
                is_terminal: false,
                process_id: 0,
                identified: false,
            };
        }

        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 {
            return TargetWindowInfo {
                hwnd,
                name: "UNKNOWN".to_string(),
                process_name: String::new(),
                is_terminal: false,
                process_id: 0,
                identified: false,
            };
        }

        let mut is_terminal = false;
        let mut process_name = String::new();
        let mut identified = false;
        let mut display_name = format!("PID_{}", pid);

        if let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
            let mut buf = [0u16; 512];
            let len = GetProcessImageFileNameW(handle, &mut buf);
            let _ = CloseHandle(handle);

            if len > 0 {
                identified = true;
                let full_path = String::from_utf16_lossy(&buf[..len as usize]);
                let file_name = full_path
                    .split('\\')
                    .last()
                    .unwrap_or(&full_path)
                    .to_lowercase();

                process_name = file_name.clone();
                if delivery::terminal_process(&file_name) {
                    is_terminal = true;
                    display_name = "TERMINAL".to_string();
                } else if file_name.contains("code") {
                    display_name = "VSCODE".to_string();
                } else if file_name.contains("chrome") {
                    display_name = "CHROME".to_string();
                } else {
                    display_name = file_name.trim_end_matches(".exe").to_uppercase();
                }
            }
        }

        TargetWindowInfo {
            hwnd,
            name: display_name,
            process_name,
            is_terminal,
            process_id: pid,
            identified,
        }
    }

    #[cfg(not(windows))]
    TargetWindowInfo {
        name: "NON_WINDOWS".to_string(),
        process_name: String::new(),
        is_terminal: false,
        process_id: 0,
        identified: false,
    }
}

fn simulate_paste(target: &TargetWindowInfo, shortcut: &str) -> bool {
    #[cfg(windows)]
    unsafe {
        // Never release physical modifiers or pull focus back from another app.
        let current = get_active_window_info();
        let modifiers_down = [VK_CONTROL, VK_MENU, VK_SHIFT, VK_LWIN, VK_RWIN]
            .iter()
            .any(|key| (GetAsyncKeyState(key.0 as i32) as u16 & 0x8000) != 0);
        if !delivery::paste_allowed(
            target.identified && current.identified,
            target.process_id == std::process::id(),
            !target.hwnd.0.is_null() && current.hwnd.0 == target.hwnd.0,
            current.process_id == target.process_id,
            modifiers_down,
        ) {
            return false;
        }

        // Which chord pastes depends on the destination: Ctrl+V types a literal `v` in
        // mintty, PuTTY and kitty, where the paste is Shift+Insert. `paste_keys` owns
        // that decision and the owner's explicit override; this function only sends it.
        let chord = delivery::paste_keys(shortcut, &target.process_name);
        if chord.is_empty() {
            return false;
        }

        // Pressed in order and released in reverse, so the modifiers are still down when
        // the action key arrives and are all up again when the sequence ends.
        let mut inputs: Vec<INPUT> = Vec::with_capacity(chord.len() * 2);
        for (code, flags) in chord
            .iter()
            .map(|code| (*code, KEYBD_EVENT_FLAGS(0)))
            .chain(chord.iter().rev().map(|code| (*code, KEYEVENTF_KEYUP)))
        {
            let mut input: INPUT = std::mem::zeroed();
            input.r#type = INPUT_KEYBOARD;
            input.Anonymous.ki = KEYBDINPUT {
                wVk: VIRTUAL_KEY(code),
                wScan: 0,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: 0,
            };
            inputs.push(input);
        }
        // The releases are the tail of the sequence, one per key held.
        let releases = chord.len();

        // Re-check at dispatch, after process inspection and input construction.
        if GetForegroundWindow().0 != target.hwnd.0 {
            return false;
        }
        let inserted = SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
        if inserted != inputs.len() as u32 {
            // A partially accepted sequence may have left our synthetic modifiers down.
            if inserted > 0 {
                SendInput(&inputs[releases..], std::mem::size_of::<INPUT>() as i32);
            }
            return false;
        }
        true
    }
    #[cfg(not(windows))]
    {
        let _ = (target, shortcut);
        false
    }
}

fn project_root_from(start: &std::path::Path) -> Option<PathBuf> {
    start
        .ancestors()
        .find(|candidate| candidate.join("src/sanbluedot_voiceflow").is_dir())
        .map(|candidate| candidate.to_path_buf())
}

fn resolve_project_root() -> PathBuf {
    std::env::current_exe()
        .ok()
        .and_then(|path| project_root_from(&path))
        .or_else(|| {
            std::env::current_dir()
                .ok()
                .and_then(|path| project_root_from(&path))
        })
        .unwrap_or_else(|| PathBuf::from("."))
}

fn resolve_whisper_model(selected: Option<&str>) -> PathBuf {
    let directory = resolve_project_root().join("models");
    directory.join(models::selected_name(&directory, selected))
}

fn engine_command(
    audio_path: &PathBuf,
    whisper_model: &PathBuf,
    cleaner: &str,
    ollama_model: Option<&str>,
) -> std::process::Command {
    // Resolve project root (contains src/sanbluedot_voiceflow)
    let project_root = resolve_project_root();

    let src_dir = project_root.join("src");
    let whisper_bin = project_root.join("models").join("whisper-cli.exe");
    let model_full_path = if whisper_model.is_absolute() {
        whisper_model.clone()
    } else {
        project_root.join(whisper_model)
    };

    let mut cmd = std::process::Command::new("python");
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        // A desktop dictation must not open a console or change the focused window.
        cmd.creation_flags(0x08000000); // CREATE_NO_WINDOW
    }
    cmd.current_dir(&project_root);
    cmd.env("PYTHONPATH", &src_dir);
    // Redirected Python output otherwise uses the Windows locale code page while
    // Rust reads UTF-8. Preserve Spanish, mixed-language text and emoji end to end.
    cmd.env("PYTHONIOENCODING", "utf-8");
    cmd.env("PYTHONUTF8", "1");
    cmd.args([
        "-m",
        "sanbluedot_voiceflow",
        "process",
        audio_path.to_str().unwrap_or_default(),
        "--whisper-bin",
        whisper_bin.to_str().unwrap_or_default(),
        "--whisper-model",
        model_full_path.to_str().unwrap_or_default(),
        "--cleaner",
        cleaner,
        "--json",
    ]);
    // Only the local route takes a model name, and only a checked one reaches here.
    if let Some(model) = ollama_model.filter(|_| cleaner == "ollama") {
        cmd.args(["--ollama-model", model]);
    }

    cmd
}

fn run_engine_process(
    audio_path: &PathBuf,
    whisper_model: &PathBuf,
    cleaner: &str,
    ollama_model: Option<&str>,
) -> Result<serde_json::Value, String> {
    let output = engine_command(audio_path, whisper_model, cleaner, ollama_model)
        .output()
        .map_err(|e| format!("Failed to invoke python engine: {}", e))?;

    if !output.status.success() && output.status.code() != Some(2) {
        let stderr = String::from_utf8_lossy(&output.stderr);
        eprintln!("voiceflow: engine execution error: {}", stderr);
        return Err(format!("Engine execution error: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(&stdout).map_err(|e| format!("Failed to parse engine JSON: {}", e))
}

fn recorded_audio_seconds(path: &std::path::Path) -> Option<f64> {
    let wav = hound::WavReader::open(path).ok()?;
    let rate = wav.spec().sample_rate;
    (rate > 0).then(|| wav.duration() as f64 / rate as f64)
}

fn copy_delivery_text(text: &str, app_handle: &tauri::AppHandle) -> Result<(), String> {
    if text.trim().is_empty() || text.contains('\0') {
        return Err("Cannot copy empty text or text containing NUL.".into());
    }
    #[cfg(windows)]
    {
        let window = app_handle
            .get_webview_window("main")
            .ok_or("VoiceFlow's clipboard owner window is unavailable.")?;
        let owner = window
            .hwnd()
            .map_err(|e| format!("Clipboard window unavailable: {e}"))?;
        delivery::copy_unicode(text, HWND(owner.0))
    }
    #[cfg(not(windows))]
    {
        let _ = (text, app_handle);
        Err("Windows clipboard is unavailable.".into())
    }
}

type AudioSampleSender = mpsc::Sender<Vec<i16>>;

/// `cpal::Stream` is neither `Send` nor `Sync` on any platform, so it cannot sit inside a
/// value that crosses threads — and the arming timer runs on a thread of its own. The
/// stream therefore stays on one thread that owns it for the life of the process, and
/// everything else addresses that thread by message.
enum AudioCommand {
    Start {
        output_path: PathBuf,
        app_handle: tauri::AppHandle,
        ack: mpsc::Sender<Result<(), String>>,
    },
    /// Answered rather than fired and forgotten: the caller hands the file to the engine as
    /// soon as this returns, so the stream must be closed and the header written by then.
    Stop {
        ack: mpsc::Sender<Result<(), String>>,
    },
}

struct AudioRecorder {
    commands: mpsc::Sender<AudioCommand>,
}

impl AudioRecorder {
    fn new() -> Self {
        let (commands, inbox) = mpsc::channel();
        std::thread::spawn(move || run_audio_thread(inbox));
        Self { commands }
    }

    fn start_recording(
        &mut self,
        output_path: PathBuf,
        app_handle: tauri::AppHandle,
    ) -> Result<(), String> {
        let (ack, answer) = mpsc::channel();
        self.commands
            .send(AudioCommand::Start {
                output_path,
                app_handle,
                ack,
            })
            .map_err(|_| "The audio thread is no longer running".to_string())?;
        answer
            .recv()
            .map_err(|_| "The audio thread stopped without answering".to_string())?
    }

    fn stop_recording(&mut self) -> Result<(), String> {
        let (ack, answer) = mpsc::channel();
        self.commands
            .send(AudioCommand::Stop { ack })
            .map_err(|_| "The audio thread is no longer running".to_string())?;
        answer
            .recv()
            .map_err(|_| "The audio thread stopped without finalizing the recording".to_string())?
    }
}

/// Owns the input stream and writer thread handle. Nothing outside this thread touches either.
fn run_audio_thread(inbox: mpsc::Receiver<AudioCommand>) {
    let mut stream: Option<cpal::Stream> = None;
    let mut writer_tx: Option<AudioSampleSender> = None;
    let mut writer_join: Option<std::thread::JoinHandle<Result<(), String>>> = None;
    let mut opened_at: Option<Instant> = None;

    while let Ok(command) = inbox.recv() {
        match command {
            AudioCommand::Start {
                output_path,
                app_handle,
                ack,
            } => match open_input_stream(output_path, app_handle) {
                Ok((opened_stream, sample_tx, join_handle)) => {
                    stream = Some(opened_stream);
                    writer_tx = Some(sample_tx);
                    writer_join = Some(join_handle);
                    opened_at = Some(Instant::now());
                    let _ = ack.send(Ok(()));
                }
                Err(message) => {
                    let _ = ack.send(Err(message));
                }
            },
            AudioCommand::Stop { ack } => {
                // 1. Drop stream first so the audio callback ceases sending samples.
                drop(stream.take());
                // 2. Drop the sender channel so the writer thread reaches EOF.
                drop(writer_tx.take());
                // 3. Wait for writer thread to drain and finalize the WAV header.
                let result = writer_join
                    .take()
                    .map(|join_handle| {
                        join_handle.join().unwrap_or_else(|_| {
                            Err("The recording writer stopped unexpectedly.".into())
                        })
                    })
                    .unwrap_or(Ok(()));
                if let Some(started) = opened_at.take() {
                    let wall = started.elapsed().as_secs_f32();
                    eprintln!("voiceflow: microphone closed, total hold {:.2} s", wall);
                }
                let _ = ack.send(result);
            }
        }
    }
}

/// What whisper.cpp reads. The WAV is written at this rate whatever the device runs at.
const TARGET_SAMPLE_RATE: u32 = 16_000;

/// Folds the device's interleaved frames into the single 16 kHz channel the WAV holds.
///
/// Averaging the frames that fall inside one output period is a box filter. It is crude,
/// but decimating 48 kHz by three without any filter folds everything above 8 kHz back
/// into the speech band, and that lands inside the range whisper listens to.
struct Downsampler {
    channels: usize,
    /// Source frames per output sample. Rarely a whole number: 44 100 Hz gives 2.756.
    frames_per_sample: f32,
    sum: f32,
    /// How many frames `sum` holds. The average divides by this and by nothing else.
    summed: f32,
    /// How far the next output sample is from the last one, in source frames. It carries
    /// the fractional remainder, which is what keeps a non-integer rate from drifting the
    /// output slower than real time.
    phase: f32,
}

impl Downsampler {
    fn new(source_rate: u32, channels: usize) -> Self {
        Self {
            channels: channels.max(1),
            frames_per_sample: source_rate as f32 / TARGET_SAMPLE_RATE as f32,
            sum: 0.0,
            summed: 0.0,
            phase: 0.0,
        }
    }

    /// Appends the 16 kHz mono samples these interleaved frames produced.
    fn push(&mut self, frames: &[f32], out: &mut Vec<i16>) {
        for frame in frames.chunks(self.channels) {
            if frame.is_empty() {
                continue;
            }
            self.sum += frame.iter().sum::<f32>() / frame.len() as f32;
            self.summed += 1.0;
            self.phase += 1.0;

            if self.phase >= self.frames_per_sample {
                // The divisor is the number of frames actually summed. Dividing by the
                // phase instead scales every sample after the first by the remainder the
                // phase carries: at 44 100 Hz that is a gain wobbling down to -3.5 dB and
                // repeating every four samples, which is a tone the microphone never heard.
                let averaged = self.sum / self.summed;
                out.push((averaged.clamp(-1.0, 1.0) * 32767.0) as i16);
                self.phase -= self.frames_per_sample;
                if self.phase < 0.0 {
                    self.phase = 0.0;
                }
                self.sum = 0.0;
                self.summed = 0.0;
            }
        }
    }
}

fn root_mean_square(frames: &[f32]) -> f32 {
    if frames.is_empty() {
        return 0.0;
    }
    let sum_squares: f32 = frames.iter().map(|sample| sample * sample).sum();
    (sum_squares / frames.len() as f32).sqrt()
}

/// How often the meter reading leaves the audio thread.
///
/// The callback runs on the order of a hundred times a second and each emit crosses into
/// both webviews. Thirty a second is past what the eye resolves on a twelve-bar meter and
/// well inside the controller's 240 ms missing-update timeout, so the display still
/// settles on silence. Samples are never throttled; only the reading is.
const METER_INTERVAL: Duration = Duration::from_millis(33);

/// Sends what the downsampler produced to the WAV writer thread and moves the meter.
fn deliver(
    mono: &[i16],
    level: f32,
    tx: &AudioSampleSender,
    app_handle: &tauri::AppHandle,
    last_meter: &mut Instant,
) {
    if !mono.is_empty() {
        let _ = tx.send(mono.to_vec());
    }
    if last_meter.elapsed() >= METER_INTERVAL {
        *last_meter = Instant::now();
        let _ = app_handle.emit("hud:vu-level", (level * 5.0).min(1.0));
    }
}

fn open_input_stream(
    output_path: PathBuf,
    app_handle: tauri::AppHandle,
) -> Result<
    (
        cpal::Stream,
        AudioSampleSender,
        std::thread::JoinHandle<Result<(), String>>,
    ),
    String,
> {
    let host = cpal::default_host();
    let device = host
        .default_input_device()
        .ok_or_else(|| "No audio input device found".to_string())?;

    let default_config = device
        .default_input_config()
        .map_err(|e| format!("The input device reported no usable format: {}", e))?;
    let sample_format = default_config.sample_format();
    let config: cpal::StreamConfig = default_config.into();
    let source_rate = config.sample_rate.0;
    let channels = config.channels as usize;
    let dev_name = device.name().unwrap_or_else(|_| "unknown".to_string());
    eprintln!(
        "voiceflow: input device \"{}\" runs at {} Hz, {} channel(s), {:?}",
        dev_name, source_rate, channels, sample_format
    );

    let spec = WavSpec {
        channels: 1,
        sample_rate: TARGET_SAMPLE_RATE,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };

    let mut wav_writer = WavWriter::create(&output_path, spec)
        .map_err(|e| format!("Failed to create WAV: {}", e))?;

    let (sample_tx, sample_rx) = mpsc::channel::<Vec<i16>>();

    let stream_error = Arc::new(Mutex::new(None::<String>));
    let writer_error = stream_error.clone();
    let join_handle = std::thread::spawn(move || {
        let mut total_samples: u64 = 0;
        let mut sum_squares: f64 = 0.0;
        let mut write_error = None;

        while let Ok(samples) = sample_rx.recv() {
            for sample in samples {
                if write_error.is_none() {
                    if let Err(error) = wav_writer.write_sample(sample) {
                        write_error = Some(format!("Failed to write recording: {error}"));
                    }
                }
                sum_squares += (sample as f64) * (sample as f64);
                total_samples += 1;
            }
        }

        let recorded_secs = total_samples as f32 / TARGET_SAMPLE_RATE as f32;
        let rms = if total_samples > 0 {
            ((sum_squares / total_samples as f64).sqrt()) / 32768.0
        } else {
            0.0
        };

        let finalized = wav_writer
            .finalize()
            .map_err(|error| format!("Failed to finalize recording: {error}"));
        if let Some(error) = write_error.or_else(|| writer_error.lock().unwrap().clone()) {
            return Err(error);
        }
        finalized?;
        eprintln!(
            "voiceflow: finalized {} samples ({:.2} s), RMS: {:.5}",
            total_samples, recorded_secs, rms
        );
        Ok(())
    });

    let err_fn = move |err| {
        *stream_error.lock().unwrap() = Some(format!("Audio stream error: {err}"));
    };

    let build = |tx: AudioSampleSender, handle: tauri::AppHandle| {
        (
            tx,
            handle,
            Downsampler::new(source_rate, channels),
            Vec::<i16>::new(),
            Instant::now() - METER_INTERVAL,
        )
    };

    let opened = (|| {
        let stream = match sample_format {
            cpal::SampleFormat::F32 => {
                let (tx, handle, mut down, mut mono, mut meter) = build(sample_tx.clone(), app_handle.clone());
                device.build_input_stream(
                    &config,
                    move |frames: &[f32], _: &_| {
                        mono.clear();
                        down.push(frames, &mut mono);
                        deliver(&mono, root_mean_square(frames), &tx, &handle, &mut meter);
                    },
                    err_fn,
                    None,
                )
            }
            cpal::SampleFormat::I16 => {
                let (tx, handle, mut down, mut mono, mut meter) = build(sample_tx.clone(), app_handle.clone());
                let mut floats: Vec<f32> = Vec::new();
                device.build_input_stream(
                    &config,
                    move |frames: &[i16], _: &_| {
                        floats.clear();
                        floats.extend(frames.iter().map(|&s| s as f32 / 32768.0));
                        mono.clear();
                        down.push(&floats, &mut mono);
                        deliver(&mono, root_mean_square(&floats), &tx, &handle, &mut meter);
                    },
                    err_fn,
                    None,
                )
            }
            cpal::SampleFormat::U16 => {
                let (tx, handle, mut down, mut mono, mut meter) = build(sample_tx.clone(), app_handle.clone());
                let mut floats: Vec<f32> = Vec::new();
                device.build_input_stream(
                    &config,
                    move |frames: &[u16], _: &_| {
                        floats.clear();
                        floats.extend(frames.iter().map(|&s| (s as f32 - 32768.0) / 32768.0));
                        mono.clear();
                        down.push(&floats, &mut mono);
                        deliver(&mono, root_mean_square(&floats), &tx, &handle, &mut meter);
                    },
                    err_fn,
                    None,
                )
            }
            other => {
                return Err(format!(
                    "The input device offers a sample format this build cannot read: {:?}",
                    other
                ))
            }
        }
        .map_err(|e| format!("Failed to build audio stream: {}", e))?;

        stream
            .play()
            .map_err(|e| format!("Failed to start audio stream: {}", e))?;
        Ok::<cpal::Stream, String>(stream)
    })();
    let stream = match opened {
        Ok(stream) => stream,
        Err(error) => {
            drop(sample_tx);
            let _ = join_handle.join();
            return Err(error);
        }
    };

    Ok((stream, sample_tx, join_handle))
}

/// What the keyboard hook tells the worker, and the whole of what the hook does.
///
/// A low-level hook runs on the thread that installed it, and every keystroke on the
/// machine waits behind it. Windows removes a hook that overruns `LowLevelHooksTimeout`
/// — about 300 ms — without saying so, and the trigger then stops working with no error
/// anywhere. Opening a process to name the foreground window, waiting on the audio
/// thread, deleting a file and running the transcription engine all used to happen here.
enum Trigger {
    Pressed,
    Released,
    Cancelled,
}

/// The plain modes carry no measurement. The two that do are built where they are sent.
fn emit_mode(app_handle: &tauri::AppHandle, mode: &str) {
    emit_mode_with_error(app_handle, mode, None);
}

fn emit_mode_with_error(app_handle: &tauri::AppHandle, mode: &str, error: Option<String>) {
    publish_mode(
        app_handle,
        ModePayload {
            mode: mode.to_string(),
            context: None,
            wpm: None,
            latency: None,
            cleaner: None,
            did_auto_paste: false,
            unrecognized_command: false,
            error,
        },
    );
}

/// Owns one dictation from the press to the pasted text. Everything slow lives here.
fn run_trigger_worker(
    inbox: mpsc::Receiver<Trigger>,
    app_handle: tauri::AppHandle,
    recorder: Arc<Mutex<AudioRecorder>>,
) {
    let temp_audio = std::env::temp_dir().join(format!(
        "voiceflow_recording_{}_{}.wav",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap_or_default()
            .as_nanos()
    ));

    loop {
        // A release or a cancel with no hold behind it is the tail of the previous
        // dictation arriving late. It starts nothing.
        match inbox.recv() {
            Ok(Trigger::Pressed) => {}
            Ok(_) => continue,
            Err(_) => return,
        }

        // The target is read now rather than at the end: this is the window the speaker
        // was looking at when the hold began.
        let target = get_active_window_info();

        // If hold_delay is greater than 0, wait for hold_delay to filter accidental brush.
        // If hold_delay is 0 (default), open immediately with sub-frame responsiveness!
        let preferences = app_handle
            .state::<Runtime>()
            .snapshot
            .lock()
            .unwrap()
            .preferences
            .clone();
        let delay = Duration::from_millis(preferences.hold_delay_ms);
        let (whisper_model, cleaner, ollama_model) = {
            let state = app_handle.state::<Runtime>();
            let snapshot = state.snapshot.lock().unwrap();
            (
                resolve_project_root().join("models").join(snapshot.model.clone()),
                snapshot.provider.cleaner().to_string(),
                snapshot.preferences.ollama_model.clone(),
            )
        };
        if delay > Duration::from_millis(0) {
            match inbox.recv_timeout(delay) {
                Err(mpsc::RecvTimeoutError::Timeout) => {}
                Err(mpsc::RecvTimeoutError::Disconnected) => return,
                Ok(Trigger::Released) => {
                    CAPTURE.lock().unwrap().finish();
                    emit_mode(&app_handle, "too_short");
                    continue;
                }
                Ok(_) => {
                    CAPTURE.lock().unwrap().finish();
                    emit_mode(&app_handle, "cancelled");
                    continue;
                }
            }
        }

        let opened = recorder
            .lock()
            .map_err(|_| "The recorder is unavailable.".to_string())
            .and_then(|mut rec| rec.start_recording(temp_audio.clone(), app_handle.clone()));
        if let Err(message) = opened {
            let _ = std::fs::remove_file(&temp_audio);
            CAPTURE.lock().unwrap().finish();
            emit_mode_with_error(&app_handle, "failed", Some(message));
            continue;
        }

        publish_mode(
            &app_handle,
            ModePayload {
                mode: "recording".to_string(),
                context: Some(target.name.clone()),
                wpm: None,
                latency: None,
                cleaner: None,
                did_auto_paste: false,
                unrecognized_command: false,
                error: None,
            },
        );

        let ending = inbox.recv();
        let audio_result = recorder
            .lock()
            .map_err(|_| "The recorder is unavailable.".to_string())
            .and_then(|mut rec| rec.stop_recording());

        match ending {
            Ok(Trigger::Released) => {}
            Ok(_) => {
                // R1: a take-back deletes the audio rather than transcribing it, and
                // writes no history.
                let _ = std::fs::remove_file(&temp_audio);
                emit_mode(&app_handle, "cancelled");
                CAPTURE.lock().unwrap().finish();
                continue;
            }
            Err(_) => {
                let _ = std::fs::remove_file(&temp_audio);
                return;
            }
        }

        if let Err(error) = audio_result {
            let _ = std::fs::remove_file(&temp_audio);
            CAPTURE.lock().unwrap().finish();
            emit_mode_with_error(&app_handle, "failed", Some(error));
            continue;
        }
        emit_mode(&app_handle, "processing");

        let start_inference = Instant::now();
        let audio_seconds = recorded_audio_seconds(&temp_audio);
        let engine_result =
            run_engine_process(&temp_audio, &whisper_model, &cleaner, ollama_model.as_deref());

        // Strict ephemeral audio cleanup
        let _ = std::fs::remove_file(&temp_audio);

        match engine_result {
            Ok(json_res) => {
                let latency = start_inference.elapsed().as_secs_f64();

                // Extract measured values (R9: no synthetic placeholders)
                let cleaner_name = json_res
                    .get("cleaner")
                    .and_then(|v| v.as_str())
                    .unwrap_or("literal")
                    .to_string();

                let final_text = json_res
                    .get("final_text")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");

                let raw_text = json_res
                    .get("raw_text")
                    .and_then(|v| v.as_str())
                    .unwrap_or("");
                let measured_wpm = delivery::speaking_rate(raw_text, audio_seconds);
                let delivered = delivery::deliver(
                    final_text,
                    target.is_terminal,
                    |text| copy_delivery_text(text, &app_handle),
                    || preferences.auto_paste && simulate_paste(&target, &preferences.paste_shortcut),
                );
                // Retain both versions before reporting a clipboard failure. No disk history.
                {
                    let runtime = app_handle.state::<Runtime>();
                    let mut state = runtime.snapshot.lock().unwrap();
                    state.retain(hub::Entry {
                        id: 0,
                        raw_text: raw_text.into(),
                        final_text: final_text.into(),
                        delivery_text: delivery::output_text(final_text, target.is_terminal),
                        target: target.name.clone(),
                        delivery: match &delivered {
                            Ok(true) => "pasted",
                            Ok(false) => "copied",
                            Err(_) => "copy_failed",
                        }
                        .into(),
                        wpm: measured_wpm,
                        latency,
                        stt_seconds: json_res
                            .get("timings")
                            .and_then(|v| v.get("transcribe_seconds"))
                            .and_then(|v| v.as_f64()),
                        speech_model: whisper_model
                            .file_name()
                            .unwrap_or_default()
                            .to_string_lossy()
                            .into_owned(),
                        cleaner: cleaner_name.clone(),
                        cleanup_seconds: json_res
                            .get("timings")
                            .and_then(|v| v.get("cleanup_seconds"))
                            .and_then(|v| v.as_f64()),
                        fallback_reason: json_res
                            .get("used_fallback")
                            .and_then(|v| v.as_bool())
                            .unwrap_or(false)
                            .then(|| {
                                json_res
                                    .get("fallback_reason")
                                    .and_then(|v| v.as_str())
                                    .unwrap_or("provider")
                                    .to_owned()
                            }),
                    });
                }
                persist_history(&app_handle.state::<Runtime>());
                let did_auto_paste = match delivered {
                    Ok(pasted) => pasted,
                    Err(error) => {
                        emit_mode_with_error(
                            &app_handle,
                            "failed",
                            Some(format!("{error} Your words are available in the station.")),
                        );
                        CAPTURE.lock().unwrap().finish();
                        continue;
                    }
                };

                publish_mode(
                    &app_handle,
                    ModePayload {
                        mode: "completed".to_string(),
                        context: Some(target.name),
                        wpm: measured_wpm,
                        latency: Some(latency),
                        cleaner: Some(cleaner_name),
                        did_auto_paste,
                        unrecognized_command: false,
                        error: None,
                    },
                );
            }
            Err(err) => {
                eprintln!("voiceflow: transcription or engine failure: {}", err);
                emit_mode_with_error(&app_handle, "failed", Some(err));
            }
        }

        // The trigger is free again only here. Between the release and this line the
        // text was still being transcribed and placed, and a hold taken in that window
        // is refused at the hook rather than mis-reported as a touch too short.
        CAPTURE.lock().unwrap().finish();
    }
}

#[tauri::command]
fn start_dragging(window: tauri::WebviewWindow) {
    let _ = window.start_dragging();
}

/// The capsule is a push-to-talk indicator, so it is on screen while a dictation is in
/// flight or its result is still up, and hidden the rest of the time. The controller
/// calls this because it owns the whole lifetime: the timers that return `completed`,
/// `cancelled` and `too_short` to idle run there and never reach this side.
#[tauri::command]
fn set_capsule_visible(window: tauri::WebviewWindow, visible: bool) -> Result<(), String> {
    if window.label() != "main" {
        return Err("This command belongs to the capsule.".into());
    }
    if visible { window.show() } else { window.hide() }.map_err(|e| e.to_string())
}

fn station_only(window: &tauri::WebviewWindow) -> Result<(), String> {
    if window.label() != "station" {
        return Err("This command belongs to the station.".into());
    }
    Ok(())
}

#[tauri::command]
fn get_station(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
) -> Result<hub::Snapshot, String> {
    station_only(&window)?;
    Ok(app.state::<Runtime>().snapshot.lock().unwrap().clone())
}

#[tauri::command]
fn start_capture(window: tauri::WebviewWindow, app: tauri::AppHandle) -> Result<(), String> {
    station_only(&window)?;
    request_press(&app, capture::Source::Button)
}

#[tauri::command]
fn select_provider(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    provider: hub::Provider,
) -> Result<hub::Snapshot, String> {
    station_only(&window)?;
    let gate = CAPTURE.lock().map_err(|_| "Capture is unavailable.")?;
    app.state::<Runtime>()
        .snapshot
        .lock()
        .unwrap()
        .select_provider(provider, gate.busy())?;
    // Choosing a route is a station action, not a dictation. Emitting a capsule mode here
    // put the capsule on screen with nothing to end it, and wrote the route's log line a
    // second time under the mode's own wording.
    publish_hub(&app);
    drop(gate);
    get_station(window, app)
}

#[tauri::command]
fn stop_capture(window: tauri::WebviewWindow, app: tauri::AppHandle) -> Result<(), String> {
    station_only(&window)?;
    request_release(&app, capture::Source::Button)
}

#[tauri::command]
fn cancel_capture(window: tauri::WebviewWindow, app: tauri::AppHandle) -> Result<(), String> {
    station_only(&window)?;
    request_cancel(&app)
}

#[tauri::command]
fn set_preferences(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    preferences: hub::Preferences,
) -> Result<(), String> {
    station_only(&window)?;
    // Recorded before anything can refuse it. A save that is rejected leaves the owner
    // looking at an unchanged setting with no account of what the station actually sent.
    app.state::<Runtime>().snapshot.lock().unwrap().note(
        "system",
        "WHISPER",
        &format!(
            "Save requested. Speech model: {}. Cleanup model: {}.",
            preferences.speech_model.as_deref().unwrap_or("none sent"),
            preferences.ollama_model.as_deref().unwrap_or("none sent"),
        ),
    );
    publish_hub(&app);
    preferences.validate()?;
    let gate = CAPTURE.lock().unwrap();
    if gate.busy() {
        return Err("Wait until this dictation finishes before changing settings.".into());
    }
    // A save is an explicit choice, so it must carry one. Resolving an absent name here
    // fell back to whichever model happened to be installed first, which wrote Base into
    // the file while the owner believed they had chosen another one.
    let Some(chosen) = preferences.speech_model.as_deref() else {
        return Err("Choose a local speech model in Control before saving.".into());
    };
    let model_path = resolve_whisper_model(Some(chosen));
    let model_name = model_path.file_name().unwrap_or_default().to_string_lossy().into_owned();
    models::validate(&resolve_project_root().join("models"), &model_name)?;
    let runtime = app.state::<Runtime>();
    let parent = runtime
        .preferences_path
        .parent()
        .ok_or("Preferences directory is unavailable.")?;
    std::fs::create_dir_all(parent).map_err(|e| e.to_string())?;
    let temporary = parent.join(format!(".preferences-{}.tmp", std::process::id()));
    let saved = serde_json::to_vec_pretty(&preferences).map_err(|e| e.to_string())?;
    let result = std::fs::write(&temporary, saved)
        .and_then(|()| std::fs::rename(&temporary, &runtime.preferences_path));
    if result.is_err() {
        let _ = std::fs::remove_file(&temporary);
    }
    result.map_err(|e| format!("Settings could not be saved: {e}"))?;
    {
        let mut state = runtime.snapshot.lock().unwrap();
        // Noted on every save, not only on a change: a save that quietly kept the previous
        // model is exactly the case that needs to be visible.
        state.note(
            "system",
            "WHISPER",
            &format!("Settings saved. Speech model: {model_name}. Applied to the next dictation."),
        );
        state.model = model_name;
        state.preferences = preferences;
    }
    drop(gate);
    publish_hub(&app);
    Ok(())
}

/// Ask the local service what it is running and which models it holds.
///
/// The answer comes from the service's own inventory through the Python bridge, so this
/// side needs no HTTP client and no second copy of the rule for what counts as ready. It
/// never pulls a model: an absent one is reported, not fetched.
#[tauri::command]
async fn check_provider(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
) -> Result<hub::Snapshot, String> {
    station_only(&window)?;
    let (provider, model) = {
        let state = app.state::<Runtime>();
        let snapshot = state.snapshot.lock().unwrap();
        (snapshot.provider, snapshot.preferences.ollama_model.clone())
    };
    // The inventory is asked for whatever route is selected, so Control can list what is
    // installed before the owner commits to the local route. Readiness is still applied
    // only to the route the answer belongs to.
    let _ = provider.needs_check();
    let request = serde_json::json!({
        "action": "provider_status",
        "provider": "ollama",
        "model": model,
    });
    let status = tauri::async_runtime::spawn_blocking(move || desktop_bridge(&request))
        .await
        .map_err(|e| e.to_string())??;
    let ready = status.get("ready").and_then(|v| v.as_bool()).unwrap_or(false);
    let detail = status
        .get("detail")
        .and_then(|v| v.as_str())
        .unwrap_or("the local service gave no answer")
        .to_string();
    let local_state = status
        .get("state")
        .and_then(|v| v.as_str())
        .map(str::to_owned);
    let installed = status
        .get("models")
        .and_then(|v| v.as_array())
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_owned))
                .collect()
        })
        .unwrap_or_default();
    app.state::<Runtime>()
        .snapshot
        .lock()
        .unwrap()
        .apply_provider_status(provider, ready, detail, local_state, installed);
    publish_hub(&app);
    get_station(window, app)
}

#[tauri::command]
fn list_speech_models(window: tauri::WebviewWindow) -> Result<Vec<models::LocalModel>, String> {
    station_only(&window)?;
    models::inventory(&resolve_project_root().join("models"))
}

#[tauri::command]
fn copy_entry(
    window: tauri::WebviewWindow,
    app: tauri::AppHandle,
    id: u64,
    raw: bool,
) -> Result<(), String> {
    station_only(&window)?;
    let gate = CAPTURE.lock().unwrap();
    if gate.busy() {
        return Err("Wait until the dictation finishes before replacing the clipboard.".into());
    }
    let text = {
        let runtime = app.state::<Runtime>();
        let state = runtime.snapshot.lock().unwrap();
        let item = state
            .history
            .iter()
            .find(|e| e.id == id)
            .ok_or("This dictation is no longer in the session history.")?;
        if raw {
            item.raw_text.clone()
        } else {
            item.delivery_text.clone()
        }
    };
    copy_delivery_text(&text, &app)
}

#[tauri::command]
fn clear_history(window: tauri::WebviewWindow, app: tauri::AppHandle) -> Result<(), String> {
    station_only(&window)?;
    let gate = CAPTURE.lock().unwrap();
    if gate.busy() {
        return Err("Wait until the dictation finishes before clearing history.".into());
    }
    app.state::<Runtime>()
        .snapshot
        .lock()
        .unwrap()
        .history
        .clear();
    persist_history(&app.state::<Runtime>());
    drop(gate);
    publish_hub(&app);
    Ok(())
}

/// Runs one request through the Python desktop bridge. The payload travels on stdin,
/// never in process arguments or through a shell, because `ps` shows arguments to every
/// process the owner runs and this carries their own text.
fn desktop_bridge(request: &serde_json::Value) -> Result<serde_json::Value, String> {
    use std::io::Write;
    let input = serde_json::to_vec(request).map_err(|e| e.to_string())?;
    if input.len() > 65536 {
        return Err("The request is too large.".into());
    }
    let root = resolve_project_root();
    let mut command = std::process::Command::new("python");
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    let mut child = command
        .current_dir(&root)
        .env("PYTHONPATH", root.join("src"))
        .env("PYTHONIOENCODING", "utf-8")
        .env("PYTHONUTF8", "1")
        .args(["-m", "sanbluedot_voiceflow.desktop"])
        .stdin(std::process::Stdio::piped())
        .stdout(std::process::Stdio::piped())
        .stderr(std::process::Stdio::null())
        .spawn()
        .map_err(|e| e.to_string())?;
    if let Err(error) = child
        .stdin
        .take()
        .ok_or("The bridge has no input stream.")?
        .write_all(&input)
    {
        let _ = child.kill();
        let _ = child.wait();
        return Err(error.to_string());
    }
    let output = child.wait_with_output().map_err(|e| e.to_string())?;
    let result: serde_json::Value = serde_json::from_slice(&output.stdout)
        .map_err(|e| format!("The bridge did not return valid data: {e}"))?;
    if !output.status.success() {
        return Err(result
            .get("error")
            .and_then(|v| v.as_str())
            .unwrap_or("The operation failed.")
            .into());
    }
    Ok(result)
}

#[tauri::command]
async fn memory_request(
    window: tauri::WebviewWindow,
    request: serde_json::Value,
) -> Result<serde_json::Value, String> {
    station_only(&window)?;
    tauri::async_runtime::spawn_blocking(move || {
        // Serialize mutations with capture startup so a dictation sees one memory state.
        let _memory_gate = if request.get("action").and_then(|value| value.as_str()) != Some("read")
        {
            let gate = CAPTURE
                .lock()
                .map_err(|_| "Capture is unavailable.".to_string())?;
            if gate.busy() {
                return Err("Finish the dictation before changing memory.".into());
            }
            Some(gate)
        } else {
            None
        };
        desktop_bridge(&request)
    })
    .await
    .map_err(|e| e.to_string())?
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .invoke_handler(tauri::generate_handler![start_dragging, get_station, start_capture, stop_capture,
            cancel_capture, set_preferences, copy_entry, clear_history, memory_request, select_provider, list_speech_models,
            set_capsule_visible, check_provider])
        .on_window_event(|window,event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if window.label()=="station" {
                    if CAPTURE.lock().unwrap().busy() { api.prevent_close(); }
                    else { window.app_handle().exit(0); }
                } else { api.prevent_close(); }
            }
        })
        .setup(|app| {
            let app_handle = app.handle().clone();
            let recorder = Arc::new(Mutex::new(AudioRecorder::new()));

            let (triggers, inbox) = mpsc::channel::<Trigger>();
            let mut snapshot = hub::Snapshot::new(
                resolve_whisper_model(None).file_name().unwrap_or_default().to_string_lossy().into_owned(),
                app.package_info().version.to_string());
            snapshot.preferences.hold_delay_ms = hold_delay().as_millis() as u64;
            let preferences_path = app.path().app_config_dir()?.join("preferences.local.json");
            let history_path = app.path().app_config_dir()?.join("history.local.json");
            if preferences_path.exists() {
                match std::fs::read(&preferences_path).ok()
                    .and_then(|b| serde_json::from_slice::<hub::Preferences>(&b).ok())
                    .filter(|p| p.validate().is_ok()) {
                    Some(preferences) => snapshot.preferences = preferences,
                    None => { snapshot.error = Some("Saved preferences could not be read. Defaults are active; the original file is preserved.".into()); }
                }
            }
            snapshot.model = models::selected_name(&resolve_project_root().join("models"), snapshot.preferences.speech_model.as_deref());
            // A history that cannot be read is left alone rather than overwritten, and the
            // session simply starts empty.
            if let Some(entries) = std::fs::read(&history_path)
                .ok()
                .and_then(|bytes| serde_json::from_slice::<Vec<hub::Entry>>(&bytes).ok())
            {
                snapshot.restore(entries);
            }
            app.manage(Runtime { triggers, snapshot: Mutex::new(snapshot), preferences_path, history_path });
            let worker_handle = app_handle.clone();
            std::thread::spawn(move || run_trigger_worker(inbox, worker_handle, recorder));
            std::thread::spawn(move || {
                let mut edges = capture::KeyEdges::default();
                loop {
                    #[cfg(windows)] {
                        let shortcut = app_handle.state::<Runtime>().snapshot.lock().unwrap().preferences.shortcut.clone();
                        let code = match shortcut.as_str() { "f8"=>0x77, "f9"=>0x78, _=>VK_RCONTROL.0 as i32 };
                        let down = unsafe { (GetAsyncKeyState(code) as u16 & 0x8000)!=0 };
                        let escape = unsafe { (GetAsyncKeyState(VK_ESCAPE.0 as i32) as u16 & 0x8000)!=0 };
                        match edges.update(down,escape) {
                            Some(capture::Edge::Press) => { let _ = request_press(&app_handle,capture::Source::Keyboard); }
                            Some(capture::Edge::Release) => { let _ = request_release(&app_handle,capture::Source::Keyboard); }
                            Some(capture::Edge::Cancel) => { let _ = request_cancel(&app_handle); }
                            None => {}
                        }
                    }
                    std::thread::sleep(Duration::from_millis(10));
                }
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running sanblueᵈᵒᵗ VoiceFlow Windows runner");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn development_executable_finds_engine_without_a_project_working_directory() {
        let manifest = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let root = manifest.parent().unwrap().parent().unwrap();
        assert_eq!(
            project_root_from(&manifest.join("target/debug/voiceflow.exe")),
            Some(root.to_path_buf())
        );
    }

    #[test]
    fn engine_cannot_copy_before_native_delivery_and_uses_utf8() {
        let command = engine_command(
            &PathBuf::from("test.wav"),
            &PathBuf::from("test.bin"),
            "literal",
            Some("qwen3:1.7b"),
        );
        let args: Vec<_> = command.get_args().collect();
        assert!(!args.contains(&std::ffi::OsStr::new("--copy")));
        assert!(args.contains(&std::ffi::OsStr::new("--json")));
        // A model name belongs to the local route alone; the literal run must not carry it.
        assert!(!args.contains(&std::ffi::OsStr::new("--ollama-model")));
        let local = engine_command(
            &PathBuf::from("t.wav"),
            &PathBuf::from("t.bin"),
            "ollama",
            Some("qwen3:1.7b"),
        );
        let local_args: Vec<_> = local.get_args().collect();
        assert!(local_args.contains(&std::ffi::OsStr::new("--ollama-model")));
        assert!(local_args.contains(&std::ffi::OsStr::new("qwen3:1.7b")));
        for (name, expected) in [("PYTHONIOENCODING", "utf-8"), ("PYTHONUTF8", "1")] {
            assert!(command
                .get_envs()
                .any(|(key, value)| key == name && value == Some(std::ffi::OsStr::new(expected))));
        }
    }

    #[test]
    fn duration_reads_audio_frames_from_the_finalized_wav() {
        let path = std::env::temp_dir().join(format!(
            "voiceflow-duration-test-{}.wav",
            std::process::id()
        ));
        let spec = WavSpec {
            channels: 2,
            sample_rate: 16_000,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };
        let mut writer = WavWriter::create(&path, spec).unwrap();
        for _ in 0..64_000 {
            writer.write_sample(0_i16).unwrap();
        }
        writer.finalize().unwrap();
        let seconds = recorded_audio_seconds(&path);
        std::fs::remove_file(&path).unwrap();
        assert_eq!(seconds, Some(2.0));
    }

    /// A constant input is what exposes the divisor. The machine this adapter was first
    /// run on samples at 48 kHz, an exact multiple of 16 kHz that leaves no remainder and
    /// hides the defect entirely, so the rates that carry one are tested beside it.
    #[test]
    fn a_constant_input_downsamples_to_a_constant_output() {
        for rate in [16_000_u32, 44_100, 48_000, 96_000] {
            let mut down = Downsampler::new(rate, 2);
            let mut out = Vec::new();
            // One second of full-scale silence-free signal, two interleaved channels.
            down.push(&vec![1.0_f32; rate as usize * 2], &mut out);

            let lowest = out.iter().copied().min().expect("no samples produced");
            assert_eq!(
                lowest, 32_767,
                "{} Hz dropped a sample below full scale on a constant input",
                rate
            );
            assert!(
                (out.len() as i64 - TARGET_SAMPLE_RATE as i64).abs() <= 1,
                "{} Hz produced {} samples for one second of audio",
                rate,
                out.len()
            );
        }
    }
}
