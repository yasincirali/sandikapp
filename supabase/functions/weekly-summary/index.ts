// Weekly Summary Edge Function — HAFTALIK ÖZET
//
// pg_cron ile PAZARTESİ TR 09:45'te tetiklenir ve o günün sabah
// brifinginin YERİNE gider (bkz. migration 0052: `daily-brief` cron'u
// `1-5` → `2-5` daraltıldı). Yeni bir bildirim slotu AÇILMAZ —
// RETENTION_STRATEJISI.md §7 haftalık tavanı 5 bildirim ve günde tek
// proaktif mesaj diyor.
//
// ── Neden Pazartesi ─────────────────────────────────────────────────────────
// Haftalık özet GEÇEN haftayı anlatır. Perşembe gönderilen bir "haftalık"
// özet, kapanmamış bir haftayı özetler (MONETIZATION_ROADMAP.md §3.4'ün ilk
// hâli Perşembe diyordu; 2026-09-13'te bu gerekçeyle revize edildi).
//
// ── ⚠️ EN ÖNEMLİ KISIT: katkı varsa GÖNDERİLMEZ ─────────────────────────────
// `snapshots.data` BRÜT piyasa değeri tutuyor: `{AssetType.name: TRY}`.
// Para giriş/çıkışı ayıklanmamıştır. Hafta içinde ₺50.000 ekleyen
// kullanıcının uçtan uca farkı "+%30" çıkar ve bu bir KAZANÇ DEĞİLDİR.
//
// Uygulamadaki Özet sekmesi tam olarak bu ayrımı görünür kılmak için var
// (`PeriodSummaryService`: katkiTRY / piyasaTRY / getiriPct). Sunucuda aynı
// ayrımı YAPAMAYIZ çünkü canlı kur burada yok — `assets.purchase_fx_rate`
// alış anının kurudur ve döviz/altın lot'larının bugünkü TRY karşılığı
// çıkarılamaz (bkz. `daily-brief` başlığındaki aynı gerekçe).
//
// Seçim (kullanıcı kararı, 2026-09-13): **hafta içinde net akış varsa push
// hiç gönderilmez** (`skipped_flow`). Akış sorusu TRY'ye çevirme
// GEREKTİRMEZ — "bu hafta alım/satım satırı var mı" sorusu `assets`
// tablosundan doğrudan yanıtlanıyor. Böylece gönderilen her rakam dürüst
// oluyor; şüpheli olan hafta sessiz kalıyor.
//
// Yanlış bir yüzde, hiç bildirim göndermemekten kötüdür: kullanıcı sayıyı
// uygulamadaki Özet sekmesiyle karşılaştırır, iki rakam çelişir ve
// uygulamaya olan güvenini kaybeder.
//
// ── Neden `snapshots` (kur itirazı burada GEÇERSİZ) ─────────────────────────
// `daily-brief` portföy yüzdesi hesaplamayı reddediyor çünkü `assets` +
// `price_history_cache` üzerinden TRY'ye çevirmek gerekir. Bu fonksiyon
// farklı bir kaynaktan okuyor: `snapshots` satırları İSTEMCİDE, canlı
// `state.toTRY` ile TRY'ye çevrilmiş halde yazılıyor
// (`portfolio_provider._saveSnapshot`). Snapshot-to-snapshot oranı bu
// yüzden meşru bir TRY/TRY karşılaştırmasıdır.
//
// ── Kapsama boşluğu ─────────────────────────────────────────────────────────
// `snapshots` cron'la değil, kullanıcı uygulamayı her açtığında yazılıyor.
// Pazartesi açmayan kullanıcıda "hafta başı" sessizce Çarşamba'ya kayar ve
// yüzde eksik bir pencereyi anlatır. Bu yüzden iki uç için TAZELIK penceresi
// şart: dönem başı ilk 48 saatte, dönem sonu son 48 saatte bir snapshot
// olmalı. Yoksa `skipped_coverage` ile atlanır.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { requireCronSecret } from '../_shared/cron_auth.ts';

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

/// Android bildirim kanalı — istemcide aynı kimlikle kayıtlı olmalı
/// (`NotificationService._createAndroidChannels`).
///
/// Brifingden AYRI kanal: kullanıcı haftalık özeti kapatıp sabah brifingini
/// açık tutabilmeli. Tek kanal, tek "kapat" düğmesi demek olurdu ve
/// rahatsız olan kullanıcı ikisini birden kaybederdi.
const CHANNEL_ID = 'summary_channel';

/// Bu eşiğin altındaki hareket bildirime değmez.
///
/// Haftalık pencerede günlük eşikten (%1,5) yüksek tutuluyor: bir haftada
/// %1,5 hareket gürültüdür ve haftalık bir bildirimin bütçesini hiçbir şey
/// söylemeden harcar.
const DEFAULT_MIN_MOVE_PCT = 2.0;

/// Dönem uçlarının TAZELİK penceresi (saat).
///
/// Snapshot kullanıcı uygulamayı açtığında yazılıyor; uçlar pencerenin
/// kenarlarına yakın olmazsa yüzde başka bir dönemi anlatır.
const UC_TAZELIK_SAAT = 48;

type TokenRow = {
  token: string;
  user_id: string;
  device_id: string | null;
  platform: string | null;
  updated_at: string | null;
};

type SnapshotRow = {
  user_id: string;
  ts: string;
  data: Record<string, unknown> | null;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

/// Bir snapshot'ın toplam TRY değeri.
///
/// `RecapService.snapshotTotal` ile AYNI kural: tüm kategorilerin toplamı.
/// Sayı olmayan değerler atlanır — eski snapshot'larda string olabiliyor
/// (bkz. `SupabaseService.fetchSnapshots` içindeki aynı savunma).
export function snapshotTotal(data: Record<string, unknown> | null): number {
  if (!data) return 0;
  let toplam = 0;
  for (const v of Object.values(data)) {
    const n = typeof v === 'number' ? v : Number(v);
    if (Number.isFinite(n) && n > 0) toplam += n;
  }
  return toplam;
}

/// Dönem yüzdesi — iki uçtan.
///
/// Uçlardan biri yok ya da dönem başı sıfırsa `null`: uydurma bir yüzde
/// üretilmez (sıfıra bölme de olmaz).
export function periodChangePct(
  basTotal: number,
  sonTotal: number,
): number | null {
  if (!Number.isFinite(basTotal) || !Number.isFinite(sonTotal)) return null;
  if (basTotal <= 0) return null;
  return (sonTotal / basTotal - 1) * 100;
}

/// Dönem uçlarını seçer ve TAZELİK denetimi yapar.
///
/// [rows] tek kullanıcının snapshot'ları (sıra önemsiz).
/// Dönüş `null` ise yüzde hesaplanmaz — sebebi [reason] ile ayrılır ki
/// yanıt gövdesinde hangi kapının kapandığı görünsün.
export function pickEndpoints(
  rows: SnapshotRow[],
  fromMs: number,
  toMs: number,
): { bas: number; son: number } | { reason: 'coverage' | 'empty' } {
  if (rows.length === 0) return { reason: 'empty' };

  const sirali = [...rows]
    .map((r) => ({ ts: Date.parse(r.ts), total: snapshotTotal(r.data) }))
    .filter((r) => Number.isFinite(r.ts) && r.total > 0 && r.ts >= fromMs && r.ts <= toMs)
    .sort((a, b) => a.ts - b.ts);

  if (sirali.length < 2) return { reason: 'empty' };

  const ilk = sirali[0];
  const son = sirali[sirali.length - 1];

  // Uçlar pencerenin KENARLARINA yakın olmalı. Aksi halde "haftalık"
  // yüzde aslında iki günlük bir farkı anlatır ve kullanıcı bunu
  // uygulamadaki Özet sekmesiyle karşılaştırdığında çelişki görür.
  const tazelikMs = UC_TAZELIK_SAAT * 60 * 60 * 1000;
  if (ilk.ts - fromMs > tazelikMs) return { reason: 'coverage' };
  if (toMs - son.ts > tazelikMs) return { reason: 'coverage' };

  return { bas: ilk.total, son: son.total };
}

/// Bildirim metni.
///
/// ## Ton (RETENTION_STRATEJISI.md §8 ve §9 — pazarlıksız)
/// * Kayıp haftasında kutlama dili YOK.
/// * "Portföyün düştü!" gibi uyarı dili de YOK — kayıp anındaki bildirim
///   panik satışı tetikler. Yerine DAHA UZUN pencere bağlamı verilir.
/// * Öneri/eylem dili YOK (SPK): durum bildirilir, eylem önerilmez.
/// * Emoji yok, streak yok, "Devam et!" yok.
///
/// [uzunDonemPct] kayıp haftasında bağlam cümlesinin ikinci yarısı
/// ("Yıl hâlâ +%31,8"). Yoksa yalnızca durum bildirilir.
export function buildWeeklyMessage(
  changePct: number,
  uzunDonemPct: number | null,
): { title: string; body: string } {
  const yukari = changePct >= 0;
  const mutlak = Math.abs(changePct).toFixed(1).replace('.', ',');

  const baslik = yukari
    ? `▲ Geçen hafta piyasadan %${mutlak}`
    : `▼ Geçen hafta piyasadan −%${mutlak}`;

  // Kayıpta bağlam; kazançta sade. Kazancı uzun pencereyle "ama" diye
  // dengelemek kutlamayı azarlamaya çevirirdi.
  let govde: string;
  if (!yukari && uzunDonemPct !== null && uzunDonemPct > 0) {
    const u = uzunDonemPct.toFixed(1).replace('.', ',');
    govde = `Hafta ekside. Daha uzun pencerede hâlâ +%${u}. ` +
      'Ayrıntı için sandık\'ı aç.';
  } else {
    govde = 'Haftalık özetin sandık\'ta hazır. Yatırım tavsiyesi değildir.';
  }

  return { title: baslik, body: govde };
}

/// Cihaz başına TEK token — aynı telefona kopya push gitmesin.
///
/// `daily-brief.collapseTokens` ile aynı gerekçe: FCM token'ı rotasyona
/// girer (yeniden kurulum, veri temizleme) ve eski satırlar tabloda kalır.
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

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error(
        'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından '
        + 'sağlanmadı. Bunlar otomatik enjekte edilir.',
      );
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error(
        'FCM secret\'ları eksik: FCM_PROJECT_ID, FCM_SERVICE_ACCOUNT_JSON.',
      );
    }
    // FAIL-CLOSED: secret yoksa 503, uyusmuyorsa 401 (bkz. _shared/cron_auth.ts).
    const denied = await requireCronSecret(request, 'WEEKLY_SUMMARY_CRON_SECRET');
    if (denied) return denied;

    let dryRun = false;
    let minMovePct = DEFAULT_MIN_MOVE_PCT;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.min_move_pct === 'number') minMovePct = body.min_move_pct;
    } catch (_) { /* gövde opsiyonel */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // ── 1) Push token'ı olan kullanıcılar ───────────────────────────────────
    const { data: tokenRows, error: tokenError } = await admin
      .from('user_push_tokens')
      .select('token, user_id, device_id, platform, updated_at');
    if (tokenError) {
      throw new Error(`Push tokenlari alinamadi: ${tokenError.message}`);
    }
    const tokens = collapseTokens((tokenRows ?? []) as TokenRow[]);
    if (tokens.length === 0) {
      return jsonResponse({
        ok: true,
        reason: 'Kayitli push token yok.',
        sent: 0,
      });
    }
    const userIds = [...new Set(tokens.map((t) => t.user_id))];

    // ── 2) Bu hafta özet almış kullanıcıları ele ────────────────────────────
    //
    // Cron haftada bir koşar ama yeniden deneme / elle tetikleme olabilir.
    // `sent_on` Pazartesi tarihidir (defterin anahtarı).
    const bugun = new Date().toISOString().slice(0, 10);
    const { data: gonderilmis } = await admin
      .from('weekly_summary_log')
      .select('user_id')
      .eq('sent_on', bugun)
      .in('user_id', userIds);
    const zatenGonderildi = new Set(
      (gonderilmis ?? []).map((r: { user_id: string }) => r.user_id),
    );

    // ── 3) Kullanıcı tercihi ────────────────────────────────────────────────
    const istemeyen = new Set<string>();
    try {
      const { data: profilRows } = await admin
        .from('profiles')
        .select('id, weekly_summary_push')
        .in('id', userIds);
      for (const p of (profilRows ?? []) as Array<Record<string, unknown>>) {
        // Sütun eski kayıtlarda null olabilir; varsayılan AÇIK.
        if (p.weekly_summary_push === false) istemeyen.add(String(p.id));
      }
    } catch (_) {
      // Tercih okunamazsa varsayılan açık kabul edilir — bildirimi hiç
      // göndermemek, tercihi bilmemekten daha kötü bir varsayım olurdu.
    }

    // ── 4) Dönem penceresi ──────────────────────────────────────────────────
    const simdi = Date.now();
    const fromMs = simdi - 7 * 24 * 60 * 60 * 1000;
    const yilFromMs = simdi - 365 * 24 * 60 * 60 * 1000;

    // ── 5) HAFTA İÇİNDE AKIŞ OLAN kullanıcıları ele ─────────────────────────
    //
    // ⚠️ Bu fonksiyonun en önemli kapısı. `snapshots` brüt değer tutuyor;
    // hafta içinde alım/satım yapan kullanıcının uçtan uca farkı getiri
    // DEĞİLDİR. Sunucuda katkıyı TRY olarak ayıklayamıyoruz (canlı kur yok),
    // bu yüzden ŞÜPHELİ HAFTA SESSİZ KALIR.
    //
    // Soru TRY gerektirmiyor: "bu hafta akış satırı var mı". `kind` alanı
    // buy/sell ise akış var; temettü (`dividend`) miktara girmez ve
    // `delete_log` silme kaydıdır — ikisi de akış sayılmaz.
    const akisliKullanicilar = new Set<string>();
    try {
      const { data: akisRows } = await admin
        .from('assets')
        .select('user_id, kind')
        .in('user_id', userIds)
        .in('kind', ['buy', 'sell'])
        .is('deleted_at', null)
        .gte('added_date', new Date(fromMs).toISOString());
      for (const r of (akisRows ?? []) as Array<Record<string, unknown>>) {
        akisliKullanicilar.add(String(r.user_id));
      }
    } catch (_) {
      // Akış sorgulanamazsa HİÇ KİMSEYE göndermemek doğrusu: ayıklanmamış
      // bir yüzde göndermek, bu fonksiyonun tek kırmızı çizgisi.
      return jsonResponse({
        ok: true,
        reason: 'Akis sorgulanamadi — guvenli tarafta kalindi, gonderim yok.',
        sent: 0,
      });
    }

    // ── 6) Snapshot'lar ─────────────────────────────────────────────────────
    const { data: snapRows, error: snapError } = await admin
      .from('snapshots')
      .select('user_id, ts, data')
      .in('user_id', userIds)
      .gte('ts', new Date(yilFromMs).toISOString())
      .order('ts', { ascending: true });
    if (snapError) {
      throw new Error(`Snapshot alinamadi: ${snapError.message}`);
    }

    const kullaniciSnap = new Map<string, SnapshotRow[]>();
    for (const r of (snapRows ?? []) as SnapshotRow[]) {
      const liste = kullaniciSnap.get(r.user_id);
      if (liste) liste.push(r); else kullaniciSnap.set(r.user_id, [r]);
    }

    // ── 7) Gönderim ─────────────────────────────────────────────────────────
    const accessToken = dryRun
      ? ''
      : await createAccessToken(
        JSON.parse(fcmServiceAccountJson) as ServiceAccount,
      );

    let sent = 0;
    let skippedFlow = 0;
    let skippedCoverage = 0;
    let skippedQuiet = 0;
    let skippedOptOut = 0;
    const failures: string[] = [];

    for (const tokenRow of tokens) {
      const uid = tokenRow.user_id;
      if (zatenGonderildi.has(uid)) continue;
      if (istemeyen.has(uid)) { skippedOptOut += 1; continue; }

      // AKIŞ KAPISI — en önemlisi.
      if (akisliKullanicilar.has(uid)) { skippedFlow += 1; continue; }

      const rows = kullaniciSnap.get(uid) ?? [];
      const uclar = pickEndpoints(rows, fromMs, simdi);
      if ('reason' in uclar) {
        if (uclar.reason === 'coverage') skippedCoverage += 1;
        continue;
      }

      const degisim = periodChangePct(uclar.bas, uclar.son);
      if (degisim === null) continue;
      if (Math.abs(degisim) < minMovePct) { skippedQuiet += 1; continue; }

      // Uzun pencere bağlamı — YALNIZCA kayıp haftasında kullanılıyor.
      // Yıllık uçlar için tazelik denetimi aranmaz: bağlam cümlesi ikincil
      // ve yaklaşık olması kabul edilebilir.
      let uzunDonemPct: number | null = null;
      if (degisim < 0) {
        const yilSirali = rows
          .map((r) => ({ ts: Date.parse(r.ts), total: snapshotTotal(r.data) }))
          .filter((r) => Number.isFinite(r.ts) && r.total > 0)
          .sort((a, b) => a.ts - b.ts);
        if (yilSirali.length >= 2) {
          uzunDonemPct = periodChangePct(
            yilSirali[0].total,
            yilSirali[yilSirali.length - 1].total,
          );
        }
      }

      const mesaj = buildWeeklyMessage(degisim, uzunDonemPct);

      if (dryRun) { sent += 1; continue; }

      const r = await sendFcmNotification({
        accessToken,
        projectId: fcmProjectId,
        token: tokenRow.token,
        title: mesaj.title,
        body: mesaj.body,
        channelId: CHANNEL_ID,
        data: { type: 'weekly_summary', sent_on: bugun },
      });

      if (r.ok) {
        sent += 1;
        // Log yazılır ama hata yutulur: yazamazsak en kötü ihtimalle
        // yeniden denemede ikinci bildirim gider.
        await admin
          .from('weekly_summary_log')
          .upsert(
            { user_id: uid, sent_on: bugun },
            { onConflict: 'user_id,sent_on' },
          );
      } else {
        failures.push(r.rawText.slice(0, 200));
        if (r.shouldDeleteToken) {
          await admin
            .from('user_push_tokens')
            .delete()
            .eq('token', tokenRow.token);
        }
      }
    }

    return jsonResponse({
      ok: true,
      sent,
      skipped_flow: skippedFlow,
      skipped_coverage: skippedCoverage,
      skipped_quiet: skippedQuiet,
      skipped_opt_out: skippedOptOut,
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
