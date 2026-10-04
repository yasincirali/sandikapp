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
// ── Para akışı cümlesi (2026-10-04, `HAFTALIK_AKIS_SATIRI=1` ile açılır) ────
// Kullanıcının tuttuğu fonlarda geçen hafta büyük para girişi/çıkışı olduysa
// (`balina_olay`, 0103) özet buna değinir. Yüzde kapıları DEĞİŞMEDİ; kapıya
// takılan haftada cümle varsa yüzdesiz "Haftanın özeti" mesajı gider. Olay
// başına ayrı push açılmadı (kullanıcı kararı; bkz. `_shared/haftalik_akis.ts`).
// Bayrak kapalıyken ya da cümle yokken davranış birebir eskisidir.
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

import {
  createAccessToken,
  sendFcmNotification,
  ServiceAccount,
} from '../_shared/fcm.ts';
import {
  appNotificationRow,
  recordAppNotification,
} from '../_shared/app_notifications.ts';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { enflasyonOranlari, tufeMesaji } from '../_shared/tufe_push.ts';
import { collapseTokens, TokenRow } from '../_shared/push_tokens.ts';

// Testler bu modülden okuyor; kaynağı `_shared/push_tokens.ts`.
export { collapseTokens };
import { sessizKullanicilar } from '../_shared/quiet_hours.ts';
import { acikPozisyonLotlari, PozisyonLot } from '../_shared/positions.ts';
import { trGun } from '../_shared/tefas_nav.ts';
import {
  fonHareketleri,
  govdeyeAkisEkle,
  haftalikAkisCumlesi,
  HaftaOlayi,
  varlikKodu,
  yalnizAkisMesaji,
} from '../_shared/haftalik_akis.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya (2026-09 L4);
  // Allow-Origin '*' bilinçli olarak yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
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

// ── Aylık özet (2026-09-20) ─────────────────────────────────────────────────
//
// Aynı fonksiyon `{"period":"month"}` gövdesiyle ayın 1'inde koşar
// (migration 0067, `monthly-summary` cron'u) ve GEÇEN takvim ayını anlatır.
// Ayrı fonksiyon yazılmadı: token, tercih, sessiz saat, snapshot ve FCM
// akışı birebir aynı; yalnızca pencere, mesaj ve iki kapı farklı.
//
// Haftalıktan İKİ fark:
//   · Akış kapısı ATLANMAZ ama SUSTURMAZ: ay içinde alım/satım yapan
//     kullanıcıya yüzde gönderilmez (yanlış olurdu), "özetin hazır" gider.
//     Bir ayda hiç işlem yapmayan kullanıcı azınlık; herkesi susturmak
//     bildirimi fiilen kapatırdı. Sayısız mesaj yalan söylemez.
//   · Sessiz eşik (min_move_pct) yok: ay tek bir cümle hak eder.
//
// ── Ayın 3'ü, TÜFE ile birleşik (2026-10-01, kullanıcı kararı) ─────────────
//
// İlk hâli ayın 1'inde gidiyordu. TÜİK geçen ayın TÜFE'sini 3'ünde 10:00'da
// açıklıyor; 1'inde "Enflasyon farkı Özet'te" diyen push'a dokunan
// kullanıcı Özet'te ÖNCEKİ ayın (Ağustos) enflasyonunu buluyordu — Eylül
// özetinin altında Ağustos'un hesabı (kullanıcı bildirimi, ekran
// görüntüsüyle). Ayrıca 3'ünde iki ayrı TÜFE push'u daha vardı
// (`fetch-inflation` 10:05, `calendar-nudge` 10:15).
//
// Şimdi: cron 3'ü ve 4'ü TR 10:30 (0093), `fetch-inflation`'dan SONRA.
//   · Ayın TÜFE'si tabloda yoksa (TÜİK gecikti) HİÇBİR ŞEY gönderilmez,
//     ertesi gün yeniden denenir.
//   · Ay başına TEK koşu: `inflation_push_log(period)` kilidi — eski
//     `fetch-inflation` push'uyla AYNI defter, yani hangisi önce koşarsa
//     o ay için tek TÜFE push'u gider (sürüm sırası ne olursa olsun).
//   · Özet bildirimini kapatmış ya da bu ay özeti ZATEN almış kullanıcı
//     (geçiş: Eylül özeti 1 Ekim'de eski takvimle gitti) yalnızca TÜFE
//     mesajını alır — eski TÜFE günü push'unun birebir aynısı.
//
// Aynı gün ikinci push yok: gönderim `daily_brief_log`'a yazılır (brifing
// 09:45'te zaten gitmişse bu, günün ikinci ve son mesajıdır — eskiden de
// TÜFE push'u öyleydi).
export type Donem = 'week' | 'month';

/** Ayın TÜFE'si — aylık özete eklenir. */
export type AyTufesi = { aylikPct: number; yillikPct: number | null };

/**
 * Özetlenen ayın TÜFE oranları. Seri `period` artan sıralı; satır o aya
 * AİT olmalı — son açıklanan ay farklıysa `null` (başka ayın enflasyonu
 * bu aya YAZILMAZ; kullanıcı bildiriminin kökü buydu).
 */
export function ayinTufesi(
  satirlar: Array<{ period: string; value: number }>,
  donem: string,
): AyTufesi | null {
  const kadar = satirlar.filter((r) => r.period.slice(0, 10) <= donem);
  const o = enflasyonOranlari(kadar);
  if (!o || o.period.slice(0, 10) !== donem) return null;
  return { aylikPct: o.aylikPct, yillikPct: o.yillikPct };
}

/** Türkçe ay adları — `intl` yok; `BugunKarti`/`RecapService` ile aynı sabit. */
const AY_ADLARI = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

/**
 * GEÇEN takvim ayının penceresi, Europe/Istanbul (UTC+3, DST yok).
 *
 * `now` 1 Eylül 06:30 UTC ise → 1 Ağustos 00:00 TR … 1 Eylül 00:00 TR.
 * Ayın 1'i yerine gecikmeli koşsa da (2'si, 3'ü) yine geçen ayı verir.
 */
export function ayPenceresi(
  now: Date,
): { fromMs: number; toMs: number; ayAdi: string; donem: string } {
  const TR_OFFSET_MS = 3 * 3600_000;
  const tr = new Date(now.getTime() + TR_OFFSET_MS);
  const y = tr.getUTCFullYear();
  const m = tr.getUTCMonth(); // bu ay (0-11)
  const buAyBasi = Date.UTC(y, m, 1) - TR_OFFSET_MS;
  const gecenAyBasi = Date.UTC(y, m - 1, 1) - TR_OFFSET_MS;
  const gecenAy = ((m - 1) % 12 + 12) % 12;
  const g = new Date(Date.UTC(y, m - 1, 1));
  // `inflation_index.period` biçimi: ayın ilk günü.
  const donem = `${g.getUTCFullYear()}-${String(g.getUTCMonth() + 1).padStart(2, '0')}-01`;
  return { fromMs: gecenAyBasi, toMs: buAyBasi, ayAdi: AY_ADLARI[gecenAy], donem };
}

/**
 * Aylık mesaj. [changePct] null → ay içinde akış vardı ya da kapsama yok:
 * sayı yazılmaz, yalnızca "hazır" denir. Kurallar haftalıkla aynı
 * (uyarı tonu yok, emoji yok, tutar yok, tavsiye yok).
 */
export function buildMonthlyMessage(
  ayAdi: string,
  changePct: number | null,
  uzunDonemPct: number | null,
  tufe: AyTufesi | null = null,
): { title: string; body: string } {
  // Ayın TÜFE'si başlığa girer: kullanıcı iki rakamı yan yana görür ve
  // Özet'teki reel getiri kartı AYNI ayı anlatır (2026-10-01).
  const enf = tufe === null
    ? ''
    : ` · enflasyon %${tufe.aylikPct.toFixed(2).replace('.', ',')}`;
  if (changePct === null) {
    const yil = tufe?.yillikPct == null
      ? ''
      : `Yıllık enflasyon %${tufe.yillikPct.toFixed(1).replace('.', ',')}. `;
    return {
      title: `${ayAdi} özetin hazır${enf}`,
      body: tufe === null
        ? 'Getirin, enflasyon farkı ve en iyi varlığın Özet\'te. Yatırım tavsiyesi değildir.'
        : `${yil}Getirin ve reel farkın Özet'te. Yatırım tavsiyesi değildir.`,
    };
  }
  const yukari = changePct >= 0;
  const mutlak = Math.abs(changePct).toFixed(1).replace('.', ',');
  const baslik = yukari
    ? `▲ ${ayAdi}: piyasadan %${mutlak}${enf}`
    : `▼ ${ayAdi}: piyasadan −%${mutlak}${enf}`;
  const ozet = tufe === null ? 'Enflasyon farkı' : 'Reel getirin';
  let govde: string;
  if (!yukari && uzunDonemPct !== null && uzunDonemPct > 0) {
    const u = uzunDonemPct.toFixed(1).replace('.', ',');
    govde = `Ay ekside. Daha uzun pencerede hâlâ +%${u}. ${ozet} Özet'te.`;
  } else {
    govde = `${ozet} ve en iyi varlığın Özet'te. Yatırım tavsiyesi değildir.`;
  }
  return { title: baslik, body: govde };
}

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
///
/// [akisCumlesi] (2026-10-04): tuttuğu fonlarda geçen hafta büyük para
/// girişi/çıkışı olduysa gövdenin BAŞINA eklenir (`_shared/haftalik_akis.ts`).
/// Verilmezse mesaj birebir eski hâlindedir.
export function buildWeeklyMessage(
  changePct: number,
  uzunDonemPct: number | null,
  akisCumlesi: string | null = null,
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

  return { title: baslik, body: govdeyeAkisEkle(govde, akisCumlesi) };
}

/// Cihaz başına TEK token — aynı telefona kopya push gitmesin.
///
/// `daily-brief.collapseTokens` ile aynı gerekçe: FCM token'ı rotasyona
/// girer (yeniden kurulum, veri temizleme) ve eski satırlar tabloda kalır.

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const cronSecret = Deno.env.get('WEEKLY_SUMMARY_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'WEEKLY_SUMMARY_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    // Env denetimi kapıdan SONRA (2026-09-23 denetimi L2): yetkisiz çağıran
    // eksik yapılandırmayı ya da secret adlarını öğrenemesin.
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

    let dryRun = false;
    let minMovePct = DEFAULT_MIN_MOVE_PCT;
    let donem: Donem = 'week';
    let sadece: Set<string> | null = null;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.min_move_pct === 'number') minMovePct = body.min_move_pct;
      if (body?.period === 'month') donem = 'month';
      // Test kancası: yalnızca verilen kullanıcılara gönder (admin'de
      // deneme). Çağrı zaten cron secret'ı gerektiriyor; istemciden
      // ulaşılamaz. Boş/eksikse herkese (normal cron).
      if (Array.isArray(body?.user_ids) && body.user_ids.length > 0) {
        sadece = new Set((body.user_ids as unknown[]).map(String));
      }
    } catch (_) { /* gövde opsiyonel */ }
    const aylik = donem === 'month';
    const bildirimTipi = aylik ? 'monthly_summary' : 'weekly_summary';

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);
    const ay = ayPenceresi(new Date());

    // ── 0) Aylık: ayın TÜFE'si + ay başına tek koşu kilidi ─────────────────
    // (bkz. "Ayın 3'ü, TÜFE ile birleşik"). TÜFE yoksa hiçbir şey
    // gönderilmez ve kilit ALINMAZ — ertesi günkü koşu yeniden dener.
    let ayTufe: AyTufesi | null = null;
    if (aylik) {
      const { data: idxRows } = await admin
        .from('inflation_index')
        .select('period, tufe_index')
        .lte('period', ay.donem)
        .order('period', { ascending: false })
        .limit(13);
      const seri = ((idxRows ?? []) as Array<{ period: string; tufe_index: number }>)
        .map((r) => ({ period: String(r.period), value: Number(r.tufe_index) }))
        .reverse();
      ayTufe = ayinTufesi(seri, ay.donem);
      if (ayTufe === null) {
        return jsonResponse({
          ok: true,
          reason: 'tufe_bekleniyor',
          period: ay.donem,
          sent: 0,
        });
      }
      if (!dryRun) {
        const { error } = await admin
          .from('inflation_push_log')
          .insert({ period: ay.donem });
        if (error) {
          // 23505 → bu ayın TÜFE push'u (eski `fetch-inflation` yolu ya da
          // önceki koşu) zaten gitti; ikinci kez gönderilmez.
          if (error.code === '23505') {
            return jsonResponse({ ok: true, reason: 'zaten gonderildi', sent: 0 });
          }
          throw new Error(`inflation_push_log yazilamadi: ${error.message}`);
        }
        // `calendar-nudge` TÜFE kancası 0093 ile takvimden kalktı; elle
        // tetiklenirse de aynı ayı ikinci kez göndermesin.
        await admin
          .from('calendar_nudge_log')
          .upsert(
            { occasion: 'inflation_day', period: ay.donem },
            { onConflict: 'occasion,period' },
          );
      }
    }

    // ── 1) Push token'ı olan kullanıcılar ───────────────────────────────────
    const { data: tokenRows, error: tokenError } = await admin
      .from('user_push_tokens')
      .select('token, user_id, device_id, platform, updated_at');
    if (tokenError) {
      throw new Error(`Push tokenlari alinamadi: ${tokenError.message}`);
    }
    const tokens = collapseTokens((tokenRows ?? []) as TokenRow[])
      .filter((t) => sadece === null || sadece.has(t.user_id));
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

    // ── 3b) Aylık: bu ay özeti ZATEN almış kullanıcı ────────────────────────
    // Geçiş: Eylül özeti 1 Ekim'de eski takvimle (ayın 1'i) gitti. 3'ündeki
    // koşu aynı ayı ikinci kez anlatmasın — bu kullanıcılar yalnızca TÜFE
    // mesajını alır (eski TÜFE günü push'unun aynısı).
    const ayOzetiAlmis = new Set<string>();
    if (aylik) {
      const { data: alanlar } = await admin
        .from('app_notifications')
        .select('user_id')
        .eq('type', 'monthly_summary')
        .gte('created_at', new Date(ay.toMs).toISOString())
        .in('user_id', userIds);
      for (const r of (alanlar ?? []) as Array<{ user_id: string }>) {
        ayOzetiAlmis.add(String(r.user_id));
      }
    }

    // ── 4) Dönem penceresi ──────────────────────────────────────────────────
    // Haftalık: son 7 gün, şimdiye kadar. Aylık: geçen TAKVİM ayı — uçlar
    // ayın ilk/son gününe yakın snapshot'lardan (tazelik kuralı aynı).
    const simdi = Date.now();
    const fromMs = aylik ? ay.fromMs : simdi - 7 * 24 * 60 * 60 * 1000;
    const toMs = aylik ? ay.toMs : simdi;
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
        .gte('added_date', new Date(fromMs).toISOString())
        .lt('added_date', new Date(toMs).toISOString());
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

    // ── 5b) SON 365 GÜNDE akış olanlar ─────────────────────────────────────
    // "Daha uzun pencerede hâlâ +%X" cümlesi snapshot uçlarından (BRÜT)
    // hesaplanıyor. Yıl içinde para ekleyen kullanıcıda bu sayı katkıyla
    // şişer (2026-10-01 denetimi) — o kullanıcıya cümle sayısız kurulur.
    // Sorgu düşerse herkes akışlı sayılır: şüpheli sayı gönderilmez.
    const yilAkisli = new Set<string>(userIds);
    try {
      const { data: yilRows, error: yilErr } = await admin
        .from('assets')
        .select('user_id')
        .in('user_id', userIds)
        .in('kind', ['buy', 'sell'])
        .is('deleted_at', null)
        .gte('added_date', new Date(yilFromMs).toISOString());
      if (!yilErr) {
        yilAkisli.clear();
        for (const r of (yilRows ?? []) as Array<Record<string, unknown>>) {
          yilAkisli.add(String(r.user_id));
        }
      }
    } catch (_) { /* herkes akışlı kalır */ }

    // ── 5c) Tutulan fonlardaki büyük para hareketleri (0103) ────────────────
    //
    // Kullanıcı kararı 2026-10-04: olay başına ayrı push yok; haftanın özeti
    // akışa da değinir. Cümle `balina_olay` satırlarından kurulur — fon
    // sayfasındaki kartla aynı kaynak.
    //
    // KAPALI doğar (`HAFTALIK_AKIS_SATIRI=1` ile açılır): istemci kartı
    // Remote Config bayrağının arkasında; bildirim, kullanıcının açınca
    // göremeyeceği bir şeyi anlatmamalı. İkisi birlikte açılır.
    //
    // Hata sessizce "cümle yok"a düşer: akış cümlesi ek bilgidir, özetin
    // kendisini düşürmemeli. Aylık özet bu cümleyi taşımaz.
    const akisCumleleri = new Map<string, string>();
    let akisCumlesiHatasi = false;
    if (!aylik && Deno.env.get('HAFTALIK_AKIS_SATIRI') === '1') {
      try {
        const { data: fonRows, error: fonErr } = await admin
          .from('assets')
          .select('id, user_id, type, ticker, name, sub_category, currency, quantity, kind, added_date, ref_asset_id')
          .in('user_id', userIds)
          .in('type', ['fon', 'bes'])
          .is('deleted_at', null);
        if (fonErr) throw fonErr;
        const tutulan = new Map<string, Set<string>>();
        for (const lot of acikPozisyonLotlari((fonRows ?? []) as PozisyonLot[])) {
          const kod = varlikKodu(String(lot.ticker ?? ''));
          if (kod.length === 0) continue;
          const set = tutulan.get(lot.user_id);
          if (set) set.add(kod); else tutulan.set(lot.user_id, new Set([kod]));
        }
        const tumKodlar = [...new Set([...tutulan.values()].flatMap((k) => [...k]))];
        if (tumKodlar.length > 0) {
          const { data: olayRows, error: olayErr } = await admin
            .from('balina_olay')
            .select('ticker, tarih, tutar, bildirime_deger')
            .in('ticker', tumKodlar.map((k) => `TEFAS:${k}`))
            .gte('tarih', trGun(new Date(fromMs)))
            .lte('tarih', trGun(new Date(toMs)));
          if (olayErr) throw olayErr;
          const olaylar = ((olayRows ?? []) as Array<Record<string, unknown>>).map((r) => ({
            ticker: String(r.ticker),
            tarih: String(r.tarih),
            tutar: Number(r.tutar),
            bildirime_deger: r.bildirime_deger === true,
          } as HaftaOlayi));
          for (const [uid, kodlar] of tutulan) {
            const cumle = haftalikAkisCumlesi(fonHareketleri(olaylar, kodlar));
            if (cumle !== null) akisCumleleri.set(uid, cumle);
          }
        }
      } catch (e) {
        akisCumlesiHatasi = true;
        console.error('weekly-summary: akis cumlesi kurulamadi', e);
      }
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
    // Yüzdesi gönderilemeyen ama akış cümlesi olan kullanıcıya giden mesaj.
    let sentFlowOnly = 0;
    const failures: string[] = [];
    // Çan kaydı kullanıcı başına TEK (çok cihaz) — bkz. app_notifications.ts.
    const cankaydi = new Set<string>();

    // Sessiz saatler (0057) — tercihle aynı kapı: atlanır, ertelenmez.
    const sessiz = await sessizKullanicilar(admin, userIds);
    let skippedQuietHours = 0;

    const tufeYalnizTokenlar: typeof tokens = [];

    for (const tokenRow of tokens) {
      const uid = tokenRow.user_id;
      // Haftalık defter aylığı SUSTURMAZ: 3'ü Pazartesi'ye düşerse haftalık
      // 09:45'te gitmiş olur ama ayın TÜFE'si yalnızca bu mesajda.
      if (!aylik && zatenGonderildi.has(uid)) continue;
      if (sessiz.has(uid)) { skippedQuietHours += 1; continue; }
      // Aylık: özeti kapatmış ya da bu ay özeti almış kullanıcıya YALNIZCA
      // TÜFE mesajı (eski TÜFE günü push'u, tercih anahtarı yok).
      if (aylik && ayTufe !== null &&
          (istemeyen.has(uid) || ayOzetiAlmis.has(uid))) {
        if (istemeyen.has(uid)) skippedOptOut += 1;
        tufeYalnizTokenlar.push(tokenRow);
        continue;
      }
      if (istemeyen.has(uid)) { skippedOptOut += 1; continue; }

      // AKIŞ KAPISI — en önemlisi. Haftalıkta susturur; aylıkta yüzdeyi
      // düşürür, bildirimi değil (bkz. "Aylık özet" notu).
      const akisVar = akisliKullanicilar.has(uid);
      // Yüzde kapıları AYNEN duruyor (yanlış sayı gönderilmez). Tek fark:
      // kapıya takılan kullanıcının tuttuğu fonda büyük para hareketi
      // varsa hafta sessiz geçmez — YÜZDESİZ, yalnız akışı anlatan mesaj
      // gider (`yalnizAkis`). Cümle yoksa davranış birebir eski.
      const akisCumlesi = akisCumleleri.get(uid) ?? null;
      let yalnizAkis = false;
      if (akisVar && !aylik) {
        skippedFlow += 1;
        if (akisCumlesi === null) continue;
        yalnizAkis = true;
      }

      const rows = kullaniciSnap.get(uid) ?? [];
      const uclar = pickEndpoints(rows, fromMs, toMs);
      let degisim: number | null = null;
      if (yalnizAkis) {
        // Yüzde hesaplanmaz.
      } else if ('reason' in uclar) {
        if (uclar.reason === 'coverage') skippedCoverage += 1;
        // Aylıkta kapsama yoksa da "hazır" mesajı gider: kullanıcı ayın
        // özetini uygulamada yine görebilir, yalnızca push'ta sayı yok.
        if (!aylik) {
          if (akisCumlesi === null) continue;
          yalnizAkis = true;
        }
      } else if (!akisVar) {
        degisim = periodChangePct(uclar.bas, uclar.son);
        if (degisim === null && !aylik) {
          if (akisCumlesi === null) continue;
          yalnizAkis = true;
        }
      }
      if (!yalnizAkis && !aylik && degisim !== null &&
          Math.abs(degisim) < minMovePct) {
        skippedQuiet += 1;
        if (akisCumlesi === null) continue;
        yalnizAkis = true;
      }

      // Uzun pencere bağlamı — YALNIZCA kayıp haftasında kullanılıyor.
      // Yıllık uçlar için tazelik denetimi aranmaz: bağlam cümlesi ikincil
      // ve yaklaşık olması kabul edilebilir.
      let uzunDonemPct: number | null = null;
      if (degisim !== null && degisim < 0 && !yilAkisli.has(uid)) {
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

      // Haftalık yol buraya `degisim` dolu gelir (yukarıdaki kapılar);
      // aylıkta null olabilir ve mesaj sayısız kurulur.
      const mesaj = aylik
        ? buildMonthlyMessage(ay.ayAdi, degisim, uzunDonemPct, ayTufe)
        : yalnizAkis
        ? yalnizAkisMesaji(akisCumlesi!)
        : buildWeeklyMessage(degisim ?? 0, uzunDonemPct, akisCumlesi);

      if (dryRun) {
        sent += 1;
        if (yalnizAkis) sentFlowOnly += 1;
        continue;
      }

      // Çan sayfası kaydı — push'tan bağımsız (token reddedilse de kalır).
      const kayitHatasi = await recordAppNotification(
        admin,
        appNotificationRow({
          userId: tokenRow.user_id,
          type: bildirimTipi,
          title: mesaj.title,
          body: mesaj.body,
          // `ay` (2026-10-01): bildirimin anlattığı takvim ayı. Eski
          // sürümler alanı yok sayar.
          data: aylik
            ? { sent_on: bugun, ay: ay.donem.slice(0, 7) }
            // `akis` (2026-10-04): mesaj fon akışına değiniyor; istemci
            // dokunuşta "Haftanın özeti"ni açar. Eski sürümler yok sayar.
            : akisCumlesi !== null ? { sent_on: bugun, akis: '1' } : { sent_on: bugun },
        }),
        cankaydi,
      );
      if (kayitHatasi) failures.push(kayitHatasi);

      const r = await sendFcmNotification({
        accessToken,
        projectId: fcmProjectId,
        token: tokenRow.token,
        title: mesaj.title,
        body: mesaj.body,
        channelId: CHANNEL_ID,
        data: aylik
          ? { type: bildirimTipi, sent_on: bugun, ay: ay.donem.slice(0, 7) }
          : akisCumlesi !== null
          ? { type: bildirimTipi, sent_on: bugun, akis: '1' }
          : { type: bildirimTipi, sent_on: bugun },
      });

      if (r.ok) {
        sent += 1;
        if (yalnizAkis) sentFlowOnly += 1;
        // Log yazılır ama hata yutulur: yazamazsak en kötü ihtimalle
        // yeniden denemede ikinci bildirim gider.
        await admin
          .from('weekly_summary_log')
          .upsert(
            { user_id: uid, sent_on: bugun },
            { onConflict: 'user_id,sent_on' },
          );
        // Aylık push günün TEK proaktif mesajı: brifing defterine de
        // yazılır ki 06:45'teki daily-brief bu kullanıcıyı atlasın.
        if (aylik) {
          await admin
            .from('daily_brief_log')
            .upsert(
              { user_id: uid, sent_on: bugun },
              { onConflict: 'user_id,sent_on' },
            );
        }
      } else {
        // Ham FCM gövdesi yalnızca günlüğe; yanıta kısa kod (2026-09-23 denetimi L2).
        console.error('[weekly-summary] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
        failures.push(`fcm: ${r.hataKodu}`);
        if (r.shouldDeleteToken) {
          await admin
            .from('user_push_tokens')
            .delete()
            .eq('token', tokenRow.token);
        }
      }
    }

    // ── 8) Aylık: yalnızca TÜFE mesajı alacaklar ────────────────────────────
    let sentTufe = 0;
    if (aylik && ayTufe !== null && tufeYalnizTokenlar.length > 0) {
      const tm = tufeMesaji(ay.ayAdi, ayTufe.aylikPct, ayTufe.yillikPct);
      const tufeCan = new Set<string>();
      for (const t of tufeYalnizTokenlar) {
        if (dryRun) { sentTufe += 1; continue; }
        const kh = await recordAppNotification(
          admin,
          appNotificationRow({
            userId: t.user_id,
            type: 'inflation_day',
            title: tm.title,
            body: tm.body,
            data: { period: ay.donem },
          }),
          tufeCan,
        );
        if (kh) failures.push(kh);
        const r = await sendFcmNotification({
          accessToken,
          projectId: fcmProjectId,
          token: t.token,
          title: tm.title,
          body: tm.body,
          channelId: CHANNEL_ID,
          data: { type: 'inflation_day', period: ay.donem },
        });
        if (r.ok) {
          sentTufe += 1;
        } else {
          console.error('[weekly-summary] TÜFE gonderimi basarisiz:', r.rawText.slice(0, 500));
          failures.push(`fcm: ${r.hataKodu}`);
          if (r.shouldDeleteToken) {
            await admin.from('user_push_tokens').delete().eq('token', t.token);
          }
        }
      }
    }

    return jsonResponse({
      ok: true,
      period: donem,
      sent,
      sent_tufe_only: sentTufe,
      // Yüzde kapısına takılıp yalnız akış cümlesiyle giden mesajlar
      // (`sent`'e dahil). `skipped_*` sayaçları yüzdenin atlandığını sayar;
      // akış cümlesi varsa o kullanıcıya yine de mesaj gitmiştir.
      sent_flow_only: sentFlowOnly,
      flow_sentences: akisCumleleri.size,
      flow_sentence_error: akisCumlesiHatasi,
      skipped_flow: skippedFlow,
      skipped_coverage: skippedCoverage,
      skipped_quiet: skippedQuiet,
      skipped_quiet_hours: skippedQuietHours,
      skipped_opt_out: skippedOptOut,
      dry_run: dryRun,
      failures: failures.slice(0, 5),
    });
  } catch (error) {
    // Ayrıntı yalnızca günlüğe: yanıtta `error.message` dönmek tablo/sütun
    // adlarını ve secret adlarını dışarı sızdırır (CLAUDE.md sunucu kuralı).
    console.error('[weekly-summary] hata:', error);
    return jsonResponse({ error: 'Ozet gonderimi basarisiz.' }, 500);
  }
});
