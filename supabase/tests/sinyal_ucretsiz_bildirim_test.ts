// Sinyal bildirimi kuralı, sunucu kapısı (`premium_ayar.kapi_acik`) açıkken
// (yasin, 2026-10-10 akşam: "en yaygın 3 tanesi ücretsiz … push bildirimi
// premium" + "olur ama limitli sayıda yapabilmeli").
//
//  - Premium: seçtiği bütün göstergeler, ileri üçü, periyotlar, sıklık.
//  - Ücretsiz: yalnız RSI/MACD/Bollinger, varsayılan periyot, günde 1 tur.
//  - Kapı kapalıyken `bildirimKurali` çağrılmaz (eski davranış).
//
// İstemci eşi: test/sinyal_premium_kapisi_test.dart.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/sinyal_ucretsiz_bildirim_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  bildirimKurali,
  slotaSigdir,
  UCRETSIZ_GOSTERGELER,
} from '../functions/analyze-signals/index.ts';

Deno.test('Premium: seçimi aynen, ileri göstergeler ve periyot açık', () => {
  assertEquals(bildirimKurali(['rsi', 'adx', 'cci'], true, 1), {
    gostergeler: ['rsi', 'adx', 'cci'],
    ileri: true,
    parametre: true,
    slot: 0,
  });
});

Deno.test('ücretsiz: yalnız üç gösterge, periyot yok, günde 1', () => {
  assertEquals(bildirimKurali(['rsi', 'ema', 'bollinger', 'adx'], false, 1), {
    gostergeler: ['rsi', 'bollinger'],
    ileri: false,
    parametre: false,
    slot: 1,
  });
});

Deno.test('ücretsiz, yalnız Premium göstergeler seçili: bildirim yok', () => {
  assertEquals(bildirimKurali(['ema', 'stochastic'], false, 1), null);
});

Deno.test('ücretsiz küme en yaygın üçü (istemci IndicatorId.ucretsiz)', () => {
  assertEquals([...UCRETSIZ_GOSTERGELER], ['rsi', 'macd', 'bollinger']);
});

Deno.test('ücretsiz sıklık günde 1 tura iner, tercih satırı değişmez', () => {
  const p = { frequency: 'hourly' as const, notify_hours: [] as number[] };
  assertEquals(slotaSigdir(p, 1), { frequency: 'daily', notify_hours: [11] });
  assertEquals(p.frequency, 'hourly');
});
