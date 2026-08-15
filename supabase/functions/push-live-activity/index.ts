// Live Activity push — iOS kilit ekranı / Dynamic Island güncelleyici.
//
// ## Neden FCM DEĞİL
// Projedeki diğer bildirimler (`send-partner-invite-push`, sinyaller) FCM
// üzerinden gidiyor. ActivityKit push'u FCM ile GÖNDERİLEMEZ: Apple özel
// bir topic (`<bundle>.push-type.liveactivity`), `apns-push-type:
// liveactivity` başlığı ve oturuma özel bir token ister. FCM bu üçünü de
// aktaramaz. Bu yüzden burada doğrudan APNs'e, token bazlı JWT ile
// bağlanılır.
//
// ## Çağrılma biçimi
// `pg_cron` seans içinde periyodik tetikler (bkz. 0033 migration).
// Ayrıca elle çağrılabilir: `{ "userId": "<uuid>" }` gövdesiyle tek
// kullanıcı güncellenir (hata ayıklama için).

import { createClient } from 'jsr:@supabase/supabase-js@2';

// ── APNs kimlik bilgileri ───────────────────────────────────────────────
// Token bazlı kimlik doğrulama (sertifika değil): .p8 anahtarı 1 yıl
// geçerli JWT üretir ve tüm uygulamalar için çalışır.
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID');
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID');
const APNS_PRIVATE_KEY = Deno.env.get('APNS_PRIVATE_KEY'); // .p8 içeriği
const APNS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID') ?? 'com.sandik.app';
// Üretim: api.push.apple.com — geliştirme: api.sandbox.push.apple.com
const APNS_HOST =
  Deno.env.get('APNS_HOST') ?? 'api.push.apple.com';

/// `live_activity_sessions.summary` içeriğinin beklenen ANLAM sürümü.
///
/// `LiveActivityService.summarySchemaVersion` ile BİREBİR aynı olmalı.
/// v1: ömürlük getiri · v2: günlük ama nakit akışından arındırılmamış ·
/// v3: arındırılmış (uygulamanın kartıyla aynı). Alan adları üç sürümde
/// de aynı kaldığı için damgasız ayırt edilemez.
const SUMMARY_SCHEMA_VERSION = 3;

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

/// APNs JWT'si — 1 saat geçerli, süresi dolunca yenilenir.
///
/// Apple aynı token'ın 20 dakikadan sık yenilenmesini reddeder
/// (`TooManyProviderTokenUpdates`), bu yüzden önbelleklenir.
let cachedJwt: { token: string; exp: number } | null = null;

async function apnsJwt(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  // 55 dakika: Apple 60 dakikayı aşan token'ı reddeder, pay bırakıyoruz.
  if (cachedJwt && cachedJwt.exp > now + 300) return cachedJwt.token;

  const key = await importP8(APNS_PRIVATE_KEY!);
  const header = { alg: 'ES256', kid: APNS_KEY_ID };
  const payload = { iss: APNS_TEAM_ID, iat: now };

  const enc = (o: unknown) =>
    b64url(new TextEncoder().encode(JSON.stringify(o)));
  const signingInput = `${enc(header)}.${enc(payload)}`;

  const sig = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  );

  const token = `${signingInput}.${b64url(new Uint8Array(sig))}`;
  cachedJwt = { token, exp: now + 3300 };
  return token;
}

/// .p8 (PKCS#8 PEM) anahtarını WebCrypto'ya yükler.
async function importP8(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s+/g, '');
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    'pkcs8',
    der,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
}

function b64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

/// BIST işlem saatleri içinde miyiz? (Istanbul saatiyle 10:00–18:10, hafta içi)
///
/// `LiveActivityService.isMarketOpen` ile AYNI kuraldır ve aynı kalmalıdır:
/// uygulama önplandayken istemci, kapalıyken sunucu karar verir; ikisi
/// ayrışırsa aynı anda "Canlı" ve "Piyasa kapalı" gösterilebilir.
///
/// Resmî tatiller burada da bilinmez — takvim gerektirir ve yanlış bir
/// tatil listesi listesizlikten kötüdür (bkz. TECHNICAL_DEBT.md).
function isBistOpen(now = new Date()): boolean {
  // `en-GB` + `Europe/Istanbul`: DST'yi runtime çözsün, elle ofset
  // eklemek yaz saati uygulamasında sessizce bir saat kaydırırdı.
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Istanbul',
    weekday: 'short',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(now);

  const get = (t: string) => parts.find((p) => p.type === t)?.value ?? '';
  const weekday = get('weekday');
  if (weekday === 'Sat' || weekday === 'Sun') return false;

  const mins = Number(get('hour')) * 60 + Number(get('minute'));
  return mins >= 10 * 60 && mins < 18 * 60 + 10;
}

/// Tek bir oturuma güncelleme gönderir.
///
/// Dönen değer: `'ok'` | `'gone'` (token ölü, satır silinmeli) | `'error'`.
async function pushToSession(
  token: string,
  contentState: Record<string, unknown>,
  staleAtSeconds: number,
): Promise<'ok' | 'gone' | 'error'> {
  const jwt = await apnsJwt();

  const body = {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: 'update',
      'content-state': contentState,
      // Sistem bu andan sonra içeriği "bayat" işaretler — kullanıcı
      // kilit ekranında eski rakama bakıp güncel sanmasın.
      'stale-date': staleAtSeconds,
    },
  };

  const res = await fetch(`https://${APNS_HOST}/3/device/${token}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      // ActivityKit'in ZORUNLU başlıkları — biri eksikse APNs reddeder.
      'apns-topic': `${APNS_BUNDLE_ID}.push-type.liveactivity`,
      'apns-push-type': 'liveactivity',
      // 10 = hemen gönder. Live Activity için 5 (güç tasarrufu) çok
      // gecikmeli; "canlı" vaadini bozar.
      'apns-priority': '10',
      'apns-expiration': '0',
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  if (res.ok) return 'ok';

  // 410 Gone = token artık geçersiz (oturum kapandı).
  // 400 + BadDeviceToken da aynı anlama gelir.
  if (res.status === 410) return 'gone';
  const text = await res.text().catch(() => '');
  if (res.status === 400 && text.includes('BadDeviceToken')) return 'gone';

  console.error(`APNs ${res.status}: ${text}`);
  return 'error';
}

Deno.serve(async (request) => {
  if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_PRIVATE_KEY) {
    return new Response(
      JSON.stringify({ error: 'APNs kimlik bilgileri eksik' }),
      { status: 500, headers: { 'content-type': 'application/json' } },
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey);

  // İsteğe bağlı tek kullanıcı filtresi (hata ayıklama).
  let onlyUser: string | null = null;
  try {
    const b = await request.json();
    onlyUser = typeof b?.userId === 'string' ? b.userId : null;
  } catch {
    // Gövdesiz çağrı normaldir (cron).
  }

  // Yalnızca SÜRESİ DOLMAMIŞ oturumlar. Ölü token'a push atmak APNs
  // tarafında hata üretir ve kotayı yakar.
  let q = admin
    .from('live_activity_sessions')
    .select('token, user_id, expires_at, show_amounts, summary')
    .gt('expires_at', new Date().toISOString());
  if (onlyUser) q = q.eq('user_id', onlyUser);

  const { data: sessions, error } = await q;
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { 'content-type': 'application/json' },
    });
  }
  if (!sessions?.length) {
    return new Response(JSON.stringify({ sent: 0, reason: 'aktif oturum yok' }), {
      headers: { 'content-type': 'application/json' },
    });
  }

  let sent = 0;
  let removed = 0;
  // Eski şema yüzünden atlanan oturumlar — teşhis için yanıta konur.
  // Sürüm geçişinden sonra bu sayı sıfıra inmeli; inmiyorsa o kullanıcılar
  // uygulamayı hiç açmıyor ve kilit ekranları donmuş demektir.
  let skippedStale = 0;
  const deadTokens: string[] = [];

  for (const s of sessions) {
    // Özet İSTEMCİ tarafından yazılır; sunucu yalnızca push'lar.
    //
    // **Neden sunucu hesaplamıyor:** portföy değeri lot toplama + döviz
    // çevrimi + altın dönüşümü ister ve bunların tamamı `HistoryService`
    // içinde yaşıyor. Sunucuda ikinci bir implementasyon kurmak iki
    // kopyanın ayrışması demekti — kullanıcı uygulamada bir rakam, kilit
    // ekranında başka bir rakam görürdü. (Aynı sınıf hata bu projede
    // ons→gram formülünün beş kopyasında yaşandı.)
    //
    // Tazelik `staleDate` ile korunur: uygulama gün boyu hiç açılmazsa
    // sistem içeriği "bayat" işaretler, yanlış rakamı güncel gibi
    // göstermez.
    const row = s.summary as Record<string, unknown> | null;
    if (!row) continue;

    // Eski ANLAM sürümüyle yazılmış özeti push ETME.
    //
    // v1'de `changeText`/`changePctText` ÖMÜRLÜK getiriydi; v2'de günlük
    // değişim. Alan adları aynı olduğu için içeriğe bakarak ayırt etmek
    // mümkün değil — damga şart.
    //
    // Atlamak, yanlış rakam göstermekten iyidir: banner son doğru
    // değerinde kalır ve kullanıcı uygulamayı bir kez açar açmaz istemci
    // yeni özeti yazar. Push'lasaydık, uygulamasını güncellemiş kullanıcı
    // kilit ekranında ömürlük getiriyi "Bugün" diye görmeye devam ederdi.
    if (Number(row.schema ?? 1) < SUMMARY_SCHEMA_VERSION) {
      skippedStale++;
      continue;
    }

    const isPositive = row.isPositive === true;
    const showAmounts = s.show_amounts === true;

    // GİZLİLİK: tutar yalnızca kullanıcı izin verdiyse gönderilir.
    // Maskeleme sunum katmanında değil BURADA yapılır — rakam cihaza
    // hiç ulaşmasın.
    const contentState = {
      totalText: showAmounts ? String(row.totalText ?? '') : '••••••',
      changeText: showAmounts ? String(row.changeText ?? '') : '••••••',
      changePctText: String(row.changePctText ?? '%0,00'),
      isPositive,
      isHidden: false,
      // Zaman damgası SUNUCUDA üretilir: istemcinin yazdığı saat, push
      // anına kadar eskimiş olur. Kullanıcı "Canlı 14:32" görüp saatin
      // 15:10 olduğunu fark ederse yüzeye güveni biter.
      updatedAtText: new Date().toLocaleTimeString('tr-TR', {
        hour: '2-digit',
        minute: '2-digit',
        timeZone: 'Europe/Istanbul',
      }),
      // Tarih de SUNUCUDA üretilir, `updatedAtText` ile aynı gerekçeyle:
      // oturum gece yarısını geçebilir ve istemcinin yazdığı tarih o anda
      // dünü gösterirdi. Gün adı dahil — "15 Ağustos Cuma".
      dateText: new Date().toLocaleDateString('tr-TR', {
        day: 'numeric',
        month: 'long',
        weekday: 'long',
        timeZone: 'Europe/Istanbul',
      }),
      sessionEndsAt: Math.floor(new Date(s.expires_at).getTime() / 1000),
      sparkline: Array.isArray(row.sparkline) ? row.sparkline : [],
      showAmounts,
      // Piyasa durumu da push anına göre hesaplanır. Bu alan hiç
      // gönderilmediği için istemci varsayılanı ("açık") devreye giriyordu
      // ve gece yarısı push'lanan banner "Canlı" diyordu — donuk rakamla
      // birlikte doğrudan yanlış bilgi.
      isMarketOpen: isBistOpen(),
    };

    const result = await pushToSession(
      s.token,
      contentState,
      Math.floor(new Date(s.expires_at).getTime() / 1000),
    );

    if (result === 'ok') sent++;
    else if (result === 'gone') deadTokens.push(s.token);
  }

  // Ölü token'ları temizle — bir sonraki turda tekrar denenmesin.
  if (deadTokens.length) {
    const { error: delErr } = await admin
      .from('live_activity_sessions')
      .delete()
      .in('token', deadTokens);
    if (!delErr) removed = deadTokens.length;
  }

  return new Response(
    JSON.stringify({ sent, removed, skippedStale, total: sessions.length }),
    { headers: { 'content-type': 'application/json' } },
  );
});
