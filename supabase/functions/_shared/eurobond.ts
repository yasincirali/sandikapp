// Eurobond piyasa verisi — kaynak ayrıştırıcıları ve sözleşme aritmetiği
//
// ── Karar (2026-10-08, yasin: "varlık tiplerimize eurobond … eklemeliyiz,
//    performanslı ve ücretsiz kaynaklardan anlık ve zaman aralığına göre") ──
// Türk eurobondları için ücretsiz, resmî bir API yok (TCMB/EVDS'de seri yok,
// BIST yalnızca endeks yayımlıyor). GitHub koşucusundan ölçülen iki kaynak
// birlikte kullanılır (`tool/kaynak_olcum.py`, 5/5 başarı):
//
//   · Börse Frankfurt (api.boerse-frankfurt.de, anahtarsız)
//       price_information/single → son TEMİZ fiyat, önceki kapanış  (~1,1 sn)
//       tradingview/symbols      → ad: "Türkei, Republik 9,875% 22/28" → kupon
//       tradingview/history      → günlük/saatlik OHLC, ~5 yıl       (~0,9 sn)
//     Fiyat ve grafik AYNI kaynaktan: ekrandaki fiyat ile grafik aynı
//     ölçekte (fiyat kaynağı sözleşmesi madde 2).
//
//   · Ziraat Bankası eurobond tablosu (HTML, ~1,6 sn)
//       ISIN, vade, döviz, banka alış/satış fiyatı ve getirisi — 37 Hazine
//       eurobondu. Katalogun (hangi ISIN'ler var, vade günü) ve "bankaya
//       satarsan" fiyatının kaynağı.
//
// ⚠️ Ziraat'in fiyatları KİRLİ fiyattır (işlemiş faiz dahil). Ölçümde
// Frankfurt temiz + 30/360 işlemiş faiz, Ziraat alış ile satışının tam
// ortasına düştü (DF45: 103,95 + 2,28 = 106,23 ↔ 105,60 / 107,20). İki
// kaynağı karıştıran her hesap bunu bilmeli; bilmezse değer ~2 puan şişer.
//
// İstemci eşi: `lib/models/eurobond.dart` (aynı aritmetik, Dart).

export const EUROBOND_ONEKI = 'EUROBOND:';

export const ZIRAAT_URL = 'https://www.ziraatbank.com.tr/tr/bireysel/yatirim/eurobond';
export const BF_API = 'https://api.boerse-frankfurt.de/v1';

/// Tarayıcı kimliği: Ziraat ve Frankfurt bot kimliğine farklı sayfa
/// dönebiliyor; ölçüm bu kimlikle yapıldı.
export const TARAYICI_UA =
  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/128.0 Safari/537.36';

// ── ISIN ────────────────────────────────────────────────────────────────────

const ISIN_DESENI = /^[A-Z]{2}[A-Z0-9]{9}[0-9]$/;

/// ISO 6166 kontrol hanesi (Luhn). Dart eşi: `isinGecerli`.
export function isinGecerli(isin: string): boolean {
  const s = isin.trim().toUpperCase();
  if (!ISIN_DESENI.test(s)) return false;
  let rakamlar = '';
  for (const c of s) {
    const k = c.charCodeAt(0);
    rakamlar += k >= 48 && k <= 57 ? c : String(k - 55);
  }
  let toplam = 0;
  let cift = false;
  for (let i = rakamlar.length - 1; i >= 0; i--) {
    let n = rakamlar.charCodeAt(i) - 48;
    if (cift) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    toplam += n;
    cift = !cift;
  }
  return toplam % 10 === 0;
}

// ── Sayı / tarih ────────────────────────────────────────────────────────────

/// "102,072958" / "1.234,5" → sayı; çözülemezse null (uydurma yok).
export function trSayi(s: string): number | null {
  const t = s.trim().replace(/\./g, '').replace(',', '.');
  if (!/^-?\d+(\.\d+)?$/.test(t)) return null;
  const n = Number(t);
  return Number.isFinite(n) ? n : null;
}

/// "15.01.2028" → "2028-01-15"; geçersizse null.
export function trTarih(s: string): string | null {
  const m = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(s.trim());
  if (!m) return null;
  const [, g, a, y] = m;
  const d = new Date(Date.UTC(Number(y), Number(a) - 1, Number(g)));
  if (d.getUTCDate() !== Number(g) || d.getUTCMonth() !== Number(a) - 1) return null;
  return `${y}-${a}-${g}`;
}

// ── Ziraat tablosu ──────────────────────────────────────────────────────────

export interface BankaSatiri {
  isin: string;
  vade: string; // YYYY-MM-DD
  para_birimi: 'USD' | 'EUR';
  /// Banka alış fiyatı — KİRLİ, 100 nominal başına. "Bankaya satarsan".
  banka_alis: number;
  banka_alis_getiri: number | null;
  banka_satis: number;
  banka_satis_getiri: number | null;
}

function hucreler(tr: string): string[] {
  const out: string[] = [];
  for (const m of tr.matchAll(/<t[hd][^>]*>([\s\S]*?)<\/t[hd]>/gi)) {
    out.push(
      m[1].replace(/<[^>]+>/g, '').replace(/&nbsp;/g, ' ').replace(/\s+/g, ' ').trim(),
    );
  }
  return out;
}

/// Ziraat "Eurobond Oranları" tablosu → satırlar.
///
/// Sütunlar (2026-10-08): Kıymet Adı | Vade | Vadeye Kalan Gün | Döviz |
/// Alış Fiyatı | Alış Oranı | Satış Fiyatı | Satış Oranı. Başlık satırı
/// sütun SIRASINI doğrulamak için okunur: sıra değişirse tablo hiç
/// okunmaz (yanlış sütunu fiyat diye yazmaktansa boş dönmek).
export function ziraatTablosunuCoz(html: string): BankaSatiri[] {
  const satirlar = [...html.matchAll(/<tr[^>]*>([\s\S]*?)<\/tr>/gi)].map((m) => hucreler(m[1]));
  const baslik = satirlar.find((h) => h[0]?.startsWith('Kıymet'));
  if (!baslik) return [];
  const beklenen = ['Vade', 'Vadeye Kalan Gün', 'Döviz', 'Alış Fiyatı', 'Alış Oranı', 'Satış Fiyatı', 'Satış Oranı'];
  if (beklenen.some((b, i) => baslik[i + 1] !== b)) return [];

  const out: BankaSatiri[] = [];
  for (const h of satirlar) {
    if (h.length < 8 || !isinGecerli(h[0])) continue;
    const vade = trTarih(h[1]);
    const doviz = h[3].toUpperCase();
    const alis = trSayi(h[4]);
    const satis = trSayi(h[6]);
    if (!vade || (doviz !== 'USD' && doviz !== 'EUR') || alis === null || satis === null) continue;
    if (alis <= 0 || satis <= 0 || satis < alis) continue;
    const getiri = (s: string) => {
      const n = trSayi(s);
      // Vadesine bir gün kalan tahvilde banka "128,57" gibi anlamsız
      // oran yazıyor; %50 üstü getiri gösterilmez.
      return n === null || n <= 0 || n > 50 ? null : n / 100;
    };
    out.push({
      isin: h[0].toUpperCase(),
      vade,
      para_birimi: doviz,
      banka_alis: alis,
      banka_alis_getiri: getiri(h[5]),
      banka_satis: satis,
      banka_satis_getiri: getiri(h[7]),
    });
  }
  return out;
}

// ── Börse Frankfurt ─────────────────────────────────────────────────────────

export interface TahvilAdi {
  kupon_orani: number; // 0.09875
  ihrac_yili: number; // 2022
  vade_yili: number; // 2028
}

/// "Türkei, Republik 9,875% 22/28" → kupon ve yıllar. Biçim tutmazsa null.
export function bfAdiniCoz(ad: string): TahvilAdi | null {
  const m = /(\d{1,2}(?:,\d{1,4})?)\s?%\s?(\d{2})\/(\d{2})\s*$/.exec(ad.trim());
  if (!m) return null;
  const kupon = trSayi(m[1]);
  if (kupon === null || kupon <= 0 || kupon > 30) return null;
  return {
    kupon_orani: Math.round(kupon * 1e4) / 1e6,
    ihrac_yili: 2000 + Number(m[2]),
    vade_yili: 2000 + Number(m[3]),
  };
}

export interface PiyasaFiyati {
  temiz_fiyat: number;
  onceki_kapanis: number | null;
  piyasa_zamani: string | null;
}

/// price_information/single yanıtı → temiz fiyat. Yüzde kote değilse
/// (`tradedInPercent` false) ya da fiyat yoksa null.
export function bfFiyatiniCoz(j: unknown): PiyasaFiyati | null {
  if (!j || typeof j !== 'object') return null;
  const o = j as Record<string, unknown>;
  if (o.tradedInPercent !== true) return null;
  const son = typeof o.lastPrice === 'number' ? o.lastPrice : null;
  if (son === null || !(son > 0)) return null;
  const onceki = typeof o.closingPricePrevTradingDay === 'number' &&
      o.closingPricePrevTradingDay > 0
    ? o.closingPricePrevTradingDay
    : null;
  const t = typeof o.timestampLastPrice === 'string' ? o.timestampLastPrice : null;
  return {
    temiz_fiyat: son,
    onceki_kapanis: onceki,
    piyasa_zamani: t && !Number.isNaN(Date.parse(t)) ? new Date(t).toISOString() : null,
  };
}

/// tradingview/history yanıtı → [[ms, kapanış]] eski→yeni. `s` 'ok'
/// değilse ya da diziler tutarsızsa boş.
export function bfGecmisiniCoz(j: unknown): [number, number][] {
  if (!j || typeof j !== 'object') return [];
  const o = j as Record<string, unknown>;
  if (o.s !== 'ok' || !Array.isArray(o.t) || !Array.isArray(o.c)) return [];
  const t = o.t as unknown[];
  const c = o.c as unknown[];
  if (t.length !== c.length) return [];
  const out: [number, number][] = [];
  for (let i = 0; i < t.length; i++) {
    const ts = t[i], v = c[i];
    if (typeof ts === 'number' && typeof v === 'number' && v > 0) out.push([ts * 1000, v]);
  }
  return out.sort((a, b) => a[0] - b[0]);
}

// ── Grafik isteği ───────────────────────────────────────────────────────────
// Aralık ve dönem adları Yahoo'nunkiyle aynı (kripto-seri gibi): istemcinin
// `HistoryService` çözünürlük katmanı değişmeden çalışır. Frankfurt yalnız
// 15, 60 dakika ve gün çözünürlüğü verir (tradingview/symbols
// `supported_resolutions`); daha ince istek en yakına yuvarlanır.

const DONEM_GUN: Record<string, number> = {
  '1d': 1, '5d': 5, '1mo': 31, '3mo': 92, '6mo': 183, 'ytd': 366, '1y': 366, '2y': 731, '5y': 1827, 'max': 3653,
};

export interface SeriIstegi {
  isin: string;
  aralik: string;
  donem: string;
}

export function seriIstegiCoz(body: unknown): SeriIstegi | null {
  if (!body || typeof body !== 'object') return null;
  const o = body as Record<string, unknown>;
  const isin = typeof o.isin === 'string' ? o.isin.trim().toUpperCase() : '';
  const aralik = typeof o.aralik === 'string' ? o.aralik : '1d';
  const donem = typeof o.donem === 'string' ? o.donem : '1y';
  if (!isinGecerli(isin) || !(donem in DONEM_GUN)) return null;
  if (!/^(1m|2m|5m|15m|30m|60m|90m|1h|1d|1wk|1mo)$/.test(aralik)) return null;
  return { isin, aralik, donem };
}

/// Yahoo aralığı → Frankfurt çözünürlüğü.
export function bfCozunurluk(aralik: string): '15' | '60' | '1D' {
  if (['1m', '2m', '5m', '15m', '30m'].includes(aralik)) return '15';
  if (['60m', '90m', '1h'].includes(aralik)) return '60';
  return '1D';
}

/// `1d` dönemi "son 24 saat" DEĞİL, SON SEANSI kapsayan geriye bakıştır.
///
/// ## Neden (seri denetimi, 2026-10-08)
/// İstemcinin GÜNLÜK yolları (`HistoryService.getPortfolioHistoryHourly…`,
/// `getSymbolHistory` + `clipToPeriod`) Yahoo'nun `range=1d` anlamına
/// dayanır: piyasa kapalıyken yanıt SON SEANSA aittir, gün başı o seansın
/// kapanışıyla kurulur. Frankfurt'a ise `from = şimdi − 24 saat` ile
/// gidiliyordu. Pazartesi 09:00'da pencere Pazar sabahından başlıyor ve
/// HİÇ nokta dönmüyordu; seyrek işlem gören tahvilde (ölçüm: DG28, üç
/// günde ~20 bar) hafta içi de boş dönebiliyordu. Boş seri istemcide
/// `currentPrice` tohumuna düşüyor ve tür "gün içi veri alınamadı"
/// notuyla işaretleniyordu — veri VARKEN.
///
/// 5 gün: hafta sonu + bir resmî tatil zincirini kapsar. Fazla gelen eski
/// noktalar zararsızdır: gün içi motoru bugünün ızgarasında yalnızca
/// "bu andan önceki son fiyatı" okur, sembol yolu da son noktanın gününe
/// kırpar. Bu Yahoo'nun `1d` yanıtıyla aynı sözleşmedir; nokta UYDURULMAZ.
export const SON_SEANS_GERIYE_GUN = 5;

export function seriBaslangici(donem: string, simdiMs: number): number {
  if (donem === 'ytd') {
    const y = new Date(simdiMs).getUTCFullYear();
    return Date.UTC(y, 0, 1);
  }
  if (donem === '1d') return simdiMs - SON_SEANS_GERIYE_GUN * 86_400_000;
  return simdiMs - (DONEM_GUN[donem] ?? 366) * 86_400_000;
}

export const seriAnahtari = (i: SeriIstegi) => `${i.isin}|${bfCozunurluk(i.aralik)}|${i.donem}`;

/// Önbellek ömrü: gün içi 15 dk, günlük 6 saat (eurobond kapanışı günde
/// bir anlam değiştirir; Frankfurt seansı 08:00–17:30 CET).
export function seriTtlMs(aralik: string): number {
  return bfCozunurluk(aralik) === '1D' ? 6 * 3_600_000 : 15 * 60_000;
}

// ── Sözleşme aritmetiği (Dart eşi `EurobondSozlesmesi`) ─────────────────────

/// Kupon sıklığı: Ziraat'in tablosu "USD eurobondlarda kupon 6 ayda bir,
/// EUR eurobondlarda yılda bir" diyor (İngilizce sayfa, 2026-10-08).
export const kuponSikligi = (paraBirimi: 'USD' | 'EUR') => (paraBirimi === 'USD' ? 2 : 1);

/// Kataloğa yazılacak okunur ad: "Türkiye %9,875 2028".
export function tahvilAdi(kupon: number, vade: string): string {
  const yuzde = (kupon * 100).toLocaleString('tr-TR', { maximumFractionDigits: 3 });
  return `Türkiye %${yuzde} ${vade.slice(0, 4)}`;
}

// ── İşlemiş faiz ve kirli fiyat (Dart eşi `EurobondSozlesmesi`) ─────────────
//
// ## Neden sunucuda da (seri denetimi, 2026-10-08)
// Uygulama eurobondu 1 NOMİNAL birimin KİRLİ değeriyle (kirli/100, tahvilin
// para biriminde) fiyatlar: `PriceService._fetchEurobond`, grafik
// `_eurobondSerisi`. Sunucu işleri (kilit ekranı ileri taşıması, takip
// hareketi, yarış snapshot'ı) aynı sayıyı üretemiyordu: `EUROBOND:` sembolü
// Yahoo'ya düşüyor ve hiç fiyatlanmıyordu. Temiz fiyatı olduğu gibi
// kullanmak da yanlış olurdu — iki ölçek (temiz %, kirli/100) arasında hem
// 100 kat hem işlemiş faiz kadar fark var.
//
// Aritmetik Dart'ınkiyle BİREBİR (aynı test vektörleri
// `supabase/tests/eurobond_test.ts` ↔ `test/eurobond_test.dart`). Biri
// değişirse öteki de değişmeli; ayrışırsa kilit ekranı ile uygulama farklı
// değer yazar.

export interface EurobondSozlesmesi {
  isin: string;
  para_birimi: 'USD' | 'EUR';
  kupon_orani: number;
  /// UTC gece yarısı (ms).
  vade: number;
  ihrac_tarihi: number;
  yillik_kupon_sayisi: 1 | 2;
  gun_sayimi: '30/360' | 'act/act';
}

/// `eurobond_katalog` satırı → sözleşme; eksik/bozuk satır null (Dart eşi
/// `eurobondSozlesmesiFromMap`). Kuponsuz tahvile işlemiş faiz uydurulmaz.
export function sozlesmeSatiri(r: Record<string, unknown>): EurobondSozlesmesi | null {
  const isin = typeof r.isin === 'string' ? r.isin.toUpperCase() : '';
  const kupon = Number(r.kupon_orani);
  const vadeM = typeof r.vade === 'string' ? /^(\d{4})-(\d{2})-(\d{2})/.exec(r.vade) : null;
  const para = r.para_birimi;
  const siklik = Number(r.kupon_sikligi);
  if (!isinGecerli(isin) || !Number.isFinite(kupon) || kupon <= 0 || !vadeM) return null;
  if ((para !== 'USD' && para !== 'EUR') || (siklik !== 1 && siklik !== 2)) return null;
  const vy = Number(vadeM[1]), va = Number(vadeM[2]), vg = Number(vadeM[3]);
  const ihracYili = Number.isFinite(Number(r.ihrac_yili)) && r.ihrac_yili != null
    ? Number(r.ihrac_yili)
    : vy - 10;
  return {
    isin,
    para_birimi: para,
    kupon_orani: kupon,
    vade: Date.UTC(vy, va - 1, vg),
    // Dart: `DateTime.utc(ihracYili, vade.month, vade.day)` — aynı taşma.
    ihrac_tarihi: Date.UTC(ihracYili, va - 1, vg),
    yillik_kupon_sayisi: siklik,
    gun_sayimi: para === 'EUR' ? 'act/act' : '30/360',
  };
}

const GUN_MS = 86_400_000;

/// Ay ekler; hedef ayda o gün yoksa ayın son günü (Dart `_ayEkle`).
function ayEkle(ms: number, ay: number): number {
  const d = new Date(ms);
  const toplam = d.getUTCFullYear() * 12 + d.getUTCMonth() + ay;
  const y = Math.floor(toplam / 12);
  const m = toplam - y * 12; // 0..11
  const sonGun = new Date(Date.UTC(y, m + 1, 0)).getUTCDate();
  return Date.UTC(y, m, Math.min(d.getUTCDate(), sonGun));
}

/// 30/360 (ABD, "bond basis") gün sayısı (Dart `_gun30360`).
function gun30360(a: number, b: number): number {
  const da = new Date(a), db = new Date(b);
  let d1 = da.getUTCDate(), d2 = db.getUTCDate();
  if (d1 === 31) d1 = 30;
  if (d2 === 31 && d1 === 30) d2 = 30;
  return 360 * (db.getUTCFullYear() - da.getUTCFullYear()) +
    30 * (db.getUTCMonth() - da.getUTCMonth()) + (d2 - d1);
}

/// [gunUtc] (UTC gece yarısı) itibarıyla son ve sonraki kupon; vadeden
/// sonra null (Dart `kuponAraligi`).
export function kuponAraligi(
  s: EurobondSozlesmesi,
  gunUtc: number,
): { onceki: number; sonraki: number } | null {
  if (!(gunUtc < s.vade)) return null;
  const adim = 12 / s.yillik_kupon_sayisi;
  let sonraki = s.vade;
  for (let i = 1; i < 2000; i++) {
    const onceki = ayEkle(s.vade, -adim * i);
    if (!(gunUtc < onceki)) {
      return { onceki: onceki < s.ihrac_tarihi ? s.ihrac_tarihi : onceki, sonraki };
    }
    sonraki = onceki;
  }
  return null;
}

/// 100 nominal başına işlemiş faiz (fiyat puanı) — Dart `islemisFaiz`.
export function islemisFaiz(s: EurobondSozlesmesi, gunUtc: number): number {
  const a = kuponAraligi(s, gunUtc);
  if (a === null) return 0;
  const kupon = 100 * s.kupon_orani / s.yillik_kupon_sayisi;
  if (s.gun_sayimi === '30/360') {
    return kupon * gun30360(a.onceki, gunUtc) / (360 / s.yillik_kupon_sayisi);
  }
  const gecen = Math.round((gunUtc - a.onceki) / GUN_MS);
  const donem = Math.round((a.sonraki - a.onceki) / GUN_MS);
  return donem <= 0 ? 0 : kupon * gecen / donem;
}

/// [ms] anının İstanbul takvim günü, UTC gece yarısı olarak.
///
/// İstemci noktanın gününü cihaz saatiyle (TR) alır
/// (`DateTime.fromMillisecondsSinceEpoch`); sunucu aynı günü bulmalı, yoksa
/// 21:00 UTC sonrası noktalar bir günlük faiz farkıyla değerlenirdi.
export function istanbulGunu(ms: number): number {
  const [y, a, g] = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(new Date(ms)).split('-').map(Number);
  return Date.UTC(y, a - 1, g);
}

/// Temiz fiyat (% nominal) → 1 nominal birimin KİRLİ değeri (kirli/100) —
/// uygulamanın lot fiyatıyla AYNI ölçek (`PriceService._fetchEurobond`).
export function birimDeger(s: EurobondSozlesmesi, temiz: number, ms: number): number {
  return (temiz + islemisFaiz(s, istanbulGunu(ms))) / 100;
}
