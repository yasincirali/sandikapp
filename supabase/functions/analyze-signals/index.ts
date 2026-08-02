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

function buildMessage(
  assetName: string,
  signal: SignalType,
  buyCount: number,
  sellCount: number,
): { title: string; body: string } {
  const isBuy = signal === 'buy';
  const total = buyCount + sellCount;
  return {
    title: isBuy ? `Yukarı trend: ${assetName}` : `Aşağı trend: ${assetName}`,
    body: isBuy
      ? `Göstergelerin çoğunluğu yukarı yönlü (${buyCount}/${total}). Yatırım tavsiyesi değildir.`
      : `Göstergelerin çoğunluğu aşağı yönlü (${sellCount}/${total}). Yatırım tavsiyesi değildir.`,
  };
}

async function sendPush({
  accessToken,
  projectId,
  token,
  title,
  body,
  assetId,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  title: string;
  body: string;
  assetId: string;
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
            payload: { aps: { sound: 'default', badge: 1 } },
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
}

const DEFAULT_THRESHOLD = 70;

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
      .select('user_id, asset_type, threshold, indicators, neutral_push')
      .in('user_id', userIds);

    const prefKey = (u: string, t: string) => `${u}|${t}`;
    const prefs = new Map<string, PrefRow>();
    for (const p of (prefRows ?? []) as PrefRow[]) {
      prefs.set(prefKey(p.user_id, p.asset_type), p);
    }

    // ── 4) Fiyat serileri — sembol başına TEK çekim ─────────────────────────
    const symbolOf = new Map<string, string>(); // assetId → symbol
    const symbols = new Set<string>();
    for (const a of assets) {
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
    const preview: Array<Record<string, unknown>> = [];
    // FCM'in reddettiği gönderimlerin sebebi. `failed > 0` olduğunda
    // "neden" sorusunu log'a bakmadan cevaplayabilmek için yanıta eklenir.
    const errors: string[] = [];

    for (const asset of assets) {
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

      // De-dup: aynı varlık için son sinyalle aynıysa tekrar gönderme.
      const { data: lastRows } = await admin
        .from('signal_notifications')
        .select('signal')
        .eq('user_id', asset.user_id)
        .eq('asset_id', asset.id)
        .order('sent_at', { ascending: false })
        .limit(1);

      if (lastRows?.[0]?.signal === summary.signal) continue;

      const { title, body } = buildMessage(
        asset.name,
        summary.signal,
        summary.buyCount,
        summary.sellCount,
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

      if (summary.signal === 'neutral') continue; // kayda geçer, push gitmez

      for (const token of tokensByUser.get(asset.user_id) ?? []) {
        const r = await sendPush({
          accessToken,
          projectId: fcmProjectId,
          token,
          title,
          body,
          assetId: asset.id,
        });
        if (r.ok) {
          sent++;
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

    return jsonResponse({
      ok: true,
      slot,
      dry_run: dryRun,
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
