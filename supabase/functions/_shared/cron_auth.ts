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
  if (fromHeader !== null && sabitZamanliEsit(fromHeader, cronSecret)) {
    return null;
  }

  const auth = request.headers.get('Authorization');
  if (auth !== null && sabitZamanliEsit(auth, `Bearer ${cronSecret}`)) {
    return null;
  }

  return new Response(
    JSON.stringify({ error: 'Yetkisiz cron cagrisi.' }),
    {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    },
  );
}

/// Sabit zamanlı karşılaştırma. `===` ilk farklı bayttta durur; yanıt
/// süresinden secret'ın kaç karakterinin doğru olduğu ölçülebilir (2026-09
/// denetimi L1). Uzunluk farkı da sızmasın diye iki dizi de aynı uzunluğa
/// getirilerek XOR toplanır.
export function sabitZamanliEsit(a: string, b: string): boolean {
  const n = Math.max(a.length, b.length);
  let fark = a.length ^ b.length;
  for (let i = 0; i < n; i++) {
    fark |= (a.charCodeAt(i) || 0) ^ (b.charCodeAt(i) || 0);
  }
  return fark === 0;
}

/// FAIL-CLOSED kapı: secret tanımsızsa 503.
///
/// `cronYetkisiVarMi` secret boşken kontrolü ATLAR (yerel geliştirme için
/// bilinçli). Üretimde bu, yanlış yazılmış ya da restore sonrası kaybolmuş
/// bir secret'ın fonksiyonu herkese açması demek (2026-09 denetimi H2).
/// Fonksiyonlar bunu `cronYetkisiVarMi`'den ÖNCE çağırır: secret yoksa
/// istek hiç işlenmez ve log'a düşer. Yerelde `CRON_AUTH_ALLOW_UNSET=1` ile
/// kapı açılır.
export function cronSecretZorunlu(
  cronSecret: string | undefined | null,
  envName: string,
): Response | null {
  if (cronSecret) return null;
  if (Deno.env.get('CRON_AUTH_ALLOW_UNSET') === '1') return null;
  console.error(
    `${envName} tanimli degil — cron yetkilendirmesi yapilamiyor, istek reddedildi.`,
  );
  return new Response(JSON.stringify({ error: 'cron_secret_missing' }), {
    status: 503,
    headers: { 'Content-Type': 'application/json' },
  });
}
