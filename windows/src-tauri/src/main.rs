// sanblueᵈᵒᵗ VoiceFlow — Windows Native Platform Adapter (Tauri v2)
// Gate 5 Implementation: Push-to-Talk, Audio Capture, and Win32 Auto-Paste

#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use hound::{WavSpec, WavWriter};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
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
    SendInput, INPUT, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_KEYUP,
    VK_CONTROL, VK_V,
};
#[cfg(windows)]
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

/// The trigger is held. It says nothing about whether the microphone is open.
static IS_RECORDING: AtomicBool = AtomicBool::new(false);
/// The microphone is open and a WAV is being written.
static IS_ARMED: AtomicBool = AtomicBool::new(false);
/// The hold this recording belongs to. A hold that ends before the arming delay is
/// followed by a new number, so the timer still sleeping for the old one starts nothing.
static PRESS_GENERATION: AtomicU64 = AtomicU64::new(0);
const DEFAULT_HOLD_DELAY_MS: u64 = 500;

/// R1: the microphone opens only after the trigger has been held this long, and a
/// shorter touch opens no device and writes no file. Discarding the audio afterwards is
/// not the same rule: on a Spanish layout AltGr types `@`, `\` and `~`, so writing an
/// email address would open the microphone once per character.
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
}

#[derive(Clone, Debug)]
struct TargetWindowInfo {
    #[cfg(windows)]
    hwnd: HWND,
    name: String,
    is_terminal: bool,
}

fn get_active_window_info() -> TargetWindowInfo {
    #[cfg(windows)]
    unsafe {
        let hwnd: HWND = GetForegroundWindow();
        if hwnd.0.is_null() {
            return TargetWindowInfo {
                hwnd,
                name: "DESKTOP".to_string(),
                is_terminal: false,
            };
        }

        let mut pid: u32 = 0;
        GetWindowThreadProcessId(hwnd, Some(&mut pid));
        if pid == 0 {
            return TargetWindowInfo {
                hwnd,
                name: "UNKNOWN".to_string(),
                is_terminal: false,
            };
        }

        let mut is_terminal = false;
        let mut display_name = format!("PID_{}", pid);

        if let Ok(handle) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
            let mut buf = [0u16; 512];
            let len = GetProcessImageFileNameW(handle, &mut buf);
            let _ = CloseHandle(handle);

            if len > 0 {
                let full_path = String::from_utf16_lossy(&buf[..len as usize]);
                let file_name = full_path
                    .split('\\')
                    .last()
                    .unwrap_or(&full_path)
                    .to_lowercase();

                if file_name.contains("windowsterminal")
                    || file_name == "cmd.exe"
                    || file_name.contains("powershell")
                    || file_name.contains("alacritty")
                    || file_name.contains("wezterm")
                {
                    is_terminal = true;
                    display_name = "TERMINAL".to_string();
                } else if file_name.contains("code") {
                    display_name = "VSCODE".to_string();
                } else if file_name.contains("chrome") {
                    display_name = "CHROME".to_string();
                } else {
                    display_name = file_name
                        .trim_end_matches(".exe")
                        .to_uppercase();
                }
            }
        }

        TargetWindowInfo {
            hwnd,
            name: display_name,
            is_terminal,
        }
    }

    #[cfg(not(windows))]
    TargetWindowInfo {
        name: "NON_WINDOWS".to_string(),
        is_terminal: false,
    }
}

fn simulate_paste() {
    #[cfg(windows)]
    unsafe {
        let mut inputs: [INPUT; 4] = std::mem::zeroed();

        // Key down Ctrl
        inputs[0].r#type = INPUT_KEYBOARD;
        inputs[0].Anonymous.ki = KEYBDINPUT {
            wVk: VK_CONTROL,
            wScan: 0,
            dwFlags: KEYBD_EVENT_FLAGS(0),
            time: 0,
            dwExtraInfo: 0,
        };

        // Key down V
        inputs[1].r#type = INPUT_KEYBOARD;
        inputs[1].Anonymous.ki = KEYBDINPUT {
            wVk: VK_V,
            wScan: 0,
            dwFlags: KEYBD_EVENT_FLAGS(0),
            time: 0,
            dwExtraInfo: 0,
        };

        // Key up V
        inputs[2].r#type = INPUT_KEYBOARD;
        inputs[2].Anonymous.ki = KEYBDINPUT {
            wVk: VK_V,
            wScan: 0,
            dwFlags: KEYEVENTF_KEYUP,
            time: 0,
            dwExtraInfo: 0,
        };

        // Key up Ctrl
        inputs[3].r#type = INPUT_KEYBOARD;
        inputs[3].Anonymous.ki = KEYBDINPUT {
            wVk: VK_CONTROL,
            wScan: 0,
            dwFlags: KEYEVENTF_KEYUP,
            time: 0,
            dwExtraInfo: 0,
        };

        SendInput(&inputs, std::mem::size_of::<INPUT>() as i32);
    }
}

fn resolve_whisper_model() -> PathBuf {
    let candidate = PathBuf::from("models/ggml-base.bin");
    if candidate.exists() {
        return candidate;
    }
    let candidate_turbo = PathBuf::from("models/ggml-large-v3-turbo.bin");
    if candidate_turbo.exists() {
        return candidate_turbo;
    }
    PathBuf::from("models/ggml-base.bin")
}

fn run_engine_process(
    audio_path: &PathBuf,
    whisper_model: &PathBuf,
    is_terminal: bool,
) -> Result<serde_json::Value, String> {
    let mut cmd = std::process::Command::new("python");
    cmd.args([
        "-m",
        "sanbluedot_voiceflow",
        "process",
        audio_path.to_str().unwrap_or_default(),
        "--whisper-model",
        whisper_model.to_str().unwrap_or_default(),
        "--copy",
        "--json",
    ]);

    let output = cmd
        .output()
        .map_err(|e| format!("Failed to invoke python engine: {}", e))?;

    if !output.status.success() && output.status.code() != Some(2) {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Engine execution error: {}", stderr));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut json_val: serde_json::Value =
        serde_json::from_str(&stdout).map_err(|e| format!("Failed to parse engine JSON: {}", e))?;

    // If target application is a terminal emulator, enforce R4 single-line flattening
    if is_terminal {
        if let Some(text) = json_val.get("final_text").and_value_str() {
            let flattened = text.replace("\r\n", " ").replace('\n', " ");
            json_val["final_text"] = serde_json::Value::String(flattened);
        }
    }

    Ok(json_val)
}

trait JsonValueExt {
    fn and_value_str(&self) -> Option<String>;
}

impl JsonValueExt for serde_json::Value {
    fn and_value_str(&self) -> Option<String> {
        self.as_str().map(|s| s.to_string())
    }
}

struct AudioRecorder {
    _stream: Option<cpal::Stream>,
    writer: Option<Arc<Mutex<WavWriter<std::io::BufWriter<std::fs::File>>>>>,
}

impl AudioRecorder {
    fn new() -> Self {
        Self {
            _stream: None,
            writer: None,
        }
    }

    fn start_recording(
        &mut self,
        output_path: PathBuf,
        app_handle: tauri::AppHandle,
    ) -> Result<(), String> {
        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or_else(|| "No audio input device found".to_string())?;

        let spec = WavSpec {
            channels: 1,
            sample_rate: 16000,
            bits_per_sample: 16,
            sample_format: hound::SampleFormat::Int,
        };

        let writer = WavWriter::create(&output_path, spec)
            .map_err(|e| format!("Failed to create WAV: {}", e))?;
        let writer_arc = Arc::new(Mutex::new(writer));
        let writer_clone = writer_arc.clone();

        let config = cpal::StreamConfig {
            channels: 1,
            sample_rate: cpal::SampleRate(16000),
        };

        let err_fn = |err| eprintln!("Audio stream error: {}", err);

        let stream = device
            .build_input_stream(
                &config,
                move |data: &[f32], _: &_| {
                    let mut sum_squares = 0.0;
                    if let Ok(mut w) = writer_clone.lock() {
                        for &sample in data {
                            sum_squares += sample * sample;
                            let sample_i16 = (sample.max(-1.0).min(1.0) * 32767.0) as i16;
                            let _ = w.write_sample(sample_i16);
                        }
                    }

                    let rms = if !data.is_empty() {
                        (sum_squares / data.len() as f32).sqrt()
                    } else {
                        0.0
                    };

                    let normalized = (rms * 5.0).min(1.0);
                    let _ = app_handle.emit("hud:vu-level", normalized);
                },
                err_fn,
                None,
            )
            .map_err(|e| format!("Failed to build audio stream: {}", e))?;

        stream
            .play()
            .map_err(|e| format!("Failed to start audio stream: {}", e))?;

        self._stream = Some(stream);
        self.writer = Some(writer_arc);
        Ok(())
    }

    fn stop_recording(&mut self) {
        self._stream = None;
        if let Some(writer_arc) = self.writer.take() {
            if let Ok(mut w) = writer_arc.lock() {
                let _ = w.flush();
            }
        }
    }
}

fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .setup(|app| {
            let app_handle = app.handle().clone();
            let recorder = Arc::new(Mutex::new(AudioRecorder::new()));

            std::thread::spawn(move || {
                let mut captured_target: Option<TargetWindowInfo> = None;
                let temp_audio = std::env::temp_dir().join("voiceflow_recording.wav");
                let whisper_model = resolve_whisper_model();

                let callback = move |event: rdev::Event| {
                    match event.event_type {
                        rdev::EventType::KeyPress(key) => {
                            match key {
                                rdev::Key::AltGr => {
                                    if !IS_RECORDING.load(Ordering::SeqCst) {
                                        IS_RECORDING.store(true, Ordering::SeqCst);
                                        IS_ARMED.store(false, Ordering::SeqCst);
                                        let generation =
                                            PRESS_GENERATION.fetch_add(1, Ordering::SeqCst) + 1;

                                        let target = get_active_window_info();
                                        captured_target = Some(target.clone());

                                        // Nothing is announced and nothing is captured
                                        // yet: the capsule appears when the microphone
                                        // actually opens, so what it shows is true.
                                        let arm_handle = app_handle.clone();
                                        let arm_recorder = recorder.clone();
                                        let arm_audio = temp_audio.clone();
                                        let arm_context = target.name.clone();
                                        std::thread::spawn(move || {
                                            std::thread::sleep(hold_delay());
                                            if PRESS_GENERATION.load(Ordering::SeqCst) != generation
                                                || !IS_RECORDING.load(Ordering::SeqCst)
                                            {
                                                return;
                                            }

                                            let started = match arm_recorder.lock() {
                                                Ok(mut rec) => rec
                                                    .start_recording(
                                                        arm_audio,
                                                        arm_handle.clone(),
                                                    )
                                                    .is_ok(),
                                                Err(_) => false,
                                            };
                                            if !started {
                                                IS_RECORDING.store(false, Ordering::SeqCst);
                                                let _ = arm_handle.emit(
                                                    "hud:mode",
                                                    ModePayload {
                                                        mode: "failed".to_string(),
                                                        context: None,
                                                        wpm: None,
                                                        latency: None,
                                                        cleaner: None,
                                                        did_auto_paste: false,
                                                        unrecognized_command: false,
                                                    },
                                                );
                                                return;
                                            }

                                            IS_ARMED.store(true, Ordering::SeqCst);
                                            let _ = arm_handle.emit(
                                                "hud:mode",
                                                ModePayload {
                                                    mode: "recording".to_string(),
                                                    context: Some(arm_context),
                                                    wpm: None,
                                                    latency: None,
                                                    cleaner: None,
                                                    did_auto_paste: false,
                                                    unrecognized_command: false,
                                                },
                                            );
                                        });
                                    }
                                }
                                rdev::Key::Escape => {
                                    // R1: Escape cancels active recording immediately
                                    if IS_RECORDING.load(Ordering::SeqCst) {
                                        IS_RECORDING.store(false, Ordering::SeqCst);
                                        IS_ARMED.store(false, Ordering::SeqCst);
                                        captured_target = None;

                                        if let Ok(mut rec) = recorder.lock() {
                                            rec.stop_recording();
                                        }
                                        let _ = std::fs::remove_file(&temp_audio);

                                        let _ = app_handle.emit(
                                            "hud:mode",
                                            ModePayload {
                                                mode: "cancelled".to_string(),
                                                context: None,
                                                wpm: None,
                                                latency: None,
                                                cleaner: None,
                                                did_auto_paste: false,
                                                unrecognized_command: false,
                                            },
                                        );
                                    }
                                }
                                _ => {}
                            }
                        }
                        rdev::EventType::KeyRelease(rdev::Key::AltGr) => {
                            if IS_RECORDING.load(Ordering::SeqCst) {
                                IS_RECORDING.store(false, Ordering::SeqCst);
                                let was_armed = IS_ARMED.swap(false, Ordering::SeqCst);

                                if let Ok(mut rec) = recorder.lock() {
                                    rec.stop_recording();
                                }

                                // R1: the hold never reached the delay, so no device was
                                // opened. It is reported rather than silent, and under
                                // its own name: a refusal is not the take-back the
                                // speaker chose.
                                if !was_armed {
                                    captured_target = None;
                                    let _ = std::fs::remove_file(&temp_audio);
                                    let _ = app_handle.emit(
                                        "hud:mode",
                                        ModePayload {
                                            mode: "too_short".to_string(),
                                            context: None,
                                            wpm: None,
                                            latency: None,
                                            cleaner: None,
                                            did_auto_paste: false,
                                            unrecognized_command: false,
                                        },
                                    );
                                    return;
                                }

                                let _ = app_handle.emit(
                                    "hud:mode",
                                    ModePayload {
                                        mode: "processing".to_string(),
                                        context: None,
                                        wpm: None,
                                        latency: None,
                                        cleaner: None,
                                        did_auto_paste: false,
                                        unrecognized_command: false,
                                    },
                                );

                                let start_inference = Instant::now();
                                let target = captured_target
                                    .take()
                                    .unwrap_or_else(get_active_window_info);

                                let engine_result = run_engine_process(
                                    &temp_audio,
                                    &whisper_model,
                                    target.is_terminal,
                                );

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

                                        let word_count = final_text.split_whitespace().count();
                                        let measured_wpm = if latency > 0.0 && word_count > 0 {
                                            Some(
                                                (word_count as f64 / (latency / 60.0)).round()
                                                    as u32,
                                            )
                                        } else {
                                            None
                                        };

                                        // R4: Verify focus immediately before pasting
                                        let current_window = get_active_window_info();
                                        #[cfg(windows)]
                                        let focus_unchanged = current_window.hwnd.0
                                            == target.hwnd.0
                                            && !current_window.hwnd.0.is_null();
                                        #[cfg(not(windows))]
                                        let focus_unchanged = true;

                                        let mut did_auto_paste = false;
                                        if focus_unchanged && !final_text.is_empty() {
                                            simulate_paste();
                                            did_auto_paste = true;
                                        }

                                        let _ = app_handle.emit(
                                            "hud:mode",
                                            ModePayload {
                                                mode: "completed".to_string(),
                                                context: Some(target.name),
                                                wpm: measured_wpm,
                                                latency: Some(latency),
                                                cleaner: Some(cleaner_name),
                                                did_auto_paste,
                                                unrecognized_command: false,
                                            },
                                        );
                                    }
                                    Err(_) => {
                                        let _ = app_handle.emit(
                                            "hud:mode",
                                            ModePayload {
                                                mode: "failed".to_string(),
                                                context: None,
                                                wpm: None,
                                                latency: None,
                                                cleaner: None,
                                                did_auto_paste: false,
                                                unrecognized_command: false,
                                            },
                                        );
                                    }
                                }
                            }
                        }
                        _ => {}
                    }
                };

                let _ = rdev::listen(callback);
            });

            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running sanblueᵈᵒᵗ VoiceFlow Windows runner");
}
