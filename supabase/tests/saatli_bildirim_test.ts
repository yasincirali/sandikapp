// Saatli fiyat bildirimi — saf kurallar (0188).
//
// Çalıştır: deno test --allow-all supabase/tests/saatli_bildirim_test.ts

import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  dilimeDuser,
  gonderimKarari,
  kullaniciyaGore,
  mesajKur,
  SaatliSatir,
  tabloYokMu,
  trDilimi,
} from '../functions/_shared/saatli_bildirim.ts';
import type { CanliKotasyon } from '../functions/_shared/live_prices.ts';

// 2026-11-26 perşembe 12:00 UTC = 15:00 TR.
const PERSEMBE_15 = new Date('2026-11-26T12:00:00Z');
const PERSEMBE = 1 << 3;

Deno.test('dilim TR saatiyle, 15 dakikaya aşağı yuvarlanır', () => {
  const d = trDilimi(new Date('2026-11-26T12:00:40Z'));
  assertEquals(d.dakika, 15 * 60);
  assertEquals(d.gunBiti, PERSEMBE);
  assertEquals(d.slotTs, '2026-11-26T12:00:00.000Z');
  assertEquals(trDilimi(new Date('2026-11-26T12:14:59Z')).dakika, 15 * 60);
  assertEquals(trDilimi(new Date('2026-11-26T12:15:00Z')).dakika, 15 * 60 + 15);
});

Deno.test('gece yarısı UTC+3 ile ertesi güne geçer', () => {
  // 21:30 UTC perşembe = 00:30 TR cuma.
  const d = trDilimi(new Date('2026-11-26T21:30:00Z'));
  assertEquals(d.dakika, 30);
  assertEquals(d.gunBiti, 1 << 4);
  // Pazar 1 << 6.
  assertEquals(trDilimi(new Date('2026-11-29T09:00:00Z')).gunBiti, 1 << 6);
});

Deno.test('saat listede ve gün maskede olmalı', () => {
  const d = trDilimi(PERSEMBE_15);
  assert(dilimeDuser({ saatler: [540, 900], gunler: 127 }, d));
  assert(!dilimeDuser({ saatler: [540, 915], gunler: 127 }, d));
  // Yalnız hafta sonu.
  assert(!dilimeDuser({ saatler: [900], gunler: (1 << 5) | (1 << 6) }, d));
  assert(dilimeDuser({ saatler: [900], gunler: PERSEMBE }, d));
});

const satir = (user_id: string, symbol: string, label: string, saatler = [900]): SaatliSatir => ({
  user_id, symbol, label, saatler, gunler: 127,
});

Deno.test('kullanıcı başına tek grup (tek push)', () => {
  const d = trDilimi(PERSEMBE_15);
  const plan = kullaniciyaGore([
    satir('a', 'ALTIN_GRAM', 'Gram altın'),
    satir('a', 'USDTRY=X', 'Dolar'),
    satir('b', 'ALTIN_GRAM', 'Gram altın'),
    satir('c', 'ALTIN_GRAM', 'Gram altın', [540]),
  ], d);
  assertEquals([...plan.keys()].sort(), ['a', 'b']);
  assertEquals(plan.get('a')!.length, 2);
});

const k = (price: number, changePct: number | null): CanliKotasyon => ({ price, changePct });

Deno.test('tek varlık: başlıkta fiyat, gövdede bugünkü değişim', () => {
  const d = trDilimi(PERSEMBE_15);
  const m = mesajKur([satir('a', 'ALTIN_GRAM', 'Gram altın')],
    new Map([['ALTIN_GRAM', k(4112.4, 0.8)]]), d, PERSEMBE_15)!;
  assertEquals(m.title, 'Gram altın ₺4.112,40');
  assertEquals(m.body, 'Bugün +%0,8');
  assertEquals(m.symbol, 'ALTIN_GRAM');
});

Deno.test('çok varlık: saat başlığı, satır başına fiyat', () => {
  const d = trDilimi(PERSEMBE_15);
  const m = mesajKur([satir('a', 'ALTIN_GRAM', 'Gram altın'), satir('a', 'USDTRY=X', 'Dolar')],
    new Map([['ALTIN_GRAM', k(4112.4, 0.8)], ['USDTRY=X', k(42.1, -0.25)]]), d, PERSEMBE_15)!;
  assertEquals(m.title, '15:00 fiyatların');
  assertEquals(m.body, 'Gram altın ₺4.112,40 (+%0,8)\nDolar ₺42,10 (−%0,3)');
  assertEquals(m.sayi, 2);
});

Deno.test('fiyatı bilinmeyen varlık yazılmaz; hepsi bilinmiyorsa push yok', () => {
  const d = trDilimi(PERSEMBE_15);
  const iki = [satir('a', 'ALTIN_GRAM', 'Gram altın'), satir('a', 'THYAO.IS', 'THY')];
  const m = mesajKur(iki, new Map([['THYAO.IS', k(300, null)]]), d, PERSEMBE_15)!;
  assertEquals(m.sayi, 1);
  assertEquals(m.symbol, 'THYAO.IS');
  assert(!m.title.includes('Gram'));
  // Değişim bilinmiyor: yüzde uydurulmaz.
  assert(!m.body.includes('%'));
  assertEquals(mesajKur(iki, new Map(), d, PERSEMBE_15), null);
  assertEquals(mesajKur(iki, new Map([['ALTIN_GRAM', k(0, 1)]]), d, PERSEMBE_15), null);
});

Deno.test('BIST seans dışında "son fiyat" eki', () => {
  // 21:00 TR perşembe: seans kapalı.
  const aksam = new Date('2026-11-26T18:00:00Z');
  const d = trDilimi(aksam);
  const m = mesajKur([satir('a', 'THYAO.IS', 'THY', [1260])],
    new Map([['THYAO.IS', k(300, 1)]]), d, aksam)!;
  assert(m.title.endsWith('(son fiyat)'));
  // Altın hiç kapalı sayılmaz.
  const a = mesajKur([satir('a', 'ALTIN_GRAM', 'Gram altın', [1260])],
    new Map([['ALTIN_GRAM', k(4000, 1)]]), d, aksam)!;
  assert(!a.title.includes('son fiyat'));
});

Deno.test('gönderim kaydı: çakışma = zaten gönderildi, başka hata = gönderme', () => {
  assertEquals(gonderimKarari(null), 'gonder');
  assertEquals(gonderimKarari({ code: '23505' }), 'zaten');
  assertEquals(gonderimKarari({ code: '42501' }), 'hata');
});

Deno.test('tablo yok (migration öncesi) sessiz tur', () => {
  assert(tabloYokMu({ code: '42P01' }));
  assert(tabloYokMu({ code: 'PGRST205' }));
  assert(!tabloYokMu({ code: '42501' }));
  assert(!tabloYokMu(null));
});

Deno.test('fonksiyon fail-closed, gönderim kaydı push\'tan önce', async () => {
  const src = await Deno.readTextFile(
    new URL('../functions/saatli-bildirim/index.ts', import.meta.url),
  );
  const zorunlu = src.indexOf('cronSecretZorunlu(');
  const yetki = src.indexOf('cronYetkisiVarMi(request, cronSecret)');
  assert(zorunlu >= 0 && yetki > zorunlu);
  const kayit = src.indexOf(".from('saatli_bildirim_gonderim')");
  const push = src.indexOf('sendFcmNotification({');
  assert(kayit >= 0 && push > kayit, 'kayıt push\'tan önce yazılmalı');
  assert(!src.includes('error.message }'), 'yanıtta hata metni dönmemeli');
});
