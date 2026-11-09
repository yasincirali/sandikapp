// Gram emtia (yasin 18 Eki 2026): `GRAM:<ons tikeri>` ons kotasyonunun
// ÷ 31,1035'idir, yüzde değişim aynı. Ölçek yalnız fiyat katmanında
// (canlı kotasyon + tarihli seri); alarm, takip hareketi, özet, yarış ve
// sinyal aynı fonksiyonlardan okuduğu için ayrıca bilmez.
//
//   deno test supabase/tests/emtia_gram_test.ts
import { assertAlmostEquals, assertEquals } from 'jsr:@std/assert@1';
import { gramTabani, ONS_GRAM } from '../functions/_shared/emtia_gram.ts';
import { fetchLiveQuotes, kaynakAyir } from '../functions/_shared/live_prices.ts';
import { fetchYahooDated } from '../functions/_shared/dated_history.ts';

function yahooYaniti(fiyat: number, dunku: number): Response {
  return new Response(JSON.stringify({
    chart: {
      result: [{
        meta: { regularMarketPrice: fiyat, chartPreviousClose: dunku },
        timestamp: [1_760_000_000, 1_760_086_400],
        indicators: { quote: [{ close: [dunku, fiyat] }] },
      }],
    },
  }), { status: 200 });
}

Deno.test('gramTabani: yalnız GRAM: öneki, boş taban yok', () => {
  assertEquals(gramTabani('GRAM:SI=F'), 'SI=F');
  assertEquals(gramTabani(' gram:pl=f '), 'PL=F');
  assertEquals(gramTabani('SI=F'), null);
  assertEquals(gramTabani('GRAM:'), null);
  assertEquals(gramTabani('ALTIN_GRAM'), null);
});

Deno.test('gram emtia Yahoo kovasına düşer (altın/döviz değil)', () => {
  const r = kaynakAyir(['GRAM:SI=F', 'SI=F', 'ALTIN_GRAM']);
  assertEquals(r.yahoo, ['GRAM:SI=F', 'SI=F']);
  assertEquals(r.truncgil, ['ALTIN_GRAM']);
});

Deno.test('tarihli seri: gram = ons ÷ 31,1035, istenen tiker ons tabanı', async () => {
  const istenen: string[] = [];
  const f = ((url: string) => {
    istenen.push(url);
    return Promise.resolve(yahooYaniti(32, 31.1035));
  }) as unknown as typeof fetch;
  const seri = await fetchYahooDated('GRAM:SI=F', f);
  assertEquals(istenen.length, 1);
  assertEquals(istenen[0].includes(encodeURIComponent('SI=F')), true);
  assertEquals(istenen[0].includes('GRAM'), false);
  assertEquals(seri.length, 2);
  assertAlmostEquals(seri[0][1], 1, 1e-9);
  assertAlmostEquals(seri[1][1], 32 / ONS_GRAM, 1e-9);
});

Deno.test('canlı kotasyon: gram fiyatı ölçeklenir, yüzde aynı kalır', async () => {
  const asil = globalThis.fetch;
  globalThis.fetch = (() => Promise.resolve(yahooYaniti(33, 30))) as typeof fetch;
  try {
    const q = await fetchLiveQuotes(new Set(['SI=F', 'GRAM:SI=F']));
    const ons = q.get('SI=F')!;
    const gram = q.get('GRAM:SI=F')!;
    assertAlmostEquals(ons.price, 33, 1e-9);
    assertAlmostEquals(gram.price, 33 / ONS_GRAM, 1e-9);
    assertEquals(gram.changePct, ons.changePct);
  } finally {
    globalThis.fetch = asil;
  }
});
