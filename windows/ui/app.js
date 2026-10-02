// sanblueᵈᵒᵗ VoiceFlow — Windows Retro HUD Controller
// Connects to Tauri v2 events emitted from Rust backend

(function () {
  const hud = document.getElementById("hud");
  const statusText = document.getElementById("statusText");
  const contextPill = document.getElementById("contextPill");
  const stageItem = document.getElementById("stageItem");
  const telemetryDetails = document.getElementById("telemetryDetails");
  const vuBars = Array.from(document.querySelectorAll(".vu-bar"));
  const totalBars = vuBars.length; // 12 bars

  let resetTimer = null;

  function setVULevel(level) {
    const clamped = Number.isFinite(level) ? Math.max(0, Math.min(1, level)) : 0;
    const activeCount = Math.round(clamped * totalBars);

    vuBars.forEach((bar, index) => {
      if (index < activeCount) {
        bar.classList.add("active");
      } else {
        bar.classList.remove("active");
      }
    });
  }

  // The capsule is a push-to-talk indicator: on screen while a dictation is in flight or
  // while its result is still up, and hidden otherwise. `ready` and `not_configured` are
  // the two idle states, and every timer below lands on `ready`.
  const IDLE_MODES = ["ready", "not_configured", "checking"];

  function showCapsule(visible) {
    const invoke = window.__TAURI__ && window.__TAURI__.core && window.__TAURI__.core.invoke;
    if (invoke) invoke("set_capsule_visible", { visible }).catch(() => {});
  }

  function setMode(mode, data = {}) {
    hud.className = `hud-container ${mode}`;
    showCapsule(!IDLE_MODES.includes(mode));
    if (resetTimer) clearTimeout(resetTimer);
    telemetryDetails.title = "";
    hud.title = "";
    if (data.context) {
      contextPill.textContent = data.context.toUpperCase();
      contextPill.style.display = "inline-block";
    }

    switch (mode) {
      case "not_configured":
        statusText.textContent = "SETUP";
        setVULevel(0);
        stageItem.textContent = "NOT CONNECTED";
        telemetryDetails.textContent = "• SELECT LITERAL";
        contextPill.style.display = "none";
        break;

      case "arming":
        statusText.textContent = "HOLD…";
        setVULevel(0);
        stageItem.textContent = "WAITING";
        telemetryDetails.textContent = "• KEEP HOLDING";
        break;

      case "recording":
        statusText.textContent = "ON AIR";
        if (data.context) {
          contextPill.textContent = data.context.toUpperCase();
          contextPill.style.display = "inline-block";
        } else {
          contextPill.style.display = "none";
        }
        stageItem.textContent = "LIVE";
        telemetryDetails.textContent = "• WHISPER";
        break;

      case "processing":
        statusText.textContent = "PROCESSING";
        setVULevel(0);
        stageItem.textContent = "TRANSCRIBING";
        telemetryDetails.textContent = "• LOCAL";
        break;

      case "completed":
        statusText.textContent = data.did_auto_paste ? "PASTED" : "COPIED";
        setVULevel(0); // This meter represents microphone input, never a success animation.

        const telemetryParts = [];
        if (Number.isFinite(data.wpm)) {
          telemetryParts.push(`${data.wpm} WPM`);
        }
        if (Number.isFinite(data.latency)) {
          telemetryParts.push(`${data.latency.toFixed(2)}s`);
        }
        if (data.cleaner) {
          telemetryParts.push(data.cleaner.toUpperCase());
        }

        if (telemetryParts.length > 0) {
          stageItem.textContent = telemetryParts[0];
          telemetryDetails.textContent = telemetryParts.slice(1).map(p => `• ${p}`).join(" ");
        } else {
          stageItem.textContent = "DONE";
          telemetryDetails.textContent = "";
        }

        resetTimer = setTimeout(() => {
          setMode("ready");
        }, 2500);
        break;

      // A hold too short to open the microphone. Named apart from a take-back: one is
      // the speaker's decision, the other is the trigger refusing a brush.
      case "too_short":
        statusText.textContent = "TOO SHORT";
        setVULevel(0);
        stageItem.textContent = "NO AUDIO";
        telemetryDetails.textContent = "";
        resetTimer = setTimeout(() => {
          setMode("ready");
        }, 1500);
        break;

      // The trigger was refused before the microphone opened: an unconnected provider, or
      // a model that is missing. Nothing was recorded, so this states the reason and then
      // gets out of the way rather than sitting on screen like a lost dictation.
      case "refused":
        statusText.textContent = "NOT READY";
        setVULevel(0);
        stageItem.textContent = "REFUSED";
        telemetryDetails.textContent = data.error ? `• ${data.error.slice(0, 30)}` : "";
        telemetryDetails.title = data.error || "";
        hud.title = data.error || "";
        contextPill.style.display = "none";
        resetTimer = setTimeout(() => {
          setMode("ready");
        }, 2600);
        break;

      case "cancelled":
        statusText.textContent = "CANCELLED";
        setVULevel(0);
        stageItem.textContent = "CANCELLED";
        telemetryDetails.textContent = "";
        resetTimer = setTimeout(() => {
          setMode("ready");
        }, 1500);
        break;

      case "failed":
        statusText.textContent = "ERROR";
        setVULevel(0);
        stageItem.textContent = "FAILED";
        telemetryDetails.textContent = data.error ? `• ${data.error.slice(0, 30)}` : "";
        // Long enough to read, then gone. Hover exposes the full reason while it is up,
        // and the station's event log keeps it after the capsule has left.
        telemetryDetails.title = data.error || "";
        hud.title = data.error || "";
        contextPill.style.display = "none";
        resetTimer = setTimeout(() => {
          setMode("ready");
        }, 8000);
        break;

      case "ready":
      default:
        statusText.textContent = "READY";
        contextPill.textContent = "DESKTOP";
        contextPill.style.display = "inline-block";
        stageItem.textContent = "READY";
        telemetryDetails.textContent = "";
        setVULevel(0);
        break;
    }
  }

  // Hook into window dragging: both native invoke and getCurrentWindow()
  hud.addEventListener("mousedown", (e) => {
    // Only trigger drag on primary (left) mouse button click and not on interactive buttons
    if (e.button === 0) {
      if (window.__TAURI__ && window.__TAURI__.core && window.__TAURI__.core.invoke) {
        window.__TAURI__.core.invoke("start_dragging").catch((error) => {
          telemetryDetails.title = `Could not move the capsule: ${error}`;
        });
      } else if (window.__TAURI__ && window.__TAURI__.window && window.__TAURI__.window.getCurrentWindow) {
        window.__TAURI__.window.getCurrentWindow().startDragging().catch((error) => {
          telemetryDetails.title = `Could not move the capsule: ${error}`;
        });
      }
    }
  });

  // Hook into Tauri v2 window events
  if (window.__TAURI__ && window.__TAURI__.event) {
    const { listen } = window.__TAURI__.event;

    Promise.all([listen("hud:mode", (event) => {
      const payload = event.payload || {};
      setMode(payload.mode || "ready", payload);
    }),

    listen("hud:vu-level", (event) => {
      const level = typeof event.payload === "number" ? event.payload : 0;
      setVULevel(level);
    })]).catch((error) => {
      setMode("failed", { error: `The capsule could not connect: ${error}` });
    });
  } else if (window.__TAURI__) {
    setMode("failed", { error: "The native event bridge is unavailable." });
  } else {
    // Standalone preview fallback
    console.log("[VoiceFlow HUD] Running in standalone preview mode");
    setMode("ready");
  }
})();
