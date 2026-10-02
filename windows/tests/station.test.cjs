const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const vm = require('node:vm');
const flush = () => new Promise(resolve => setImmediate(resolve));
function element() {
  const events = {}, classes = new Set();
  return {events, textContent: '', hidden: false, disabled: false, children: [], dataset: {}, value: '', checked: false,
    style: {setProperty(name, value) {this[name] = value;}},
    addEventListener(name, callback) { (events[name] ||= []).push(callback); },
    fire(name, event = {}) { for (const fn of events[name] || []) fn({preventDefault() {}, button: 0, pointerId: 1, ...event}); },
    click() { this.fire('click'); },
    setAttribute(name, value) { this[name] = value; },
    append(...nodes) { this.children.push(...nodes); }, replaceChildren() { this.children = []; },
    setPointerCapture() {}, focus() {}, showModal() { this.open = true; }, close() { this.open = false; },
    classList: {toggle(name, on) { on ? classes.add(name) : classes.delete(name); }, contains(name) { return classes.has(name); }}
  };
}
const state = (revision = 0, status = 'ready', history = []) => ({revision, status, history, error: null, provider: 'literal', provider_ready: true, log: [], preferences: {shortcut: 'right_ctrl', hold_delay_ms: 0, auto_paste: true}, model: 'ggml-base.bin', version: 'test'});
function station({native = true, initial = state(), invoke: override} = {}) {
  const nodes = {}, listeners = {}, calls = [], win = element(), timers = new Map();
  let timerId = 0;
  win.setTimeout = callback => {timers.set(++timerId, callback); return timerId;};
  win.clearTimeout = id => timers.delete(id);
  const html = readFileSync(join(__dirname, '../ui/station.html'), 'utf8');
  for (const match of html.matchAll(/id="([^"]+)"/g)) nodes[match[1]] = element();
  for (const [id, names] of Object.entries({preferencesForm: ['shortcut','hold_delay_ms','auto_paste','speech_model','ollama_model'], correctionForm: ['heard','intended','allow_global'], snippetForm: ['trigger','expansion','description']})) {
    const fields = names.map(() => element()); names.forEach((name,i) => fields[name] = fields[i]);
    nodes[id].elements = fields; nodes[id].reset = () => fields.forEach(field => { field.value = ''; field.checked = false; });
  }
  nodes.speechModel = nodes.preferencesForm.elements.speech_model;
  nodes.cleanupModel = nodes.preferencesForm.elements.ollama_model;
  const groups = {'[data-page]': Array.from(html.matchAll(/data-page="([^"]+)"/g), match => Object.assign(element(), {dataset: {page: match[1]}})),
    '[data-library]': Array.from(html.matchAll(/data-library="([^"]+)"/g), match => Object.assign(element(), {dataset: {library: match[1]}})), '.bars i': Array.from({length: 12}, element)};
  if (native) win.__TAURI__ = {core: {invoke(command, args) { calls.push({command,args}); return Promise.resolve(override ? override(command,args) : command === 'get_station' ? initial : undefined); }}, event: {listen(name, fn) { listeners[name] = fn; return Promise.resolve(() => {}); }}};
  vm.runInNewContext(readFileSync(join(__dirname, '../ui/station.js'), 'utf8'), {window: win, document: {getElementById: id => {assert.ok(nodes[id], `unknown DOM id ${id}`); return nodes[id];}, querySelectorAll: selector => {assert.ok(groups[selector], selector); return groups[selector];}, createElement: element}, console});
  return {nodes, groups, calls, win, timers, emit(payload) { listeners['hub:state']({payload}); }, vu(payload) {listeners['hud:vu-level']({payload});}};
}
test('missing native bridge cannot present a ready microphone', async () => {
  const h = station({native: false}); await flush();
  assert.equal(h.nodes.connectionTag.textContent, 'DISCONNECTED');
  assert.match(h.nodes.notice.textContent, /desktop app/);
  assert.equal(h.calls.length, 0);
});
test('older startup response cannot overwrite a newer native state', async () => {
  let resolve;
  const h = station({invoke: command => command === 'get_station' ? new Promise(r => {resolve = r;}) : undefined});
  await flush(); h.emit(state(3, 'processing')); resolve(state(1)); await flush();
  assert.equal(h.nodes.connectionTag.textContent, 'TRANSCRIBING');
  assert.equal(h.nodes.recordButton.disabled, true);
  assert.ok(h.nodes.preferencesForm.elements.every(field => field.disabled));
});
test('fast release waits for start acknowledgement, without duplicate stop or press', async () => {
  let resolve;
  const h = station({invoke: command => command === 'get_station' ? state() : command === 'start_capture' ? new Promise(r => {resolve = r;}) : undefined});
  await flush(); h.nodes.recordButton.fire('pointerdown'); h.nodes.recordButton.fire('keydown', {key:' ', repeat:true});
  h.nodes.recordButton.fire('pointerup'); h.win.fire('pointerup'); h.nodes.recordButton.fire('pointerdown'); await flush();
  assert.equal(h.calls.filter(x => x.command === 'stop_capture').length, 0);
  resolve(); await flush();
  assert.equal(h.calls.filter(x => x.command === 'start_capture').length, 1);
  assert.equal(h.calls.filter(x => x.command === 'stop_capture').length, 1);
});
test('lost focus cancels only button-owned capture', async () => {
  const h = station(); await flush(); h.emit(state(1,'recording')); h.win.fire('blur'); await flush();
  assert.equal(h.calls.filter(x => x.command === 'cancel_capture').length, 0);
  h.emit(state(2)); h.nodes.dialButton.fire('pointerdown'); h.win.fire('blur'); await flush();
  assert.equal(h.calls.filter(x => x.command === 'cancel_capture').length, 1);
});
test('copy failure remains recoverable; transcript markup is text, telemetry is measured', async () => {
  const entry = {id:9,raw_text:'<img src=x onerror=alert(1)>',final_text:'Español 日本語',target:'NOTEPAD',delivery:'copy_failed',wpm:null,stt_seconds:1.234};
  const h = station({initial: state(4,'failed',[entry])}); await flush();
  assert.equal(h.nodes.rawText.textContent, entry.raw_text);
  assert.match(h.nodes.deliveryLabel.textContent,/Clipboard failed/);
  assert.equal(h.nodes.sttReading.textContent,'1.23 s');
  assert.equal(h.nodes.wpmReading.textContent,'—');
  h.nodes.copyLast.fire('click'); await flush();
  assert.equal(h.calls.at(-1).command,'copy_entry'); assert.equal(h.calls.at(-1).args.id,9);
  h.vu(1); assert.ok(h.groups['.bars i'].every(bar => !bar.classList.contains('active')));
  h.emit(state(5,'recording',[entry])); h.vu(.5);
  assert.equal(h.groups['.bars i'].filter(bar => bar.classList.contains('active')).length,6);
});
test('history removal requires confirmation and memory is not read on startup', async () => {
  const h = station(); await flush(); assert.deepEqual(h.calls.map(x=>x.command), ['get_station']);
  h.nodes.clearHistory.fire('click'); await flush(); assert.equal(h.calls.length,1);
  h.nodes.confirmNo.fire('click'); await flush(); assert.equal(h.calls.length,1);
  h.nodes.clearHistory.fire('click'); h.nodes.confirmYes.fire('click'); await flush();
  assert.equal(h.calls.at(-1).command,'clear_history');
});

test('provider selection measures the local route and never starts or downloads one', async () => {
  let revision = 0;
  const h = station({invoke: (command, args) => {
    if (command === 'get_station') return state();
    if (command === 'select_provider') return {...state(++revision, args.provider === 'literal' ? 'ready' : args.provider === 'ollama' ? 'checking' : 'not_configured'), provider: args.provider, provider_ready: args.provider === 'literal', provider_models: [], log: [{id:revision,timestamp_ms:1000,category:'cleanup',tag:args.provider.toUpperCase(),message:'Selected route.'}]};
    // The check reads the service's inventory. It reports a missing model; it never pulls one.
    if (command === 'check_provider') return {...state(++revision, 'not_configured'), provider: 'ollama', provider_ready: false, provider_state: 'model_missing', provider_detail: 'service available; model not installed: qwen3:1.7b', provider_models: ['other:1b'], log: [{id:revision,timestamp_ms:1000,category:'cleanup',tag:'OLLAMA',message:'Local cleanup: model not installed.'}]};
    throw Error(`Unexpected command ${command}`);
  }});
  await flush();
  h.nodes.providerOllama.fire('click'); await flush();
  assert.equal(h.nodes.cleanupName.textContent,'ollama local');
  assert.equal(h.nodes.cleanupScope.textContent,'CLEANUP · LOCAL');
  assert.equal(h.nodes.providerOllama['aria-pressed'],'true');
  // Selecting the route is not readiness: the check answered that the model is absent,
  // so capture stays refused and the reason is the service's own words.
  assert.ok(h.calls.some(call=>call.command==='check_provider'));
  assert.equal(h.nodes.recordButton.disabled,true);
  // A local route never asks for an account, so it must not say so.
  assert.equal(h.nodes.capsuleState.textContent,'MODEL NOT INSTALLED');
  assert.equal(h.nodes.setupConnection.textContent,'CLEANUP · no model chosen');
  assert.equal(h.nodes.setupModel.textContent,'SPEECH · ggml-base.bin');
  assert.equal(h.nodes.logCleanup.textContent,'AI CLEAN (1)');
  h.nodes.providerGemini.fire('click'); await flush();
  assert.equal(h.nodes.cleanupScope.textContent,'CLEANUP · CLOUD');
  assert.equal(h.nodes.setupConnection.textContent,'KEY · Not configured');
  assert.equal(h.nodes.capsuleState.textContent,'API KEY REQUIRED');
  assert.equal(h.nodes.cleanupReading.textContent,'—');
  h.nodes.recordButton.fire('keydown',{key:' ',repeat:false}); await flush();
  assert.ok(!h.calls.some(call=>call.command==='start_capture'));
  h.nodes.providerLiteral.fire('click'); await flush();
  assert.equal(h.nodes.recordButton.disabled,false);
  assert.equal(h.nodes.cleanupName.textContent,'no cleanup');
  // The strip stays up when the route works: it is where the loaded model is read back.
  assert.equal(h.nodes.providerSetup.hidden,false);
  assert.equal(h.nodes.setupConnection.textContent,'CLEANUP · off');
  // Reading an inventory and choosing a route are the only calls a selection makes.
  assert.ok(h.calls.every(call=>['get_station','select_provider','check_provider'].includes(call.command)));
});
test('provider changes wait for acknowledgement and cannot race a new button hold', async () => {
  let resolve;
  const h = station({invoke: command => command==='get_station' ? state() : new Promise(r=>{resolve=r;})});
  await flush(); h.nodes.providerGemini.fire('click'); await flush();
  h.nodes.recordButton.fire('keydown',{key:' ',repeat:false}); h.nodes.providerOllama.fire('click'); await flush();
  assert.equal(h.calls.length,2);
  resolve({...state(2,'not_configured'),provider:'gemini',provider_ready:false}); await flush();
  assert.equal(h.nodes.recordButton.disabled,true);
  assert.equal(h.nodes.providerGemini.disabled,false);
});
test('failed selection preserves the actual provider and exposes the error', async () => {
  const h = station({invoke: command => command==='get_station' ? state() : Promise.reject('Selection refused')});
  await flush(); h.nodes.providerGemini.fire('click'); await flush();
  assert.equal(h.nodes.providerLiteral['aria-pressed'],'true');
  assert.match(h.nodes.notice.textContent,/Selection refused/);
  assert.equal(h.nodes.recordButton.disabled,false);
});
test('log filters use actual categories and preserve markup as text', async () => {
  const log=[{id:1,timestamp_ms:1000,category:'system',tag:'SYS',message:'Started'}, {id:2,timestamp_ms:2000,category:'error',tag:'ERROR',message:'<img onerror=alert(1)>'}];
  const h=station({initial:{...state(),log}}); await flush();
  assert.equal(h.nodes.logAll.textContent,'ALL (2)');
  h.nodes.logErrors.fire('click');
  assert.equal(h.nodes.eventLog.children.length,1);
  assert.equal(h.nodes.eventLog.children[0].children[2].textContent,log[1].message);
  h.nodes.consoleResult.fire('click'); assert.equal(h.nodes.eventLog.hidden,true);
  h.nodes.consoleLog.fire('click'); assert.equal(h.nodes.eventLog.hidden,false);
});

test('snippets has its own page and preserves the Your words category', async () => {
  const memory = {snippets: [], corrections: [], vocabulary: [], directory: 'temporary fixture'};
  const h = station({invoke: command => command === 'get_station' ? state() : memory});
  await flush();
  assert.deepEqual(h.groups['[data-page]'].map(x => x.dataset.page), ['station','modes','snippets','words','control']);
  assert.deepEqual(h.groups['[data-library]'].map(x => x.dataset.library), ['history','vocabulary','corrections']);
  h.groups['[data-library]'][2].click(); await flush();
  h.nodes.consoleSnippets.click(); await flush();
  assert.equal(h.nodes.snippets.hidden, false);
  assert.equal(h.nodes.words.hidden, true);
  assert.equal(h.nodes.snippetCount.textContent, '0 voice snippets · local');
  h.groups['[data-page]'].find(x => x.dataset.page === 'words').click();
  assert.equal(h.nodes.snippets.hidden, true);
  assert.equal(h.nodes.correctionForm.hidden, false);
  assert.equal(h.nodes.historyPanel.hidden, true);
  assert.deepEqual(h.calls.filter(x => x.command === 'memory_request').map(x => x.args.request.action), ['read']);
  h.nodes.consoleHistory.click();
  assert.equal(h.nodes.historyPanel.hidden, false);
  assert.equal(h.nodes.correctionForm.hidden, true);
});

test('snippet editing preserves description and waits for the memory write', async () => {
  const entry = {trigger: 'my signature', expansion: '<signature>', description: 'Work'};
  const memory = {snippets: [entry], corrections: [], vocabulary: []};
  let finishSave;
  const h = station({invoke: (command, args) => command === 'get_station' ? state() : args.request.action === 'read' ? memory : new Promise(resolve => {finishSave = resolve;})});
  await flush(); h.nodes.consoleSnippets.click(); await flush();
  const row = h.nodes.snippetList.children[0];
  assert.equal(row.children[1].textContent, 'Work');
  assert.equal(row.children[2].textContent, '<signature>');
  row.children[3].children[0].click(); await flush();
  const fields = h.nodes.snippetForm.elements;
  assert.equal(fields.trigger.value, entry.trigger);
  assert.equal(fields.expansion.value, entry.expansion);
  assert.equal(fields.description.value, entry.description);
  fields.description.value = 'Updated';
  h.nodes.snippetForm.fire('submit'); await flush();
  assert.equal(h.calls.at(-1).args.request.description, 'Updated');
  assert.ok(fields.every(field => field.disabled));
  assert.equal(fields.trigger.value, entry.trigger);
  finishSave({...memory, snippets: [{...entry, description: 'Updated'}]}); await flush();
  assert.ok(fields.every(field => !field.disabled));
  assert.equal(fields.trigger.value, '');
  assert.equal(h.nodes.snippetList.children[0].children[1].textContent, 'Updated');
  h.emit(state(2, 'recording'));
  assert.ok(fields.every(field => field.disabled));
});

test('voice motion follows measured loudness and resets on silence or capture exit', async () => {
  const h = station(); await flush();
  const bars = h.groups['.bars i'];
  h.emit(state(1, 'recording'));
  h.vu(.04); const quietScale = Number(h.nodes.voiceDial.style['--voice-scale']);
  h.vu(1);
  assert.ok(Number(h.nodes.voiceDial.style['--voice-scale']) > quietScale);
  assert.equal(Number(h.nodes.voiceDial.style['--voice-scale']), 1.04);
  assert.ok(parseFloat(bars.at(-1).style['--voice-height']) > parseFloat(bars.at(-2).style['--voice-height']));
  assert.equal(h.timers.size, 1);
  for (const silent of [0, NaN, Infinity, -1]) {
    h.vu(.8); h.vu(silent);
    assert.equal(h.nodes.voiceDial.style['--voice-scale'], '1');
    assert.ok(bars.every(bar => bar.style['--voice-height'] === '9px'));
    assert.equal(h.timers.size, 0);
  }
  for (const [i, status] of ['processing','cancelled','failed','ready'].entries()) {
    h.emit(state(i * 2 + 2, 'recording')); h.vu(2);
    assert.equal(h.nodes.voiceDial.style['--voice-scale'], '1.04');
    h.emit(state(i * 2 + 3, status)); h.vu(1);
    assert.equal(h.nodes.voiceDial.style['--voice-scale'], '1');
    assert.ok(bars.every(bar => bar.style['--voice-height'] === '9px'));
    assert.equal(h.timers.size, 0);
  }
});

test('missing audio updates settle the dial and bars instead of leaving activity frozen', async () => {
  const h = station(); await flush(); h.emit(state(1, 'recording')); h.vu(1);
  [...h.timers.values()][0]();
  assert.equal(h.nodes.voiceDial.style['--voice-scale'], '1');
  assert.equal(h.nodes.voiceDial.style['--voice-glow'], '0');
  assert.ok(h.groups['.bars i'].every(bar => bar.style['--voice-height'] === '9px' && !bar.classList.contains('active')));
  assert.equal(h.timers.size, 0);
});

test('Control lists local models, preserves an unsaved choice and saves it explicitly', async () => {
  let current = state();
  const installed = [{name:'ggml-base.bin',size_bytes:148000000,available:true,detail:'Header and size checked'},
    {name:'ggml-small.bin',size_bytes:480000000,available:true,detail:'Header and size checked'},
    {name:'ggml-broken.bin',size_bytes:12,available:false,detail:'Incomplete header'}];
  const h = station({invoke:(command,args) => {
    if(command === 'get_station') return current;
    if(command === 'list_speech_models') return installed;
    if(command === 'set_preferences') {current={...state(3),model:args.preferences.speech_model,preferences:args.preferences};return;}
    throw Error(command);
  }});
  await flush(); h.groups['[data-page]'].find(x=>x.dataset.page==='control').click(); await flush();
  assert.equal(h.nodes.speechModel.value,'ggml-base.bin');
  assert.equal(h.nodes.speechModel.children[2].disabled,true);
  h.nodes.speechModel.value='ggml-small.bin';h.nodes.speechModel.fire('change');
  h.emit(state(1));
  assert.equal(h.nodes.speechModel.value,'ggml-small.bin');
  assert.ok(!h.calls.some(x=>x.command==='set_preferences'));
  h.nodes.preferencesForm.fire('submit');await flush();
  assert.equal(h.calls.find(x=>x.command==='set_preferences').args.preferences.speech_model,'ggml-small.bin');
  assert.equal(h.nodes.activeModel.textContent,'ggml-small.bin');
  h.emit({...current,revision:4,status:'recording'});
  assert.equal(h.nodes.speechModel.disabled,true);
  assert.equal(h.nodes.refreshModels.disabled,true);
});

test('missing selected model stays visible instead of silently choosing another', async () => {
  const h=station({initial:{...state(),model:'ggml-missing.bin'},invoke:command=>command==='get_station'?{...state(),model:'ggml-missing.bin'}:[]});
  await flush();h.groups['[data-page]'].find(x=>x.dataset.page==='control').click();await flush();
  assert.equal(h.nodes.speechModel.value,'ggml-missing.bin');
  assert.equal(h.nodes.speechModel.children[0].disabled,true);
  assert.match(h.nodes.speechModelStatus.textContent,/missing/);
});

test('a filter count shows only when it carries one, and ERRORS only when it holds something', async () => {
  const h = station(); await flush();
  const entry = (id, category) => ({id, timestamp_ms: 0, category, tag: 'SYS', message: 'event'});
  h.emit({...state(1), log: [entry(1, 'system')]});
  assert.equal(h.nodes.logSystem.textContent, 'SYSTEM (1)');
  assert.equal(h.nodes.logCapture.textContent, 'MIC/STT');
  // The arrival of an error is the signal; a chip reading zero spends row width saying
  // nothing, and a failure among thirty routine lines is what went unfound before.
  assert.equal(h.nodes.logErrors.textContent, 'ERRORS');
  assert.equal(h.nodes.logErrors.hidden, true);
  h.emit({...state(2), log: [entry(1, 'system'), entry(2, 'error')]});
  assert.equal(h.nodes.logErrors.textContent, 'ERRORS (1)');
  assert.equal(h.nodes.logErrors.hidden, false);
});

test('a result names the model and cleaner that produced it, and the cleanup it measured', async () => {
  const h = station(); await flush();
  const entry = {id: 1, raw_text: 'raw', final_text: 'final', delivery_text: 'final', target: 'CLAUDE',
    delivery: 'pasted', wpm: 104, latency: 4.2, stt_seconds: 3.86, speech_model: 'ggml-large-v3-turbo.bin',
    cleaner: 'ollama', cleanup_seconds: 1.42, fallback_reason: null};
  h.emit({...state(1, 'completed', [entry]), provider: 'ollama', provider_ready: true});

  // The current setting is not evidence about a run that happened before it changed.
  assert.equal(h.nodes.deliveryLabel.textContent, 'CLAUDE · ggml-large-v3-turbo.bin · ollama · Inserted into the original target');
  assert.equal(h.nodes.cleanupReading.textContent, '1.42 s');
  assert.equal(h.nodes.fallbackNote.hidden, true);

  // A replaced cleanup says which side refused; the two call for opposite responses.
  h.emit({...state(2, 'completed', [{...entry, id: 2, cleanup_seconds: null, fallback_reason: 'guard'}]), provider: 'ollama', provider_ready: true});
  assert.equal(h.nodes.fallbackNote.hidden, false);
  assert.match(h.nodes.fallbackNote.textContent, /output guard/);
  assert.equal(h.nodes.cleanupReading.textContent, '—');
});

test('a kept result survives a route change and a restart', async () => {
  const entry = {id: 7, raw_text: 'raw', final_text: 'final', delivery_text: 'final', target: 'CLAUDE',
    delivery: 'pasted', wpm: 104, latency: 4.2, stt_seconds: 3.86, speech_model: 'ggml-large-v3-turbo.bin',
    cleaner: 'ollama', cleanup_seconds: 1.42, fallback_reason: null};
  // The station starts from a history the adapter restored, not from an empty session.
  const h = station({initial: {...state(1, 'ready', [entry]), provider: 'literal', provider_ready: true}});
  await flush();
  assert.equal(h.nodes.historyCount.textContent, '1');
  assert.match(h.nodes.deliveryLabel.textContent, /ggml-large-v3-turbo\.bin/);
});

test('a chosen model that has not been saved says so', async () => {
  const h = station(); await flush();
  assert.equal(h.nodes.unsavedNote.hidden, true);

  // Choosing in the dropdown changes nothing a dictation can see until it is saved.
  h.nodes.speechModel.value = 'ggml-large-v3-turbo.bin';
  h.nodes.speechModel.fire('change');
  assert.equal(h.nodes.unsavedNote.hidden, false);

  h.nodes.preferencesForm.fire('submit'); await flush(); await flush();
  const saved = h.calls.find(call => call.command === 'set_preferences');
  assert.equal(saved.args.preferences.speech_model, 'ggml-large-v3-turbo.bin');
  assert.equal(h.nodes.unsavedNote.hidden, true);
});
