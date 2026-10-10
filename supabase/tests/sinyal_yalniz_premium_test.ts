// Sinyal yalnız Premium kapısı (yasin, 2026-10-10: "varlık gösterge sinyali
// özelliği tamamen premiuma geçsin").
//
// `yalnizPremiumFiltresi` sunucu kapısı (`premium_ayar.kapi_acik`) açıkken
// premium olmayan kullanıcıların bütün lotlarını eler; kapalıyken diziye
// dokunmaz — paywall açılmadan davranış birebir eskisi. İstemci eşi
// `sinyalYuzeyiProvider` (test/sinyal_premium_kapisi_test.dart).
//
// Çalıştır:
//   deno test supabase/tests/sinyal_yalniz_premium_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import { yalnizPremiumFiltresi } from '../functions/analyze-signals/index.ts';

const lotlar = [
  { id: '1', user_id: 'ucretsiz' },
  { id: '2', user_id: 'abone' },
  { id: '3', user_id: 'ucretsiz' },
  { id: '4', user_id: 'admin' },
];

Deno.test('kapı kapalıyken herkes sinyal alır (eski davranış)', () => {
  assertEquals(
    yalnizPremiumFiltresi(lotlar, false, new Set(['abone'])).map((l) => l.id),
    ['1', '2', '3', '4'],
  );
});

Deno.test('kapı açıkken yalnız premium kümesi kalır', () => {
  assertEquals(
    yalnizPremiumFiltresi(lotlar, true, new Set(['abone', 'admin'])).map((l) => l.id),
    ['2', '4'],
  );
});

Deno.test('kapı açık, kimse premium değil: hiç lot kalmaz', () => {
  assertEquals(yalnizPremiumFiltresi(lotlar, true, new Set()), []);
});

Deno.test('girdi dizisi değişmez', () => {
  const kopya = [...lotlar];
  yalnizPremiumFiltresi(lotlar, true, new Set());
  assertEquals(lotlar, kopya);
});
