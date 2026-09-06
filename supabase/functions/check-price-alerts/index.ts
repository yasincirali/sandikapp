// Check Price Alerts — kullanıcının kendi kurduğu fiyat alarmları.
//
// pg_cron ile TR 08:00–21:30 arası yarım saatte bir tetiklenir.
//
// Bu, kullanıcının KENDİSİNİN istediği tek bildirim: alaka garantili,
// opt-out riski taşımıyor. Sunucuda değerlendirilir ki uygulama kapalıyken
// de çalışsın — yalnızca açıkken çalışan bir alarm geri getirme kanalı
// değildir, sadece bir ekran öğesidir.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import {
  createAccessToken,
  sendFcmNotification,
  ServiceAccount,
} from '../_shared/fcm.ts';
import { fetchLivePrices } from '../_shared/live_prices.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

/// Ayrı kanal: kullanıcı alarmları açık tutup brifingi kapatabilmeli.
const CHANNEL_ID = 'alert_channel';

type AlertRow = {
  id: string;
  user_id: string;
  symbol: string;
  label: string;
  target_price: number;
  direction: string;
};

type TokenRow = {
  token: string;
  user_id: string;
  device_id: string | null;
  platform: string | null;
  updated_at: string | null;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Alarm tetiklendi mi?
///
/// Sınır DAHİLDİR: kullanıcı "5.400 olunca" der, "5.400'ü geçince" demez.
/// Tam eşitlikte tetiklememek, hedefine ulaşmış bir alarmın sessiz kalması
/// demek olurdu.
export function isTriggered(
  price: number,
  target: number,
  direction: string,
): boolean {
  if (!Number.isFinite(price) || price <= 0) return false;
  return direction === 'above' ? price >= target : price <= target;
}

/// Türkçe para biçimi: 5412.37 → "5.412,37"
///
/// `Intl` Deno'da mevcut ama `tr-TR` verisi çalışma zamanına göre eksik
/// olabiliyor; bildirim metni sessizce "5,412.37" olarak çıkarsa kullanıcı
/// rakamı yanlış okur. Elle biçimlendirmek bu belirsizliği kaldırır.
export function formatTRY(value: number): string {
  const [tam, kesir] = Math.abs(value).toFixed(2).split('.');
  const binlik = tam.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  const isaret = value < 0 ? '-' : '';
  return `${isaret}${binlik},${kesir}`;
}

export function buildAlertMessage(
  label: string,
  price: number,
  target: number,
  direction: string,
): { title: string; body: string } {
  const yukari = direction === 'above';
  return {
    title: `${yukari ? '▲' : '▼'} ${label} ${formatTRY(target)} ` +
      `${yukari ? 'seviyesine ulaştı' : 'seviyesinin altına indi'}`,
    body: `Şu anki fiyat ${formatTRY(price)}. Kurduğun alarm çalıştı. ` +
      'Yatırım tavsiyesi değildir.',
  };
}

/// Cihaz başına tek token (bkz. daily-brief/index.ts — aynı gerekçe).
export function collapseTokens(rows: TokenRow[]): TokenRow[] {
  const enTaze = new Map<string, TokenRow>();
  for (const row of rows) {
    const anahtar =
      `${row.user_id}|${row.device_id ?? `platform:${row.platform ?? '?'}`}`;
    const mevcut = enTaze.get(anahtar);
    if (
      !mevcut ||
      Date.parse(row.updated_at ?? '') > Date.parse(mevcut.updated_at ?? '')
    ) {
      enTaze.set(anahtar, row);
    }
  }
  return [...enTaze.values()];
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const cronSecret = Deno.env.get('PRICE_ALERTS_CRON_SECRET');

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY yok.');
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error('FCM secret\'ları eksik.');
    }
    if (cronSecret) {
      const authHeader = request.headers.get('Authorization');
      if (authHeader !== `Bearer ${cronSecret}`) {
        return jsonResponse({ error: 'Yetkisiz cron cagrisi.' }, 401);
      }
    }

    let dryRun = false;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
    } catch (_) { /* gövde opsiyonel */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // ── 1) Aktif alarmlar ───────────────────────────────────────────────────
    const { data: alertRows, error: alertError } = await admin
      .from('price_alerts')
      .select('id, user_id, symbol, label, target_price, direction')
      .eq('enabled', true)
      .is('triggered_at', null);
    if (alertError) throw new Error(`Alarmlar alinamadi: ${alertError.message}`);

    const alerts = (alertRows ?? []) as AlertRow[];
    if (alerts.length === 0) {
      return jsonResponse({ ok: true, reason: 'Aktif alarm yok.', sent: 0 });
    }

    // ── 2) Fiyatlar ─────────────────────────────────────────────────────────
    // Sembol başına TEK çekim: 500 kullanıcı aynı gram altın alarmını
    // kurmuşsa da tek istek gider.
    const semboller = new Set(alerts.map((a) => a.symbol));
    const fiyatlar = await fetchLivePrices(semboller);
    if (fiyatlar.size === 0) {
      return jsonResponse({ ok: true, reason: 'Fiyat alinamadi.', sent: 0 });
    }

    const tetiklenen = alerts.filter((a) => {
      const p = fiyatlar.get(a.symbol);
      // Fiyatı alınamayan sembol DEĞERLENDİRİLMEZ: yanlış tetiklemektense
      // bir tur beklemek doğru.
      return p !== undefined && isTriggered(p, Number(a.target_price), a.direction);
    });
    if (tetiklenen.length === 0) {
      return jsonResponse({
        ok: true,
        checked: alerts.length,
        priced: fiyatlar.size,
        sent: 0,
      });
    }

    // ── 3) Token'lar ────────────────────────────────────────────────────────
    const userIds = [...new Set(tetiklenen.map((a) => a.user_id))];
    const { data: tokenRows } = await admin
      .from('user_push_tokens')
      .select('token, user_id, device_id, platform, updated_at')
      .in('user_id', userIds);
    const tokens = collapseTokens((tokenRows ?? []) as TokenRow[]);

    const tokensByUser = new Map<string, TokenRow[]>();
    for (const t of tokens) {
      const liste = tokensByUser.get(t.user_id);
      if (liste) {
        liste.push(t);
      } else {
        tokensByUser.set(t.user_id, [t]);
      }
    }

    const accessToken = dryRun
      ? ''
      : await createAccessToken(
        JSON.parse(fcmServiceAccountJson) as ServiceAccount,
      );

    let sent = 0;
    const failures: string[] = [];

    for (const alarm of tetiklenen) {
      const fiyat = fiyatlar.get(alarm.symbol)!;
      const mesaj = buildAlertMessage(
        alarm.label,
        fiyat,
        Number(alarm.target_price),
        alarm.direction,
      );

      if (dryRun) {
        sent += 1;
        continue;
      }

      // Alarm ÖNCE söndürülür, sonra bildirim gider.
      //
      // Sıra kasıtlı: push başarısız olup damga atılmazsa alarm bir sonraki
      // turda yeniden denenir (istenen davranış). Ters sırada, push gidip
      // damga yazılamazsa kullanıcı yarım saatte bir aynı bildirimi alırdı —
      // geri alınamaz olan bu.
      const { error: damgaHatasi } = await admin
        .from('price_alerts')
        .update({ triggered_at: new Date().toISOString(), enabled: false })
        .eq('id', alarm.id)
        .is('triggered_at', null); // yarış koruması: iki tur çakışırsa biri boşa düşer
      if (damgaHatasi) {
        failures.push(`damga: ${damgaHatasi.message}`);
        continue;
      }

      for (const t of tokensByUser.get(alarm.user_id) ?? []) {
        const r = await sendFcmNotification({
          accessToken,
          projectId: fcmProjectId,
          token: t.token,
          title: mesaj.title,
          body: mesaj.body,
          channelId: CHANNEL_ID,
          data: { type: 'price_alert', alert_id: alarm.id, symbol: alarm.symbol },
        });
        if (r.ok) {
          sent += 1;
        } else {
          failures.push(r.rawText.slice(0, 200));
          if (r.shouldDeleteToken) {
            await admin.from('user_push_tokens').delete().eq('token', t.token);
          }
        }
      }
    }

    return jsonResponse({
      ok: true,
      checked: alerts.length,
      priced: fiyatlar.size,
      triggered: tetiklenen.length,
      sent,
      dry_run: dryRun,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
