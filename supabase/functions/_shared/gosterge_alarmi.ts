// Gösterge alarmı — "THYAO EMA50'yi yukarı keserse haber ver" (0170,
// yasin 2026-10-29: "Gösterge ya da çizgiye değdiğinde push gelmesi
// yapılabilir mi?").
//
// Bu dosya gösterge alarmının SAF kısmı: kapsam, seviye hesabı ve seri
// önbelleği. Taraf değişimi, damga ve push `seviye_alarmi.ts`'te (çizgi
// alarmıyla ortak).
//
// ── Seviye: günlük kapanışlar + canlı fiyat ────────────────────────────────
// Göstergeler GÜNLÜK kapanışlardan hesaplanır; bugünün (TR günü) yarım
// çubuğu atılır, yerine canlı fiyat son nokta olur. Böylece "EMA50" hem
// uygulamanın günlük grafiğindeki çizgiyle aynı tanım (istemci
// `TechnicalAnalysisService.emaSeries`, tohum ilk `periyot` noktanın basit
// ortalaması, TÜM geçmiş üzerinden) hem de fiyatın şu anki konumunu görür.
// `technical_analysis.ts › ema()` yalnız son periyot×3 noktaya baktığı için
// burada kullanılmaz (EMA200'de ~%1'e varan fark).
//
// ── Kapsam (uydurma sayı yasak) ────────────────────────────────────────────
// Yalnız günlük serisi ve canlı fiyatı AYNI kaynaktan, aynı birimde gelen
// semboller. Altın ayarları ve TL dövizler HARİÇ: canlı fiyat truncgil'den,
// günlük seri Yahoo'dan (vadeli × kur); aradaki yapısal fark kesişim
// kararını sahte kılardı. Eurobond alarm kuramaz (`alarmSembolu`).
// İstemci eşi `FiyatKaynagi.gostergeAlarmiKapsamindaMi`.

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import { istanbulGunu } from './kripto.ts';
import { isFxSymbol, isGoldSymbol } from './live_prices.ts';
import { EUROBOND_ONEKI } from './eurobond.ts';
import { fetchGunlukNoktalar } from './price_history.ts';

export type GostergeKodu = 'ema20' | 'ema50' | 'ema200' | 'sma20' | 'bb_ust' | 'bb_alt';

export const GOSTERGELER: readonly GostergeKodu[] = [
  'ema20', 'ema50', 'ema200', 'sma20', 'bb_ust', 'bb_alt',
];

export function gostergeGecerli(g: string): g is GostergeKodu {
  return (GOSTERGELER as readonly string[]).includes(g);
}

/// Bollinger: standart (20, 2σ), nüfus standart sapması — istemcinin
/// `bollingerBands` formülüyle aynı bölen (/periyot). Türe göre değişen
/// sinyal varsayılanları (altında 14, dövizde 1,5σ) burada YOK: alarm
/// listede "Bollinger üst (20, 2σ)" diye okunur, tek tanım.
export const BB_PERIYOT = 20;
export const BB_CARPAN = 2;

/// Gösterge alarmı bu sembolde değerlendirilir mi.
export function gostergeAlarmKapsamindaMi(sembol: string): boolean {
  const s = sembol.trim();
  if (s.length === 0) return false;
  if (isGoldSymbol(s) || s.toUpperCase().startsWith('ALTIN_')) return false;
  if (isFxSymbol(s)) return false;
  if (s.toUpperCase().startsWith(EUROBOND_ONEKI)) return false;
  return true;
}

/// Tam geçmiş EMA'nın SON değeri. İstemci `emaSeries` ile birebir: ilk
/// [periyot] noktanın ortalamasıyla tohumlanır, sonra k = 2/(periyot+1).
/// Yetersiz veri → null (uydurma yok).
export function emaSon(kapanislar: number[], periyot: number): number | null {
  const n = kapanislar.length;
  if (periyot <= 0 || n < periyot) return null;
  let toplam = 0;
  for (let i = 0; i < periyot; i++) toplam += kapanislar[i];
  let ema = toplam / periyot;
  const k = 2 / (periyot + 1);
  for (let i = periyot; i < n; i++) ema = kapanislar[i] * k + ema * (1 - k);
  return Number.isFinite(ema) ? ema : null;
}

/// Son [periyot] noktanın basit ortalaması (istemci `smaSeries` son değeri).
export function smaSon(kapanislar: number[], periyot: number): number | null {
  const n = kapanislar.length;
  if (periyot <= 0 || n < periyot) return null;
  let toplam = 0;
  for (let i = n - periyot; i < n; i++) toplam += kapanislar[i];
  return toplam / periyot;
}

/// Bollinger bantlarının son değerleri.
export function bollingerSon(
  kapanislar: number[],
  periyot = BB_PERIYOT,
  carpan = BB_CARPAN,
): { orta: number; ust: number; alt: number } | null {
  const orta = smaSon(kapanislar, periyot);
  if (orta === null) return null;
  const son = kapanislar.slice(kapanislar.length - periyot);
  const varyans = son.reduce((a, p) => a + (p - orta) ** 2, 0) / periyot;
  const sapma = Math.sqrt(varyans);
  return { orta, ust: orta + carpan * sapma, alt: orta - carpan * sapma };
}

/// Göstergenin seviyesi; veri yetmiyorsa null.
export function gostergeSeviyesi(kod: string, kapanislar: number[]): number | null {
  switch (kod) {
    case 'ema20': return emaSon(kapanislar, 20);
    case 'ema50': return emaSon(kapanislar, 50);
    case 'ema200': return emaSon(kapanislar, 200);
    case 'sma20': return smaSon(kapanislar, 20);
    case 'bb_ust': return bollingerSon(kapanislar)?.ust ?? null;
    case 'bb_alt': return bollingerSon(kapanislar)?.alt ?? null;
    default: return null;
  }
}

/// Bildirimde okunan ad: "EMA50", "Bollinger üst bandı (20, 2σ)".
export function gostergeAdi(kod: string): string {
  switch (kod) {
    case 'ema20': return 'EMA20';
    case 'ema50': return 'EMA50';
    case 'ema200': return 'EMA200';
    case 'sma20': return 'MA20';
    case 'bb_ust': return 'Bollinger üst bandı';
    case 'bb_alt': return 'Bollinger alt bandı';
    default: return kod;
  }
}

/// Günlük noktalar + canlı fiyat → hesaba girecek kapanış dizisi.
///
/// Bugünün (TR günü) çubuğu varsa atılır, canlı fiyat sona eklenir. Canlı
/// fiyat yoksa ya da seri yoksa null: canlıyı bilmeden "şu an kesti"
/// denmez. Seri bayatsa (son kapanış 7 günden eski — tatil haftası dahil
/// pay) null: haftalar önceki seriye bugünün fiyatını eklemek ortalamayı
/// sessizce yanlış kurardı.
export function canliIleKapanislar(
  noktalar: Array<[number, number]>,
  canli: number | undefined,
  simdiMs: number,
): number[] | null {
  if (canli === undefined || !Number.isFinite(canli) || canli <= 0) return null;
  const bugun = istanbulGunu(new Date(simdiMs));
  const temiz = noktalar.filter(([t, v]) =>
    Number.isFinite(t) && Number.isFinite(v) && v > 0 && t <= simdiMs
  );
  const gecmis = temiz.filter(([t]) => istanbulGunu(new Date(t)) < bugun);
  if (gecmis.length === 0) return null;
  const sonT = gecmis[gecmis.length - 1][0];
  if (simdiMs - sonT > 7 * 24 * 60 * 60 * 1000) return null;
  return [...gecmis.map((p) => p[1]), canli];
}

// ── Seri önbelleği (0170 `gosterge_seri_onbellegi`) ─────────────────────────

/// Önbellek ömrü: günlük kapanış gün içinde değişmez; 3 saat, sabah ilk
/// turda dünkü kapanışın gelmesine yeter. Ayrıca önbellek bugünden önce
/// yazıldıysa (gün dönümü) tazelenir — dünkü kapanış eksik kalmasın.
export const GOSTERGE_SERI_TTL_MS = 3 * 60 * 60 * 1000;

export function onbellekTaze(fetchedAtMs: number, simdiMs: number): boolean {
  if (!Number.isFinite(fetchedAtMs)) return false;
  if (simdiMs - fetchedAtMs >= GOSTERGE_SERI_TTL_MS) return false;
  return istanbulGunu(new Date(fetchedAtMs)) === istanbulGunu(new Date(simdiMs));
}

/// Sembol başına 2 yıllık günlük nokta. Önbellek → yoksa ağ (sınırlı
/// paralel) → önbelleğe yaz. Ağ boş dönerse bayat önbellek son çare
/// (sinyal önbelleğiyle aynı kural); o da yoksa sembol haritada yok.
export async function gunlukSeriler(
  admin: SupabaseClient,
  semboller: string[],
  simdiMs: number,
  cek: (s: string) => Promise<Array<[number, number]>> = (s) => fetchGunlukNoktalar(admin, s),
): Promise<Map<string, Array<[number, number]>>> {
  const out = new Map<string, Array<[number, number]>>();
  if (semboller.length === 0) return out;
  const bayat = new Map<string, Array<[number, number]>>();
  const { data, error } = await admin
    .from('gosterge_seri_onbellegi')
    .select('symbol, zamanlar, kapanislar, fetched_at')
    .in('symbol', semboller);
  if (error) console.error('[gosterge-alarmi] onbellek okunamadi:', error.code);
  for (const r of (data ?? []) as Array<Record<string, unknown>>) {
    const z = (r.zamanlar as unknown[]) ?? [];
    const k = (r.kapanislar as unknown[]) ?? [];
    const noktalar: Array<[number, number]> = [];
    for (let i = 0; i < Math.min(z.length, k.length); i++) {
      noktalar.push([Number(z[i]), Number(k[i])]);
    }
    const s = String(r.symbol);
    if (onbellekTaze(Date.parse(String(r.fetched_at)), simdiMs)) out.set(s, noktalar);
    else bayat.set(s, noktalar);
  }
  const eksik = semboller.filter((s) => !out.has(s));
  const yazilacak: Array<Record<string, unknown>> = [];
  const PARALEL = 6;
  for (let i = 0; i < eksik.length; i += PARALEL) {
    const grup = eksik.slice(i, i + PARALEL);
    const sonuc = await Promise.all(grup.map(async (s) => [s, await cek(s)] as const));
    for (const [s, noktalar] of sonuc) {
      if (noktalar.length > 0) {
        out.set(s, noktalar);
        yazilacak.push({
          symbol: s,
          zamanlar: noktalar.map((p) => Math.round(p[0])),
          kapanislar: noktalar.map((p) => p[1]),
          fetched_at: new Date(simdiMs).toISOString(),
        });
      } else {
        const b = bayat.get(s);
        if (b && b.length > 0) out.set(s, b);
      }
    }
  }
  if (yazilacak.length > 0) {
    const { error: e } = await admin
      .from('gosterge_seri_onbellegi')
      .upsert(yazilacak, { onConflict: 'symbol' });
    if (e) console.error('[gosterge-alarmi] onbellek yazilamadi:', e.code);
  }
  return out;
}
