// Analyze Signals Edge Function — SUNUCU TARAFLI ANALİZ
//
// pg_cron tarafından tetiklenir. Her kullanıcının portföyünü sunucuda analiz
// eder ve eşiği geçen sinyaller için GERÇEK push notification gönderir.
//
// ── Neden değişti ───────────────────────────────────────────────────────────
// Önceki sürüm "hibrit" idi: cron yalnızca data-only bir tetik atıyor, analizi
// client yapıyordu. Bu tasarımın kırılma noktası: bildirim `flutter_local_
// notifications` ile üretiliyordu, yani Dart kodunun ÇALIŞIYOR olması
// gerekiyordu. Uygulama kapalıyken arka plan handler'ı yalnızca Firebase'i
// başlatıp çıkıyordu → kullanıcı hiçbir zaman bildirim almıyordu. iOS'ta
// `content-available` sessiz mesajları zaten garanti edilmez.
//
// Artık analiz burada yapılır ve FCM `notification` payload'ı gönderilir —
// uygulama kapalı olsa da sistem bildirimi gösterir.
//
// ── Maliyet ─────────────────────────────────────────────────────────────────
// Fiyat çekimi sembol başına TEK sefer yapılır ve `price_history_cache`
// üzerinden tüm kullanıcılar arasında paylaşılır (bkz. _shared/price_history.ts).
// Böylece istek sayısı kullanıcı sayısıyla değil portföy çeşitliliğiyle
// ölçeklenir; Supabase ve FCM ücretsiz katmanlarında kalınır.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import {
  analyze,
  AssetType,
  DEFAULT_INDICATORS,
  SignalType,
  summarize,
} from '../_shared/technical_analysis.ts';
import {
  loadPriceHistories,
  MIN_POINTS,
  resolveSymbol,
} from '../_shared/price_history.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ── Google OAuth (FCM v1) ───────────────────────────────────────────────────

function base64UrlEncode(input: string | Uint8Array) {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

async function createAccessToken(serviceAccount: ServiceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claimSet = base64UrlEncode(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const unsignedToken = `${header}.${claimSet}`;
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedToken),
  );
  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch(
    serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    },
  );
  if (!response.ok) {
    throw new Error(`Google access token alinamadi: ${await response.text()}`);
  }
  return (await response.json()).access_token as string;
}

// ── Bildirim metni ──────────────────────────────────────────────────────────
//
// Yasal not: "AL/SAT sinyali" yerine trend yönü ifadesi kullanılır ve
// "Yatırım tavsiyesi değildir" ibaresi eklenir — client'taki
// `NotificationService.sendSignalNotification` ile aynı dil.

/// Bildirim başlığındaki kısa varlık etiketi.
///
/// Kilit ekranı başlığı tek satırdır ve fon adları buna sığmaz
/// ("YAPI KREDİ PORTFÖY YABANCI TEKNOLOJİ SEKTÖRÜ HİSSE SENEDİ FONU" gibi).
/// İşletim sistemine bırakılırsa ortadan keser ve AYIRT EDİCİ kısım —
/// yön okunun hemen yanındaki asıl bilgi — kaybolur.
///
/// Ticker kullanılır ama HAM haliyle değil: kaynak ön ekleri kullanıcıya
/// hiçbir şey ifade etmez, hatta teknik bir hata gibi görünür.
///   `TEFAS:AFO` → `AFO`      (fon kodu)
///   `AGHOL.IS`  → `AGHOL`    (BIST kodu)
///   `EURTRY=X`  → adına düş  (kod değil, kur çifti — "Euro" daha anlaşılır)
export function shortLabel(assetName: string, ticker: string): string {
  const t = (ticker ?? '').trim();

  // Kur çiftleri kod olarak okunmaz; adı zaten kısa ve nettir ("Euro").
  if (t.endsWith('=X') || t === '') return assetName;

  const sade = t.includes(':') ? t.split(':').pop()! : t.replace(/\.IS$/i, '');

  // Sadeleşmiş kod boş ya da anlamsız kısaysa ada güven.
  return sade.length >= 2 ? sade : assetName;
}

function buildMessage(
  assetName: string,
  signal: SignalType,
  buyCount: number,
  sellCount: number,
  ticker = '',
): { title: string; body: string } {
  const total = buyCount + sellCount;
  const disclaimer = 'Yatırım tavsiyesi değildir.';
  const etiket = shortLabel(assetName, ticker);

  // Yön OKU başlıkta, en solda.
  //
  // Kilit ekranında bildirimler yığın halinde görünür ve kullanıcı önce
  // sol kenarı tarar. Ok, metni okumadan önce yönü verir — emoji yerine
  // ▲▼ tercih edildi: finansal ciddiyeti korur, her yazı tipinde aynı
  // görünür ve VoiceOver bunu "yukarı üçgen" diye okur (emoji'nin uzun
  // sesli adı yerine).
  //
  // Yön RENKLE anlatılmaz — bildirim yüzeyinde renk kontrolü yoktur.
  // Bu, uygulamadaki "kazanç/kayıp yalnızca renkle anlatılamaz" kuralının
  // aynısıdır.
  const total2 = total > 0 ? total : 1;

  if (signal === 'neutral') {
    return {
      title: `◆ ${etiket} · yön belirsiz`,
      body: `Göstergeler bölünmüş: ${buyCount} yukarı, ${sellCount} aşağı. ` +
        disclaimer,
    };
  }

  const isBuy = signal === 'buy';
  const lehte = isBuy ? buyCount : sellCount;
  // Güven oranı gövdede AÇIKÇA verilir. "Çoğunluğu yukarı yönlü" ifadesi
  // 4/6 ile 6/6 arasındaki farkı gizliyordu; kullanıcı zayıf bir sinyali
  // güçlü sanabilirdi.
  const yuzde = Math.round((lehte / total2) * 100);

  return {
    title: isBuy ? `▲ ${etiket} · yukarı yönlü` : `▼ ${etiket} · aşağı yönlü`,
    body: `${lehte}/${total} gösterge ${isBuy ? 'yukarı' : 'aşağı'} · ` +
      `güven %${yuzde}. ${disclaimer}`,
  };
}

async function sendPush({
  accessToken,
  projectId,
  token,
  title,
  body,
  assetId,
  badge,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  assetId: string;
  /// iOS rozet sayısı — okunmamış (dismissed_at is null) sinyal adedi.
  /// Sabit 1 göndermek Apple'ın beklentisine aykırı: rozet okunmamış öğe
  /// sayısını yansıtmalı, yoksa 5 bildirim gelse de "1" görünür.
  badge: number;
}) {
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify({
        message: {
          token,
          // GERÇEK notification payload — uygulama kapalıyken de gösterilir.
          notification: { title, body },
          data: { type: 'signal_alert', asset_id: assetId },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'signal_channel',
              sound: 'default',
              // Marka görünümü. `icon` res adıdır (uzantısız) ve beyaz siluet
              // + şeffaf zemin olmalı; Android yalnızca alfa kanalını kullanır.
              icon: 'ic_stat_sandik',
              color: '#F5A623',
            },
          },
          apns: {
            headers: { 'apns-priority': '10', 'apns-push-type': 'alert' },
            payload: { aps: { sound: 'default', badge } },
          },
        },
      }),
    },
  );

  const rawText = await response.text();
  if (response.ok) return { ok: true as const };
  return {
    ok: false as const,
    rawText,
    shouldDeleteToken:
      response.status === 404 ||
      rawText.includes('UNREGISTERED') ||
      rawText.includes('registration-token-not-registered'),
  };
}

// ── Veri tipleri ────────────────────────────────────────────────────────────

interface AssetRow {
  id: string;
  user_id: string;
  name: string;
  ticker: string;
  type: string;
  is_manual_price: boolean | null;
  kind: string | null;
}

interface PrefRow {
  user_id: string;
  asset_type: string;
  threshold: number;
  indicators: string[];
  neutral_push: boolean;
  signals_enabled: boolean;
  frequency?: SignalFrequency;
  notify_hours?: number[];
  window_start?: number;
  window_end?: number;
  last_notified_at?: string | null;
}

type SignalFrequency =
  | 'hourly'
  | 'every_2h'
  | 'every_3h'
  | 'twice_daily'
  | 'daily';

const DEFAULT_THRESHOLD = 70;

/// Bildirim penceresi — TR saati. Kullanıcı bunun dışına çıkamaz.
const DEFAULT_WINDOW_START = 10;
const DEFAULT_WINDOW_END = 18;
const DEFAULT_FREQUENCY: SignalFrequency = 'twice_daily';
const DEFAULT_NOTIFY_HOURS = [11, 15];

/// Periyodik sıklıklar için saat cinsinden aralık.
const PERIOD_HOURS: Partial<Record<SignalFrequency, number>> = {
  hourly: 1,
  every_2h: 2,
  every_3h: 3,
};

/// Şu anki TR saati (0-23). Sunucu UTC çalışır; TR sabit UTC+3
/// (2016'dan beri yaz saati uygulaması yok, bu yüzden ofset sabit).
function istanbulHour(now: Date): number {
  return (now.getUTCHours() + 3) % 24;
}

/// Bu tercih için ŞU AN bildirim gönderilmeli mi?
///
/// İki kural birlikte çalışır:
///   1. Şu anki TR saati kullanıcının penceresinde olmalı (varsayılan 10–18).
///   2. Sıklığa göre sıra gelmiş olmalı:
///      - periyodik (hourly/2h/3h): son gönderimden beri yeterli süre geçti mi.
///        Süre bazlı olması önemli — cron bir turu kaçırırsa bir sonrakinde
///        telafi edilir, slot bazlı olsa o gönderim tamamen kaybolurdu.
///      - twice_daily/daily: şu anki saat, seçilen saatlerden biri mi.
/// Bu sinyal için bildirim gönderilmeli mi? (de-dup kuralı)
///
/// Kural: aynı varlık için aynı sinyal art arda bildirilmez. Sabah SAT
/// verildiyse akşam yine SAT çıkarsa sessiz kalınır; NÖTR veya AL'a
/// dönerse bildirilir.
///
/// [oncekiSinyal] son PUSH EDİLEN sinyal (`signal_state`). Kullanıcının
/// sildiği bildirim geçmişinden BAĞIMSIZDIR — geçmişe bakılsaydı liste
/// temizlenince aynı sinyal yeniden gönderilirdi.
export function shouldSendSignal(
  oncekiSinyal: string | undefined,
  yeniSinyal: string,
): boolean {
  // Hiç gönderilmemişse ilk bildirim gider.
  if (oncekiSinyal === undefined) return true;
  return oncekiSinyal !== yeniSinyal;
}

export function shouldNotifyNow(
  pref: {
    frequency?: SignalFrequency;
    notify_hours?: number[];
    window_start?: number;
    window_end?: number;
    last_notified_at?: string | null;
  } | undefined,
  now: Date,
): boolean {
  const freq = pref?.frequency ?? DEFAULT_FREQUENCY;
  const wStart = pref?.window_start ?? DEFAULT_WINDOW_START;
  const wEnd = pref?.window_end ?? DEFAULT_WINDOW_END;
  const hour = istanbulHour(now);

  // Pencere dışında hiçbir koşulda bildirim yok.
  if (hour < wStart || hour > wEnd) return false;

  const periodHours = PERIOD_HOURS[freq];
  if (periodHours !== undefined) {
    const last = pref?.last_notified_at
      ? new Date(pref.last_notified_at)
      : null;
    if (last === null) return true; // hiç gönderilmemiş → ilk tur
    const gecenSaat = (now.getTime() - last.getTime()) / 3_600_000;
    // 5 dakikalık tolerans (0.0833 saat): cron tam saat başında tetiklenmeyip
    // birkaç saniye/dakika kayabilir; tolerans olmazsa "saatlik" bildirim her
    // turda bir sonraki saate ötelenirdi.
    //
    // Tolerans DAR tutulmalı: yarım saat gibi geniş bir pay, saatlik periyodu
    // fiilen yarım saatliğe çevirir (30 dk önce gönderilmişken yeniden
    // gönderilir). Bu tam olarak testin yakaladığı hataydı.
    const TOLERANS_SAAT = 5 / 60;
    return gecenSaat >= periodHours - TOLERANS_SAAT;
  }

  // twice_daily / daily → seçilen saatlerden biri mi?
  const hours = pref?.notify_hours?.length
    ? pref.notify_hours
    : DEFAULT_NOTIFY_HOURS;
  if (!hours.includes(hour)) return false;

  // Aynı saat içinde ikinci kez çalışırsa tekrar gönderme.
  const last = pref?.last_notified_at ? new Date(pref.last_notified_at) : null;
  if (last === null) return true;
  const gecenSaat = (now.getTime() - last.getTime()) / 3_600_000;
  return gecenSaat >= 1;
}

/// Sinyal üretilebilen türler. Vadeli mevduatın teknik göstergesi yoktur.
const ANALYZABLE = new Set(['hisse', 'fon', 'altin', 'doviz', 'emtia']);

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const cronSecret = Deno.env.get('ANALYZE_SIGNALS_CRON_SECRET');

    // SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY platform tarafından otomatik
    // enjekte edilir (elle girilemez — `SUPABASE_` öneki rezerve). Yoksa
    // runtime bozuk demektir, secret eksikliği değil.
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error(
        'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından '
        + 'sağlanmadı. Bunlar otomatik enjekte edilir; elle secret olarak '
        + 'eklenemez.',
      );
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error(
        'FCM secret\'ları eksik. Gerekli: FCM_PROJECT_ID, '
        + 'FCM_SERVICE_ACCOUNT_JSON. Bkz. README → "Secret\'lar".',
      );
    }

    if (cronSecret) {
      const authHeader = request.headers.get('Authorization');
      if (authHeader !== `Bearer ${cronSecret}`) {
        return jsonResponse({ error: 'Yetkisiz cron cagrisi.' }, 401);
      }
    }

    let slot = 'unknown';
    let dryRun = false;
    try {
      const body = await request.json();
      if (typeof body?.slot === 'string') slot = body.slot;
      // dry_run: push göndermeden analizi çalıştırır (deploy sonrası doğrulama).
      if (body?.dry_run === true) dryRun = true;
    } catch (_) { /* body opsiyonel */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // ── 1) Push token'ı olan kullanıcılar ───────────────────────────────────
    // Token'ı olmayan kullanıcıyı analiz etmenin anlamı yok.
    const { data: tokenRows, error: tokenError } = await admin
      .from('user_push_tokens')
      .select('token, user_id');
    if (tokenError) throw new Error(`Push tokenlari alinamadi: ${tokenError.message}`);
    if (!tokenRows || tokenRows.length === 0) {
      return jsonResponse({ ok: true, reason: 'Kayitli push token yok.', sent: 0 });
    }

    const tokensByUser = new Map<string, string[]>();
    for (const r of tokenRows) {
      const uid = r.user_id as string;
      const list = tokensByUser.get(uid) ?? [];
      list.push(r.token as string);
      tokensByUser.set(uid, list);
    }
    const userIds = [...tokensByUser.keys()];

    // ── 2) Varlıklar ────────────────────────────────────────────────────────
    const { data: assetRows, error: assetError } = await admin
      .from('assets')
      .select('id, user_id, name, ticker, type, is_manual_price, kind')
      .in('user_id', userIds);
    if (assetError) throw new Error(`Varliklar alinamadi: ${assetError.message}`);

    // Yalnızca aktif alım lot'ları; manuel fiyatlılar için geçmiş yok.
    const assets = (assetRows ?? []).filter((a: AssetRow) =>
      ANALYZABLE.has(a.type) &&
      a.is_manual_price !== true &&
      (a.kind ?? 'buy') === 'buy'
    ) as AssetRow[];

    if (assets.length === 0) {
      return jsonResponse({ ok: true, reason: 'Analiz edilecek varlik yok.', sent: 0 });
    }

    // ── 3) Tercihler ────────────────────────────────────────────────────────
    const { data: prefRows } = await admin
      .from('signal_preferences')
      .select('user_id, asset_type, threshold, indicators, neutral_push, signals_enabled, frequency, notify_hours, window_start, window_end, last_notified_at')
      .in('user_id', userIds);

    const prefKey = (u: string, t: string) => `${u}|${t}`;
    const prefs = new Map<string, PrefRow>();
    for (const p of (prefRows ?? []) as PrefRow[]) {
      prefs.set(prefKey(p.user_id, p.asset_type), p);
    }

    // ── 4) Son sinyal durumu — de-dup için TEK sorguda ─────────────────────
    //
    // Eskiden de-dup döngü İÇİNDE varlık başına ayrı sorgu yapıyordu (N+1) ve
    // kontrol tüm ağır işten SONRA geliyordu. Artık durum önceden toplu
    // okunur; hem N+1 gider hem de kontrol erkene alınabilir.
    const lastSignalOf = new Map<string, string>(); // assetId → signal
    {
      const { data: lastRows } = await admin
        .from('signal_state')
        .select('asset_id, signal')
        .in('user_id', userIds);
      for (const r of (lastRows ?? []) as { asset_id: string; signal: string }[]) {
        lastSignalOf.set(r.asset_id, r.signal);
      }
    }

    const now = new Date();
    // Sıklık/pencere yüzünden atlananlar — teşhiste "neden gönderilmedi"
    // sorusunun cevabı. Bu sayaç olmadan sessiz atlama hata gibi görünür.
    let skippedByFrequency = 0;

    // ── 4b) Bu turda gerçekten analiz edilecek varlıklar ───────────────────
    //
    // YÜK AZALTMA: sıklık/pencere yüzünden sırası gelmemiş veya bildirimi
    // kapalı varlıkların fiyat geçmişi HİÇ ÇEKİLMEZ. Önceden tüm varlıkların
    // serisi yükleniyor, sonra döngüde atlanıyordu — saatbaşı çalışan cron'da
    // bu, çoğu tur boş yere yapılan iş demekti.
    const aktifAssets = assets.filter((a) => {
      const pref = prefs.get(prefKey(a.user_id, a.type));
      if (pref && !pref.signals_enabled) return false;
      if (!dryRun && !shouldNotifyNow(pref, now)) {
        skippedByFrequency++;
        return false;
      }
      return true;
    });

    // ── 4c) Fiyat serileri — YALNIZCA aktif varlıkların sembolleri ─────────
    const symbolOf = new Map<string, string>(); // assetId → symbol
    const symbols = new Set<string>();
    for (const a of aktifAssets) {
      const sym = resolveSymbol(a.ticker ?? '', a.type);
      if (!sym) continue;
      symbolOf.set(a.id, sym);
      symbols.add(sym);
    }

    const histories = await loadPriceHistories(admin, symbols);

    // ── 5) Analiz + de-dup ──────────────────────────────────────────────────
    const accessToken = dryRun
      ? ''
      : await createAccessToken(JSON.parse(fcmServiceAccountJson) as ServiceAccount);

    let evaluated = 0;
    let passed = 0;
    let sent = 0;
    let failed = 0;
    // Sinyal değişmediği için atlananlar. Teşhiste "neden bildirim gelmedi"
    // sorusunun cevabı: hata değil, kasıtlı sessizlik.
    let skippedByDedup = 0;
    // Sıra gelen (user,type) çiftleri — gönderim sonrası last_notified_at
    // güncellenecek. Set: aynı türde birden çok varlık varsa tek yazım.
    const notifiedPrefKeys = new Set<string>();
    // Başarıyla push edilen sinyaller — döngü sonunda signal_state'e yazılır.
    const sentSignalOf = new Map<string, { userId: string; signal: string }>();
    const preview: Array<Record<string, unknown>> = [];
    // FCM'in reddettiği gönderimlerin sebebi. `failed > 0` olduğunda
    // "neden" sorusunu log'a bakmadan cevaplayabilmek için yanıta eklenir.
    const errors: string[] = [];

    // `aktifAssets`: signals_enabled ve sıklık/pencere filtresi YUKARIDA
    // uygulandı (fiyat çekiminden önce). Burada tekrar kontrol edilmez.
    for (const asset of aktifAssets) {
      const symbol = symbolOf.get(asset.id);
      if (!symbol) continue;
      const prices = histories.get(symbol);
      if (!prices || prices.length < MIN_POINTS) continue;

      const pref = prefs.get(prefKey(asset.user_id, asset.type));
      const threshold = pref?.threshold ?? DEFAULT_THRESHOLD;
      const indicators = pref?.indicators?.length
        ? pref.indicators
        : DEFAULT_INDICATORS;
      const neutralPush = pref?.neutral_push ?? false;
      const oncekiSinyal = lastSignalOf.get(asset.id);

      // Premium göstergeler sunucuda hesaplanmaz — premium durumu burada
      // güvenilir biçimde bilinmiyor. Kullanıcı premium ise uygulama içi
      // analiz zaten gösteriyor; push temel göstergelerle üretilir.
      const inds = analyze(prices, asset.type as AssetType, indicators, false);
      if (inds.length === 0) continue;

      evaluated++;
      const summary = summarize(inds);

      if (summary.signal === 'neutral' && !neutralPush) continue;
      if (summary.confidence < threshold) continue;
      passed++;

      // De-dup: aynı varlık için son PUSH EDİLEN sinyalle aynıysa gönderme.
      // Sabah SAT → akşam SAT: sessiz. NÖTR/AL'a dönerse: bildirim.
      //
      // Durum `signal_state`'ten toplu okundu (döngü içinde sorgu YOK) ve
      // ilk kontrol analizden önce yapıldı; buraya yalnızca sinyali gerçekten
      // değişmiş olanlar gelir. Bu ikinci kontrol yine de durur çünkü
      // erken kontrol yalnızca "değişme İHTİMALİ yok" durumunu eleyebiliyor.
      if (!shouldSendSignal(oncekiSinyal, summary.signal)) {
        skippedByDedup++;
        continue;
      }

      const { title, body } = buildMessage(
        asset.name,
        summary.signal,
        summary.buyCount,
        summary.sellCount,
        asset.ticker,
      );

      // dry-run: HİÇBİR yan etki bırakma.
      //
      // Önceden geçmiş kaydı bu kontrolden önce yazılıyordu; dry-run kendi
      // yazdığı satır yüzünden bir sonraki GERÇEK çağrıda de-dup'a takılıyor
      // ve push hiç gitmiyordu ("passed_threshold: 1, sent: 0"). Prova,
      // provası olduğu şeyi bozmamalı.
      if (dryRun) {
        preview.push({
          user: asset.user_id.slice(0, 8),
          asset: asset.name,
          signal: summary.signal,
          confidence: Math.round(summary.confidence),
          threshold,
          title,
        });
        sent++;
        continue;
      }

      // Geçmişe yaz (uygulama içi bildirim listesi bunu okur).
      const { error: insertError } = await admin
        .from('signal_notifications')
        .insert({
          user_id: asset.user_id,
          asset_id: asset.id,
          asset_name: asset.name,
          asset_ticker: asset.ticker,
          asset_type: asset.type,
          signal: summary.signal,
          buy_count: summary.buyCount,
          sell_count: summary.sellCount,
          confidence: summary.confidence,
        });
      if (insertError) { failed++; continue; }

      // NOT: Burada eskiden `if (summary.signal === 'neutral') continue;`
      // vardı — nötr sinyal geçmişe yazılıp push HİÇ gönderilmiyordu.
      // Ama nötr sinyal bu noktaya ancak kullanıcı "Nötr sinyalleri de
      // bildir" ayarını AÇTIYSA gelebilir (bkz. yukarıdaki `neutralPush`
      // kontrolü); açıkça bildirim isteyen kullanıcıya bildirim gitmemesi
      // ayarın verdiği sözü tutmamaktı. Belirtisi: cron çıktısında
      // "passed_threshold: 1, sent: 0, failed: 0" — hata yok, gönderim de yok.
      // İstemci tarafı (signal_provider.dart) zaten böyle bir engel koymuyor;
      // iki taraf bu değişiklikle aynı davranıyor.

      // iOS rozeti: okunmamış sinyal adedi. Yeni satır yukarıda eklendiği
      // için bu sayım onu da kapsar. Sayım başarısız olursa rozet
      // gönderilmez (0) — yanlış sayı göstermektense hiç göstermemek yeğdir.
      let unreadBadge = 0;
      try {
        const { count } = await admin
          .from('signal_notifications')
          .select('id', { count: 'exact', head: true })
          .eq('user_id', asset.user_id)
          .is('dismissed_at', null);
        unreadBadge = count ?? 0;
      } catch (_) { /* yut — rozet ikincil */ }

      for (const token of tokensByUser.get(asset.user_id) ?? []) {
        const r = await sendPush({
          accessToken,
          projectId: fcmProjectId,
          token,
          title,
          body,
          assetId: asset.id,
          badge: unreadBadge,
        });
        if (r.ok) {
          sent++;
          // Periyodik sıklık bu damgaya bakar; yazılmazsa "hiç
          // gönderilmemiş" sanılır ve her turda tekrar gönderilir.
          notifiedPrefKeys.add(prefKey(asset.user_id, asset.type));
          // De-dup durumu: yalnızca gönderim BAŞARILI olduğunda güncellenir.
          // Başarısız gönderimde yazılsaydı, kullanıcıya ulaşmamış bir sinyal
          // bir sonraki turu bloklardı.
          sentSignalOf.set(asset.id, {
            userId: asset.user_id,
            signal: summary.signal,
          });
        } else {
          failed++;
          // Sebebi kısaltarak sakla — tam FCM yanıtı uzun olabiliyor.
          if (errors.length < 5) {
            errors.push(r.rawText.slice(0, 300));
          }
          if (r.shouldDeleteToken) {
            try {
              await admin.from('user_push_tokens').delete().eq('token', token);
            } catch (_) { /* yut */ }
          }
        }
      }
    }

    // Gönderim yapılan (kullanıcı, tür) çiftleri için sıklık damgasını
    // güncelle. Tercih satırı YOKSA upsert ile oluşturulur: kullanıcı hiç
    // ayara girmemiş olabilir ve o durumda damga tutulacak yer olmazdı —
    // periyodik sıklık her turda yeniden tetiklenirdi.
    // De-dup durumunu yaz. Bu olmadan aynı sinyal her turda yeniden
    // gönderilir — istenen "sinyal değişince bildir" davranışı bozulur.
    if (!dryRun && sentSignalOf.size > 0) {
      const stamp = now.toISOString();
      for (const [assetId, v] of sentSignalOf) {
        try {
          await admin.rpc('touch_signal_state', {
            p_user_id: v.userId,
            p_asset_id: assetId,
            p_signal: v.signal,
            p_at: stamp,
          });
        } catch (_) { /* yut — bir sonraki turda telafi edilir */ }
      }
    }

    if (!dryRun && notifiedPrefKeys.size > 0) {
      const stamp = now.toISOString();
      for (const k of notifiedPrefKeys) {
        const [user_id, asset_type] = k.split('|');
        try {
          // RPC kullanılır çünkü düz upsert, var olan satırın
          // threshold/indicators alanlarını varsayılana döndürürdü.
          await admin.rpc('touch_signal_notified', {
            p_user_id: user_id,
            p_asset_type: asset_type,
            p_at: stamp,
          });
        } catch (_) { /* yut — bir sonraki turda telafi edilir */ }
      }
    }

    return jsonResponse({
      ok: true,
      slot,
      dry_run: dryRun,
      tr_hour: istanbulHour(now),
      skipped_by_frequency: skippedByFrequency,
      skipped_by_dedup: skippedByDedup,
      users: userIds.length,
      assets: assets.length,
      symbols: symbols.size,
      histories: histories.size,
      evaluated,
      passed_threshold: passed,
      sent,
      failed,
      ...(errors.length > 0 ? { errors } : {}),
      ...(dryRun ? { preview } : {}),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
