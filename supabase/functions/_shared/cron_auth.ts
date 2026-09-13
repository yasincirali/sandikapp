// Cron çağrısı yetkilendirmesi — TEK kaynak.
//
// ── Neden Authorization DEĞİL de ayrı bir header ────────────────────────────
// Supabase API gateway, edge function'a ulaşmadan ÖNCE `Authorization`
// header'ını JWT olarak ayrıştırır. Rastgele hex bir cron secret JWT
// biçiminde olmadığı için gateway isteği fonksiyona hiç iletmeden
// `401 UNAUTHORIZED_INVALID_JWT_FORMAT` döner.
//
// Bu hata SESSİZDİ: cron her gün koşuyor, pg_net 401'i `net._http_response`
// içine yazıyor ve kimse bakmıyordu. `daily_brief_log` Mayıs 2026'dan beri
// boştu — brifing hiç gitmemişti. `live-activity-refresh`'in çalışmasının
// tek sebebi Vault'undaki değerin (219 karakter) rastgele bir string değil,
// gerçek bir service_role JWT'si olmasıydı.
//
// Doğru bölüşüm:
//   Authorization: Bearer <service_role JWT>  → gateway'i geçer
//   x-cron-secret: <rastgele uzun string>     → fonksiyon doğrular
//
// İki katman korunur. Gateway'i `verify_jwt = false` ile kapatmak tek
// savunma olarak secret'ı bırakırdı; Vault'a service_role JWT'yi cron
// secret'ı OLARAK yazmak ise fonksiyon başına izolasyonu yok ederdi
// (tek sızıntı tüm DB'yi açar).

/// Cron secret'ını taşıyan header. `Authorization` gateway'e ait.
export const CRON_SECRET_HEADER = 'x-cron-secret';

/// Cron çağrısını doğrular. `null` = geçti, `Response` = reddedildi.
///
/// `cronSecret` boşsa kontrol atlanır (yerel geliştirme). Bu, üretimde
/// secret'ın tanımlı olmasına güvenir — `daily-brief` gibi fonksiyonlarda
/// zaten var olan davranış, korunuyor.
///
/// Geriye dönük uyum: `Authorization: Bearer <cron_secret>` de kabul edilir.
/// Migration'lar ve fonksiyonlar aynı anda dağıtılamaz; arada kalan çağrı
/// yetkisiz sayılıp kaybolmasın. Gateway'in JWT duvarı yüzünden bu yol
/// pratikte yalnızca gateway doğrulamasının kapalı olduğu durumda çalışır.
export function cronYetkisiVarMi(
  request: Request,
  cronSecret: string | undefined | null,
): Response | null {
  if (!cronSecret) return null;

  const fromHeader = request.headers.get(CRON_SECRET_HEADER);
  if (fromHeader === cronSecret) return null;

  const auth = request.headers.get('Authorization');
  if (auth === `Bearer ${cronSecret}`) return null;

  return new Response(
    JSON.stringify({ error: 'Yetkisiz cron cagrisi.' }),
    {
      status: 401,
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Content-Type': 'application/json',
      },
    },
  );
}
