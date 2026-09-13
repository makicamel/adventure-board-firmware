// Drives sim/index.html in a headless Chromium and reports what actually
// happened: console output, page errors, and the panel read back out of the
// canvas as text so a result can be asserted on rather than eyeballed.
//
//   rake sim:check              all examples
//   rake sim:check[l_shape]     one example
//
// Screenshots land in tmp/browser-check/ (git-ignored).

// CommonJS on purpose: playwright lives in the image at /opt/browser-check,
// this file is bind-mounted under /work, and NODE_PATH is honoured by require
// but not by ESM import, which resolves only by walking up from the importing
// file.
const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const { chromium } = require('playwright');

const ROOT = '/work';
const OUT = path.join(ROOT, 'tmp', 'browser-check');
const PORT = 8099;
const ONLY = process.argv[2] || null;

// Geometry of the panel, mirroring the constants in sim/index.html.
const CELL = 26, GAP = 2, PAD = 4, N = 16;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.rb': 'text/plain; charset=utf-8',
  '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.json': 'application/json',
  // Without this the browser refuses to compile the module by streaming and
  // falls back to an ArrayBuffer, which works but is slower and noisy.
  '.wasm': 'application/wasm',
};

function serve() {
  const server = http.createServer((req, res) => {
    const url = decodeURIComponent(req.url.split('?')[0]);
    let file = path.join(ROOT, url);
    if (url.endsWith('/')) file = path.join(file, 'index.html');
    if (!file.startsWith(ROOT)) { res.writeHead(403); res.end(); return; }
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); res.end('not found: ' + url); return; }
      const type = MIME[path.extname(file)] || 'application/octet-stream';
      // The page probes for a local wasm build with HEAD; answering it with a
      // body makes the browser abort the request.
      if (req.method === 'HEAD') {
        res.writeHead(200, { 'Content-Type': type, 'Content-Length': data.length });
        res.end();
        return;
      }
      res.writeHead(200, { 'Content-Type': type });
      res.end(data);
    });
  });
  return new Promise((resolve) => server.listen(PORT, '127.0.0.1', () => resolve(server)));
}

// Read the canvas back as a 16x16 map. The renderer paints an unlit dot as a
// dark well and a lit one towards white, so the red channel at the centre of a
// cell separates them cleanly.
async function readPanel(page) {
  return await page.evaluate(({ CELL, GAP, PAD, N }) => {
    const canvas = document.getElementById('panel');
    const ctx = canvas.getContext('2d');
    const rows = [];
    for (let y = 0; y < N; y++) {
      let row = '';
      for (let x = 0; x < N; x++) {
        const px = PAD + x * (CELL + GAP) + Math.floor(CELL / 2);
        const py = PAD + y * (CELL + GAP) + Math.floor(CELL / 2);
        const d = ctx.getImageData(px, py, 1, 1).data;
        const r = d[0];
        row += r > 170 ? '#' : (r > 90 ? '+' : (r > 45 ? '-' : '.'));
      }
      rows.push(row);
    }
    return rows;
  }, { CELL, GAP, PAD, N });
}

function show(label, rows) {
  console.log(`--- ${label} ---`);
  console.log('    0123456789012345');
  rows.forEach((row, i) => console.log(String(i + 1).padStart(3, ' ') + ' ' + row));
}

// Hold a button down, let a few ticks go by, then let go. mousedown/mouseup
// rather than click, because the board's buttons are momentary and the page
// models that.
async function press(page, selector, ms = 500, whileHeld = null) {
  await page.hover(selector);
  await page.mouse.down();
  await page.waitForTimeout(ms);
  // Anything that only shows while the button is down has to be read before
  // letting go.
  if (whileHeld) await whileHeld();
  await page.mouse.up();
  await page.waitForTimeout(300);
}

async function showNotes(page, label) {
  const text = await page.textContent('#notelog');
  const lines = (text || '').trim().split('\n').filter((l) => l.length);
  console.log(`--- ${label}: ${lines.length} note events ---`);
  lines.slice(0, 14).forEach((l) => console.log('  ' + l));
  if (lines.length > 14) console.log(`  ... and ${lines.length - 14} more`);
  return lines;
}

// The status LED is a class on a span, so it can be read the same way the
// panel is: sampled a few times to see it actually blinking.
async function watchStatusLed(page, samples = 8, gapMs = 120) {
  const seen = [];
  for (let i = 0; i < samples; i++) {
    const cls = await page.getAttribute('#status-led', 'class');
    seen.push(cls && !cls.includes('off') ? 'on' : 'off');
    await page.waitForTimeout(gapMs);
  }
  console.log(`--- status led over ${samples} samples ---`);
  console.log('  ' + seen.join(' '));
  return seen;
}

const INTERACTIVE = {
  status_led: async (page) => {
    const seen = await watchStatusLed(page);
    const blinked = seen.includes('on') && seen.includes('off');
    console.log(`# blinking: ${blinked}`);
    await press(page, '[data-pin="22"]', 700, async () => {
      const held = await page.getAttribute('#status-led', 'class');
      console.log(`# while A is held: ${held && !held.includes('off') ? 'on' : 'off'}`);
    });
  },
  melody: async (page) => {
    // The player runs as its own task, so the notes arrive over time.
    await page.waitForTimeout(2500);
    await showNotes(page, 'melody');
  },
  sound_and_light: async (page) => {
    await page.waitForTimeout(2000);
    await showNotes(page, 'sound_and_light');
    show('sound_and_light: panel', await readPanel(page));
  },
  buttons: async (page) => {
    // A very short click must still move exactly one cell: the press is an
    // event on a queue, so it cannot fall between two loop ticks.
    await press(page, '[data-pin="19"]', 20); // right, a flick
    show('buttons: after a 20ms click on right (expect one step)', await readPanel(page));
    await press(page, '[data-pin="19"]', 120); // right, briefly
    show('buttons: after a short tap on right (expect one step)', await readPanel(page));
    await press(page, '[data-pin="19"]', 900); // right, held
    show('buttons: after holding right (expect a few more)', await readPanel(page));
    await press(page, '[data-pin="20"]', 120); // down, briefly
    show('buttons: after a short tap on down', await readPanel(page));
    await page.keyboard.down('ArrowLeft');
    await page.waitForTimeout(500);
    await page.keyboard.up('ArrowLeft');
    await page.waitForTimeout(300);
    show('buttons: after holding the left arrow key', await readPanel(page));
    await press(page, '[data-pin="21"]', 500, async () => {
      show('buttons: B held (cross)', await readPanel(page));
    });
  },
};

const messages = [];
const errors = [];

function summary() {
  console.log('\n# console output');
  if (messages.length === 0) console.log('  (none)');
  messages.forEach((m) => console.log('  ' + m));
  console.log('\n# errors');
  if (errors.length === 0) console.log('  (none)');
  else errors.forEach((e) => console.log('  ' + e));
}

async function main() {
  fs.mkdirSync(OUT, { recursive: true });
  const server = await serve();
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });

  page.on('console', (m) => {
    const line = `[${m.type()}] ${m.text()}`;
    messages.push(line);
    if (m.type() === 'error') errors.push(line);
  });
  page.on('pageerror', (e) => errors.push(`[pageerror] ${e.message}`));
  page.on('requestfailed', (r) => errors.push(`[requestfailed] ${r.url()} ${r.failure()?.errorText}`));

  console.log(`# loading http://127.0.0.1:${PORT}/sim/`);
  await page.goto(`http://127.0.0.1:${PORT}/sim/`, { waitUntil: 'load', timeout: 60000 });

  // The Ruby task enables the buttons once it has set the page up.
  let ready = true;
  try {
    await page.waitForFunction(() => {
      const run = document.getElementById('run');
      return run && !run.disabled;
    }, null, { timeout: 60000 });
  } catch (e) {
    ready = false;
    console.log('# the page never became ready');
  }

  // Read what we can even when the page never came up: a status element that
  // is missing is itself the finding, and the console output below is what
  // says why.
  try {
    const status = await page.textContent('#status', { timeout: 2000 });
    const statusClass = await page.getAttribute('#status', 'class', { timeout: 2000 });
    console.log(`# status (${statusClass}): ${status}`);
  } catch (e) {
    console.log('# no #status element on the page');
    const body = await page.evaluate(() => document.body.innerHTML.slice(0, 400));
    console.log(`# body starts: ${body}`);
  }

  await page.screenshot({ path: path.join(OUT, '00-startup.png') });
  try {
    // A board at rest shows nothing; the examples below are what prove the
    // drawing path works.
    show('startup (expected blank)', await readPanel(page));
  } catch (e) {
    console.log(`# could not read the panel: ${e.message}`);
  }

  if (ready) {
    const options = await page.$$eval('#examples option', (els) =>
      els.map((el) => ({ value: el.value, label: el.textContent })));
    console.log(`# ${options.length} examples`);

    for (const [i, opt] of options.entries()) {
      const name = opt.value.replace(/\.rb$/, '');
      if (ONLY && name !== ONLY) continue;

      // Each example starts from a fresh board. Without this an example that
      // resets a chip (forgot_setup does, deliberately) leaves it at its
      // power-on state, and every later example shows only the other half.
      await page.click('#reset');
      await page.waitForTimeout(300);

      const before = await page.inputValue('#code');
      await page.selectOption('#examples', opt.value);
      // The example is fetched by the Ruby task, so wait for the new text to
      // land rather than for the box to be merely non-empty.
      await page.waitForFunction(
        (prev) => {
          const v = document.getElementById('code').value;
          return v.trim().length > 0 && v !== prev;
        }, before, { timeout: 15000 }).catch(() => {});
      const code = await page.inputValue('#code');
      await page.click('#run');
      await page.waitForTimeout(1200);
      const st = await page.textContent('#status');
      const cls = await page.getAttribute('#status', 'class');
      const file = path.join(OUT, `${String(i + 1).padStart(2, '0')}-${name}.png`);
      await page.screenshot({ path: file });
      console.log(`\n# example: ${opt.label} (${opt.value})  [${code.length} bytes of code]`);
      console.log(`# status (${cls}): ${st}`);
      show(name, await readPanel(page));

      // Audio has to be switched on from a user gesture before a synth exists.
      if (i === 0) {
        await page.click('#audio');
        await page.waitForTimeout(300);
      }


      // Examples that read the buttons need someone to press them.
      if (INTERACTIVE[name]) await INTERACTIVE[name](page);
    }
  }

  await browser.close();
  server.close();

  summary();
  console.log(`\n# screenshots in tmp/browser-check/`);
  process.exit(errors.length === 0 && ready ? 0 : 1);
}

main().catch((e) => { console.error(e); summary(); process.exit(2); });
