(function () {
  "use strict";
  const $ = id => document.getElementById(id);
  const all = selector => Array.from(document.querySelectorAll(selector));
  const bridge = window.__TAURI__;
  let snapshot = null, connected = false, held = false, starting = null, finishing = false;
  let library = "history", memory = null, memoryBusy = false, preferencesDirty = false;
  let confirmAction = null, displayedId = null;
  let providerPending = false, consoleView = "log", logFilter = "all", lastLogKey = "";
  const voiceEnvelope = Array(12).fill(0);
  let meterReset = null;
  let localModels = null, modelsBusy = false;
  const providers = {
    literal: {button: "providerLiteral", help: "helpLiteral", name: "no cleanup", scope: "CLEANUP · LOCAL", footer: "100% Local · Whisper", description: "Literal applies your confirmed memory without an AI cleanup model. Speech stays on this device."},
    ollama: {button: "providerOllama", help: "helpOllama", name: "ollama local", scope: "CLEANUP · LOCAL", footer: "Ollama · local", description: "Ollama runs a text model on this computer, with no API key and nothing leaving the device. Selecting it checks the local service and the model chosen in Control; it never downloads one. Capture stays refused until that check answers."},
    gemini: {button: "providerGemini", help: "helpGemini", name: "Gemini · pending", scope: "CLEANUP · CLOUD", footer: "Gemini · setup required", description: "Gemini is the planned cloud text-cleanup route. Its Windows adapter, model and secure credential setup are not connected yet. Selecting it sends no data and verifies no key. Select Literal to dictate now."}
  };
  const filters = {logAll: "all", logCapture: "capture", logCleanup: "cleanup", logSystem: "system", logErrors: "error"};
  const filterLabels = {logAll: "ALL", logCapture: "MIC/STT", logCleanup: "AI CLEAN", logSystem: "SYSTEM", logErrors: "ERRORS"};
  const canCapture = () => connected && snapshot?.provider_ready !== false && !providerPending;
  const busy = () => snapshot && ["arming", "recording", "processing"].includes(snapshot.status);
  const tell = message => { $("notice").textContent = String(message || ""); $("notice").hidden = !message; };
  const invoke = (command, args) => bridge.core.invoke(command, args);
  const safely = action => Promise.resolve().then(action).catch(tell);
  function node(tag, text, className) {
    const element = document.createElement(tag);
    if (text !== undefined) element.textContent = String(text);
    if (className) element.className = className;
    return element;
  }
  function button(text, action) {
    const element = node("button", text);
    element.type = "button";
    element.disabled = !connected || !!busy() || memoryBusy;
    element.addEventListener("click", () => safely(action));
    return element;
  }
  function confirm(text, action) {
    confirmAction = action;
    $("confirmText").textContent = text;
    $("confirmDialog").showModal();
  }
  $("confirmNo").addEventListener("click", () => { confirmAction = null; $("confirmDialog").close(); });
  $("confirmDialog").addEventListener("cancel", () => { confirmAction = null; });
  $("confirmYes").addEventListener("click", () => {
    const action = confirmAction; confirmAction = null; $("confirmDialog").close();
    if (action) safely(action);
  });
  const deliveryLabel = entry => ({pasted: "Inserted into the original target", copied: "Copied — ready to paste", copy_failed: "Clipboard failed — your words are still here"}[entry.delivery] || entry.delivery);
  async function copy(entry, raw = false) {
    await invoke("copy_entry", {id: entry.id, raw});
    tell(raw ? "Original transcript copied." : "Result copied.");
  }
  function renderHistory() {
    const list = $("historyList"); list.replaceChildren();
    const entries = snapshot?.history || [];
    if (!entries.length) list.append(node("p", "Your next dictation will appear here. Nothing is saved to disk.", "empty-row"));
    for (const entry of entries) {
      const row = node("article", undefined, "memory-row");
      row.append(node("small", `${entry.target} · ${deliveryLabel(entry)}`), node("p", entry.final_text));
      const actions = node("div", undefined, "result-actions");
      actions.append(button("Copy result", () => copy(entry)), button("Copy original", () => copy(entry, true)));
      row.append(actions); list.append(row);
    }
    $("clearHistory").disabled = !connected || !!busy() || !entries.length;
  }
  function renderMemory() {
    $("historyPanel").hidden = library !== "history";
    $("memoryPanel").hidden = library === "history";
    $("correctionForm").hidden = library !== "corrections";
    $("memoryPath").textContent = memory?.directory || "Loaded only when you open a memory category.";
    $("memoryWarning").textContent = memory?.warning || "";
    $("refreshMemory").disabled = !connected || memoryBusy || !!busy();
    for (const id of ["correctionForm"]) {
      Array.from($(id).elements).forEach(element => { element.disabled = !connected || memoryBusy || !!busy(); });
    }
    const list = $("memoryList"); list.replaceChildren();
    if (library === "history") return;
    if (!memory) { list.append(node("p", memoryBusy ? "Reading local memory…" : "Refresh to load your local memory.", "empty-row")); return; }
    const entries = memory[library] || [];
    if (!entries.length) list.append(node("p", "No entries yet.", "empty-row"));
    for (const entry of entries) {
      const row = node("article", undefined, "memory-row");
      if (library === "vocabulary") { row.append(node("p", entry)); list.append(row); continue; }
      const correction = library === "corrections";
      const key = correction ? entry.heard : entry.trigger;
      const value = correction ? entry.intended : entry.expansion;
      row.append(node("strong", key), node("p", value));
      const actions = node("div", undefined, "result-actions");
      actions.append(button("Edit", () => {
        const form = $(correction ? "correctionForm" : "snippetForm");
        form.elements[correction ? "heard" : "trigger"].value = key;
        form.elements[correction ? "intended" : "expansion"].value = value;
        if (correction) form.elements.allow_global.checked = false;
        form.elements[correction ? "heard" : "trigger"].focus();
      }), button("Delete", () => confirm(`Delete “${key}” from your local memory?`, () => memoryAction(correction ? {action: "correction_delete", heard: key} : {action: "snippet_delete", trigger: key}))));
      row.append(actions); list.append(row);
    }
    if (library === "vocabulary") list.append(node("p", "Vocabulary is read-only here. Use the engine's vocabulary file to edit it.", "hint"));
  }
  function renderSnippets() {
    Array.from($("snippetForm").elements).forEach(element => { element.disabled = !connected || memoryBusy || !!busy(); });
    $("refreshSnippets").disabled = !connected || memoryBusy || !!busy();
    $("snippetWarning").textContent = memory?.warning || "";
    $("snippetWarning").hidden = !memory?.warning;
    const entries = memory?.snippets || [];
    $("snippetCount").textContent = memory ? `${entries.length} voice snippet${entries.length === 1 ? "" : "s"} · local` : "Local voice snippets";
    const list = $("snippetList"); list.replaceChildren();
    if (!entries.length) {
      const empty = node("div", undefined, "terminal-empty");
      empty.append(node("span", "❝≡", "empty-symbol"), node("h2", memoryBusy ? "Reading local snippets…" : memory ? "No voice snippets registered yet." : "Your voice snippets live here."), node("p", "Say a trigger phrase to expand URLs, signatures or templates."));
      list.append(empty);
    }
    for (const entry of entries) {
      const row = node("article", undefined, "memory-row");
      row.append(node("strong", entry.trigger));
      if (entry.description) row.append(node("small", entry.description, "snippet-description"));
      row.append(node("p", entry.expansion));
      const actions = node("div", undefined, "result-actions");
      actions.append(button("Edit", () => {
        const fields = $("snippetForm").elements;
        fields.trigger.value = entry.trigger; fields.expansion.value = entry.expansion;
        fields.description.value = entry.description || ""; fields.trigger.focus();
      }), button("Delete", () => confirm(`Delete “${entry.trigger}” from your local snippets?`, () => memoryAction({action: "snippet_delete", trigger: entry.trigger}))));
      row.append(actions); list.append(row);
    }
  }
  async function memoryAction(request) {
    if (memoryBusy || busy()) throw new Error("Finish the dictation before changing or refreshing memory.");
    memoryBusy = true; renderMemory(); renderSnippets();
    try {
      memory = await invoke("memory_request", {request});
      tell(memory.warning || (request.action === "read" ? "" : "Local memory updated."));
    } finally { memoryBusy = false; renderMemory(); renderSnippets(); }
  }
  function meter(level) {
    const value = snapshot?.status === "recording" && Number.isFinite(level) ? Math.max(0, Math.min(1, level)) : 0;
    if (meterReset !== null) { window.clearTimeout(meterReset); meterReset = null; }
    // A short history of measured loudness, not simulated frequency bands.
    if (value > 0) {
      voiceEnvelope.shift(); voiceEnvelope.push(value);
      meterReset = window.setTimeout(() => meter(0), 240);
    } else voiceEnvelope.fill(0);
    $("voiceDial").style.setProperty("--voice-scale", String(1 + .04 * Math.sqrt(value)));
    $("voiceDial").style.setProperty("--voice-glow", String(.55 * Math.sqrt(value)));
    const bars = all(".bars i");
    bars.forEach((bar, index) => {
      bar.classList.toggle("active", index < Math.round(value * bars.length));
      bar.style.setProperty("--voice-height", `${9 + 19 * Math.sqrt(voiceEnvelope[index] || 0)}px`);
    });
  }
  function renderLog() {
    $("eventLog").hidden = consoleView !== "log";
    $("logFilters").hidden = consoleView !== "log";
    $("resultPanel").hidden = consoleView !== "result";
    $("resultActions").hidden = consoleView !== "result";
    for (const [id, view] of [["consoleLog", "log"], ["consoleResult", "result"]]) {
      $(id).setAttribute("aria-pressed", String(consoleView === view));
      $(id).classList.toggle("console-tab", consoleView === view);
    }
    const entries = snapshot?.log || [];
    for (const [id, category] of Object.entries(filters)) {
      const count = entries.filter(entry => category === "all" || category === entry.category).length;
      // A count is shown only when it carries one. ERRORS goes further: its arrival is the
      // signal, and the row has no width for a chip that would read zero almost always.
      $(id).textContent = count ? `${filterLabels[id]} (${count})` : filterLabels[id];
      $(id).hidden = id === "logErrors" && count === 0;
      $(id).setAttribute("aria-pressed", String(logFilter === category));
    }
    // An error can age out of the bounded log while its filter is selected. Hiding the
    // chip under the cursor would leave the view empty with no way back to it.
    if (logFilter === "error" && $("logErrors").hidden) { logFilter = "all"; lastLogKey = ""; return renderLog(); }
    const key = `${entries[0]?.id}:${entries.at(-1)?.id}:${logFilter}`;
    if (key === lastLogKey) return;
    lastLogKey = key;
    const list = $("eventLog");
    const atBottom = !Number.isFinite(list.scrollTop) || list.scrollHeight - list.scrollTop - list.clientHeight < 36;
    const previousScroll = list.scrollTop;
    list.replaceChildren();
    for (const entry of entries.filter(entry => logFilter === "all" || entry.category === logFilter)) {
      const row = node("div", undefined, "event-row");
      const stamp = Number.isFinite(entry.timestamp_ms) ? new Date(entry.timestamp_ms).toLocaleTimeString([], {hour12: false}) : "—";
      row.append(node("time", `[${stamp}]`), node("span", entry.tag, `event-tag tag-${entry.tag.toLowerCase().replace(/[^a-z]/g, "")}`), node("span", entry.message));
      list.append(row);
    }
    if (!list.children.length) list.append(node("p", "No events in this category.", "log-empty"));
    list.scrollTop = atBottom ? list.scrollHeight : previousScroll;
  }
  // What the local route needs is never an account or a key: it is a model on this
  // machine, or the service running. Calling either one "setup" reads as a sign-up, and
  // sends the reader looking for a form that does not exist.
  const LOCAL_STATES = {
    ready: {label: "LOCAL · READY", hint: null},
    no_model_chosen: {label: "CHOOSE A MODEL", hint: "Open Control, choose one of your installed Ollama models and save. No key, nothing leaves this computer."},
    no_model_installed: {label: "NO MODEL INSTALLED", hint: "Ollama is running but holds no model. Install one on this computer, then check again in Control."},
    model_missing: {label: "MODEL NOT INSTALLED", hint: "The saved model is not on this computer. Choose an installed one in Control."},
    unreachable: {label: "SERVICE OFF", hint: "Ollama is not answering on this computer. Start it, then check again in Control."}
  };
  function localState() {
    if (snapshot?.provider !== "ollama") return null;
    if (snapshot?.status === "checking") return {label: "CHECKING…", hint: "Reading the local service and the models it holds."};
    return LOCAL_STATES[snapshot?.provider_state] || {label: "NOT CHECKED", hint: "Open Control and check the local service."};
  }
  function renderProvider() {
    const selected = snapshot?.provider || "literal", route = providers[selected] || providers.literal;
    for (const [name, provider] of Object.entries(providers)) {
      $(provider.button).disabled = !connected || !!busy() || held || finishing || providerPending;
      $(provider.button).setAttribute("aria-pressed", String(name === selected));
      $(provider.button).classList.toggle("selected", name === selected);
      $(provider.button).textContent = `${name === selected ? "◉" : "○"} ${{literal: "Literal — no cleanup", ollama: "Local cleanup — Ollama", gemini: "Gemini — cloud, text only"}[name]}`;
    }
    $("cleanupScope").textContent = route.scope;
    $("cleanupName").textContent = route.name;
    $("cleanupNode").className = `signal-node route-${selected}`;
    $("cleanupIcon").className = `signal-icon route-icon-${selected}`;
    $("cleanupLamp").classList.toggle("pending", snapshot?.provider_ready === false);
    // The reading belongs to the run, not to the current setting: the engine reports
    // the seconds cleanup spent, and an unmeasured stage stays empty rather than
    // showing a dash that could mean either "off" or "nobody looked".
    const last = snapshot?.history[0];
    $("cleanupReading").textContent = Number.isFinite(last?.cleanup_seconds)
      ? `${last.cleanup_seconds.toFixed(2)} s`
      : selected === "literal" ? "OFF" : "—";
    const local = localState();
    $("providerStatus").textContent = selected === "literal" ? "LITERAL · NO CLOUD" : local ? local.label : "API KEY REQUIRED";
    $("providerFooter").textContent = route.footer;
    $("providerSetup").hidden = false;
    // The strip names what is actually loaded, and stays on screen when it is. Hiding it
    // once everything worked left no place to read the model back without changing a
    // setting to make the panel reappear.
    $("setupModel").textContent = `SPEECH · ${snapshot?.model || "not chosen"}`;
    $("setupConnection").textContent = selected === "gemini"
      ? "KEY · Not configured"
      : selected === "literal"
        ? "CLEANUP · off"
        : `CLEANUP · ${snapshot?.preferences.ollama_model || "no model chosen"}`;
    $("providerSetup").classList.toggle("local-route", selected === "ollama");
    if (snapshot?.provider_ready === false) {
      $("capsuleState").textContent = local ? local.label : "API KEY REQUIRED";
      $("consoleStatus").textContent = local ? local.label : "API key required";
      $("captureHint").textContent = local
        ? local.hint
        : "Gemini needs an API key, which has no Windows path yet. Select Literal or Ollama to dictate on this computer.";
      $("captureCaption").textContent = "Ambient motion · microphone off.";
    }
    renderLog();
  }
  function renderModels() {
    const select = $("speechModel");
    const selected = preferencesDirty ? select.value : snapshot?.preferences.speech_model || snapshot?.model || "";
    select.replaceChildren();
    for (const model of localModels || []) {
      const option = node("option", `${model.name} · ${(model.size_bytes / 1_000_000).toFixed(0)} MB${model.available ? "" : " · unavailable"}`);
      option.value = model.name; option.disabled = !model.available; select.append(option);
    }
    if (selected && !localModels?.some(model => model.name === selected)) {
      const option = node("option", `${selected}${localModels ? " · missing" : " · not checked yet"}`);
      option.value = selected; option.disabled = true; select.append(option);
    }
    select.value = selected;
    select.disabled = !connected || !!busy() || modelsBusy;
    $("refreshModels").disabled = !connected || !!busy() || modelsBusy;
    const model = localModels?.find(item => item.name === selected);
    $("speechModelStatus").textContent = modelsBusy ? "Checking local files…" : model ? model.detail : localModels ? "Selected model is missing. Choose an available model." : "Local files have not been checked yet.";
  }
  // A dropdown that shows the new model looks like the new model is in use. It is not:
  // a dictation reads what was saved, and nothing said the two had parted.
  function renderDirty() {
    $("unsavedNote").hidden = !preferencesDirty;
    $("savePreferences").textContent = preferencesDirty ? "Save settings ·" : "Save settings";
  }
  function renderCleanupModel() {
    const select = $("cleanupModel");
    const chosen = preferencesDirty ? select.value : snapshot?.preferences.ollama_model || "";
    const installed = snapshot?.provider_models || [];
    select.replaceChildren();
    const none = node("option", "None — local cleanup off");
    none.value = "";
    select.append(none);
    for (const name of installed) {
      const option = node("option", name);
      option.value = name;
      select.append(option);
    }
    // A chosen model that the service does not hold stays visible and refused, rather
    // than being replaced by whichever one happens to be installed.
    if (chosen && !installed.includes(chosen)) {
      const option = node("option", `${chosen}${installed.length ? " · not installed" : " · not checked yet"}`);
      option.value = chosen;
      option.disabled = installed.length > 0;
      select.append(option);
    }
    select.value = chosen;
    select.disabled = !connected || !!busy();
    $("checkCleanup").disabled = !connected || !!busy();
    $("cleanupModelStatus").textContent = snapshot?.provider_detail
      || "Not checked yet. Nothing is downloaded from here.";
  }
  $("checkCleanup").addEventListener("click", () => safely(async () => render(await invoke("check_provider"))));
  $("cleanupModel").addEventListener("change", () => { preferencesDirty = true; renderCleanupModel(); renderDirty(); });

  async function refreshModels() {
    if (!connected || busy() || modelsBusy) return;
    modelsBusy = true; renderModels();
    try { localModels = await invoke("list_speech_models"); }
    finally { modelsBusy = false; renderModels(); }
  }
  $("refreshModels").addEventListener("click", () => safely(refreshModels));
  $("speechModel").addEventListener("change", () => { preferencesDirty = true; renderModels(); renderDirty(); });
  for (const [name, provider] of Object.entries(providers)) {
    $(provider.button).addEventListener("click", () => safely(async () => {
      if (!connected || busy() || held || finishing || providerPending) return;
      providerPending = true; if (snapshot) render(snapshot);
      try {
                // The result stays in view. Switching the console back to the log on every route
        // change took the last dictation off screen a second after it arrived.
        render(await invoke("select_provider", {provider: name})); tell("");
        // Selection is not readiness: the local route is measured before it can capture.
        if (name === "ollama") render(await invoke("check_provider"));
      }
      finally { providerPending = false; if (snapshot) render(snapshot); }
    }));
    $(provider.help).addEventListener("click", () => { $("providerHelpText").textContent = provider.description; $("providerHelp").showModal(); });
  }
  $("closeProviderHelp").addEventListener("click", () => $("providerHelp").close());
  $("consoleLog").addEventListener("click", () => { consoleView = "log"; renderLog(); });
  $("consoleResult").addEventListener("click", () => { consoleView = "result"; renderLog(); });
  for (const [id, category] of Object.entries(filters)) $(id).addEventListener("click", () => { logFilter = category; lastLogKey = ""; renderLog(); });
  function render(next) {
    if (!next || (snapshot && next.revision < snapshot.revision)) return;
    snapshot = next;
    const active = !!busy();
    const status = ({ready: "READY", arming: "HOLD…", recording: "ON AIR", processing: "TRANSCRIBING", completed: "DELIVERED", failed: "ERROR", cancelled: "CANCELLED", too_short: "TOO SHORT", refused: "NOT READY"})[next.status] || next.status.toUpperCase();
    $("connectionTag").textContent = status; $("capsuleState").textContent = status;
    $("consoleStatus").textContent = status;
    $("sessionStatus").textContent = next.error || ({ready: "Native station connected. Local dictation ready.", arming: "Hold detected. Waiting for the microphone.", recording: "Microphone active. Release to transcribe.", processing: "Whisper is transcribing on this device.", completed: "Dictation processed. Delivery result below.", cancelled: "Recording cancelled. No transcript created.", too_short: "Hold ended before recording started.", refused: "Trigger refused; the microphone never opened."})[next.status] || status;
    $("historyCount").textContent = String(next.history.length);
    $("outputBadge").textContent = next.preferences.auto_paste ? "AUTO-PASTE" : "CLIPBOARD";
    $("appVersion").textContent = `v${next.version}`;
    $("activeModel").textContent = next.model;
    $("deliverySetting").textContent = next.preferences.auto_paste ? "Verified target" : "Clipboard only";
    $("captureHint").textContent = `Hold ${ {right_ctrl: "Right Ctrl", f8: "F8", f9: "F9"}[next.preferences.shortcut] } in another app, or hold the button here. Escape cancels recording.`;
    $("captureCaption").textContent = ({arming: "Keep holding to open the microphone.", recording: "Listening. Release to transcribe.", processing: "Your words are being processed on this computer."})[next.status] || "Ambient motion · hold to turn on the microphone.";
    for (const id of ["dialButton", "recordButton"]) {
      $(id).disabled = !canCapture() || (active && !held);
      $(id).setAttribute("aria-pressed", String(held));
    }
    $("recordButton").textContent = held ? "Release to transcribe" : "Hold to talk";
    $("cancelButton").hidden = !["arming", "recording"].includes(next.status);
    Array.from($("preferencesForm").elements).forEach(element => { element.disabled = !connected || active; });
    renderDirty();
    if (!preferencesDirty) {
      const fields = $("preferencesForm").elements;
      fields.shortcut.value = next.preferences.shortcut;
      fields.hold_delay_ms.value = next.preferences.hold_delay_ms;
      fields.auto_paste.checked = next.preferences.auto_paste;
      fields.ollama_model.value = next.preferences.ollama_model || "";
    }
    const entry = next.history[0];
    if (displayedId !== (entry?.id ?? null)) { $("rawText").hidden = true; $("toggleRaw").textContent = "Show original"; displayedId = entry?.id ?? null; if (entry) consoleView = "result"; }
    $("finalText").textContent = entry?.final_text || "Room for your next thought.";
    $("rawText").textContent = entry?.raw_text || "";
    $("deliveryLabel").textContent = entry
      ? [entry.target, entry.speech_model, entry.cleaner, deliveryLabel(entry)].filter(Boolean).join(" · ")
      : "Your transcript will appear here after a dictation.";
    // A cleanup that was replaced says which side refused, because the two call for
    // opposite responses: shorten the sentence, or wait for the provider.
    $("fallbackNote").textContent = entry?.fallback_reason
      ? entry.fallback_reason === "guard"
        ? "Cleanup was refused by the output guard. The deterministic transcript was delivered."
        : "The cleanup provider did not answer. The deterministic transcript was delivered."
      : "";
    $("fallbackNote").hidden = !entry?.fallback_reason;
    $("sttReading").textContent = Number.isFinite(entry?.stt_seconds) ? `${entry.stt_seconds.toFixed(2)} s` : "—";
    $("wpmReading").textContent = Number.isFinite(entry?.wpm) ? `${entry.wpm} WPM` : "—";
    $("copyLast").disabled = !connected || active || !entry;
    $("toggleRaw").disabled = !entry;
    if (next.error) tell(next.error);
    if (next.status !== "recording") meter(0);
    renderHistory(); renderMemory(); renderSnippets(); renderProvider(); renderModels(); renderCleanupModel();
  }
  function begin() {
    if (!canCapture() || held || finishing || busy()) return;
    held = true; tell("");
    starting = invoke("start_capture").then(() => true, error => { held = false; tell(error); if (snapshot) render(snapshot); return false; });
    if (snapshot) render(snapshot);
  }
  function end(cancel = false) {
    if (!held) return;
    held = false;
    const pending = starting; starting = null; finishing = true;
    safely(async () => {
      try { if (await pending) await invoke(cancel ? "cancel_capture" : "stop_capture"); }
      finally { finishing = false; if (snapshot) render(snapshot); }
    });
    if (snapshot) render(snapshot);
  }
  for (const id of ["dialButton", "recordButton"]) {
    const element = $(id);
    element.addEventListener("pointerdown", event => {
      if (event.button !== 0 || element.disabled) return;
      event.preventDefault(); element.setPointerCapture(event.pointerId); begin();
    });
    element.addEventListener("pointerup", () => end());
    element.addEventListener("pointercancel", () => end(true));
    element.addEventListener("lostpointercapture", () => end(true));
    element.addEventListener("keydown", event => {
      if (![" ", "Enter"].includes(event.key)) return;
      event.preventDefault(); if (!event.repeat) begin();
    });
    element.addEventListener("keyup", event => { if ([" ", "Enter"].includes(event.key)) { event.preventDefault(); end(); } });
  }
  window.addEventListener("pointerup", () => end());
  window.addEventListener("keyup", event => { if ([" ", "Enter"].includes(event.key)) end(); });
  window.addEventListener("blur", () => end(true));
  $("cancelButton").addEventListener("click", () => { if (held) end(true); else safely(() => invoke("cancel_capture")); });
  all("[data-page]").forEach(element => element.addEventListener("click", () => {
    all("[data-page]").forEach(item => item.setAttribute("aria-current", item === element ? "page" : "false"));
    ["station", "modes", "snippets", "words", "control"].forEach(id => { $(id).hidden = id !== element.dataset.page; });
    $("sectionName").textContent = {station: "Station", modes: "Modes", snippets: "Snippets", words: "Your words", control: "Control"}[element.dataset.page];
    if (element.dataset.page === "snippets" && !memory && !memoryBusy && connected) safely(() => memoryAction({action: "read"}));
    if (element.dataset.page === "control" && !localModels && !modelsBusy && connected) safely(refreshModels);
    if (element.dataset.page === "control" && !snapshot?.provider_detail && connected) safely(async () => render(await invoke("check_provider")));
  }));
  all("[data-library]").forEach(element => element.addEventListener("click", () => {
    library = element.dataset.library;
    all("[data-library]").forEach(item => item.setAttribute("aria-pressed", String(item === element)));
    renderMemory(); if (library !== "history" && !memory && !memoryBusy && connected) safely(() => memoryAction({action: "read"}));
  }));
  $("refreshMemory").addEventListener("click", () => safely(() => memoryAction({action: "read"})));
  $("refreshSnippets").addEventListener("click", () => safely(() => memoryAction({action: "read"})));
  $("consoleHistory").addEventListener("click", () => {
    all("[data-page]").find(item => item.dataset.page === "words").click();
    all("[data-library]").find(item => item.dataset.library === "history").click();
  });
  $("consoleSnippets").addEventListener("click", () => {
    all("[data-page]").find(item => item.dataset.page === "snippets").click();
  });
  for (const id of ["correctionForm", "snippetForm"]) $(id).addEventListener("submit", event => {
    event.preventDefault(); const fields = $(id).elements;
    const request = id === "correctionForm" ? {action: "correction_save", heard: fields.heard.value, intended: fields.intended.value, allow_global: fields.allow_global.checked} : {action: "snippet_save", trigger: fields.trigger.value, expansion: fields.expansion.value, description: fields.description.value};
    safely(async () => { await memoryAction(request); $(id).reset(); });
  });
  $("preferencesForm").addEventListener("input", () => { preferencesDirty = true; renderDirty(); });
  $("preferencesForm").addEventListener("submit", event => {
    event.preventDefault(); const fields = $("preferencesForm").elements;
    $("unsavedNote").hidden = false;
    $("unsavedNote").textContent = "Saving…";
    safely(async () => {
      await invoke("set_preferences", {preferences: {shortcut: fields.shortcut.value, hold_delay_ms: Number(fields.hold_delay_ms.value), auto_paste: fields.auto_paste.checked, speech_model: fields.speech_model.value || null, ollama_model: fields.ollama_model.value || null, paste_shortcut: snapshot?.preferences.paste_shortcut ?? "auto"}});
      preferencesDirty = false; render(await invoke("get_station"));
      // The saved model is what the check measures, so it is measured again here.
      render(await invoke("check_provider"));
      $("unsavedNote").textContent = "Not saved yet. Your choice reaches a dictation only after you save.";
      tell("Settings saved on this computer.");
    });
  });
  $("copyLast").addEventListener("click", () => { if (snapshot?.history[0]) safely(() => copy(snapshot.history[0])); });
  $("toggleRaw").addEventListener("click", () => { $("rawText").hidden = !$("rawText").hidden; $("toggleRaw").textContent = $("rawText").hidden ? "Show original" : "Hide original"; });
  $("clearHistory").addEventListener("click", () => confirm("Clear all transcripts from this session? This cannot be undone.", () => invoke("clear_history")));
  async function connect() {
    if (!bridge?.core?.invoke || !bridge?.event?.listen) throw new Error("Open the VoiceFlow desktop app to connect the microphone and local engine.");
    await Promise.all([bridge.event.listen("hub:state", event => render(event.payload)), bridge.event.listen("hud:vu-level", event => meter(event.payload))]);
    connected = true; render(await invoke("get_station"));
  }
  connect().catch(error => { connected = false; if (snapshot) render(snapshot); $("connectionTag").textContent = "DISCONNECTED"; $("capsuleState").textContent = "DISCONNECTED"; tell(error); });
})();
