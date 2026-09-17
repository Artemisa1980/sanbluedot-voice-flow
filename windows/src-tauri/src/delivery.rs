//! Delivery rules shared by the native adapter and dependency-free regression checks.

pub fn terminal_process(name: &str) -> bool {
    matches!(name.to_ascii_lowercase().as_str(), "windowsterminal.exe" | "cmd.exe" |
        "powershell.exe" | "pwsh.exe" | "conhost.exe" | "openconsole.exe" |
        "alacritty.exe" | "wezterm.exe" | "wezterm-gui.exe" | "mintty.exe" |
        "putty.exe" | "kitty.exe" | "conemu.exe" | "conemu64.exe" |
        "hyper.exe" | "tabby.exe" | "terminus.exe" | "fluentterminal.exe")
}

/// Virtual-key chord only; Enter is never part of dictation delivery.
pub fn paste_keys(preference: &str, process: &str) -> Vec<u16> {
    match preference {
        "shift_insert" => vec![0x10, 0x2D],
        "ctrl_shift_v" => vec![0x11, 0x10, 0x56],
        "auto" if matches!(process.to_ascii_lowercase().as_str(), "mintty.exe" | "putty.exe" | "kitty.exe") => vec![0x10, 0x2D],
        _ => vec![0x11, 0x56],
    }
}

pub fn output_text(text: &str, terminal: bool) -> String {
    if terminal {
        // Include lone CR, tabs and Unicode line separators, not just Windows CRLF.
        text.split_whitespace().collect::<Vec<_>>().join(" ")
    } else {
        text.to_owned()
    }
}

pub fn speaking_rate(raw_text: &str, audio_seconds: Option<f64>) -> Option<u32> {
    let seconds = audio_seconds.filter(|v| v.is_finite() && *v > 0.0)?;
    let words = raw_text.split_whitespace().count();
    (words > 0).then(|| (words as f64 * 60.0 / seconds).round() as u32)
}

pub fn paste_allowed(
    identified: bool,
    own_app: bool,
    same_window: bool,
    same_process: bool,
    modifiers_down: bool,
) -> bool {
    identified && !own_app && same_window && same_process && !modifiers_down
}

/// Copy the exact delivery payload first. A failed copy must never paste stale text.
pub fn deliver(
    text: &str,
    terminal: bool,
    copy: impl FnOnce(&str) -> Result<(), String>,
    paste: impl FnOnce() -> bool,
) -> Result<bool, String> {
    if text.trim().is_empty() || text.contains('\0') {
        return Err(
            "The engine returned empty text or an embedded NUL; nothing was copied.".into(),
        );
    }
    copy(&output_text(text, terminal))?;
    Ok(paste())
}

#[cfg(windows)]
pub fn copy_unicode(text: &str, owner: windows::Win32::Foundation::HWND) -> Result<(), String> {
    use windows::Win32::Foundation::{GlobalFree, HANDLE};
    use windows::Win32::System::DataExchange::{
        CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData,
    };
    use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};

    if owner.0.is_null() {
        return Err("The clipboard has no VoiceFlow owner window.".into());
    }
    let units: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        // Allocate before emptying the clipboard. Windows owns this allocation only
        // after SetClipboardData succeeds; every failure frees it here.
        let memory = GlobalAlloc(GMEM_MOVEABLE, units.len() * std::mem::size_of::<u16>())
            .map_err(|e| format!("Could not allocate clipboard text: {e}"))?;
        let destination = GlobalLock(memory);
        if destination.is_null() {
            let _ = GlobalFree(memory);
            return Err("Could not lock clipboard text.".into());
        }
        std::ptr::copy_nonoverlapping(units.as_ptr(), destination.cast::<u16>(), units.len());
        let _ = GlobalUnlock(memory);

        let mut opened = false;
        for attempt in 0..5 {
            if OpenClipboard(owner).is_ok() {
                opened = true;
                break;
            }
            if attempt < 4 {
                std::thread::sleep(std::time::Duration::from_millis(10));
            }
        }
        if !opened {
            let _ = GlobalFree(memory);
            return Err("The clipboard is busy. Text was not pasted.".into());
        }
        // CF_UNICODETEXT: UTF-16 including a terminating NUL, independent of code page.
        let result = EmptyClipboard()
            .and_then(|()| SetClipboardData(13, HANDLE(memory.0)).map(|_| ()))
            .map_err(|e| format!("Could not copy text: {e}"));
        let _ = CloseClipboard();
        if result.is_err() {
            let _ = GlobalFree(memory);
        }
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::{Cell, RefCell};

    #[test]
    fn terminal_paste_adapts_without_enter_and_allows_custom_bindings() {
        for name in ["WindowsTerminal.exe", "mintty.exe", "putty.exe", "wezterm-gui.exe", "tabby.exe"] {
            assert!(terminal_process(name));
            assert!(!paste_keys("auto", name).contains(&0x0D));
        }
        assert!(!terminal_process("code.exe"));
        assert!(!terminal_process("terminal-notes.exe"));
        assert_eq!(paste_keys("auto", "mintty.exe"), vec![0x10, 0x2D]);
        assert_eq!(paste_keys("auto", "WindowsTerminal.exe"), vec![0x11, 0x56]);
        assert_eq!(paste_keys("ctrl_shift_v", "custom.exe"), vec![0x11, 0x10, 0x56]);
        assert_eq!(paste_keys("ctrl_v", "mintty.exe"), vec![0x11, 0x56]);
    }

    #[test]
    fn terminal_clipboard_receives_the_flattened_payload_before_paste() {
        let clipboard = RefCell::new(String::from("old clipboard"));
        let pasted = deliver(
            "echo one\r\necho two\rthree\n\tfour\u{2028}five",
            true,
            |text| {
                *clipboard.borrow_mut() = text.into();
                Ok(())
            },
            || {
                assert_eq!(&*clipboard.borrow(), "echo one echo two three four five");
                true
            },
        )
        .unwrap();
        assert!(pasted);
    }

    #[test]
    fn ordinary_documents_keep_formatting_and_unicode() {
        let text = "Español: acción. 日本語 🎙\n\n    indented";
        deliver(
            text,
            false,
            |copied| {
                assert_eq!(copied, text);
                Ok(())
            },
            || false,
        )
        .unwrap();
    }

    #[test]
    fn clipboard_failure_never_dispatches_paste() {
        let called = Cell::new(false);
        assert!(deliver(
            "new words",
            false,
            |_| Err("busy".into()),
            || {
                called.set(true);
                true
            }
        )
        .is_err());
        assert!(!called.get());
    }

    #[test]
    fn failed_insertion_is_reported_as_clipboard_only() {
        assert!(!deliver("words", false, |_| Ok(()), || false).unwrap());
    }

    #[test]
    fn invalid_results_never_replace_the_clipboard() {
        for text in ["", " \r\n", "hidden\0suffix"] {
            assert!(deliver(
                text,
                false,
                |_| panic!("copied invalid result"),
                || panic!()
            )
            .is_err());
        }
    }

    #[test]
    fn every_paste_guard_is_required() {
        assert!(paste_allowed(true, false, true, true, false));
        for args in [
            (false, false, true, true, false),
            (true, true, true, true, false),
            (true, false, false, true, false),
            (true, false, true, false, false),
            (true, false, true, true, true),
        ] {
            assert!(!paste_allowed(args.0, args.1, args.2, args.3, args.4));
        }
    }

    #[test]
    fn rate_uses_recorded_audio_and_raw_words() {
        assert_eq!(speaking_rate("one two three four", Some(2.0)), Some(120));
        // No processing duration, snippet expansion or rewritten text enters this API.
        assert_eq!(speaking_rate("", Some(2.0)), None);
        for duration in [
            None,
            Some(0.0),
            Some(-1.0),
            Some(f64::NAN),
            Some(f64::INFINITY),
        ] {
            assert_eq!(speaking_rate("one", duration), None);
        }
    }
}
