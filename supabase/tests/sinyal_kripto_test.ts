// Kripto sinyal serisi — Binance günlük mumları, TL'ye çevrilmiş (2026-09-28).
//
//   deno test --allow-all supabase/tests/sinyal_kripto_test.ts
import { assertEquals } from 'jsr:@std/assert@1';
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { fetchKripto } from '../functions/_shared/price_history.ts';
import { ANALYZABLE } from '../functions/analyze-signals/index.ts';

/// `from('kripto_varlik').select().eq().maybeSingle()` zincirini taklit eder.
function sahteIstemci(satir: Record<string, unknown> | null): SupabaseClient {
  const zincir = {
    select: () => zincir,
    eq: () => zincir,
    maybeSingle: () => Promise.resolve({ data: satir, error: null }),
  };
  return { from: () => zincir } as unknown as SupabaseClient;
}

function mumYaniti(noktalar: [number, string][]): Response {
  return Response.json(noktalar.map(([t, c]) => [t, '', '', '', c, '']));
}

Deno.test('ANALYZABLE kriptoyu içerir; diger (elle fiyat) hariç', () => {
  assertEquals(ANALYZABLE.has('kripto'), true);
  assertEquals(ANALYZABLE.has('diger'), false);
});

Deno.test('fetchKripto: TRY paritesi doğrudan kapanış', async () => {
  const f = ((_: string) => Promise.resolve(
    mumYaniti([[1000, '100'], [2000, '110']]),
  )) as unknown as typeof fetch;
  const seri = await fetchKripto(
    sahteIstemci({ parite: 'TRY', binance_sembol: 'BTCTRY' }),
    'KRIPTO:BTC',
    f,
  );
  assertEquals(seri, [100, 110]);
});

Deno.test('fetchKripto: USDT paritesi aynı günün USDTTRY kuruyla çevrilir', async () => {
  const f = ((u: string) => Promise.resolve(
    String(u).includes('USDTTRY')
      ? mumYaniti([[1000, '40'], [2000, '41']])
      : mumYaniti([[1000, '2'], [2000, '3']]),
  )) as unknown as typeof fetch;
  const seri = await fetchKripto(
    sahteIstemci({ parite: 'USDT', binance_sembol: 'SOLUSDT' }),
    'KRIPTO:SOL',
    f,
  );
  assertEquals(seri, [80, 123]);
});

Deno.test('fetchKripto: katalogda olmayan kod için Binance\'e gidilmez', async () => {
  let cagri = 0;
  const f = ((_: string) => {
    cagri++;
    return Promise.resolve(mumYaniti([]));
  }) as unknown as typeof fetch;
  assertEquals(await fetchKripto(sahteIstemci(null), 'KRIPTO:YOK', f), []);
  assertEquals(await fetchKripto(sahteIstemci(null), 'THYAO.IS', f), []);
  assertEquals(cagri, 0);
});
