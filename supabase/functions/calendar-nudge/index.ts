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

/// Brifingle AYNI kanal: ikisi de "bilgilendirici, acil değil" sınıfında ve
/// kullanıcı ayrı ayrı kapatmak istemez. Kanal enflasyonu, kapatma kararını
/// zorlaştırmaktan başka işe yaramaz.
const CHANNEL_ID = 'brief_channel';

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

/// Bir seriden, [sonPeriod]'dan tam [ayGeri] ay önceki satırın endeksini
/// bulur. Yoksa `null`.
///
/// **Neden dizi indeksi KULLANILMAZ (2026-09-16).** Eskiden `seri[12]` "12
/// ay öncesi", `seri[1]` de "bir önceki ay" varsayılıyordu. `limit(13)`
/// SATIR sayısıdır, tarih değil: seride bir ay eksikse (ki bu projede bir
/// kez yaşandı — TÜİK Ocak 2026'da baz yılını değiştirdi ve eski seri orada
/// bitti) `seri[12]` 13 ay öncesi olur ve push bildirimi YANLIŞ bir yıllık
/// TÜFE gönderir. Uygulama tarafındaki hesaplar tarih anahtarıyla çalışıyor
/// (`InflationService.changePct`); burası tek istisnaydı.
///
/// Bildirim geri alınamaz: yanlış rakam telefonlara gider ve kullanıcı onu
/// TÜİK'in açıkladığıyla karşılaştırır. Eksik ay varsa hesap yapılmaması,
/// yanlış hesaptan iyidir.
export function endeksAyGeri(
  seri: Array<{ period: string; tufe_index: number }>,
  sonPeriod: string,
  ayGeri: number,
): number | null {
  const [yil, ay] = sonPeriod.split('-').map(Number);
  if (!Number.isFinite(yil) || !Number.isFinite(ay)) return null;
  // Date.UTC ay taşmasını kendisi çevirir (ay 0 → önceki yılın Aralık'ı).
  const hedef = new Date(Date.UTC(yil, ay - 1 - ayGeri, 1));
  const anahtar = `${hedef.getUTCFullYear()}-` +
    `${(hedef.getUTCMonth() + 1).toString().padStart(2, '0')}`;
  const satir = seri.find((r) => r.period.slice(0, 7) === anahtar);
  if (!satir) return null;
  const v = Number(satir.tufe_index);
  return Number.isFinite(v) && v > 0 ? v : null;
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
    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'CALENDAR_NUDGE_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

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

    // Uçlar TARİHTEN seçilir, dizi indeksinden değil ([endeksAyGeri]).
    const son = Number(seri[0].tufe_index);
    const oncekiAy = endeksAyGeri(seri, sonPeriod, 1);
    const onIkiAyOnce = endeksAyGeri(seri, sonPeriod, 12);
    const aylik = oncekiAy === null ? null : monthlyInflation(oncekiAy, son);
    const yillik = onIkiAyOnce === null
      ? null
      : annualInflation(onIkiAyOnce, son);
    if (aylik === null && yillik === null) {
      return jsonResponse({ ok: true, reason: 'Hesap yapilamadi.', sent: 0 });
    }

    const mesaj = buildInflationMessage(aylik, yillik);

    // ── Bu ay ZATEN gönderildi mi? ──────────────────────────────────────────
    //
    // Gönderim defteri (`0053_fetch_inflation.sql`). Kanca artık İKİ gün
    // koşuyor — ayın 3'ü ve 4'ü — çünkü TÜFE verisi bir gün geç
    // yayımlanabiliyor ve `0048`'de o ayın kancası tamamen kaçıyordu.
    //
    // İkinci tur ancak defter varsa güvenli: veri 3'ünde zamanında
    // girildiyse 4'ündeki tur burada durur. Defter OLMADAN ikinci turu
    // açmak, `0048`'in onu kapatma sebebinin aynısını geri getirir
    // (çift bildirim).
    //
    // Anahtar GÖNDERİM GÜNÜ değil, endeksin AİT OLDUĞU ay: 3'ünde ve
    // 4'ünde koşan iki tur aynı ayı anlatıyor.
    const donem = `${sonPeriod}-01`;
    const { data: defterRows } = await admin
      .from('calendar_nudge_log')
      .select('period')
      .eq('occasion', 'inflation_day')
      .eq('period', donem)
      .limit(1);
    if ((defterRows ?? []).length > 0) {
      return jsonResponse({
        ok: true,
        reason: `${sonPeriod} kancasi zaten gonderildi.`,
        sent: 0,
      });
    }

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
    let skippedQuietHours = 0;
    const failures: string[] = [];
    // Sessiz saatler (0057): takvim hatırlatması zamana bağlı değil, atlanır.
    const sessiz = await sessizKullanicilar(admin, tokens.map((t) => t.user_id));
    for (const t of tokens) {
      if (sessiz.has(t.user_id)) { skippedQuietHours += 1; continue; }
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

    // Defter YAZIMI — ikinci turun duracağı yer.
    //
    // Yalnızca gerçekten bir şey gönderildiyse yazılır: hepsi başarısız
    // olduysa ayın 4'ündeki tur yeniden denemeli.
    //
    // Hata YUTULUR: yazamazsak en kötü ihtimalle 4'ünde ikinci bildirim
    // gider. `daily_brief_log` ile aynı denge — bildirimi hiç
    // göndermemekten iyidir.
    if (sent > 0) {
      try {
        await admin
          .from('calendar_nudge_log')
          .upsert(
            { occasion: 'inflation_day', period: donem },
            { onConflict: 'occasion,period' },
          );
      } catch (_) { /* bkz. yukarıdaki not */ }
    }

    return jsonResponse({
      ok: true,
      sent,
      skipped_quiet_hours: skippedQuietHours,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
