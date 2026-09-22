// The page's link to a board, against a fake navigator.serial: connect, run,
// restart the board (the port drops and comes back three seconds later, with
// a boot log ending in the prompt), and read the device log to see whether
// the page found its way back. The real browser is not in the loop, but
// everything on the Ruby side of the bridge is.
//
//   docker compose -f docker/compose.yml run --rm browser node /work/tools/browser-check/reconnect-check.cjs
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = '/work';
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.rb': 'text/plain' };

const FAKE_SERIAL = () => {
  const enc = new TextEncoder(), dec = new TextDecoder();
  class FakePort extends EventTarget {
    constructor(name, shell) { super(); this.name = name; this.shell = shell; this.connected = true; this.opened = false;
      this.readable = null; this.writable = null; this.written = []; this.bootText = null; }
    async open() {
      if (!this.connected) throw new DOMException('The device has been lost.', 'NetworkError');
      if (this.opened) throw new DOMException('The port is already open.', 'InvalidStateError');
      this.opened = true;
      const self = this;
      this.readable = new ReadableStream({ start(c) { self.ctrl = c; } });
      this.writable = new WritableStream({ write(chunk) {
        const s = dec.decode(chunk); self.written.push(s);
        if (!self.shell) return;
        if (s.includes('reboot')) { self.emit('\r\nRebooting in 500 ms\r\n'); setTimeout(() => window.__board.reboot(), 500); return; }
        if (s.includes('\r') || s.includes('\x03')) self.emit('\r\n$> ');
      } });
      if (this.bootText) { const t = this.bootText; this.bootText = null; setTimeout(() => this.emit(t), 200); }
    }
    emit(text) { try { this.ctrl && this.ctrl.enqueue(enc.encode(text)); } catch (e) {} }
    async close() { this.opened = false; try { this.ctrl && this.ctrl.close(); } catch (e) {} this.readable = null; this.writable = null; }
    drop() { this.connected = false; this.opened = false;
      try { this.ctrl && this.ctrl.error(new DOMException('The device has been lost.', 'NetworkError')); } catch (e) {}
      this.readable = null; this.writable = null; this.dispatchEvent(new Event('disconnect')); }
  }
  class FakeSerial extends EventTarget {
    constructor() { super(); this.granted = []; }
    async requestPort() { return this.granted.find((p) => p.shell); }
    async getPorts() { return this.granted.filter((p) => p.connected); }
  }
  const serial = new FakeSerial();
  const midi = new FakePort('MIDI', false), shell = new FakePort('shell', true);
  serial.granted = [midi, shell];              // both allowed at some point; MIDI listed first
  Object.defineProperty(navigator, 'serial', { value: serial, configurable: true });
  window.__board = {
    shell, midi, events: [],
    reboot() {
      this.events.push('drop'); shell.drop(); midi.drop();
      setTimeout(() => {
        this.events.push('back'); midi.connected = true; shell.connected = true;
        shell.bootText = '....\r\nLoading app.rb\r\nStarting shell...\r\n$> ';
        if (window.__announce) { serial.dispatchEvent(new Event('connect')); }
      }, 3000);
    },
  };
  window.__announce = !location.search.includes('noannounce');
};

(async () => {
  const server = http.createServer((req, res) => {
    const file = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
      res.end(data);
    });
  }).listen(8097);
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  for (const announce of [true, false]) {
    const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
    const console_ = [];
    page.on('console', (m) => console_.push(`[${m.type()}] ${m.text()}`));
    page.on('pageerror', (e) => console_.push(`[pageerror] ${e.message}`));
    await page.addInitScript(FAKE_SERIAL);
    await page.goto('http://127.0.0.1:8097/sim/' + (announce ? '' : '?noannounce'));
    await page.waitForFunction(() => (document.getElementById('status') || {}).className === 'ok', null, { timeout: 60000 });
    console.log(`\n=== browser ${announce ? 'announces' : 'does not announce'} the returning port ===`);
    await page.click('#device-connect');
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('接続しました'), null, { timeout: 10000 });
    console.log('# connected:', await page.textContent('#status'));
    await page.click('#device-reboot');
    const t0 = Date.now();
    const ok = await page.waitForFunction(() => document.getElementById('status').textContent.includes('つなぎ直しました'), null, { timeout: 45000 })
      .then(() => true).catch(() => false);
    console.log(`# reconnected: ${ok} after ${((Date.now() - t0) / 1000).toFixed(1)} s`);
    console.log('# status:', await page.textContent('#status'));
    console.log('# board events:', await page.evaluate(() => window.__board.events.join(' ')));
    console.log('# shell was sent:', JSON.stringify(await page.evaluate(() => window.__board.shell.written.join(''))).slice(0, 200));
    await page.waitForTimeout(3000);
    console.log('# midi was sent:', JSON.stringify(await page.evaluate(() => window.__board.midi.written.join(''))));
    console.log('# device log:');
    (await page.textContent('#devicelog')).split('\n').filter((l) => l.trim()).forEach((l) => console.log('   ' + l));
    if (ok) {
      await page.evaluate(() => { window.__board.shell.written = []; window.__board.midi.written = []; });
      await page.click('#device-reboot');
      await page.waitForFunction(() => document.getElementById('status').textContent.includes('切れました'), null, { timeout: 15000 });
      const t1 = Date.now();
      const ok2 = await page.waitForFunction(() => document.getElementById('status').textContent.includes('つなぎ直しました'), null, { timeout: 45000 })
        .then(() => true).catch(() => false);
      console.log(`# second restart, reconnected: ${ok2} after ${((Date.now() - t1) / 1000).toFixed(1)} s; midi got ${JSON.stringify(await page.evaluate(() => window.__board.midi.written.join('')))}`);
      await page.click('#device-connect');   // now "disconnect"
      await page.waitForTimeout(500);
      console.log('# after disconnect:', await page.textContent('#status'), '| button:', await page.textContent('#device-connect'));
    }
    const errs = console_.filter((l) => l.startsWith('[error]') || l.startsWith('[pageerror]'));
    console.log('# console errors:', errs.length ? '' : '(none)'); errs.forEach((l) => console.log('   ' + l));
    await page.close();
  }
  await browser.close();
  server.close();
})();
