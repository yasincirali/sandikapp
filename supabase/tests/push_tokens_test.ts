// `_shared/push_tokens.ts` — beş fonksiyonun ortak "cihaz başına tek token"
// kuralı (2026-09-14 birleştirme).
//
// Kopyalar `updated_at` eksikken farklı davranıyordu (NaN karşılaştırması
// vs 0). Tek kaynağın sözleşmesi burada kilitlenir; fonksiyon düzeyindeki
// testler (daily_brief_test vb.) kendi modüllerinden yeniden dışa aktarılan
// aynı fonksiyonu okumaya devam eder.
//
//   deno test supabase/tests/push_tokens_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  collapseTokens,
  dedupeTokensByDevice,
} from '../functions/_shared/push_tokens.ts';

// Fonksiyon modülleri İMPORT EDİLMEZ: her biri yüklenince `Deno.serve`
// kurar ve ikinci modül `AddrInUse` ile test koşucusunu düşürür. Kopyanın
// geri gelmediği kaynak metninden denetlenir.
Deno.test('beş fonksiyon aynı kaynağı kullanıyor — yerel kopya kalmadı', async () => {
  const fonksiyonlar = [
    'daily-brief',
    'weekly-summary',
    'calendar-nudge',
    'check-price-alerts',
    'analyze-signals',
  ];
  for (const f of fonksiyonlar) {
    const src = await Deno.readTextFile(
      new URL(`../functions/${f}/index.ts`, import.meta.url),
    );
    assertEquals(src.includes("from '../_shared/push_tokens.ts'"), true, f);
    assertEquals(/function (collapseTokens|dedupeTokensByDevice)\(/.test(src), false,
      `${f}: yerel kopya geri gelmiş`);
  }
});

Deno.test('updated_at eksik satır 0 sayılır: damgalı olan kazanır, sıra fark etmez', () => {
  const a = collapseTokens([
    { token: 'damgasiz', user_id: 'u', device_id: 'd', updated_at: null },
    { token: 'damgali', user_id: 'u', device_id: 'd', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  const b = collapseTokens([
    { token: 'damgali', user_id: 'u', device_id: 'd', updated_at: '2026-09-01T00:00:00Z' },
    { token: 'damgasiz', user_id: 'u', device_id: 'd', updated_at: null },
  ]);
  assertEquals(a.map((r) => r.token), ['damgali']);
  assertEquals(b.map((r) => r.token), ['damgali']);
});

Deno.test('eşit damgada ilk satır kalır (deterministik)', () => {
  const out = collapseTokens([
    { token: 'ilk', user_id: 'u', device_id: 'd', updated_at: '2026-09-01T00:00:00Z' },
    { token: 'ikinci', user_id: 'u', device_id: 'd', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out.map((r) => r.token), ['ilk']);
});

Deno.test('bozuk tarih metni çökertmez, 0 sayılır', () => {
  const out = collapseTokens([
    { token: 'bozuk', user_id: 'u', device_id: 'd', updated_at: 'dün' },
    { token: 'iyi', user_id: 'u', device_id: 'd', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out[0].token, 'iyi');
});

Deno.test('dedupe: kullanıcı → tokenlar ve elenen sayısı', () => {
  const { tokensByUser, skipped } = dedupeTokensByDevice([
    { token: 'a1', user_id: 'u1', device_id: 'd1', updated_at: '2026-01-01T00:00:00Z' },
    { token: 'a2', user_id: 'u1', device_id: 'd1', updated_at: '2026-02-01T00:00:00Z' },
    { token: 'b', user_id: 'u1', device_id: 'd2', updated_at: '2026-02-01T00:00:00Z' },
    { token: 'c', user_id: 'u2', device_id: null, platform: 'ios', updated_at: null },
  ]);
  assertEquals(tokensByUser.get('u1'), ['a2', 'b']);
  assertEquals(tokensByUser.get('u2'), ['c']);
  assertEquals(skipped, 1);
});
