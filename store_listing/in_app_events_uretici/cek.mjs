// App Store In-App Event görselleri (2026-10-19). Sahne sahne.html'de
// (sade SVG; Pillow çizimi build_event_graphics.py'nin yerini aldı), bu betik
// başsız Chromium'da çizip PNG'ye alır: tarayıcı kenar yumuşatması ve
// gradyanı Pillow'dan temiz veriyor, tek kaynak dosya iki boyutu da üretiyor.
//
//   cd store_listing/in_app_events_uretici && npm i && node cek.mjs
//   CHROME=/yol/chrome node cek.mjs     # Playwright'ın kendi Chromium'u yoksa
//
// Çıktı: store_listing/ios/in_app_events/<gorsel>_{kart_1920x1080,detay_1080x1920}.png
// (commit'li; etkinlikler.json "gorsel" adlarıyla eşleşir).
import { chromium } from 'playwright-core';
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';

const kok = path.dirname(new URL(import.meta.url).pathname);
const tipler = { '.html': 'text/html', '.js': 'text/javascript' };
const sv = http.createServer((q, s) => {
  const p = path.join(kok, decodeURIComponent(q.url.split('?')[0]));
  fs.readFile(p, (e, d) => { if (e) { s.writeHead(404); s.end(); return; } s.writeHead(200, { 'Content-Type': tipler[path.extname(p)] || 'application/octet-stream' }); s.end(d); });
}).listen(8765);

const out = process.argv[2] ?? path.join(kok, '..', 'ios', 'in_app_events');
const b = await chromium.launch({ ...(process.env.CHROME ? { executablePath: process.env.CHROME } : {}) });
for (const [s, ad] of [['enf', 'enflasyon_gunu'], ['yil', 'yil_sonu_ozeti']]) {
  for (const [w, h, ek] of [[1920, 1080, 'kart_1920x1080'], [1080, 1920, 'detay_1080x1920']]) {
    const p = await b.newPage({ viewport: { width: w, height: h } });
    p.on('console', m => console.log(s, m.text()));
    p.on('pageerror', e => console.log('HATA', e.message));
    await p.goto(`http://localhost:8765/sahne.html?s=${s}&w=${w}&h=${h}`);
    await p.waitForFunction(() => window.HAZIR, null, { timeout: 120000 });
    await p.screenshot({ path: path.join(out, `${ad}_${ek}.png`) });
    console.log('ok', ad, ek);
    await p.close();
  }
}
await b.close(); sv.close();
