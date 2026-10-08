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
  '1d': 1, '5d': 5, '1mo': 31, '3mo': 92, '6mo': 183, 'ytd': 366, '1y': 366, '2y': 731, '5y': 1827,
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

export function seriBaslangici(donem: string, simdiMs: number): number {
  if (donem === 'ytd') {
    const y = new Date(simdiMs).getUTCFullYear();
    return Date.UTC(y, 0, 1);
  }
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
