use serde::{Deserialize, Serialize};

/// A selected route is not proof that its adapter is configured.
#[derive(Clone, Copy, Serialize, Deserialize, Debug, PartialEq)]
#[serde(rename_all = "snake_case")]
pub enum Provider {
    Literal,
    Ollama,
    Gemini,
}
impl Provider {
    /// Whether this route's readiness has to be measured before capture.
    pub fn needs_check(self) -> bool {
        matches!(self, Self::Ollama)
    }
    /// The name the engine knows this route by.
    pub fn cleaner(self) -> &'static str {
        match self {
            Self::Literal => "literal",
            Self::Ollama => "ollama",
            Self::Gemini => "gemini",
        }
    }
}

#[derive(Clone, Serialize)]
pub struct LogEntry {
    pub id: u64,
    pub timestamp_ms: u64,
    pub category: String,
    pub tag: String,
    pub message: String,
}

#[derive(Clone, Serialize, Deserialize, Debug, PartialEq)]
#[serde(deny_unknown_fields)]
pub struct Preferences {
    pub shortcut: String,
    pub hold_delay_ms: u64,
    pub auto_paste: bool,
    #[serde(default)]
    pub speech_model: Option<String>,
    #[serde(default = "default_paste_shortcut")]
    pub paste_shortcut: String,
    #[serde(default)]
    pub ollama_model: Option<String>,
}
fn default_paste_shortcut() -> String { "auto".into() }
impl Default for Preferences {
    fn default() -> Self {
        Self {
            shortcut: "right_ctrl".into(),
            hold_delay_ms: 0,
            auto_paste: true,
            speech_model: None,
            paste_shortcut: default_paste_shortcut(),
            ollama_model: None,
        }
    }
}
impl Preferences {
    pub fn validate(&self) -> Result<(), String> {
        if !["auto", "ctrl_v", "ctrl_shift_v", "shift_insert"].contains(&self.paste_shortcut.as_str()) {
            return Err("Choose a supported paste shortcut.".into());
        }
        if self.speech_model.as_deref().is_some_and(|name| !crate::models::valid_name(name)) {
            return Err("Choose a local ggml model from Control.".into());
        }
        // A tag, never a path: this name is handed to the engine, which hands it to the
        // local service, and neither should be asked to open something from disk.
        if self.ollama_model.as_deref().is_some_and(|name| {
            name.is_empty()
                || name.len() > 200
                || !name
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"-_.:".contains(&b))
        }) {
            return Err("Choose an installed Ollama model from Control.".into());
        }
        if !["right_ctrl", "f8", "f9"].contains(&self.shortcut.as_str())
            || self.hold_delay_ms > 3000
        {
            return Err("Choose Right Ctrl, F8 or F9 and a delay between 0 and 3000 ms.".into());
        }
        Ok(())
    }
}

#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Entry {
    pub id: u64,
    pub raw_text: String,
    pub final_text: String,
    pub delivery_text: String,
    pub target: String,
    pub delivery: String,
    pub wpm: Option<u32>,
    pub latency: f64,
    pub stt_seconds: Option<f64>,
    /// What actually produced this entry. The current setting is not evidence about a
    /// dictation that ran before it changed, so each run carries its own.
    pub speech_model: String,
    pub cleaner: String,
    pub cleanup_seconds: Option<f64>,
    /// Set when cleanup was replaced by the deterministic transcript, naming which side
    /// refused: the output guard, or the provider.
    pub fallback_reason: Option<String>,
}
impl Default for Entry {
    fn default() -> Self {
        Self {
            id: 0,
            raw_text: String::new(),
            final_text: String::new(),
            delivery_text: String::new(),
            target: String::new(),
            delivery: String::new(),
            wpm: None,
            latency: 0.0,
            stt_seconds: None,
            speech_model: String::new(),
            cleaner: String::new(),
            cleanup_seconds: None,
            fallback_reason: None,
        }
    }
}

#[derive(Clone, Serialize)]
pub struct Snapshot {
    pub revision: u64,
    pub status: String,
    pub error: Option<String>,
    pub preferences: Preferences,
    pub history: Vec<Entry>,
    pub model: String,
    pub version: String,
    pub provider: Provider,
    pub provider_ready: bool,
    pub provider_detail: Option<String>,
    /// Which local condition the last check found, for wording that fits it.
    pub provider_state: Option<String>,
    pub provider_models: Vec<String>,
    pub log: Vec<LogEntry>,
    #[serde(skip)]
    pub last_event_id: u64,
    #[serde(skip)]
    pub last_id: u64,
}
impl Snapshot {
    pub fn new(model: String, version: String) -> Self {
        let mut state = Self {
            revision: 0,
            status: "ready".into(),
            error: None,
            preferences: Preferences::default(),
            history: vec![],
            model,
            version,
            last_id: 0,
            provider: Provider::Literal,
            provider_ready: true,
            provider_detail: None,
            provider_state: None,
            provider_models: vec![],
            log: vec![],
            last_event_id: 0,
        };
        state.note(
            "system",
            "SYS",
            "Station initialized. Provider: Literal — no cleanup.",
        );
        state
    }
    pub fn note(&mut self, category: &str, tag: &str, message: &str) {
        self.last_event_id += 1;
        self.log.push(LogEntry {
            id: self.last_event_id,
            timestamp_ms: std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap_or_default()
                .as_millis() as u64,
            category: category.into(),
            tag: tag.into(),
            message: message.into(),
        });
        if self.log.len() > 100 {
            self.log.drain(..self.log.len() - 100);
        }
    }
    pub fn select_provider(
        &mut self,
        provider: Provider,
        capture_busy: bool,
    ) -> Result<(), String> {
        if capture_busy {
            return Err("Finish the dictation before changing providers.".into());
        }
        if self.provider == provider {
            return Ok(());
        }
        self.provider = provider;
        self.provider_detail = None;
        self.provider_state = None;
        self.provider_models.clear();
        // Selecting a route is not evidence that it works. Literal needs none; Ollama
        // waits for the local service's own answer; Gemini has no Windows credential
        // path yet, so it stays refused whatever is selected.
        self.provider_ready = provider == Provider::Literal;
        self.status = match provider {
            Provider::Literal => "ready",
            Provider::Ollama => "checking",
            Provider::Gemini => "not_configured",
        }
        .into();
        self.error = None;
        let (tag, message) = match provider {
            Provider::Literal => ("SYS", "Provider: Literal — no cleanup. Local dictation available."),
            Provider::Ollama => ("OLLAMA", "Selected local cleanup — Ollama. Checking the local service and its installed models."),
            Provider::Gemini => ("GEMINI", "Selected Gemini — cloud, text only. Setup required; no credentials checked or data sent."),
        };
        self.note("cleanup", tag, message);
        Ok(())
    }

    /// What refuses capture on the selected route right now, if anything.
    pub fn capture_error(&self) -> Option<String> {
        match self.provider {
            Provider::Literal => None,
            Provider::Ollama if self.provider_ready => None,
            Provider::Ollama => Some(self.provider_detail.clone().unwrap_or_else(|| {
                "Ollama has not been checked yet. Open Control to check the local service.".into()
            })),
            Provider::Gemini => {
                Some("Gemini is not connected yet. Select Literal to dictate locally.".into())
            }
        }
    }

    /// Record what a readiness check found. A route becomes capture-ready only here, and
    /// only while it is still the selected one: the owner can change route mid-check.
    pub fn apply_provider_status(
        &mut self,
        provider: Provider,
        ready: bool,
        detail: String,
        state: Option<String>,
        models: Vec<String>,
    ) -> bool {
        self.provider_models = models;
        if self.provider != provider {
            return false;
        }
        self.provider_ready = ready;
        self.provider_detail = Some(detail.clone());
        self.provider_state = state;
        self.status = if ready { "ready" } else { "not_configured" }.into();
        self.note("cleanup", "OLLAMA", &format!("Local cleanup: {detail}"));
        true
    }
    pub fn retain(&mut self, mut entry: Entry) {
        self.last_id += 1;
        entry.id = self.last_id;
        self.history.insert(0, entry);
        self.history.truncate(10);
    }

    /// Restore a kept history. Identifiers continue past the highest one restored, never
    /// from a count: counting reuses a number after any deletion.
    pub fn restore(&mut self, entries: Vec<Entry>) {
        self.last_id = entries.iter().map(|entry| entry.id).max().unwrap_or(0);
        self.history = entries;
        self.history.truncate(10);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn a_selected_route_is_never_ready_until_it_is_measured() {
        let mut state = Snapshot::new("base".into(), "test".into());

        // Selecting Ollama starts a check; it refuses capture until one answers.
        state.select_provider(Provider::Ollama, false).unwrap();
        assert!(!state.provider_ready);
        assert_eq!(state.status, "checking");
        assert!(state.capture_error().unwrap().contains("not been checked"));

        // A service that answers without the model is refused with the real reason.
        state.apply_provider_status(
            Provider::Ollama,
            false,
            "service available; model not installed: qwen3:1.7b".into(),
            Some("model_missing".into()),
            vec![],
        );
        assert!(!state.provider_ready);
        assert!(state.capture_error().unwrap().contains("not installed"));

        state.apply_provider_status(
            Provider::Ollama,
            true,
            "available with qwen3:1.7b".into(),
            Some("ready".into()),
            vec!["qwen3:1.7b".into()],
        );
        assert!(state.provider_ready);
        assert!(state.capture_error().is_none());

        // A check that lands after the route changed must not make the new one ready.
        state.select_provider(Provider::Gemini, false).unwrap();
        assert!(!state.apply_provider_status(Provider::Ollama, true, "stale".into(), None, vec![]));
        assert!(!state.provider_ready);
        assert!(state.capture_error().unwrap().contains("Gemini"));

        assert!(state.select_provider(Provider::Literal, true).is_err());
        assert_eq!(state.provider, Provider::Gemini);
        state.select_provider(Provider::Literal, false).unwrap();
        assert!(state.provider_ready);
        assert!(state.capture_error().is_none());
    }
    #[test]
    fn log_is_bounded_ordered_and_selection_is_idempotent() {
        let mut state = Snapshot::new("base".into(), "test".into());
        state.select_provider(Provider::Literal, false).unwrap();
        assert_eq!(state.log.len(), 1);
        for _ in 0..110 {
            state.note("system", "SYS", "test event");
        }
        assert_eq!(state.log.len(), 100);
        assert_eq!(state.log[0].id, 12);
        assert_eq!(state.log[99].id, 111);
        assert!(serde_json::from_str::<Provider>("\"unknown\"").is_err());
    }
    fn entry() -> Entry {
        Entry {
            id: 0,
            raw_text: "spoken".into(),
            final_text: "result".into(),
            delivery_text: "result".into(),
            target: "NOTEPAD".into(),
            delivery: "copy_failed".into(),
            wpm: None,
            latency: 1.0,
            stt_seconds: None,
            speech_model: "ggml-base.bin".into(),
            cleaner: "literal".into(),
            cleanup_seconds: None,
            fallback_reason: None,
        }
    }
    #[test]
    fn recovery_survives_copy_failure_and_ids_are_not_reused_after_clear() {
        let mut s = Snapshot::new("base".into(), "test".into());
        s.retain(entry());
        assert_eq!(s.history[0].delivery, "copy_failed");
        s.history.clear();
        s.retain(entry());
        assert_eq!(s.history[0].id, 2);
        for _ in 0..12 {
            s.retain(entry());
        }
        assert_eq!(s.history.len(), 10);
        assert_eq!(s.history[0].id, 14);
    }
    #[test]
    fn the_payload_the_station_sends_is_accepted_exactly_as_it_is_sent() {
        // Copied from the shape `station.js` builds on save. `deny_unknown_fields` makes
        // any drift here a refusal the owner sees as a save that did nothing.
        let sent = r#"{"shortcut":"right_ctrl","hold_delay_ms":0,"auto_paste":true,"speech_model":"ggml-large-v3-turbo.bin","ollama_model":"qwen3:1.7b","paste_shortcut":"auto"}"#;
        let parsed: Preferences = serde_json::from_str(sent)
            .unwrap_or_else(|error| panic!("the station's own payload was refused: {error}"));
        assert_eq!(parsed.speech_model.as_deref(), Some("ggml-large-v3-turbo.bin"));
        assert_eq!(parsed.ollama_model.as_deref(), Some("qwen3:1.7b"));
        parsed
            .validate()
            .unwrap_or_else(|error| panic!("the station's own payload failed validation: {error}"));
    }

    #[test]
    fn preferences_reject_unknown_shortcuts_and_excessive_delays() {
        let mut p = Preferences::default();
        assert!(p.validate().is_ok());
        p.shortcut = "command".into();
        assert!(p.validate().is_err());
        p.shortcut = "f8".into();
        p.hold_delay_ms = 3001;
        assert!(p.validate().is_err());
    }
    #[test]
    fn older_preferences_keep_default_model_and_new_preferences_reject_paths() {
        let mut p: Preferences = serde_json::from_str(r#"{"shortcut":"f8","hold_delay_ms":100,"auto_paste":false}"#).unwrap();
        assert_eq!(p.speech_model, None);
        assert!(p.validate().is_ok());
        p.speech_model = Some("../ggml-base.bin".into());
        assert!(p.validate().is_err());
        p.speech_model = Some("ggml-small.bin".into());
        assert!(p.validate().is_ok());
        let restored: Preferences = serde_json::from_slice(&serde_json::to_vec(&p).unwrap()).unwrap();
        assert_eq!(p, restored);
    }
}
