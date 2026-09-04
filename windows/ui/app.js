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
    const clamped = Math.max(0, Math.min(1, level));
    const activeCount = Math.round(clamped * totalBars);

    vuBars.forEach((bar, index) => {
      if (index < activeCount) {
        bar.classList.add("active");
      } else {
        bar.classList.remove("active");
      }
    });
  }

  function setMode(mode, data = {}) {
    hud.className = `hud-container ${mode}`;
    if (resetTimer) clearTimeout(resetTimer);

    switch (mode) {
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
        stageItem.textContent = "CLEANING";
        telemetryDetails.textContent = "• INFERENCE...";
        break;

      case "completed":
        statusText.textContent = data.did_auto_paste ? "PASTED" : "COPIED";
        setVULevel(totalBars); // Light all bars briefly on delivery

        const telemetryParts = [];
        if (typeof data.wpm === "number") {
          telemetryParts.push(`${data.wpm} WPM`);
        }
        if (typeof data.latency === "number") {
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
        stageItem.textContent = "ERROR";
        telemetryDetails.textContent = "";
        resetTimer = setTimeout(() => {
          setMode("ready");
        }, 2500);
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

  // Hook into Tauri v2 window events
  if (window.__TAURI__ && window.__TAURI__.event) {
    const { listen } = window.__TAURI__.event;

    listen("hud:mode", (event) => {
      const payload = event.payload || {};
      setMode(payload.mode || "ready", payload);
    });

    listen("hud:vu-level", (event) => {
      const level = typeof event.payload === "number" ? event.payload : 0;
      setVULevel(level);
    });
  } else {
    // Standalone preview fallback
    console.log("[VoiceFlow HUD] Running in standalone preview mode");
    setMode("ready");
  }
})();
