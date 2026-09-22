// The page's link to a board, against a fake navigator.serial: connect, type
// at the shell, run a program (a PicoModem transfer), restart the board (the
// port drops and comes back three seconds later, with a boot log ending in
// the prompt), and read the terminal to see whether the page found its way
// back. The real browser is not in the loop, but everything on the Ruby side
// of the bridge is, and the fake board answers PicoModem's frames.
//
//   docker compose -f docker/compose.yml run --rm browser node /work/tools/browser-check/reconnect-check.cjs
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = '/work';
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.rb': 'text/plain', '.css': 'text/css' };

const FAKE_SERIAL = () => {
  const enc = new TextEncoder(), dec = new TextDecoder();
  class FakePort extends EventTarget {
    constructor(name, shell) { super(); this.name = name; this.shell = shell; this.connected = true; this.opened = false;
      this.readable = null; this.writable = null; this.written = []; this.bootText = null;
      this.line = ''; this.modem = null; this.file = null; this.files = {}; this.ran = []; }
    async open() {
      if (!this.connected) throw new DOMException('The device has been lost.', 'NetworkError');
      if (this.opened) throw new DOMException('The port is already open.', 'InvalidStateError');
      this.opened = true;
      const self = this;
      this.readable = new ReadableStream({ start(c) { self.ctrl = c; } });
      this.writable = new WritableStream({ write(chunk) { self.take(chunk); } });
      if (this.bootText) { const t = this.bootText; this.bootText = null; setTimeout(() => this.emit(t), 200); }
    }
    // The shell side of the fake board: echoes keys, answers Enter and Ctrl-C
    // with a prompt, `reboot` with a restart, and Ctrl-B with PicoModem.
    take(chunk) {
      this.written.push(dec.decode(chunk));
      if (!this.shell) return;
      if (this.modem) { this.modemBytes(chunk); return; }
      for (const b of chunk) {
        if (b === 0x02) { this.modem = { buf: [] }; this.emit('\x06'); continue; }
        if (b === 0x03) { this.line = ''; this.emit('^C\r\n$> '); continue; }
        if (b === 0x0d) {
          const line = this.line; this.line = '';
          if (line === 'reboot') { this.emit('\r\nRebooting in 500 ms\r\n'); setTimeout(() => window.__board.reboot(), 500); continue; }
          if (line.startsWith('/home/')) { this.emit('\r\nLoading ' + line + '\r\n'); this.ran.push(line); continue; }
          if (line === 'free') { this.emit('\r\nfree: 176536\r\n$> '); continue; }
          this.emit('\r\n$> '); continue;
        }
        this.line += String.fromCharCode(b); this.emit(String.fromCharCode(b));   // echo
      }
    }
    modemBytes(chunk) {
      const m = this.modem; for (const b of chunk) m.buf.push(b);
      while (m.buf.length >= 3 && m.buf[0] === 0x02) {
        const len = (m.buf[1] << 8) | m.buf[2];
        if (m.buf.length < 3 + len + 2) return;
        const body = m.buf.slice(3, 3 + len); m.buf = m.buf.slice(3 + len + 2);
        const cmd = body[0];
        if (cmd === 0x02) {          // FILE_WRITE: 4-byte size, then the path
          this.file = { size: (body[1] << 24) | (body[2] << 16) | (body[3] << 8) | body[4], path: dec.decode(new Uint8Array(body.slice(5))), data: [] };
          this.reply(0x82, [0]);
        } else if (cmd === 0x04) {   // CHUNK
          for (const x of body.slice(1)) this.file.data.push(x);
          this.reply(0x84, [0]);
          if (this.file.data.length >= this.file.size) {
            const crc = window.__crc32(this.file.data);
            this.reply(0x8f, [0, (crc >>> 24) & 0xff, (crc >>> 16) & 0xff, (crc >>> 8) & 0xff, crc & 0xff]);
            this.files[this.file.path] = dec.decode(new Uint8Array(this.file.data));
            this.modem = null;
            this.emit('[PicoModem] write ' + this.file.path + '\r\n$> ');   // as the shell prints on the way back
          }
        } else if (cmd === 0xff) {   // ABORT
          this.modem = null; this.emit('\r\n$> ');
        }
      }
    }
    reply(cmd, payload) {
      // the CRC is not checked by the fake; the page checks the one it gets
      const body = [cmd, ...payload]; const crc = window.__crc16(body);
      this.emitBytes(new Uint8Array([0x02, body.length >> 8, body.length & 0xff, ...body, crc >> 8, crc & 0xff]));
    }
    emitBytes(u8) { try { this.ctrl && this.ctrl.enqueue(u8); } catch (e) {} }
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
  window.__crc32 = (bytes) => { let c = 0xffffffff; for (const b of bytes) { c ^= b; for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1)); } return (c ^ 0xffffffff) >>> 0; };
  window.__crc16 = (bytes) => { let c = 0xffff; for (const b of bytes) { c ^= b << 8; for (let k = 0; k < 8; k++) c = (c & 0x8000) ? ((c << 1) ^ 0x1021) & 0xffff : (c << 1) & 0xffff; } return c; };
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

// What the terminal shows, line by line, from xterm's buffer.
async function termText(page) {
  return await page.evaluate(() => {
    const t = window.deviceTerminal(); if (!t) return '(no terminal)';
    const b = t.buffer.active; const lines = [];
    for (let i = 0; i < b.length; i++) lines.push(b.getLine(i).translateToString(true));
    return lines.join('\n');
  });
}

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
    // Typing at the shell: click the terminal, type a command, Enter.
    await page.click('#devicelog');
    await page.keyboard.type('free');
    await page.keyboard.press('Enter');
    await page.waitForTimeout(500);
    console.log('# typed "free", the board got:', JSON.stringify(await page.evaluate(() => window.__board.shell.written.join(''))));
    console.log('# terminal shows:', JSON.stringify(await termText(page)).slice(0, 160));
    // A program: the transfer through PicoModem, then the run.
    await page.evaluate(() => { window.__board.shell.written = []; });
    await page.click('#device-run');
    await page.waitForFunction(() => document.getElementById('status').textContent.includes('実機で実行しています'), null, { timeout: 15000 })
      .catch(() => console.log('# run did not finish: ' + document.getElementById('status').textContent));
    console.log('# run:', await page.textContent('#status'));
    if (announce) await page.screenshot({ path: '/work/tmp/browser-check/terminal.png' });
    console.log('# board files:', await page.evaluate(() => Object.keys(window.__board.shell.files).map((k) => k + ' (' + window.__board.shell.files[k].length + ' bytes)').join(', ')), '| ran:', await page.evaluate(() => window.__board.shell.ran.join(' ')));
    await page.evaluate(() => { window.__board.shell.written = []; });
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
    console.log('# terminal:');
    (await termText(page)).split('\n').filter((l) => l.trim()).forEach((l) => console.log('   ' + l));
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
