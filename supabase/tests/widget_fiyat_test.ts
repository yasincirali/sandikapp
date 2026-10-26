// widget-fiyat — saf yardımcılar (beyaz liste, istek sınırı, bayatlık).
//
//   deno test supabase/tests/widget_fiyat_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import {
  kriptoWidgetFiyati,
  WIDGET_AZAMI_SEMBOL,
  widgetIstegiCoz,
  widgetSembolTuru,
  yurtIciWidgetFiyati,
} from '../functions/_shared/widget_fiyat.ts';

const simdi = Date.parse('2026-10-26T10:00:00Z');

Deno.test('beyaz liste: altın, TL döviz, kripto; gerisi yok', () => {
  assertEquals(widgetSembolTuru('ALTIN_GRAM24'), 'yurt_ici');
  assertEquals(widgetSembolTuru('ALTIN_CEYREK'), 'yurt_ici');
  assertEquals(widgetSembolTuru('USDTRY=X'), 'yurt_ici');
  assertEquals(widgetSembolTuru('KRIPTO:BTC'), 'kripto');
  for (const s of ['THYAO.IS', 'TEFAS:AFT', 'XU100.IS', 'GC=F', 'ALTIN_YOK', 'kripto:btc', 'KRIPTO:', '']) {
    assertEquals(widgetSembolTuru(s), null, s);
  }
});

Deno.test('istek: bilinmeyen sembol düşer, tekrar tekilleşir', () => {
  assertEquals(
    widgetIstegiCoz({ semboller: ['ALTIN_GRAM', 'THYAO.IS', 'ALTIN_GRAM', 7, 'KRIPTO:ETH'] }),
    ['ALTIN_GRAM', 'KRIPTO:ETH'],
  );
  assertEquals(widgetIstegiCoz({ semboller: ['THYAO.IS'] }), []);
});

Deno.test('istek: biçim dışı ya da sınırı aşan gövde reddedilir', () => {
  assertEquals(widgetIstegiCoz(null), null);
  assertEquals(widgetIstegiCoz([]), null);
  assertEquals(widgetIstegiCoz({}), null);
  assertEquals(widgetIstegiCoz({ semboller: [] }), null);
  assertEquals(widgetIstegiCoz({ semboller: 'ALTIN_GRAM' }), null);
  const fazla = Array.from({ length: WIDGET_AZAMI_SEMBOL + 1 }, () => 'USDTRY=X');
  assertEquals(widgetIstegiCoz({ semboller: fazla }), null);
});

Deno.test('yurt içi: taze satır fiyat + zaman + yüzde', () => {
  assertEquals(
    yurtIciWidgetFiyati(
      { ts: '2026-10-26T09:55:00Z', fiyat: '5412.37', degisim_pct: '-0.72' },
      simdi,
    ),
    { fiyat: 5412.37, zaman: Date.parse('2026-10-26T09:55:00Z'), degisim: -0.72 },
  );
});

Deno.test('yurt içi: yüzde yoksa alan yazılmaz (uydurma yok)', () => {
  assertEquals(
    yurtIciWidgetFiyati({ ts: '2026-10-26T09:55:00Z', fiyat: 41.5, degisim_pct: null }, simdi),
    { fiyat: 41.5, zaman: Date.parse('2026-10-26T09:55:00Z') },
  );
});

Deno.test('yurt içi: 2 saatten eski ya da geçersiz satır dönmez', () => {
  assertEquals(
    yurtIciWidgetFiyati({ ts: '2026-10-26T07:59:00Z', fiyat: 41.5, degisim_pct: 0.1 }, simdi),
    null,
  );
  assertEquals(
    yurtIciWidgetFiyati({ ts: '2026-10-26T09:55:00Z', fiyat: 0, degisim_pct: 0.1 }, simdi),
    null,
  );
  assertEquals(
    yurtIciWidgetFiyati({ ts: 'bozuk', fiyat: 41.5, degisim_pct: 0.1 }, simdi),
    null,
  );
});

Deno.test('kripto: yüzde günün açılışına göre; açılış yoksa yüzde yok', () => {
  const t = '2026-10-26T09:59:00Z';
  assertEquals(
    kriptoWidgetFiyati({ fiyat_try: 110, gun_acilis_try: 100, guncellendi: t }, simdi),
    { fiyat: 110, zaman: Date.parse(t), degisim: 10.000000000000009 },
  );
  assertEquals(
    kriptoWidgetFiyati({ fiyat_try: 110, gun_acilis_try: null, guncellendi: t }, simdi),
    { fiyat: 110, zaman: Date.parse(t) },
  );
});

Deno.test('kripto: 30 dakikadan eski satır dönmez', () => {
  assertEquals(
    kriptoWidgetFiyati(
      { fiyat_try: 110, gun_acilis_try: 100, guncellendi: '2026-10-26T09:29:00Z' },
      simdi,
    ),
    null,
  );
});

Deno.test('fonksiyon yanıtı hata metni ve kişisel veri taşımaz', async () => {
  const kaynak = await Deno.readTextFile(
    new URL('../functions/widget-fiyat/index.ts', import.meta.url),
  );
  // Hata yalnız günlükte; yanıt gövdesinde e.message / error.message yok.
  assertEquals(/json\([^)]*\.message/.test(kaynak), false);
  // Kullanıcı kimliği sorulmaz.
  assertEquals(kaynak.includes('auth.getUser'), false);
  // Tablolara yazılmaz.
  for (const y of ['.insert(', '.upsert(', '.update(', '.delete()', '.rpc(']) {
    assertEquals(kaynak.includes(y), false, y);
  }
});
