// SVG → PNG (resvg, WebAssembly). `index.ts`'ten ayrı: test, `Deno.serve`
// kurmadan buradan içe aktarır.

import { initWasm, Resvg } from 'npm:@resvg/resvg-wasm@2.6.2';
import { DM_SANS_BOLD, DM_SANS_MEDIUM } from './fontlar.ts';

const SURUM = '2.6.2';

function b64Coz(s: string): Uint8Array {
  return Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
}

/// wasm ikilisi: önce paketin kendisinden (Deno npm önbelleği), olmazsa
/// CDN'den. Edge runtime'ın npm paketinin wasm dosyasını paketleyip
/// paketlemediği sürüme bağlı; iki yol da denenir, ilk başaran kalır.
async function wasmGetir(): Promise<Uint8Array | Response> {
  try {
    const yol = import.meta.resolve(`npm:@resvg/resvg-wasm@${SURUM}/index_bg.wasm`);
    if (yol.startsWith('file:')) return await Deno.readFile(new URL(yol));
  } catch (_) { /* CDN'e düş */ }
  for (const url of [
    `https://cdn.jsdelivr.net/npm/@resvg/resvg-wasm@${SURUM}/index_bg.wasm`,
    `https://unpkg.com/@resvg/resvg-wasm@${SURUM}/index_bg.wasm`,
  ]) {
    try {
      const r = await fetch(url);
      if (r.ok) return new Uint8Array(await r.arrayBuffer());
    } catch (_) { /* sıradaki */ }
  }
  throw new Error('resvg wasm yuklenemedi');
}

let hazir: Promise<void> | null = null;
let fontlar: Uint8Array[] | null = null;

function hazirla(): Promise<void> {
  if (!hazir) {
    hazir = wasmGetir().then((w) => initWasm(w)).catch((e) => {
      hazir = null; // sonraki istek yeniden denesin
      throw e;
    });
  }
  return hazir;
}

/// Kart SVG'sini PNG'ye çevirir (1200 px genişlik).
export async function pngCiz(svg: string): Promise<Uint8Array<ArrayBuffer>> {
  await hazirla();
  fontlar ??= [b64Coz(DM_SANS_BOLD), b64Coz(DM_SANS_MEDIUM)];
  const r = new Resvg(svg, {
    fitTo: { mode: 'width', value: 1200 },
    font: {
      fontBuffers: fontlar,
      loadSystemFonts: false,
      defaultFontFamily: 'DM Sans',
    },
  });
  try {
    return new Uint8Array(r.render().asPng());
  } finally {
    r.free();
  }
}
