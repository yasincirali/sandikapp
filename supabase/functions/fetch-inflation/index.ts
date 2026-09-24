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
// TCMB EVDS `TP.TUKFIY2025.GENEL` serisi = TÜFE genel endeks (2025=100).
// `source` kolonu bu adı taşır ve baz yılını ayırt etmenin tek kanıtıdır.
//
// EVDS API anahtarı ŞART: evds3.tcmb.gov.tr → üye ol → Profil → API
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

import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { enflasyonOranlari, tufeGunuPushu } from '../_shared/tufe_push.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya (2026-09 L4);
  // Allow-Origin '*' bilinçli olarak yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

/// EVDS serisi — TÜFE genel endeks (2025=100).
///
/// **2026-09-14'te değişti.** Önceki kod `TP.FG.J0` idi (2003=100) ve TÜİK
/// baz yılını `2025=100`'e çevirdiğinde o seri **Ocak 2026'da sona erdi**.
/// Tablo dolu görünmeye devam ediyordu (29 satır) ama Şubat–Ağustos 2026
/// hiç gelmiyordu ve fonksiyon bunu `no_new_data` diye raporluyordu —
/// yine sessiz bir arıza.
///
/// Yeni kod EVDS3 kataloğundan OKUNDU, tahmin edilmedi:
///
///     kategori 2005  "TÜKETİCİ FİYAT ENDEKSİ (TÜİK)"
///       └─ grup bie_tukfiy2025  "Tüketici Fiyat Endeksi (2025=100)"
///            └─ TP.TUKFIY2025.GENEL  "Genel Endeks"  01-2005 … 08-2026
///
/// Katalog gezinmesi fonksiyonun kendi `catalog` moduyla yapıldı (anahtar
/// yalnızca sunucuda olduğu için dışarıdan sorgulanamıyor); o mod bir
/// sonraki baz değişiminde de aynı işi görecek.
const EVDS_SERIES = 'TP.TUKFIY2025.GENEL';

/// EVDS servis adresi.
///
/// **2026-09-14'te değişti — sessiz kırılma.** TCMB, EVDS'yi `evds2`'den
/// `evds3`'e taşıdı ve eski `evds2.tcmb.gov.tr/service/evds/` yolu artık
/// API DEĞİL, web uygulamasının HTML'ini döndürüyor:
///
///     evds2/service/evds/  → 302 → evds3.tcmb.gov.tr → <!DOCTYPE html>
///
/// Bu bir HTTP hatası olarak GÖRÜNMÜYOR: yönlendirme takip edilince
/// durum 200 geliyor, yani `res.ok` geçiyor ve hata ancak `res.json()`
/// aşamasında "Unexpected token '<'" olarak patlıyor. Fonksiyon bunu
/// `evds_unreachable` diye raporluyordu ve gerçek sebep (adres değişimi)
/// görünmüyordu — ölçüldü, canlıda 502 alındı.
///
/// Yeni yol `/igmevdsms-dis/`. Doğrulandı: anahtarsız istekte HTML değil,
/// `401 Invalid API Key` (text/plain) dönüyor — yani gerçekten API.
///
/// Anahtar yine HEADER'da (`key`), sorgu dizesinde değil.
const EVDS_BASE = 'https://evds3.tcmb.gov.tr/igmevdsms-dis/';

/// Tabloya yazılan kaynak etiketi — `0045`'in varsayılanıyla aynı biçim.
///
/// Baz yılı değişirse TÜİK seri adını da değiştirir; etiket o yüzden
/// SERİ KODUNDAN türetilir, sabit değildir. Böylece `2003=100` ve
/// `2025=100` satırları tabloda ayırt edilebiliyor — iki bazı birbirine
/// bölmek anlamsız bir enflasyon üretirdi ve hangi satırın hangi bazdan
/// geldiği tek kanıt bu kolon.
function sourceLabel(seri: string): string {
  return `TUIK-${seri}`;
}

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
/// { "items": [ { "Tarih": "01-2026", "TP_TUKFIY2025_GENEL": "118.5" }, ...] }
/// ```
/// Alan adı serideki noktaların alt çizgiye dönmüş hâlidir. Tarih
/// `AY-YIL` biçiminde ve tabloya AYIN İLK GÜNÜ olarak yazılmalı
/// (`0045`: "Ayın İLK günü ... gün alanı sabit tutulur ki '2026-03' ile
/// '2026-03-15' iki ayrı satır olmasın").
///
/// Bozuk/eksik satırlar ATLANIR, hata fırlatılmaz: EVDS bazı aylar için
/// boş string (`""`) ya da `null` döndürebiliyor ve tek bozuk ay tüm turu
/// düşürmemeli.
/// [seri] verilmezse varsayılan [EVDS_SERIES] kullanılır. Parametre, baz
/// yılı değişiminde seri kodunun gövdeden geçilebilmesi için var (bkz.
/// istek gövdesindeki `series` alanı) — alan adı seri koduna bağlı olduğu
/// için ayrıştırma da aynı kodu bilmek zorunda.
export function parseEvds(json: unknown, seri: string = EVDS_SERIES): EndeksSatiri[] {
  const govde = json as { items?: unknown } | null;
  const items = Array.isArray(govde?.items) ? govde!.items : [];
  const alan = seri.replaceAll('.', '_');

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
    const cronSecret = Deno.env.get('INFLATION_FETCH_CRON_SECRET');
    // TÜFE günü push'u (0068). FCM secret'ları proje geneli; yoksa push
    // ATLANIR, endeks yazımı yine tamamlanır — push ikincil.
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const fcm = fcmProjectId && fcmServiceAccountJson
      ? { projectId: fcmProjectId, serviceAccountJson: fcmServiceAccountJson }
      : null;

    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'INFLATION_FETCH_CRON_SECRET');
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
          + 'evds3.tcmb.gov.tr uzerinden anahtar alip '
          + 'supabase secrets set EVDS_API_KEY=... yap.',
        written: 0,
      });
    }

    let dryRun = false;
    let backfillAy = BACKFILL_AY;
    let seri = EVDS_SERIES;
    let katalogKodu: string | null = null;
    let filtre: string | null = null;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.backfill_months === 'number') {
        // 1…120 arası sınırla: EVDS çok uzun aralıkta yavaşlıyor ve
        // 10 yıldan eskisi zaten baz kırılmalarıyla dolu.
        backfillAy = Math.min(120, Math.max(1, Math.floor(body.backfill_months)));
      }
      // Seri kodu GÖVDEDEN geçilebilir.
      //
      // **Neden gerekiyor:** TÜİK baz yılını değiştirdiğinde seri kodu da
      // değişiyor (2026-01'de `2003=100` → `2025=100` oldu ve `TP.FG.J0`
      // sona erdi). Kod sabit olsaydı her baz değişiminde deploy gerekirdi;
      // daha kötüsü, doğru kodu bulmak için önce yanlış kodla deneme
      // yapmak imkânsız olurdu — anahtar yalnızca sunucuda.
      //
      // `dry_run` ile birlikte kullanıldığında tabloya HİÇBİR ŞEY yazmaz,
      // yani aday kodlar güvenle denenebilir.
      if (typeof body?.series === 'string' && /^[A-Z0-9._]{3,64}$/.test(body.series)) {
        seri = body.series;
      }
      // Katalog keşfi: EVDS'nin seri listesini olduğu gibi döndürür.
      // Doğru seri kodunu TAHMİN ETMEK yerine katalogdan OKUMAK için.
      if (typeof body?.catalog === 'string' && /^[A-Za-z0-9._:-]{2,64}$/.test(body.catalog)) {
        katalogKodu = body.catalog;
      }
      // Katalog süzgeci: seri adı/kodu içinde geçen metin. Kırpma yüzünden
      // aranan satırın listeden düşmesini engeller.
      if (typeof body?.q === 'string' && body.q.length <= 40) {
        filtre = body.q;
      }
    } catch (_) { /* gövde opsiyonel */ }

    // ── 0) Katalog keşfi (opsiyonel) ────────────────────────────────────────
    // Yalnızca OKUR, tabloya dokunmaz. Baz yılı değiştiğinde yeni seri
    // kodunu bulmanın tek güvenli yolu: anahtar sunucuda olduğu için
    // katalog dışarıdan sorgulanamıyor.
    if (katalogKodu) {
      try {
        // İki mod:
        //   · `catalog: "groups:<kategori id>"` → o kategorinin VERİ
        //     GRUPLARINI listeler (grup kodunu tahmin etmemek için)
        //   · `catalog: "<grup kodu>"`          → grubun SERİLERİNİ listeler
        //
        // Grup kodunu tahmin etmek işe yaramadı (ölçüldü: `bie_tufe`,
        // `bie_tufe2`, `bie_tufe3` hepsi boş dizi döndürdü), bu yüzden
        // katalog gezinmesi iki adımlı.
        const kUrl = katalogKodu === 'categories'
          ? 'https://evds3.tcmb.gov.tr/igmevdsms-dis/categories/type=json'
          : katalogKodu.startsWith('groups:')
          ? `https://evds3.tcmb.gov.tr/igmevdsms-dis/datagroups/mode=2&code=${katalogKodu.slice(7)}&type=json`
          : `https://evds3.tcmb.gov.tr/igmevdsms-dis/serieList/type=json&code=${katalogKodu}`;
        const kRes = await fetch(kUrl, {
          headers: { key: evdsApiKey, Accept: 'application/json' },
          signal: AbortSignal.timeout(20_000),
        });
        const kHam = await kRes.text();

        // Katalog binlerce seri taşıyor ve pg_net gövdesi okunabilir
        // kalmalı. Ham metni kırpmak JSON'u ortadan bölüyordu (ölçüldü:
        // ayrıştırma "Unterminated string" veriyordu), bu yüzden ÖNCE
        // parse edip SONRA süzüyoruz — ve yalnızca işe yarayan alanları
        // döndürüyoruz.
        let ozet: unknown = kHam.slice(0, 4000);
        try {
          const dizi = JSON.parse(kHam) as Record<string, unknown>[];
          const q = (filtre ?? '').toLocaleUpperCase('tr');
          const secili = dizi
            .filter((k) => {
              if (q.length === 0) return true;
              const hedef = [
                k['SERIE_CODE'], k['SERIE_NAME'], k['DATAGROUP_CODE'],
                k['DATAGROUP_NAME'], k['TOPIC_TITLE_TR'], k['CATEGORY_ID'],
              ].join(' ').toLocaleUpperCase('tr');
              return hedef.includes(q);
            })
            .slice(0, 60)
            .map((k) => ({
              code: k['SERIE_CODE'] ?? k['DATAGROUP_CODE'] ?? k['CATEGORY_ID'],
              name: k['SERIE_NAME'] ?? k['DATAGROUP_NAME'] ?? k['TOPIC_TITLE_TR'],
              start: k['START_DATE'], end: k['END_DATE'],
            }));
          ozet = { total: dizi.length, matched: secili.length, items: secili };
        } catch (_) { /* dizi değilse ham kırpılmış hâli döner */ }

        return jsonResponse({
          ok: kRes.ok,
          mode: 'catalog',
          status: kRes.status,
          body: ozet,
          written: 0,
        });
      } catch (e) {
        // Ham hata metni yalnızca günlüğe; yanıtta sabit kod (2026-09-23 denetimi L2).
        console.error('[fetch-inflation] katalog istegi basarisiz:', e);
        return jsonResponse({
          ok: false,
          mode: 'catalog',
          reason: 'evds_unreachable',
          written: 0,
        }, 502);
      }
    }

    // ── 1) EVDS'den seriyi çek ──────────────────────────────────────────────
    const simdi = new Date();
    const bitis = simdi;
    const baslangic = new Date(Date.UTC(
      simdi.getUTCFullYear(),
      simdi.getUTCMonth() - backfillAy,
      1,
    ));

    // EVDS parametreleri YOLA gömülür, sorgu dizesine DEĞİL:
    //
    //     .../igmevdsms-dis/series=<kod>&startDate=...&type=json   ✓ 200
    //     .../igmevdsms-dis/?series=<kod>&startDate=...             ✗ 404
    //
    // Alışılmadık ama TCMB'nin biçimi bu; ölçüldü (2026-09-14): soru
    // işaretli sürüm 404 HTML döndürüyor, gömülü sürüm gerçek API yanıtı
    // veriyor. Bu yüzden `new URL(...).searchParams` KULLANILAMAZ — o
    // otomatik olarak `?` ekler ve isteği 404'e düşürür.
    //
    // Değerlerin hiçbiri kullanıcı girdisi değil (sabit seri adı + kendi
    // ürettiğimiz tarihler), yani kaçış gerektiren bir enjeksiyon yüzeyi
    // yok; yine de tarihler `evdsTarihBicimi` ile tek yerden üretiliyor.
    const url = new URL(
      `${EVDS_BASE}series=${seri}`
      + `&startDate=${evdsTarihBicimi(baslangic)}`
      + `&endDate=${evdsTarihBicimi(bitis)}`
      + '&type=json'
      + '&frequency=5', // 5 = aylık
    );

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
      // JSON'a doğrudan gitmiyoruz: EVDS adres değiştirdiğinde (2026-09'da
      // evds2 → evds3 oldu) eski yol HTML döndürüyor ve durum 200 geliyor.
      // `res.json()` o hâlde "Unexpected token '<'" diye patlıyor ve hata
      // `evds_unreachable` olarak raporlanıyordu — ağ sorunu gibi görünen,
      // aslında adres değişimi olan bir teşhis. Bir daha o yanılgıya
      // düşmemek için içerik türü ÖNCE kontrol ediliyor.
      const ham = await res.text();
      const ct = res.headers.get('content-type') ?? '';
      if (!ct.includes('json') || ham.trimStart().startsWith('<')) {
        return jsonResponse({
          ok: false,
          reason: 'evds_html_response',
          detail: 'EVDS JSON yerine HTML dondu — servis adresi degismis '
            + `olabilir. content-type=${ct}, ilk 80 karakter: `
            + ham.slice(0, 80),
          written: 0,
        }, 502);
      }
      evdsJson = JSON.parse(ham);
    } catch (e) {
      // Ham hata metni yalnızca günlüğe; `reason` teşhis için yeterli
      // (2026-09-23 denetimi L2).
      console.error('[fetch-inflation] EVDS istegi basarisiz:', e);
      return jsonResponse({
        ok: false,
        reason: 'evds_unreachable',
        written: 0,
      }, 502);
    }

    // ── 2) Ayrıştır ve denetle ──────────────────────────────────────────────
    const tumu = parseEvds(evdsJson, seri);
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
          source: sourceLabel(seri),
        })),
        { onConflict: 'period' },
      );
    if (upsertError) {
      throw new Error(`inflation_index yazilamadi: ${upsertError.message}`);
    }

    // ── TÜFE günü push'u (0068) ─────────────────────────────────────────────
    // Yalnızca YENİ ay yazıldıysa; `inflation_push_log` aynı ay için ikinci
    // koşuyu keser. Push hatası endeks yazımını geri almaz — ayrı raporlanır.
    let push: Record<string, unknown> | null = null;
    if (yeniVarMi) {
      const oranlar = enflasyonOranlari(satirlar);
      if (oranlar) {
        try {
          push = await tufeGunuPushu(admin, {
            period: oranlar.period,
            aylikPct: oranlar.aylikPct,
            yillikPct: oranlar.yillikPct,
            fcm,
            dryRun: false,
          });
        } catch (e) {
          console.error('[fetch-inflation] TÜFE push başarısız:', e);
          push = { ok: false, reason: 'push hatasi' };
        }
      }
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
      push,
    });
  } catch (error) {
    // Ayrıntı günlüğe; yanıtta `error.message` dönmek tablo/secret adlarını
    // sızdırır (CLAUDE.md sunucu kuralı).
    console.error('[fetch-inflation] hata:', error);
    return jsonResponse({ error: 'Enflasyon guncellemesi basarisiz.' }, 500);
  }
});
