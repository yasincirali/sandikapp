// Calendar Nudge — ulusal dikkat anlarına bağlı bildirim.
//
// ── Neden bu, uydurma bir hatırlatmadan farklı ──────────────────────────────
// "sandık'ı açmayı unutma" tipi bildirimin taşıdığı bilgi yoktur ve
// kullanıcı üç tekrarda kapatır. Buradaki tetikleyici ise ülkenin ZATEN
// baktığı bir an: TÜİK her ayın 3'ünde saat 10:00'da enflasyonu açıklıyor ve
// o sabah Türkiye'de milyonlarca kişi zaten "ne kadar oldu?" diye bakıyor.
// Bildirim o merakı karşılıyor, üretmiyor.
//
// ── Kişiselleştirme neden burada değil ──────────────────────────────────────
// Bildirim ULUSAL rakamı taşır ("Enflasyon %X"), kullanıcının kendi reel
// getirisini değil. Kişiye özel hesap sunucuda yok (portföy getirisini
// çıkarmak için canlı kur ve tüm geçmiş gerekir) ve uydurulmuş bir sayı
// göndermektense kullanıcıyı uygulamadaki gerçek hesaba çağırmak doğru.
// Reel getiri rozeti onu açtığında zaten karşılıyor.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import {
  createAccessToken,
  sendFcmNotification,
  ServiceAccount,
} from '../_shared/fcm.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

/// Brifingle AYNI kanal: ikisi de "bilgilendirici, acil değil" sınıfında ve
/// kullanıcı ayrı ayrı kapatmak istemez. Kanal enflasyonu, kapatma kararını
/// zorlaştırmaktan başka işe yaramaz.
const CHANNEL_ID = 'brief_channel';

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

/// Yüzdeyi Türkçe biçimde yazar: 2.487 → "2,49"
export function formatPct(v: number): string {
  return v.toFixed(2).replace('.', ',');
}

/// Son iki endeks değerinden AYLIK enflasyon.
export function monthlyInflation(
  onceki: number,
  son: number,
): number | null {
  if (!Number.isFinite(onceki) || !Number.isFinite(son) || onceki <= 0) {
    return null;
  }
  return (son / onceki - 1) * 100;
}

/// Yıllık enflasyon: 12 ay önceki endekse göre.
export function annualInflation(
  onOnceki: number,
  son: number,
): number | null {
  if (!Number.isFinite(onOnceki) || !Number.isFinite(son) || onOnceki <= 0) {
    return null;
  }
  return (son / onOnceki - 1) * 100;
}

export function buildInflationMessage(
  aylik: number | null,
  yillik: number | null,
): { title: string; body: string } {
  const parcalar: string[] = [];
  if (aylik !== null) parcalar.push(`aylık %${formatPct(aylik)}`);
  if (yillik !== null) parcalar.push(`yıllık %${formatPct(yillik)}`);
  return {
    title: `Enflasyon açıklandı: ${parcalar.join(' · ')}`,
    body: 'Portföyünün enflasyonun önünde mi olduğunu görmek için sandık\'ı aç.',
  };
}

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
    const cronSecret = Deno.env.get('CALENDAR_NUDGE_CRON_SECRET');

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

    // ── Endeks ──────────────────────────────────────────────────────────────
    // Son 13 ay: aylık için son iki, yıllık için 12 ay öncesi gerekiyor.
    const { data: idxRows } = await admin
      .from('inflation_index')
      .select('period, tufe_index')
      .order('period', { ascending: false })
      .limit(13);

    const seri = (idxRows ?? []) as Array<{ period: string; tufe_index: number }>;
    if (seri.length < 2) {
      // Tablo boş ya da tek satır — bildirim GÖNDERİLMEZ.
      //
      // Bu, özelliğin sessizce kapalı kalması demek ve doğrusu bu: TÜFE
      // verisi olmadan gönderilecek bir bildirim ya boş ya uydurma olurdu.
      return jsonResponse({
        ok: true,
        reason: 'Yeterli TUFE verisi yok — bildirim gonderilmedi.',
        sent: 0,
      });
    }

    // ── Bu ay YENİ mi açıklandı? ────────────────────────────────────────────
    //
    // Cron her ayın 3'ünde koşuyor ama veri o gün girilmemiş olabilir (endeks
    // elle dolduruluyor). En son satır BİR ÖNCEKİ aya aitse yeni açıklama
    // henüz yok demektir; eski rakamı "açıklandı" diye göndermek yanlış olur.
    const sonPeriod = seri[0].period.slice(0, 7); // 'YYYY-MM'
    const simdi = new Date();
    const gecenAy = new Date(Date.UTC(
      simdi.getUTCFullYear(),
      simdi.getUTCMonth() - 1,
      1,
    ));
    const beklenen = `${gecenAy.getUTCFullYear()}-` +
      `${(gecenAy.getUTCMonth() + 1).toString().padStart(2, '0')}`;
    if (sonPeriod !== beklenen) {
      return jsonResponse({
        ok: true,
        reason: `Beklenen ay ${beklenen}, tabloda ${sonPeriod} — veri girilmemis.`,
        sent: 0,
      });
    }

    const aylik = monthlyInflation(
      Number(seri[1].tufe_index),
      Number(seri[0].tufe_index),
    );
    const yillik = seri.length >= 13
      ? annualInflation(Number(seri[12].tufe_index), Number(seri[0].tufe_index))
      : null;
    if (aylik === null && yillik === null) {
      return jsonResponse({ ok: true, reason: 'Hesap yapilamadi.', sent: 0 });
    }

    const mesaj = buildInflationMessage(aylik, yillik);

    // ── Gönderim ────────────────────────────────────────────────────────────
    const { data: tokenRows } = await admin
      .from('user_push_tokens')
      .select('token, user_id, device_id, platform, updated_at');
    const tokens = collapseTokens((tokenRows ?? []) as TokenRow[]);
    if (tokens.length === 0) {
      return jsonResponse({ ok: true, reason: 'Token yok.', sent: 0 });
    }

    if (dryRun) {
      return jsonResponse({
        ok: true,
        dry_run: true,
        would_send: tokens.length,
        title: mesaj.title,
      });
    }

    const accessToken = await createAccessToken(
      JSON.parse(fcmServiceAccountJson) as ServiceAccount,
    );

    let sent = 0;
    const failures: string[] = [];
    for (const t of tokens) {
      const r = await sendFcmNotification({
        accessToken,
        projectId: fcmProjectId,
        token: t.token,
        title: mesaj.title,
        body: mesaj.body,
        channelId: CHANNEL_ID,
        data: { type: 'calendar_nudge', occasion: 'inflation_day' },
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

    return jsonResponse({ ok: true, sent, failures: failures.slice(0, 5) });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
