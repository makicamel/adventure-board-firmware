// One picture of the code box with colours, scrolled down to where the code
// is (every sample opens with a screenful of comments), and a measurement of
// whether the coloured copy lines up with the textarea on top of it.
//
//   docker compose -f docker/compose.yml run --rm browser node /work/tools/browser-check/editor-shot.cjs [sample] [scrollTop]
const http = require('http');
const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const ROOT = '/work';
const OUT = path.join(ROOT, 'tmp', 'browser-check');
const SAMPLE = process.argv[2] || 'buttons.rb';
const SCROLL = parseInt(process.argv[3] || '420', 10);
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.rb': 'text/plain' };

(async () => {
  const server = http.createServer((req, res) => {
    const file = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]).replace(/\/$/, '/index.html'));
    fs.readFile(file, (err, data) => {
      if (err) { res.writeHead(404); res.end(); return; }
      res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
      res.end(data);
    });
  }).listen(8098);
  const browser = await chromium.launch({ args: ['--no-sandbox'] });
  const page = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  await page.goto('http://127.0.0.1:8098/sim/');
  await page.waitForFunction(() => (document.getElementById('status') || {}).className === 'ok', null, { timeout: 60000 });
  await page.selectOption('#examples', SAMPLE);
  await page.waitForFunction(() => document.querySelectorAll('#code-colors span').length > 0, null, { timeout: 15000 });
  await page.evaluate((y) => { const b = document.getElementById('code'); b.scrollTop = y; b.dispatchEvent(new Event('scroll')); }, SCROLL);
  await page.waitForTimeout(200);
  // The same character offset, measured in both layers.
  console.log(await page.evaluate(() => {
    const box = document.getElementById('code'), pre = document.getElementById('code-colors');
    const a = box.getBoundingClientRect(), b = pre.getBoundingClientRect();
    return JSON.stringify({
      box: [a.left, a.top, a.width, a.height], pre: [b.left, b.top, b.width, b.height],
      scroll: [box.scrollTop, pre.scrollTop], scrollHeight: [box.scrollHeight, pre.scrollHeight],
      scrollWidth: [box.scrollWidth, pre.scrollWidth],
    });
  }));
  fs.mkdirSync(OUT, { recursive: true });
  await (await page.$('.editor')).screenshot({ path: path.join(OUT, 'editor-colours.png') });
  await browser.close();
  server.close();
})();
