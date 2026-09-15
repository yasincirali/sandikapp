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
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { collapseTokens, TokenRow } from '../_shared/push_tokens.ts';

// Testler bu modülden okuyor; kaynağı `_shared/push_tokens.ts`.
export { collapseTokens };
import { sessizKullanicilar } from '../_shared/quiet_hours.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya (2026-09 L4);
  // Allow-Origin '*' bilinçli olarak yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
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
    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'PRICE_ALERTS_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

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
    let skippedQuietHours = 0;
    const failures: string[] = [];

    // Sessiz saatler (0057): alarm ATLANIR ama damgalanmaz — pencere bitince
    // koşul sürüyorsa bir sonraki turda gider. Kuru koşuda da uygulanır ki
    // rapor gerçek davranışı göstersin.
    const sessiz = await sessizKullanicilar(admin, userIds);

    for (const alarm of tetiklenen) {
      if (sessiz.has(alarm.user_id)) { skippedQuietHours += 1; continue; }
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

      // Uygulama içi bildirim listesi kaydı (0065).
      //
      // Token döngüsünden ÖNCE ve push'un sonucundan BAĞIMSIZ yazılır:
      // kullanıcı push'u kaçırsa da (bildirim izni kapalı, token bayat,
      // cihaz kapalı) alarmın çalıştığını uygulamada görebilmeli. Push'a
      // bağlasaydık "alarm kurmuştum, çalıştı mı?" sorusu yine cevapsız
      // kalırdı — bu tablonun var olma sebebi tam olarak o.
      //
      // Hata YUTULUR: liste kaydı yazılamadı diye bildirimi göndermemek
      // daha kötü olurdu. Alarm zaten damgalandı, geri dönüşü yok.
      const { error: kayitHatasi } = await admin
        .from('price_alert_notifications')
        .insert({
          user_id: alarm.user_id,
          alert_id: alarm.id,
          symbol: alarm.symbol,
          label: alarm.label,
          target_price: alarm.target_price,
          triggered_price: fiyat,
          direction: alarm.direction,
        });
      if (kayitHatasi) failures.push(`liste: ${kayitHatasi.message}`);

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
      skipped_quiet_hours: skippedQuietHours,
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
