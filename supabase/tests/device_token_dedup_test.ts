// Cihaz başına token indirgemesi testleri.
//
// Kapsanan hata (2026-09-01): kullanıcı tek bir sinyal için AYNI telefonda
// birden çok push alıyordu. `collapseLotsToPositions` lot çoklanmasını zaten
// çözmüştü (2026-08-31) ve doğru çalışıyordu — kalan çoklanma BAŞKA bir
// katmandan geliyordu:
//
//   for (const token of tokensByUser.get(asset.user_id) ?? []) { ... }
//
// Kullanıcının kaç token'ı varsa o kadar push gider. Tablo `token` PK'lı
// olduğu için aynı token çoğalamaz, ama aynı CİHAZ zamanla birden çok token
// üretir (FCM rotasyonu: yeniden kurulum, veri temizleme, güncelleme).
// İstemci eski token'ı yalnızca bellekteki `_currentToken` doluyken siliyordu;
// uygulama yeniden başlayınca o alan null olur ve eski satır tabloda kalır.
// FCM eski token'ı çoğu zaman GEÇERLİ sayıp aynı cihaza teslim eder, yani
// `UNREGISTERED` temizliği de devreye girmez.
//
// Çalıştır:
//   deno test supabase/tests/device_token_dedup_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import { dedupeTokensByDevice } from '../functions/analyze-signals/index.ts';

Deno.test('aynı cihazın üç token’ı → tek push', () => {
  const { tokensByUser, skipped } = dedupeTokensByDevice([
    { token: 'eski1', user_id: 'u1', device_id: 'dev-a', updated_at: '2026-01-01T00:00:00Z' },
    { token: 'eski2', user_id: 'u1', device_id: 'dev-a', updated_at: '2026-05-01T00:00:00Z' },
    { token: 'guncel', user_id: 'u1', device_id: 'dev-a', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(tokensByUser.get('u1')?.length, 1, 'tek cihaz = tek bildirim');
  assertEquals(tokensByUser.get('u1')?.[0], 'guncel', 'en taze token kazanmalı');
  assertEquals(skipped, 2);
});

Deno.test('İKİ AYRI cihaz ikisi de bildirim alır', () => {
  // Telefon + tablet meşru bir senaryodur; indirgeme bunu bastırmamalı.
  const { tokensByUser, skipped } = dedupeTokensByDevice([
    { token: 'telefon', user_id: 'u1', device_id: 'dev-a', updated_at: '2026-09-01T00:00:00Z' },
    { token: 'tablet', user_id: 'u1', device_id: 'dev-b', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(tokensByUser.get('u1')?.length, 2);
  assertEquals(skipped, 0);
});

Deno.test('device_id YOKSA platform’a düşer — eski sürüm istemciler', () => {
  // Migration öncesi satırlar ve güncellenmemiş istemciler `device_id`
  // taşımaz. Bu satırlar korumasız kalırsa çoklanma sürerdi.
  const { tokensByUser, skipped } = dedupeTokensByDevice([
    { token: 'eski', user_id: 'u1', platform: 'android', updated_at: '2026-01-01T00:00:00Z' },
    { token: 'yeni', user_id: 'u1', platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(tokensByUser.get('u1')?.length, 1, 'aynı platform = aynı cihaz varsayılır');
  assertEquals(tokensByUser.get('u1')?.[0], 'yeni');
  assertEquals(skipped, 1);
});

Deno.test('android + ios ayrı cihaz sayılır', () => {
  const { tokensByUser } = dedupeTokensByDevice([
    { token: 'a', user_id: 'u1', platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
    { token: 'i', user_id: 'u1', platform: 'ios', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(tokensByUser.get('u1')?.length, 2);
});

Deno.test('FARKLI kullanıcılar asla birleşmez', () => {
  // `user_id` anahtarın parçasıdır. Birleşirlerse yalnızca birine bildirim
  // gider — ortaklık tarafındaki "farklı sahipler havuzlanmaz" değişmezinin
  // push karşılığı.
  const { tokensByUser } = dedupeTokensByDevice([
    { token: 't1', user_id: 'u1', device_id: 'dev-a', updated_at: '2026-09-01T00:00:00Z' },
    { token: 't2', user_id: 'u2', device_id: 'dev-a', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(tokensByUser.get('u1')?.length, 1);
  assertEquals(tokensByUser.get('u2')?.length, 1);
});

Deno.test('updated_at yoksa çökmez', () => {
  const { tokensByUser } = dedupeTokensByDevice([
    { token: 'a', user_id: 'u1', device_id: 'dev-a' },
    { token: 'b', user_id: 'u1', device_id: 'dev-a', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(tokensByUser.get('u1')?.length, 1);
  assertEquals(tokensByUser.get('u1')?.[0], 'b', 'damgalı satır damgasıza yeğlenir');
});

Deno.test('boş girdi', () => {
  const { tokensByUser, skipped } = dedupeTokensByDevice([]);
  assertEquals(tokensByUser.size, 0);
  assertEquals(skipped, 0);
});

// ── Bağlantı (wiring) koruması ────────────────────────────────────────────
//
// Yukarıdaki testler fonksiyonun DOĞRU olduğunu kanıtlar, KULLANILDIĞINI
// değil — `lot_collapse_test.ts`'de bu ayrım sabotajla ölçülmüştü: fonksiyon
// doğruyken çağrı yeri bozulunca sekiz testin sekizi de geçmişti.
//
// Aynı tuzak burada da var: `tokensByUser` ham `tokenRows`'tan yeniden
// kurulursa tüm birim testleri geçmeye devam eder ama kullanıcı yine kopya
// bildirim alır.
Deno.test('token listesi indirgemeden GEÇİYOR', async () => {
  const src = await Deno.readTextFile(
    new URL('../functions/analyze-signals/index.ts', import.meta.url),
  );

  assertEquals(
    src.includes('dedupeTokensByDevice(tokenRows)'),
    true,
    '`tokensByUser` `dedupeTokensByDevice`’tan gelmeli — ham `tokenRows` ' +
      'üzerinden kurulursa aynı cihaza KOPYA push gider.',
  );

  // Sorgu indirgemenin ihtiyaç duyduğu sütunları çekmeli. `device_id`
  // seçilmezse fonksiyon sessizce platform’a düşer ve iki gerçek cihaz
  // tek cihaz sanılır.
  assertEquals(
    src.includes("select('token, user_id, device_id, platform, updated_at')"),
    true,
    'Token sorgusu `device_id`, `platform` ve `updated_at` çekmeli.',
  );
});
