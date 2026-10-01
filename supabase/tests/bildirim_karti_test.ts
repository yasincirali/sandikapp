// Bildirim kartı (0092) — imza, veri sınırları, SVG ve sürüm kapısı.
//
// Kilitlenen sözleşme (kullanıcı kuralı 2026-10-01: "store kullanıcılarını
// etkilemesin"): kart YALNIZ `bildirim_surumu >= 2` token'a; eski sürüm
// satırı (NULL) için `kartGorseli` undefined döner ve FCM gövdesi değişmez
// (gövde tarafı fcm_send_test'te).
//
//   deno test --allow-all supabase/tests/bildirim_karti_test.ts

import { assert, assertEquals, assertStringIncludes } from 'jsr:@std/assert@1';
import {
  degisimKarti,
  KART_SURUMU,
  kartAlabilir,
  kartGorseli,
  kartSvg,
  kartUrl,
  kartUrlCoz,
  KartVerisi,
  kartVerisiniHazirla,
} from '../functions/_shared/bildirim_karti.ts';
import { tokenSatirlariniOku } from '../functions/_shared/push_tokens.ts';
import { pngCiz } from '../functions/bildirim-karti/cizici.ts';

const ANAHTAR = 'test-service-role-key';
const VERI: KartVerisi = { e: 'ASELS', b: '%4,2', y: 'u', p: 4.2, a: 'Son kapanış · en hareketli' };

function parametreler(url: string): { d: string | null; s: string | null } {
  const u = new URL(url);
  return { d: u.searchParams.get('d'), s: u.searchParams.get('s') };
}

Deno.test('imzalı URL aynı anahtarla çözülür, veri aynen döner', async () => {
  const url = await kartUrl('https://proj.supabase.co/', ANAHTAR, VERI);
  assert(url.startsWith('https://proj.supabase.co/functions/v1/bildirim-karti?d='));
  const { d, s } = parametreler(url);
  assertEquals(await kartUrlCoz(ANAHTAR, d, s), VERI);
});

Deno.test('imza tutmazsa null: başka anahtar, oynanmış veri, eksik parametre', async () => {
  const { d, s } = parametreler(await kartUrl('https://p', ANAHTAR, VERI));
  assertEquals(await kartUrlCoz('baska-anahtar', d, s), null);
  const sahte = await kartUrl('https://p', 'baska-anahtar', { ...VERI, b: '%99,9' });
  assertEquals(await kartUrlCoz(ANAHTAR, parametreler(sahte).d, s), null);
  assertEquals(await kartUrlCoz(ANAHTAR, d, null), null);
  assertEquals(await kartUrlCoz(ANAHTAR, null, s), null);
  assertEquals(await kartUrlCoz(ANAHTAR, 'x'.repeat(601), s), null);
});

Deno.test('veri kısaltılır; boş etiket ya da geçersiz yön → kart yok', () => {
  const h = kartVerisiniHazirla({
    e: 'COK UZUN BIR VARLIK ADI',
    b: '%1,0',
    y: 'd',
    a: 'x'.repeat(80),
  })!;
  assertEquals(h.e.length, 14);
  assertEquals(h.a.length, 32);
  assertEquals(kartVerisiniHazirla({ ...VERI, e: '  ' }), null);
  assertEquals(kartVerisiniHazirla({ ...VERI, y: 'x' as never }), null);
});

Deno.test('değişim kartı: yön ve Türkçe yüzde', () => {
  assertEquals(degisimKarti('KCHOL', -3.14, 'a')!.b, '%3,1');
  assertEquals(degisimKarti('KCHOL', -3.14, 'a')!.y, 'd');
  assertEquals(degisimKarti('X', 0, 'a')!.y, 'n');
  assertEquals(degisimKarti('X', Number.NaN, 'a'), null);
});

Deno.test('SVG: metin kaçırılır, yön işareti glif değil çizim (DM Sans\'ta ▲ yok)', () => {
  const svg = kartSvg({ ...VERI, e: '<b>&"', a: "a'b" });
  assertStringIncludes(svg, '&lt;b&gt;&amp;&quot;');
  assertStringIncludes(svg, 'a&apos;b');
  assert(!/[▲▼◆]/.test(svg), 'ok glifi metin olarak basılmamalı');
  assertStringIncludes(svg, '<polygon');
});

Deno.test('sürüm kapısı: NULL ve 1 kart almaz, 2 alır', async () => {
  assertEquals(KART_SURUMU, 2);
  assertEquals(kartAlabilir({}), false);
  assertEquals(kartAlabilir({ bildirim_surumu: null }), false);
  assertEquals(kartAlabilir({ bildirim_surumu: 1 }), false);
  assertEquals(kartAlabilir({ bildirim_surumu: 2 }), true);

  const ayar = { supabaseUrl: 'https://p', anahtar: ANAHTAR };
  assertEquals(await kartGorseli(ayar, { bildirim_surumu: null }, VERI), undefined);
  assertEquals(await kartGorseli(null, { bildirim_surumu: 2 }, VERI), undefined);
  assertEquals(await kartGorseli(ayar, { bildirim_surumu: 2 }, null), undefined);
  assert((await kartGorseli(ayar, { bildirim_surumu: 2 }, VERI))!.includes('/bildirim-karti?'));
});

Deno.test('token okuma: sütun yoksa (0092 dağıtılmamış) eski seçime düşer', async () => {
  const istenen: string[] = [];
  const { data, error } = await tokenSatirlariniOku((s) => {
    istenen.push(s);
    return Promise.resolve(
      s.includes('bildirim_surumu')
        ? { data: null, error: { code: '42703', message: 'column user_push_tokens.bildirim_surumu does not exist' } }
        : { data: [{ token: 't', user_id: 'u' }], error: null },
    );
  });
  assertEquals(error, null);
  assertEquals(data, [{ token: 't', user_id: 'u' }]);
  assertEquals(istenen.length, 2);
});

Deno.test('token okuma: başka hata eskiye düşmez, çağırana döner', async () => {
  let cagri = 0;
  const { error } = await tokenSatirlariniOku(() => {
    cagri += 1;
    return Promise.resolve({ data: null, error: { code: '57014', message: 'timeout' } });
  });
  assertEquals(error?.code, '57014');
  assertEquals(cagri, 1);
});

Deno.test('PNG çizilir: 1200×600, gömülü yazı tipiyle', async () => {
  const png = await pngCiz(kartSvg(VERI));
  assertEquals([...png.slice(1, 4)], [0x50, 0x4e, 0x47]); // "PNG"
  const v = new DataView(png.buffer, png.byteOffset);
  assertEquals(v.getUint32(16), 1200);
  assertEquals(v.getUint32(20), 600);
});
