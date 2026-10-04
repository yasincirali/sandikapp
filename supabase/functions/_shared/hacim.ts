// Hisse hacim radarı — SAF yardımcılar (Balina B2, 2026-10-04).
//
// `hacim-gozlem/index.ts` ağ + veritabanı işini yapar; buradaki fonksiyonlar
// `supabase/tests/hacim_test.ts` ile Yahoo'ya ve Postgres'e dokunmadan
// sınanır (emsal: `balina.ts`).
//
// ── Ne ölçülüyor ────────────────────────────────────────────────────────────
// Para hacmi = günlük işlem adedi × kapanış (TL). Bir günün para hacmi kendi
// son 20 işlem gününe göre olağandışı büyükse olay yazılır.
//
// ── Ne ölçülMÜYOR (etiket bu yüzden "olağandışı hacim") ────────────────────
// Kimin aldığı ya da sattığı bu veride YOK — o bilgi aracı kurum dağılımıdır
// ve lisans ister (B5). Her işlemin bir alıcısı ve bir satıcısı vardır;
// yüksek hacim "para girdi" demek DEĞİLDİR. Bu yüzden olay yönü akış değil
// FİYAT yönüdür ("yüksek hacimli yükseliş / düşüş") ve kart "balina" demez.
//
// ── Eşikler ─────────────────────────────────────────────────────────────────
// Üç koşul birden: sapma (z ≥ 3), kat (ortalamanın ≥ 2 katı) ve taban
// (≥ ₺50 mn). Yalnız z, hacmi çok düzenli bir hissede küçük bir artışı olay
// yapar; yalnız kat, sığ hissede her haber gününü. Taban, birkaç milyonluk
// işlemle "3 kat" olan tahtaları eler.

import { trGun } from './tefas_nav.ts';

/// Bir hissenin bir işlem günü.
export type HacimGunu = { tarih: string; kapanis: number; hacim: number };

/// Tespit edilen olay (`balina_olay` satırının hesaplanan alanları).
export type HacimOlayi = {
  tur: 'hisse_hacim_yukselis' | 'hisse_hacim_dusus';
  /// Günün para hacmi, TL (yön taşımaz; yön `tur`'da).
  tutar: number;
  /// Para hacmi / son 20 günün ortalaması.
  ortalama_kati: number;
  /// (hacim − ortalama) / standart sapma.
  sapma_kati: number;
  /// Günün kapanış değişimi (0,041 = +%4,1).
  fiyat_degisim: number;
};

/// Ortalama ve sapmanın hesaplandığı ÖNCEKİ işlem günü sayısı.
export const ORTALAMA_GUN = 20;
export const Z_ESIGI = 3;
export const KAT_ESIGI = 2;
/// Bundan küçük para hacmi olay olmaz (TL).
export const ASGARI_PARA_HACMI = 50_000_000;
/// Olayların üretildiği geriye dönük süre (takvim günü); kart 30 gün gösterir.
export const HACIM_OLAY_PENCERE_GUN = 40;

/// BIST hissesi mi? Uygulama hisseyi Yahoo sembolüyle saklar (`THYAO.IS`).
/// Yabancı hisse (TRY değil) kapsam dışı: para hacmi TL olmazdı.
export function bistSembolu(ticker: string): string | null {
  const t = String(ticker ?? '').trim().toUpperCase();
  return /^[A-Z0-9]{2,10}\.IS$/.test(t) ? t : null;
}

/// Yahoo `chart` yanıtındaki `result[0]`'dan günlük satırlar, eskiden yeniye.
///
/// Kapanışı ya da hacmi boş bar (tatil, eksik) ATILIR. Aynı güne iki bar
/// düşerse sonuncusu kalır (Yahoo seans içinde günün barını ayrıca verir).
export function yahooGunleri(result: unknown): HacimGunu[] {
  if (result === null || typeof result !== 'object') return [];
  const r = result as Record<string, unknown>;
  const ts = r.timestamp;
  const quote = (r.indicators as Record<string, unknown> | undefined)?.quote;
  const q = Array.isArray(quote) ? quote[0] as Record<string, unknown> : null;
  if (!Array.isArray(ts) || q === null) return [];
  const closes = Array.isArray(q.close) ? q.close : [];
  const vols = Array.isArray(q.volume) ? q.volume : [];

  const m = new Map<string, HacimGunu>();
  for (let i = 0; i < ts.length; i++) {
    const t = ts[i], c = closes[i], v = vols[i];
    if (typeof t !== 'number' || typeof c !== 'number' || typeof v !== 'number') continue;
    if (!Number.isFinite(t) || !(c > 0) || !(v >= 0)) continue;
    const tarih = trGun(new Date(t * 1000));
    m.set(tarih, { tarih, kapanis: c, hacim: v });
  }
  return [...m.values()].sort((a, b) => a.tarih.localeCompare(b.tarih));
}

/// Seansı BİTMEMİŞ günün barı çıkarılır: gün ortasındaki hacim yarımdır,
/// "ortalamanın altında" görünür ve akşam değişir. BIST sürekli işlem 18:00'de
/// biter, Yahoo 15 dk gecikmeli; 18:30 TR'den önce bugünün barı sayılmaz.
export function tamamlananGunler(gunler: HacimGunu[], simdi: Date): HacimGunu[] {
  const bugun = trGun(simdi);
  const saat = Number(new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Europe/Istanbul', hour: '2-digit', minute: '2-digit', hour12: false,
  }).format(simdi).replace(':', ''));
  const seansBitti = saat >= 1830;
  return gunler.filter((g) => g.tarih < bugun || (g.tarih === bugun && seansBitti));
}

export const paraHacmi = (g: HacimGunu) => Math.round(g.kapanis * g.hacim * 100) / 100;

/// [i]. gün olağandışı hacim günü mü? Önceki `ORTALAMA_GUN` işlem günü tam
/// değilse ya da sapma sıfırsa `null` — eşik tahmin edilmez.
export function hacimOlayi(gunler: HacimGunu[], i: number): HacimOlayi | null {
  if (i < ORTALAMA_GUN || i >= gunler.length) return null;
  const x = paraHacmi(gunler[i]);
  if (!(x >= ASGARI_PARA_HACMI)) return null;

  let toplam = 0;
  const onceki: number[] = [];
  for (let k = i - ORTALAMA_GUN; k < i; k++) {
    const p = paraHacmi(gunler[k]);
    onceki.push(p);
    toplam += p;
  }
  const ort = toplam / ORTALAMA_GUN;
  if (!(ort > 0)) return null;
  const varyans = onceki.reduce((s, p) => s + (p - ort) ** 2, 0) / (ORTALAMA_GUN - 1);
  const sapma = Math.sqrt(varyans);
  if (!(sapma > 0)) return null;

  const z = (x - ort) / sapma;
  const kat = x / ort;
  if (z < Z_ESIGI || kat < KAT_ESIGI) return null;

  const degisim = gunler[i].kapanis / gunler[i - 1].kapanis - 1;
  return {
    tur: degisim >= 0 ? 'hisse_hacim_yukselis' : 'hisse_hacim_dusus',
    tutar: x,
    ortalama_kati: Math.round(kat * 10) / 10,
    sapma_kati: Math.round(z * 10) / 10,
    fiyat_degisim: Math.round(degisim * 10000) / 10000,
  };
}
