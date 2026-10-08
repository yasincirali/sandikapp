// Ücretsiz sürümün günlük sinyal bildirimi kapısı (Premium planı, 2026-10-08).
//
// `slotaSigdir` yalnız bu turun zamanlama kararını kısar; tercih satırı
// değişmez. Kapı `SINYAL_UCRETSIZ_SLOT` tanımlı değilken yoktur.
//
// Çalıştır:
//   deno test supabase/tests/sinyal_slot_kapisi_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  GUNLUK_EN_FAZLA,
  shouldNotifyNow,
  slotaSigdir,
} from '../functions/analyze-signals/index.ts';

function trSaati(hour: number): Date {
  return new Date(Date.UTC(2026, 9, 8, (hour - 3 + 24) % 24, 0));
}

Deno.test('slot 0 ya da tanımsız: tercih olduğu gibi döner', () => {
  const p = { frequency: 'hourly' as const, notify_hours: [] };
  assertEquals(slotaSigdir(p, 0), p);
  assertEquals(slotaSigdir(p, undefined), p);
  assertEquals(slotaSigdir(undefined, 0), undefined);
});

Deno.test('sığan sıklık dokunulmadan kalır', () => {
  const p = { frequency: 'daily' as const, notify_hours: [14] };
  assertEquals(slotaSigdir(p, 1), p);
  const iki = { frequency: 'twice_daily' as const, notify_hours: [11, 15] };
  assertEquals(slotaSigdir(iki, 2), iki);
});

Deno.test('günde 2 kez → günde 1, seçtiği ilk saat', () => {
  const p = { frequency: 'twice_daily' as const, notify_hours: [10, 16] };
  assertEquals(slotaSigdir(p, 1), { frequency: 'daily', notify_hours: [10] });
  // Kopya döner; tercih satırı değişmez.
  assertEquals(p.frequency, 'twice_daily');
});

Deno.test('periyodik sıklık → günde 1, sabah 11:00', () => {
  for (const f of ['hourly', 'every_2h', 'every_3h'] as const) {
    assertEquals(
      slotaSigdir({ frequency: f, notify_hours: [17] }, 1),
      { frequency: 'daily', notify_hours: [11] },
      f,
    );
  }
});

Deno.test('tercih satırı yoksa varsayılan (günde 2) → 11:00', () => {
  const s = slotaSigdir(undefined, 1);
  assertEquals(s, { frequency: 'daily', notify_hours: [11] });
  assertEquals(shouldNotifyNow(s, trSaati(11)), true);
  assertEquals(shouldNotifyNow(s, trSaati(15)), false);
});

Deno.test('kısıtlı ücretsiz kullanıcı öğleden sonra bildirim almaz', () => {
  const p = { frequency: 'twice_daily' as const, notify_hours: [11, 15] };
  assertEquals(shouldNotifyNow(p, trSaati(15)), true);
  assertEquals(shouldNotifyNow(slotaSigdir(p, 1), trSaati(15)), false);
});

Deno.test('günlük tur sayıları istemciyle aynı', () => {
  // lib/models/signal_frequency.dart → gunlukEnFazla
  assertEquals(GUNLUK_EN_FAZLA, {
    hourly: 9,
    every_2h: 5,
    every_3h: 3,
    twice_daily: 2,
    daily: 1,
  });
});
