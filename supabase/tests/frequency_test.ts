// Bildirim sıklığı / zaman penceresi testleri.
//
// `shouldNotifyNow` saatbaşı çalışan cron'un hangi kullanıcıya gönderim
// yapacağına karar verir. Zamana bağlı olduğu için elle test kırılgan —
// bu yüzden saat enjekte edilebilir tutuldu.
//
// Çalıştır:
//   deno test supabase/tests/frequency_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  shouldNotifyNow,
  shouldSendSignal,
} from '../functions/analyze-signals/index.ts';

/// TR saatini (UTC+3) veren yardımcı: verilen TR saatinde bir UTC tarihi.
function trSaati(hour: number, minute = 0): Date {
  // TR = UTC+3 → UTC saati = TR - 3
  return new Date(Date.UTC(2026, 7, 6, (hour - 3 + 24) % 24, minute));
}

Deno.test('pencere dışında hiçbir sıklıkta gönderim yok', () => {
  for (const freq of ['hourly', 'every_2h', 'every_3h', 'daily'] as const) {
    // 09:00 → pencere (10-18) başlamadan
    assertEquals(
      shouldNotifyNow({ frequency: freq, notify_hours: [9] }, trSaati(9)),
      false,
      `${freq} 09:00'da gönderim yapmamalı`,
    );
    // 19:00 → pencere bittikten sonra
    assertEquals(
      shouldNotifyNow({ frequency: freq, notify_hours: [19] }, trSaati(19)),
      false,
      `${freq} 19:00'da gönderim yapmamalı`,
    );
  }
});

Deno.test('pencere sınırları dahildir (10 ve 18)', () => {
  assertEquals(shouldNotifyNow({ frequency: 'hourly' }, trSaati(10)), true);
  assertEquals(shouldNotifyNow({ frequency: 'hourly' }, trSaati(18)), true);
});

Deno.test('saatlik: son gönderimden 1 saat geçmeden tekrar göndermez', () => {
  const now = trSaati(14);
  const yarimSaatOnce = new Date(now.getTime() - 30 * 60_000).toISOString();
  assertEquals(
    shouldNotifyNow(
      { frequency: 'hourly', last_notified_at: yarimSaatOnce },
      now,
    ),
    false,
  );

  const birSaatOnce = new Date(now.getTime() - 60 * 60_000).toISOString();
  assertEquals(
    shouldNotifyNow({ frequency: 'hourly', last_notified_at: birSaatOnce }, now),
    true,
  );
});

Deno.test('2 ve 3 saatlik periyotlar süreye göre çalışır', () => {
  const now = trSaati(16);
  const ikiSaatOnce = new Date(now.getTime() - 2 * 3_600_000).toISOString();

  assertEquals(
    shouldNotifyNow(
      { frequency: 'every_2h', last_notified_at: ikiSaatOnce },
      now,
    ),
    true,
  );
  // 3 saatlik için 2 saat yetmez
  assertEquals(
    shouldNotifyNow(
      { frequency: 'every_3h', last_notified_at: ikiSaatOnce },
      now,
    ),
    false,
  );
});

Deno.test('cron birkaç dakika kayarsa gönderim düşmez (5 dk tolerans)', () => {
  // Cron 57. dakikada tetiklenirse "1 saat" tam dolmamıştır; dar tolerans
  // olmasaydı saatlik bildirim her turda bir sonraki saate ötelenirdi.
  const now = trSaati(13);
  const elliYediDkOnce = new Date(now.getTime() - 57 * 60_000).toISOString();
  assertEquals(
    shouldNotifyNow(
      { frequency: 'hourly', last_notified_at: elliYediDkOnce },
      now,
    ),
    true,
  );

  // Ama tolerans GENİŞ olmamalı: 30 dk önce gönderilmişken saatlik bildirim
  // tekrar gitmemeli, yoksa periyot fiilen yarıya iner.
  const otuzDkOnce = new Date(now.getTime() - 30 * 60_000).toISOString();
  assertEquals(
    shouldNotifyNow({ frequency: 'hourly', last_notified_at: otuzDkOnce }, now),
    false,
  );
});

Deno.test('hiç gönderilmemişse ilk turda gönderilir', () => {
  assertEquals(
    shouldNotifyNow({ frequency: 'every_3h', last_notified_at: null }, trSaati(11)),
    true,
  );
});

Deno.test('günde 2: yalnızca seçilen saatlerde', () => {
  const pref = { frequency: 'twice_daily' as const, notify_hours: [11, 15] };
  assertEquals(shouldNotifyNow(pref, trSaati(11)), true);
  assertEquals(shouldNotifyNow(pref, trSaati(15)), true);
  assertEquals(shouldNotifyNow(pref, trSaati(13)), false);
});

Deno.test('günde 1: yalnızca seçilen saatte', () => {
  const pref = { frequency: 'daily' as const, notify_hours: [17] };
  assertEquals(shouldNotifyNow(pref, trSaati(17)), true);
  assertEquals(shouldNotifyNow(pref, trSaati(11)), false);
});

Deno.test('günde 2: aynı saat içinde ikinci kez göndermez', () => {
  const now = trSaati(11, 30);
  const onDkOnce = new Date(now.getTime() - 10 * 60_000).toISOString();
  assertEquals(
    shouldNotifyNow(
      {
        frequency: 'twice_daily',
        notify_hours: [11, 15],
        last_notified_at: onDkOnce,
      },
      now,
    ),
    false,
  );
});

Deno.test('tercih satırı yoksa varsayılan: günde 2 (11 ve 15)', () => {
  assertEquals(shouldNotifyNow(undefined, trSaati(11)), true);
  assertEquals(shouldNotifyNow(undefined, trSaati(15)), true);
  assertEquals(shouldNotifyNow(undefined, trSaati(12)), false);
});

Deno.test('kullanıcı penceresi daraltılabilir', () => {
  // Kullanıcı 12–16 seçtiyse 11:00'de gönderim olmamalı.
  const pref = {
    frequency: 'hourly' as const,
    window_start: 12,
    window_end: 16,
  };
  assertEquals(shouldNotifyNow(pref, trSaati(11)), false);
  assertEquals(shouldNotifyNow(pref, trSaati(12)), true);
  assertEquals(shouldNotifyNow(pref, trSaati(16)), true);
  assertEquals(shouldNotifyNow(pref, trSaati(17)), false);
});

// ── De-dup: aynı sinyal art arda bildirilmez ───────────────────────────────
// Kullanıcı isteği: "sabah SAT verdiyse, akşam yine SAT verdiğinde push
// gelmemeli, ancak nötr ya da AL'a dönerse vermeli."

Deno.test('aynı sinyal tekrar ederse gönderilmez', () => {
  assertEquals(shouldSendSignal('sell', 'sell'), false);
  assertEquals(shouldSendSignal('buy', 'buy'), false);
  assertEquals(shouldSendSignal('neutral', 'neutral'), false);
});

Deno.test('sinyal değişince gönderilir', () => {
  // Kullanıcının verdiği örnek: SAT → NÖTR ve SAT → AL bildirilmeli.
  assertEquals(shouldSendSignal('sell', 'neutral'), true);
  assertEquals(shouldSendSignal('sell', 'buy'), true);
  assertEquals(shouldSendSignal('buy', 'sell'), true);
  assertEquals(shouldSendSignal('neutral', 'buy'), true);
});

Deno.test('ilk sinyal her zaman gönderilir', () => {
  assertEquals(shouldSendSignal(undefined, 'buy'), true);
  assertEquals(shouldSendSignal(undefined, 'sell'), true);
});

// ── De-dup: cooldown, tekrar aralığı, güven sıçraması ──────────────────────
//
// Saf "değişti mi" kuralı iki uçta birden yanlıştı:
//   · sinyal sabit kalırsa SÜRESİZ sessizlik (2026-08-09 → 08-18: 9 gün),
//   · eşik civarında salınırsa her geçişte bildirim (zıplama/spam).

const T0 = new Date('2026-08-20T12:00:00Z');
const saatOnce = (s: number) => new Date(T0.getTime() - s * 3_600_000);

Deno.test('cooldown: sinyal değişse bile çok yakın bildirim bastırılır', () => {
  // 30 dk önce bildirim yapıldı; sinyal değişti ama cooldown (2s) dolmadı.
  assertEquals(
    shouldSendSignal('buy', 'sell', {
      sonBildirim: saatOnce(0.5),
      simdi: T0,
    }),
    false,
  );

  // 3 saat geçmiş — artık gönderilir.
  assertEquals(
    shouldSendSignal('buy', 'sell', {
      sonBildirim: saatOnce(3),
      simdi: T0,
    }),
    true,
  );
});

Deno.test('tekrar aralığı: aynı sinyal 24 saat sonra HATIRLATILIR', () => {
  // Durum sürüyor ama gün dolmadı → sessiz.
  assertEquals(
    shouldSendSignal('sell', 'sell', {
      sonBildirim: saatOnce(10),
      simdi: T0,
    }),
    false,
  );

  // 25 saat geçti → hatırlatma. Bu olmadan kullanıcı süresiz sessizlikte
  // kalıyordu ve sistemi "bozuk" sanıyordu.
  assertEquals(
    shouldSendSignal('sell', 'sell', {
      sonBildirim: saatOnce(25),
      simdi: T0,
    }),
    true,
  );
});

Deno.test('güven sıçraması: aynı sinyal ama belirgin güçlenme bildirilir', () => {
  // SAT %50 → SAT %85: göstergeler çok daha güçlü uzlaşmış, YENİ BİLGİ.
  assertEquals(
    shouldSendSignal('sell', 'sell', {
      oncekiGuven: 50,
      yeniGuven: 85,
      sonBildirim: saatOnce(5),
      simdi: T0,
    }),
    true,
  );

  // Küçük oynama (50 → 58) eşiğin altında — bildirilmez.
  assertEquals(
    shouldSendSignal('sell', 'sell', {
      oncekiGuven: 50,
      yeniGuven: 58,
      sonBildirim: saatOnce(5),
      simdi: T0,
    }),
    false,
  );

  // Güven DÜŞTÜYSE bildirilmez — daha zayıf sinyal kullanıcıyı uyandırmaz.
  assertEquals(
    shouldSendSignal('sell', 'sell', {
      oncekiGuven: 85,
      yeniGuven: 50,
      sonBildirim: saatOnce(5),
      simdi: T0,
    }),
    false,
  );

  // Sıçrama da cooldown'a tabi: 1 saat önce bildirildiyse beklenir.
  assertEquals(
    shouldSendSignal('sell', 'sell', {
      oncekiGuven: 50,
      yeniGuven: 90,
      sonBildirim: saatOnce(1),
      simdi: T0,
    }),
    false,
  );
});

Deno.test('zaman bilgisi YOKSA eski davranışa düşer', () => {
  // Migration 0038 öncesi satırlarda `notified_at` NULL. Sessiz kalmaktansa
  // bir kez fazla bildirmek yeğdir; ama aynı sinyal yine bastırılır.
  assertEquals(shouldSendSignal('buy', 'sell', {}), true);
  assertEquals(shouldSendSignal('sell', 'sell', {}), false);
});
