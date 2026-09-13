// Fetch Inflation Edge Function — TÜFE ENDEKSİ OTOMATİK ÇEKİMİ
//
// pg_cron ile her ayın 3'ünde TR 10:05'te koşar ve `inflation_index`
// tablosunu TCMB EVDS'den doldurur.
//
// ── Neden bu fonksiyon var ──────────────────────────────────────────────────
// `inflation_index` ELLE dolduruluyordu (bkz. TECHNICAL_DEBT.md "TÜFE
// endeksi elle dolduruluyor"). Unutulduğunda reel getiri rozeti sessizce
// eskiyordu: hesap son AÇIKLANMIŞ aya dayandığı için yanlış sayı
// göstermiyor, ama pencere geriye kayıyor ve "enflasyonun kaç puan
// önündesin" bilgisi bayatlıyordu.
//
// ── ⏰ SAAT SIRASI KRİTİK ───────────────────────────────────────────────────
// `calendar-nudge` ayın 3'ünde TR 10:15'te koşuyor ve tabloda BU AYIN
// satırını arıyor; yoksa sessizce hiçbir şey göndermiyor.
//
// Bu fonksiyon TR 10:05'te, yani NUDGE'DAN 10 DAKİKA ÖNCE koşar. Sıra
// tersine çevrilirse (borç kaydı `0 8 3 * *` = TR 11:00 öneriyordu) nudge
// hep bayat veriyle karşılaşır ve o ayın kancası kaçar — otomatikleştirmenin
// asıl kazancı kaybolur.
//
// TÜİK 10:00'da açıklıyor; 5 dakika EVDS'nin seriyi yayımlaması için.
// Veri henüz yoksa fonksiyon `no_new_data` döner ve ayın 4'ündeki ikinci
// tur onu yakalar (aşağıya bak).
//
// ── Neden EVDS ──────────────────────────────────────────────────────────────
// TCMB EVDS `TP.FG.J0` serisi = TÜFE genel endeks (2003=100). Tablo
// zaten `source` kolonunda bu adı varsayılan tutuyor.
//
// EVDS API anahtarı ŞART: evds2.tcmb.gov.tr → üye ol → Profil → API
// Anahtarı → `supabase secrets set EVDS_API_KEY=...`. Anahtar yoksa
// fonksiyon `no_api_key` döner ve HİÇBİR ŞEY YAZMAZ — yarım bir
// entegrasyonla tabloyu bozmaktan iyidir.
//
// ── ENDEKS DEĞERİ saklanır, yüzde DEĞİL ─────────────────────────────────────
// `0045_inflation_index.sql`: iki tarih arası enflasyon tek bölmeyle çıkar
// (sonEndeks / ilkEndeks − 1). Yüzde saklansaydı aradaki bütün ayları
// çarpmak gerekirdi ve her ay bir yuvarlama hatası eklenirdi.
//
// ── Baz yılı değişimi — SESSİZ TEHLİKE ──────────────────────────────────────
// TÜİK zaman zaman baz yılını değiştirir (ör. 2003=100 → 2025=100). Baz
// değişince endeks SIFIRLANIR ve eski satırlarla yeni satırlar DOĞRUDAN
// karşılaştırılamaz: bölme anlamsız bir sonuç verir. Fonksiyon bunu
// sezgisel olarak yakalar (bkz. `bazKirilmasiVarMi`) ve yazmayı reddeder
// — yanlış bir reel getiri, hiç göstermemekten kötüdür.

import { requireCronSecret } from '../_shared/cron_auth.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

/// EVDS serisi — TÜFE genel endeks.
const EVDS_SERIES = 'TP.FG.J0';

/// Tabloya yazılan kaynak etiketi — `0045`'in varsayılanıyla aynı.
///
/// Baz yılı değişirse TÜİK seri adını da değiştirir; bu etiket o yüzden
/// hangi seriden geldiğini taşıyor ve eski satırlar ayırt edilebiliyor.
const SOURCE_LABEL = 'TUIK-TP.FG.J0';

/// İlk koşuda kaç ay geriye gidilsin.
///
/// Reel getiri rozeti 365 günlük pencere kullanıyor, yani en az 13 ay
/// gerekiyor (başlangıç ayı + son açıklanan ay). 24 ay isteniyor ki ilk
/// koşu pencereyi rahatça doldursun ve bir sonraki baz değişimine kadar
/// geçmiş elde olsun.
const BACKFILL_AY = 24;

/// Baz kırılması eşiği (yüzde).
///
/// Ardışık iki ay arasında TÜFE %15'ten fazla DÜŞERSE bu enflasyon
/// değildir — baz yılı değişmiştir (ya da EVDS bozuk veri döndürmüştür).
/// Türkiye'de aylık deflasyon tarihsel olarak hiç bu boyutta olmadı.
const BAZ_KIRILMA_ESIGI = -15;

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export type EndeksSatiri = { period: string; value: number };

/// EVDS yanıtını `(period, value)` satırlarına çevirir.
///
/// EVDS gövdesi şu şekilde gelir:
/// ```json
/// { "items": [ { "Tarih": "01-2026", "TP_FG_J0": "2100.50" }, ... ] }
/// ```
/// Alan adı serideki noktaların alt çizgiye dönmüş hâlidir. Tarih
/// `AY-YIL` biçiminde ve tabloya AYIN İLK GÜNÜ olarak yazılmalı
/// (`0045`: "Ayın İLK günü ... gün alanı sabit tutulur ki '2026-03' ile
/// '2026-03-15' iki ayrı satır olmasın").
///
/// Bozuk/eksik satırlar ATLANIR, hata fırlatılmaz: EVDS bazı aylar için
/// boş string (`""`) ya da `null` döndürebiliyor ve tek bozuk ay tüm turu
/// düşürmemeli.
export function parseEvds(json: unknown): EndeksSatiri[] {
  const govde = json as { items?: unknown } | null;
  const items = Array.isArray(govde?.items) ? govde!.items : [];
  const alan = EVDS_SERIES.replaceAll('.', '_');

  const out: EndeksSatiri[] = [];
  for (const raw of items) {
    const item = raw as Record<string, unknown>;
    const tarih = String(item['Tarih'] ?? '').trim();
    const ham = item[alan];
    if (tarih.length === 0 || ham === null || ham === undefined) continue;

    const deger = typeof ham === 'number' ? ham : Number(String(ham).trim());
    // `0045` CHECK'i `tufe_index > 0` istiyor; sıfır/negatif/NaN yazılamaz.
    if (!Number.isFinite(deger) || deger <= 0) continue;

    const period = evdsTarihToPeriod(tarih);
    if (period === null) continue;

    out.push({ period, value: deger });
  }

  // Kronolojik sıra: baz kırılması denetimi ardışık aylara bakıyor.
  out.sort((a, b) => a.period.localeCompare(b.period));
  return out;
}

/// EVDS `AY-YIL` → `YYYY-MM-01`.
///
/// EVDS ayrıca `YYYY-MM` ve `GG-AY-YIL` biçimleri döndürebiliyor; üçü de
/// kabul edilir. Tanınmayan biçim `null` döner ve satır atlanır — tarihi
/// tahmin etmek yanlış aya yazmak demek olurdu.
export function evdsTarihToPeriod(tarih: string): string | null {
  const t = tarih.trim();

  // 'AY-YIL' → '01-2026'
  let m = /^(\d{1,2})-(\d{4})$/.exec(t);
  if (m) return `${m[2]}-${m[1].padStart(2, '0')}-01`;

  // 'YYYY-MM' → '2026-01'
  m = /^(\d{4})-(\d{1,2})$/.exec(t);
  if (m) return `${m[1]}-${m[2].padStart(2, '0')}-01`;

  // 'GG-AY-YIL' → '01-01-2026'
  m = /^\d{1,2}-(\d{1,2})-(\d{4})$/.exec(t);
  if (m) return `${m[2]}-${m[1].padStart(2, '0')}-01`;

  return null;
}

/// Ardışık aylar arasında baz kırılması var mı?
///
/// TÜİK baz yılını değiştirdiğinde endeks sıfırlanır ve eski satırlarla
/// yeni satırlar karşılaştırılamaz hale gelir. Böyle bir seriyi tabloya
/// yazmak, reel getiriyi sessizce anlamsız yapardı.
///
/// Dönüş: kırılmanın görüldüğü `period`, yoksa `null`.
export function bazKirilmasiVarMi(satirlar: EndeksSatiri[]): string | null {
  for (let i = 1; i < satirlar.length; i++) {
    const onceki = satirlar[i - 1].value;
    const simdi = satirlar[i].value;
    if (onceki <= 0) continue;
    const degisim = (simdi / onceki - 1) * 100;
    if (degisim < BAZ_KIRILMA_ESIGI) return satirlar[i].period;
  }
  return null;
}

/// Bir tarihi `YYYY-MM-01` biçimine indirger (UTC).
export function ayBasi(d: Date): string {
  const y = d.getUTCFullYear();
  const m = (d.getUTCMonth() + 1).toString().padStart(2, '0');
  return `${y}-${m}-01`;
}

/// EVDS'nin beklediği `GG-AA-YYYY` biçimi.
export function evdsTarihBicimi(d: Date): string {
  const g = d.getUTCDate().toString().padStart(2, '0');
  const a = (d.getUTCMonth() + 1).toString().padStart(2, '0');
  return `${g}-${a}-${d.getUTCFullYear()}`;
}

/// İçinde bulunulan ay TABLOYA YAZILMAZ.
///
/// `InflationService.inflationForPeriod` "son AÇIKLANMIŞ ay"ı arıyor ve
/// yorumu şu: TÜİK bir ayın verisini ertesi ayın 3'ünde yayımlar, yani
/// içinde bulunulan ay tabloda henüz YOKTUR. Geçici bir satır yazmak o
/// varsayımı kırardı.
export function guncelAyiEle(
  satirlar: EndeksSatiri[],
  simdi: Date,
): EndeksSatiri[] {
  const buAy = ayBasi(simdi);
  return satirlar.filter((s) => s.period < buAy);
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const evdsApiKey = Deno.env.get('EVDS_API_KEY');

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error(
        'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından '
        + 'sağlanmadı. Bunlar otomatik enjekte edilir.',
      );
    }
    // FAIL-CLOSED: secret yoksa 503, uyusmuyorsa 401 (bkz. _shared/cron_auth.ts).
    const denied = await requireCronSecret(request, 'INFLATION_FETCH_CRON_SECRET');
    if (denied) return denied;

    // Anahtar yoksa HİÇBİR ŞEY yazılmaz.
    //
    // Yarım bir entegrasyonla tabloyu bozmak, elle girişten kötü olurdu
    // (borç kaydının erteleme gerekçesi de buydu). Kuru koşu bu durumda
    // da anlamlı bir cevap verir.
    if (!evdsApiKey) {
      return jsonResponse({
        ok: true,
        reason: 'no_api_key',
        detail: 'EVDS_API_KEY yok — tabloya yazilmadi. '
          + 'evds2.tcmb.gov.tr uzerinden anahtar alip '
          + 'supabase secrets set EVDS_API_KEY=... yap.',
        written: 0,
      });
    }

    let dryRun = false;
    let backfillAy = BACKFILL_AY;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.backfill_months === 'number') {
        // 1…120 arası sınırla: EVDS çok uzun aralıkta yavaşlıyor ve
        // 10 yıldan eskisi zaten baz kırılmalarıyla dolu.
        backfillAy = Math.min(120, Math.max(1, Math.floor(body.backfill_months)));
      }
    } catch (_) { /* gövde opsiyonel */ }

    // ── 1) EVDS'den seriyi çek ──────────────────────────────────────────────
    const simdi = new Date();
    const bitis = simdi;
    const baslangic = new Date(Date.UTC(
      simdi.getUTCFullYear(),
      simdi.getUTCMonth() - backfillAy,
      1,
    ));

    const url = new URL('https://evds2.tcmb.gov.tr/service/evds/');
    url.searchParams.set('series', EVDS_SERIES);
    url.searchParams.set('startDate', evdsTarihBicimi(baslangic));
    url.searchParams.set('endDate', evdsTarihBicimi(bitis));
    url.searchParams.set('type', 'json');
    url.searchParams.set('frequency', '5'); // 5 = aylık

    let evdsJson: unknown;
    try {
      const res = await fetch(url.toString(), {
        headers: {
          // EVDS anahtarı GÖVDEDE değil header'da: sorgu dizesine koymak
          // anahtarı günlüklere sızdırırdı.
          key: evdsApiKey,
          Accept: 'application/json',
        },
        // Repo geneli kural: her fetch'in timeout'u var
        // (bkz. _shared/live_prices.ts).
        signal: AbortSignal.timeout(20_000),
      });
      if (!res.ok) {
        return jsonResponse({
          ok: false,
          reason: 'evds_http_error',
          status: res.status,
          written: 0,
        }, 502);
      }
      evdsJson = await res.json();
    } catch (e) {
      return jsonResponse({
        ok: false,
        reason: 'evds_unreachable',
        detail: e instanceof Error ? e.message : String(e),
        written: 0,
      }, 502);
    }

    // ── 2) Ayrıştır ve denetle ──────────────────────────────────────────────
    const tumu = parseEvds(evdsJson);
    const satirlar = guncelAyiEle(tumu, simdi);

    if (satirlar.length === 0) {
      return jsonResponse({
        ok: true,
        reason: 'no_rows_parsed',
        detail: 'EVDS yaniti ayristirilamadi ya da bos.',
        written: 0,
      });
    }

    // Baz kırılması: yazmayı REDDET.
    //
    // Yanlış bir reel getiri, hiç göstermemekten kötüdür. Bu durumda insan
    // müdahalesi gerekiyor (yeni seri adı + eski satırların ne olacağı bir
    // ürün kararı), o yüzden yüksek sesle raporlanır.
    const kirilma = bazKirilmasiVarMi(satirlar);
    if (kirilma !== null) {
      return jsonResponse({
        ok: false,
        reason: 'base_year_break',
        detail: `${kirilma} ayinda endeks %${BAZ_KIRILMA_ESIGI}'ten fazla `
          + 'dustu — TUIK baz yilini degistirmis olabilir. Eski satirlarla '
          + 'yeni satirlar karsilastirilamaz; elle inceleme gerekiyor.',
        written: 0,
      }, 409);
    }

    // ── 3) Yeni satır var mı? ───────────────────────────────────────────────
    const { createClient } = await import('jsr:@supabase/supabase-js@2');
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: mevcutRows } = await admin
      .from('inflation_index')
      .select('period')
      .order('period', { ascending: false })
      .limit(1);
    const enSonMevcut = (mevcutRows ?? [])[0]?.period as string | undefined;
    const enSonGelen = satirlar[satirlar.length - 1].period;

    const yeniVarMi = enSonMevcut === undefined ||
      enSonGelen > enSonMevcut.slice(0, 10);

    if (dryRun) {
      return jsonResponse({
        ok: true,
        dry_run: true,
        fetched: satirlar.length,
        latest_fetched: enSonGelen,
        latest_in_table: enSonMevcut ?? null,
        would_write: satirlar.length,
        has_new_month: yeniVarMi,
      });
    }

    // ── 4) Upsert ───────────────────────────────────────────────────────────
    //
    // `period` birincil anahtar; upsert hem ilk doldurmayı hem TÜİK'in
    // REVİZYONLARINI halleder (açıklanan bir ay sonradan düzeltilebiliyor).
    const { error: upsertError } = await admin
      .from('inflation_index')
      .upsert(
        satirlar.map((s) => ({
          period: s.period,
          tufe_index: s.value,
          source: SOURCE_LABEL,
        })),
        { onConflict: 'period' },
      );
    if (upsertError) {
      throw new Error(`inflation_index yazilamadi: ${upsertError.message}`);
    }

    return jsonResponse({
      ok: true,
      written: satirlar.length,
      latest: enSonGelen,
      previous_latest: enSonMevcut ?? null,
      has_new_month: yeniVarMi,
      // `calendar-nudge` 10 dakika sonra koşacak ve bu ayın satırını
      // arayacak; `has_new_month: false` ise o da sessiz kalır.
      reason: yeniVarMi ? 'updated' : 'no_new_data',
    });
  } catch (error) {
    return jsonResponse(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});
