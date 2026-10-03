// Yurt içi kotasyon kaydı — saf satır üretimi (0101).
//
//   deno test supabase/tests/yurt_ici_kotasyon_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import {
  YURT_ICI_SEMBOLLER,
  yurtIciSatirlari,
} from '../functions/_shared/live_prices.ts';

const simdi = new Date('2026-10-03T09:37:42Z');

Deno.test('kova 5 dakikaya aşağı yuvarlanır (istemci slotuyla aynı)', () => {
  const r = yurtIciSatirlari({ USD: { Buying: 41.5, Change: 0.1 } }, simdi);
  assertEquals(r.length, 1);
  assertEquals(r[0].ts, '2026-10-03T09:35:00.000Z');
});

Deno.test('fiyat alanı uygulamayla aynı: Buying önce, Selling değil', () => {
  const r = yurtIciSatirlari(
    { YIA: { Buying: 5400, Selling: 5450, Change: -0.72 } },
    simdi,
  );
  assertEquals(r, [{
    sembol: 'ALTIN_GRAM',
    ts: '2026-10-03T09:35:00.000Z',
    fiyat: 5400,
    degisim_pct: -0.72,
  }]);
});

Deno.test('fiyatı okunamayan sembol satır üretmez (uydurma nokta yok)', () => {
  const r = yurtIciSatirlari(
    { USD: { Buying: 0 }, EUR: {}, GBP: { Buying: 'abc' } },
    simdi,
  );
  assertEquals(r, []);
});

Deno.test('liste tüm altın ayarlarını ve üç TL dövizini kapsar', () => {
  for (const s of ['ALTIN_GRAM', 'ALTIN_CEYREK', 'ALTIN_GRAM24', 'USDTRY=X', 'EURTRY=X', 'GBPTRY=X']) {
    assertEquals(YURT_ICI_SEMBOLLER.includes(s), true, s);
  }
});
