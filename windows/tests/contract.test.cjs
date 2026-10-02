// Checks the Windows surface against `design-system.md`, which requires the measurements
// to be declared once and the colours to come from tokens. The Swift side fails its build
// on a colour literal outside the token declaration; this is its Windows counterpart.
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');

const read = name => readFileSync(join(__dirname, '..', name), 'utf8');

// Both stylesheets are matched with `[^}]*` rather than a lazy scan to a newline: one of
// them is minified onto single lines, and a pattern that needed a line break matched
// nothing there and reported the file clean while it carried seventy literals.
const ROOT = /:root\s*\{([^}]*)\}/;

function tokens(css) {
  const block = css.match(ROOT);
  assert.ok(block, 'no :root block');
  // The last declaration in a minified block carries no trailing semicolon.
  return Array.from(block[1].matchAll(/(--[\w-]+)\s*:\s*([^;]+);?/g), m => [m[1], m[2].trim()]);
}

const outsideRoot = css => css.replace(new RegExp(ROOT.source, 'g'), '');

test('the capsule is measured once, and tauri.conf.json agrees with it', () => {
  const style = Object.fromEntries(tokens(read('ui/style.css')));
  const px = name => {
    assert.ok(style[name], `${name} is not declared`);
    assert.match(style[name], /^\d+px$/, `${name} should be a pixel value, got ${style[name]}`);
    return Number.parseInt(style[name], 10);
  };

  const width = px('--capsule-width'), height = px('--capsule-height');
  const capsule = JSON.parse(read('src-tauri/tauri.conf.json')).app.windows.find(w => w.label === 'main');
  assert.ok(capsule, 'no capsule window in tauri.conf.json');

  // The window and the stylesheet used to carry these numbers independently. On the Swift
  // side that is how the capsule came to be resized 17pt narrower than its own content on
  // every show, silently, because both numbers were right when they were written.
  assert.equal(capsule.width, width, 'the window width left the stylesheet behind');
  assert.equal(capsule.height, height, 'the window height left the stylesheet behind');

  // The contract states the row as 44 + 14 + 226 inside 14px of horizontal padding, which
  // is 312, and requires the panel never to be smaller than what it carries.
  const row = px('--mic-disc') + px('--mic-gap') + px('--content-width') + 2 * px('--capsule-padding-x');
  assert.equal(row, 312, `the row now spends ${row}px; the contract states 312`);
  assert.ok(row <= width, `a ${row}px row cannot fit a ${width}px panel`);

  // Twelve bars and their eleven gaps spend 141 of the 226pt row, and the rest is what
  // the ESC reminder sits in. Widening a bar silently takes that space back.
  const meter = 12 * px('--vu-bar') + 11 * px('--vu-gap');
  assert.equal(meter, 141, `the meter now spends ${meter}px; the contract states 141`);
  assert.ok(meter < px('--content-width'), 'the meter leaves the ESC reminder no room');
});

test('no colour literal sits outside the token declarations', () => {
  // Hex only; an rgba() tint is not covered yet. A literal passes when it is a token's own
  // value, or that value carrying an alpha suffix, so `#16213e40` reads as navy at 25%
  // rather than a second copy of navy. Black and white are bases, not palette entries.
  const BASES = ['#000000', '#ffffff'];
  for (const name of ['ui/style.css', 'ui/station.css']) {
    const css = read(name);
    const declared = tokens(css).map(([, value]) => value.toLowerCase());
    const known = new Set([...declared, ...BASES].filter(value => /^#[0-9a-f]{6}$/.test(value)));
    const stray = [...new Set(
      Array.from(outsideRoot(css).matchAll(/#[0-9A-Fa-f]{3,8}\b/g), m => m[0])
        .filter(hex => !known.has(hex.toLowerCase().slice(0, 7)))
    )];
    assert.deepEqual(stray, [], `${name} carries a colour outside :root`);
  }
});
