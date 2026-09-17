const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const vm = require('node:vm');

function hud(bridge = true) {
  const nodes = new Map();
  function element() {
    const classes = new Set();
    return { textContent: '', title: '', style: {}, addEventListener() {},
      classList: { add: c => classes.add(c), remove: c => classes.delete(c), contains: c => classes.has(c) } };
  }
  const bars = Array.from({ length: 12 }, element);
  const listeners = new Map(), timers = new Map();
  let timerId = 0;
  const invoked = [];
  const tauri = bridge ? { event: { listen(name, cb) { listeners.set(name, cb); return Promise.resolve(() => {}); } },
    core: { invoke(name, args) { invoked.push({ name, args }); return Promise.resolve(); } } } : {};
  vm.runInNewContext(readFileSync(join(__dirname, '../ui/app.js'), 'utf8'), {
    window: { __TAURI__: tauri }, console,
    document: { getElementById(id) { if (!nodes.has(id)) nodes.set(id, element()); return nodes.get(id); },
      querySelectorAll() { return bars; } },
    setTimeout(cb) { timers.set(++timerId, cb); return timerId; },
    clearTimeout(id) { timers.delete(id); }
  });
  return { nodes, bars, timers, invoked, emit(name, payload) { listeners.get(name)({ payload }); } };
}

test('processing describes the actual local stage; delivery never fakes microphone activity', () => {
  const h = hud();
  h.emit('hud:mode', { mode: 'processing' });
  assert.equal(h.nodes.get('stageItem').textContent, 'TRANSCRIBING');
  h.emit('hud:vu-level', 0.8);
  h.emit('hud:mode', { mode: 'completed', did_auto_paste: false, context: 'Notepad', latency: 1.5, wpm: 120 });
  assert.equal(h.nodes.get('statusText').textContent, 'COPIED');
  assert.equal(h.nodes.get('contextPill').textContent, 'NOTEPAD');
  assert.equal(h.nodes.get('stageItem').textContent, '120 WPM');
  assert.ok(h.bars.every(b => !b.classList.contains('active')));
});

test('an error replaces the success timer, keeps the full reason, and clears on its own', () => {
  const h = hud();
  h.emit('hud:mode', { mode: 'completed' });
  const error = 'The clipboard is locked by another application. Nothing was pasted.';
  h.emit('hud:mode', { mode: 'failed', error });
  // One timer, not two: the success timer was cleared, so no stale COPIED can return.
  assert.equal(h.timers.size, 1);
  assert.equal(h.nodes.get('statusText').textContent, 'ERROR');
  assert.equal(h.nodes.get('telemetryDetails').title, error);
  h.emit('hud:mode', { mode: 'recording' });
  assert.equal(h.nodes.get('telemetryDetails').title, '');
});

test('unmeasured or nonfinite telemetry stays absent', () => {
  const h = hud();
  h.emit('hud:mode', { mode: 'completed', wpm: NaN, latency: Infinity });
  assert.equal(h.nodes.get('stageItem').textContent, 'DONE');
  assert.equal(h.nodes.get('telemetryDetails').textContent, '');
  h.emit('hud:vu-level', Infinity);
  assert.ok(h.bars.every(b => !b.classList.contains('active')));
});

test('a missing native event bridge reports failure', () => {
  assert.equal(hud(false).nodes.get('statusText').textContent, 'ERROR');
});

test('unconfigured providers clear success timers and never show ready', () => {
  const h = hud();
  h.emit('hud:mode', {mode: 'completed'});
  h.emit('hud:mode', {mode: 'not_configured'});
  assert.equal(h.nodes.get('statusText').textContent, 'SETUP');
  assert.equal(h.nodes.get('stageItem').textContent, 'NOT CONNECTED');
  assert.equal(h.timers.size, 0);
  assert.ok(h.bars.every(b => !b.classList.contains('active')));
  h.emit('hud:mode', {mode: 'ready'});
  assert.equal(h.nodes.get('statusText').textContent, 'READY');
});

test('the capsule is on screen for a dictation and hidden when idle', () => {
  const h = hud();
  const shown = () => h.invoked.filter(c => c.name === 'set_capsule_visible').map(c => c.args.visible);
  for (const mode of ['arming', 'recording', 'processing', 'completed', 'failed']) {
    h.emit('hud:mode', { mode });
  }
  assert.deepEqual(shown(), [true, true, true, true, true]);
  // Both idle states hide it, and `ready` is where the success and cancel timers land.
  h.emit('hud:mode', { mode: 'ready' });
  h.emit('hud:mode', { mode: 'not_configured' });
  assert.deepEqual(shown().slice(-2), [false, false]);
});

test('a refused trigger names the reason and then takes the capsule away', () => {
  const h = hud();
  const shown = () => h.invoked.filter(c => c.name === 'set_capsule_visible').map(c => c.args.visible);
  const reason = 'Ollama is not connected yet. Select Literal to dictate locally.';
  h.emit('hud:mode', { mode: 'refused', error: reason });

  // Nothing was recorded, so this is not a lost dictation and must not sit there like one.
  assert.equal(h.nodes.get('statusText').textContent, 'NOT READY');
  assert.equal(h.nodes.get('stageItem').textContent, 'REFUSED');
  assert.equal(h.nodes.get('telemetryDetails').title, reason);
  assert.deepEqual(shown(), [true]);

  [...h.timers.values()][0]();
  assert.equal(h.nodes.get('statusText').textContent, 'READY');
  assert.deepEqual(shown(), [true, false]);
});

test('a station-side provider check never puts the capsule on screen', () => {
  const h = hud();
  const shown = () => h.invoked.filter(c => c.name === 'set_capsule_visible').map(c => c.args.visible);
  // Choosing a route in the station is not a dictation. Each of these used to open the
  // capsule with nothing that would ever close it again.
  for (const mode of ['checking', 'not_configured', 'ready']) {
    h.emit('hud:mode', { mode });
  }
  assert.deepEqual(shown(), [false, false, false]);
});
