// Kilit ekranı (Live Activity) — uygulama KAPALIYKEN dakikalık ileri taşıma.
//
// ## Neden (kullanıcı kararı 2026-10-03: "Canlı aktiviteler her zaman 1 dk'da
// bir performans günlükle eş olmalı")
// Uygulama arkaya alınınca iOS süreci askıya alır; kilit ekranını yalnızca
// `push-live-activity` tazeler. O fonksiyon istemcinin SON yazdığı metni
// 5 dakikada bir olduğu gibi basıyordu: rakam donuyor, yalnızca saat
// ilerliyordu. Kullanıcı uygulamayı açınca Performans GÜNLÜK başka, kilit
// ekranı başka rakam gösteriyordu.
//
// ## Ne yapar
// İstemci özetle birlikte bir TARİF yazar (`lib/services/
// canli_etkinlik_tarifi.dart`): portföy değerinin kotasyona bağlı parçaları,
// gün içi serinin canlı uçtan önceki hâli, açılış damgası ve nakit akışları.
// Buradaki kod portföyü baştan DEĞERLEMEZ (o karar `push-live-activity`'de
// yazılı: ikinci kopya ayrışır); yalnızca parçalara kotasyon ORANI uygular
// ve gün içi değişimi `DailySummary.from` ile AYNI kurallarla yeniden kurar.
//
// Dart karşılıkları — biri değişirse diğeri de değişmeli; parite
// `supabase/tests/canli_etkinlik_parite.json` ile iki taraftan kilitli:
//   · gunlukDegerler     ↔ DailySummary.dayValues (canlı uç kuralı)
//   · paraAgirlikliPct   ↔ paraAgirlikliGetiriPct
//   · niceAxisBounds     ↔ DailySummary.niceAxisBounds
//   · normalizeSparkline ↔ DailySummary.normalizeForSparkline
//   · fmtTRY / fmtPct / fmtTRYAxis ↔ lib/utils/tr_format.dart

/// İstemcinin yazdığı tarif — `CanliEtkinlikTarifi.kur` çıktısı.
export interface Tarif {
  v: number;
  /// Tarifin yazıldığı gün (cihaz saatiyle `YYYY-MM-DD`).
  gun: string;
  yazildiMs: number;
  toplam: number;
  sabit: number;
  parcalar: Array<{ s: string; d: number; p: number; k?: string; kf?: number }>;
  acilisMs: number;
  akislar: Array<{ f: number; ms: number }>;
  /// Gün içi seri, canlı uç UYGULANMADAN önce (TRY).
  seri: number[];
  sonSlotMs: number;
  /// Günü sürükleyen pozisyon (goz_alici madde 4) — yalnız kullanıcı
  /// "Tutarları göster"i açtıysa yazılır. `a0` gün başı, `v` yazım anındaki
  /// değer (TRY); `i` varsa `parcalar[i]`'nin kotasyon oranı `v`'ye uygulanır.
  /// Alan ekleyerek geldi: sürüm aynı, eski istemcinin tarifinde yoktur.
  sr?: Surukleyen;
}

export interface Surukleyen {
  ad: string;
  a0: number;
  v: number;
  i?: number;
}

/// Kilit ekranının "günü sürükleyen" satırı — push gövdesine giden metinler.
export interface SurukleyenMetni {
  surukleyenAd: string;
  surukleyenPctText: string;
  surukleyenTutarText: string;
  surukleyenPozitif: boolean;
}

export const TARIF_SURUMU = 1;

/// Serinin ucu bu süreden eskiyse canlı değer son noktayı EZMEZ, eklenir —
/// `TazelikRitmi.canliUcAzamiGecikme`.
export const CANLI_UC_AZAMI_GECIKME_MS = 5 * 60_000;

/// `DailySummary.gunIciSlot`.
export const GUN_ICI_SLOT_MS = 5 * 60_000;

/// İstemci bu kadar yeni yazdıysa (uygulama büyük olasılıkla önde) sunucu
/// ileri TAŞIMAZ, yazılanı basar: ActivityKit'e uygulamanın kendi
/// güncellemesi zaten gidiyor; aynı dakikada farklı anın kotasyonuyla
/// hesaplanmış ikinci bir rakam kilit ekranında ileri geri oynardı.
export const TAZE_YAZIM_MS = 60_000;

/// Tek oranın kabul sınırı. BIST günlük limiti ±%10; bir dakikada bunun
/// iki katından büyük oran fiyat hareketi değil, ölçek/kaynak uyuşmazlığıdır
/// (yanlış sembol, birim değişikliği). O parça sabit kalır — uydurma yok.
export const ORAN_ALT = 0.8;
export const ORAN_UST = 1.25;

/// `gunIciAsgariBantOrani` (lib/utils/chart_axis.dart).
export const GUN_ICI_ASGARI_BANT_ORANI = 0.005;

/// İleri taşınmış özet — push gövdesinde yazılı metnin YERİNE geçer.
export interface IleriOzet {
  totalText: string;
  changeText: string;
  changePctText: string;
  isPositive: boolean;
  isFlatChange: boolean;
  sparkline: number[];
  axisMinText: string;
  axisMaxText: string;
  /// Tarifte sürükleyen varsa ve tutar gösterimi açıksa dolu.
  surukleyen: SurukleyenMetni | null;
}

/// Tarifte geçen bütün kotasyon sembolleri (parça + kur).
export function tarifSembolleri(t: Tarif): Set<string> {
  const out = new Set<string>();
  for (const p of t.parcalar) {
    out.add(p.s);
    if (p.k) out.add(p.k);
  }
  return out;
}

/// Gelen `summary.dakikalik` alanı kullanılabilir bir tarif mi? Saf.
export function tarifCoz(raw: unknown): Tarif | null {
  if (!raw || typeof raw !== 'object') return null;
  const t = raw as Record<string, unknown>;
  if (t.v !== TARIF_SURUMU) return null;
  const sayi = (x: unknown) => typeof x === 'number' && Number.isFinite(x);
  if (typeof t.gun !== 'string' || !sayi(t.yazildiMs) || !sayi(t.toplam)) return null;
  if (!sayi(t.sabit) || !sayi(t.acilisMs) || !sayi(t.sonSlotMs)) return null;
  if (!Array.isArray(t.parcalar) || !Array.isArray(t.akislar) || !Array.isArray(t.seri)) {
    return null;
  }
  if (t.seri.length === 0 || !t.seri.every(sayi)) return null;
  for (const p of t.parcalar as Array<Record<string, unknown>>) {
    if (typeof p?.s !== 'string' || !sayi(p.d) || !sayi(p.p) || (p.p as number) <= 0) {
      return null;
    }
    if (p.k !== undefined && (typeof p.k !== 'string' || !sayi(p.kf) || (p.kf as number) <= 0)) {
      return null;
    }
  }
  for (const a of t.akislar as Array<Record<string, unknown>>) {
    if (!sayi(a?.f) || !sayi(a?.ms)) return null;
  }
  // Sürükleyen İSTEĞE BAĞLI: bozuksa yalnız o düşer, toplam yine taşınır.
  if (t.sr !== undefined) {
    const r = t.sr as Record<string, unknown> | null;
    const parcaSayisi = (t.parcalar as unknown[]).length;
    const gecerli = !!r && typeof r === 'object' && typeof r.ad === 'string' &&
      r.ad.length > 0 && sayi(r.a0) && (r.a0 as number) > 0 && sayi(r.v) &&
      (r.i === undefined ||
        (Number.isInteger(r.i) && (r.i as number) >= 0 && (r.i as number) < parcaSayisi));
    if (!gecerli) {
      const { sr: _sr, ...geri } = t;
      return geri as unknown as Tarif;
    }
  }
  return t as unknown as Tarif;
}

/// İstanbul saatiyle bugünün `YYYY-MM-DD`'si.
export function istanbulGunMetni(simdi: Date): string {
  // en-CA: ISO sırası (YYYY-MM-DD). DST'yi runtime çözer.
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(simdi);
}

function oran(yeni: number | undefined, eski: number): number {
  if (yeni === undefined || !Number.isFinite(yeni) || yeni <= 0 || eski <= 0) return 1;
  const r = yeni / eski;
  return r >= ORAN_ALT && r <= ORAN_UST ? r : 1;
}

/// Tarifi [kotasyonlar] ile [simdiMs] anına taşır. Taşınamıyorsa `null` —
/// çağıran yazılı metni basar (eski davranış).
///
/// [bugun]: İstanbul saatiyle bugünün `YYYY-MM-DD`'si. Tarif başka güne
/// aitse taşınmaz: yeni günün açılışını yalnızca istemcinin serisi bilir.
export function ileriTasi(
  t: Tarif,
  kotasyonlar: Map<string, number>,
  simdiMs: number,
  bugun: string,
  tutarGoster: boolean,
): IleriOzet | null {
  if (t.gun !== bugun) return null;
  if (simdiMs - t.yazildiMs < TAZE_YAZIM_MS) return null;

  const parcaOrani = (p: Tarif['parcalar'][number]) => {
    let r = oran(kotasyonlar.get(p.s), p.p);
    if (p.k && p.kf) r *= oran(kotasyonlar.get(p.k), p.kf);
    return r;
  };
  let toplam = t.sabit;
  for (const p of t.parcalar) toplam += p.d * parcaOrani(p);
  if (!(toplam > 0)) return null;

  const degerler = gunlukDegerler(t.seri, t.sonSlotMs, simdiMs, toplam);
  if (degerler.length < 2) return null;
  const acilis = degerler[0];
  const son = degerler[degerler.length - 1];
  if (acilis <= 0) return null;

  let katki = 0;
  for (const a of t.akislar) katki += a.f;
  const tutar = (son - acilis) - katki;

  // Ağırlık push anına göre — `DailySummary.gunIciGetiriPct` ile aynı.
  const sure = simdiMs - t.acilisMs;
  const akislar = t.akislar.map((a) => ({
    f: a.f,
    w: sure <= 0 ? 0 : Math.min(1, Math.max(0, (simdiMs - a.ms) / sure)),
  }));
  const yuzde = paraAgirlikliPct(acilis, son, akislar);
  if (yuzde === null || !Number.isFinite(yuzde)) return null;

  // `DailySummary.isFlat` + `LiveActivityService._payload` sunumu.
  const duz = Math.abs(Math.round(tutar)) === 0 && Math.abs(yuzde) < 0.005;
  const pozitif = tutar >= 0;
  const changeText = duz
    ? fmtTRY(0, 2)
    : `${pozitif ? '+' : '-'}${fmtTRY(Math.abs(tutar), 2)}`;

  let axisMinText = '';
  let axisMaxText = '';
  if (tutarGoster) {
    const b = niceAxisBounds(degerler);
    const span = b.max - b.min;
    axisMinText = fmtTRYAxis(b.min, span);
    axisMaxText = fmtTRYAxis(b.max, span);
  }

  return {
    totalText: fmtTRY(toplam, 2),
    changeText,
    changePctText: fmtPct(Math.abs(yuzde), 2),
    isPositive: pozitif,
    isFlatChange: duz,
    sparkline: normalizeSparkline(degerler),
    axisMinText,
    axisMaxText,
    // Sürükleyen yalnız tutar gösterimi açıkken — gizlilik kapısı BURADA da.
    surukleyen: tutarGoster && t.sr
      ? surukleyenMetinleri(
        t.sr.ad,
        t.sr.a0,
        t.sr.v * (t.sr.i !== undefined ? parcaOrani(t.parcalar[t.sr.i]) : 1),
      )
      : null,
  };
}

/// `KilitSurukleyen.surukleyenMetinleri` (live_activity_service.dart) —
/// aynı vektörler iki tarafta test edilir. Yuvarlanınca sıfır olan değişim
/// satır üretmez.
export function surukleyenMetinleri(ad: string, a0: number, v: number): SurukleyenMetni | null {
  if (!(a0 > 0) || !Number.isFinite(v)) return null;
  const pct = (v / a0 - 1) * 100;
  if (!Number.isFinite(pct) || Math.abs(pct) < 0.005) return null;
  const tutar = v - a0;
  const pozitif = tutar >= 0;
  return {
    surukleyenAd: ad,
    surukleyenPctText: fmtPct(Math.abs(pct), 2),
    surukleyenTutarText: `${pozitif ? '+' : '-'}${fmtTRY(Math.abs(tutar), 0)}`,
    surukleyenPozitif: pozitif,
  };
}

/// İstemcinin özete yazdığı sürükleyen alanları (ileri taşınamayan satır).
export function satirSurukleyeni(row: Record<string, unknown>): SurukleyenMetni | null {
  const ad = row.surukleyenAd;
  if (typeof ad !== 'string' || ad.length === 0) return null;
  const pct = row.surukleyenPctText;
  const tutar = row.surukleyenTutarText;
  if (typeof pct !== 'string' || typeof tutar !== 'string') return null;
  return {
    surukleyenAd: ad,
    surukleyenPctText: pct,
    surukleyenTutarText: tutar,
    surukleyenPozitif: row.surukleyenPozitif !== false,
  };
}

/// `DailySummary.dayValues`'un canlı uç kuralı — seri zaten bugüne ait ve
/// baştaki sıfırlardan arındırılmış gelir.
export function gunlukDegerler(
  seri: number[],
  sonSlotMs: number,
  simdiMs: number,
  canliToplam: number,
): number[] {
  const out = seri.slice();
  if (out.length === 0) return out;
  if (canliToplam > 0) {
    if (simdiMs - sonSlotMs <= CANLI_UC_AZAMI_GECIKME_MS) out[out.length - 1] = canliToplam;
    else out.push(canliToplam);
  }
  return out;
}

/// `paraAgirlikliGetiriPct` — Modified Dietz tohumlu, bisection ile tam
/// para ağırlıklı getiri (%).
export function paraAgirlikliPct(
  bas: number,
  son: number,
  akislar: Array<{ f: number; w: number }>,
): number | null {
  let sermaye = bas;
  let katki = 0;
  for (const a of akislar) {
    sermaye += a.f * a.w;
    katki += a.f;
  }
  if (sermaye <= 0) return null;
  const piyasa = son - bas - katki;
  const dietz = piyasa / sermaye * 100;
  if (akislar.length === 0 || piyasa === 0 || bas <= 0) return dietz;

  const fark = (r: number) => {
    let v = bas * (1 + r);
    for (const a of akislar) v += a.f * Math.pow(1 + r, a.w);
    return v - son;
  };

  let lo = piyasa > 0 ? 0.0 : -0.999999;
  let hi = piyasa > 0 ? 1.0 : 0.0;
  if (piyasa > 0) {
    while (fark(hi) < 0 && hi < 1e6) hi *= 2;
  }
  const fLo = fark(lo);
  const fHi = fark(hi);
  if (!Number.isFinite(fLo) || !Number.isFinite(fHi) || Math.sign(fLo) === Math.sign(fHi)) {
    return dietz;
  }
  for (let i = 0; i < 200; i++) {
    const m = (lo + hi) / 2;
    if (Math.sign(fark(m)) === Math.sign(fLo)) lo = m;
    else hi = m;
  }
  const r = (lo + hi) / 2 * 100;
  if (!Number.isFinite(r) || Math.sign(r) !== Math.sign(piyasa)) return dietz;
  return r;
}

// ── Grafik ekseni + normalize (DailySummary) ─────────────────────────────

const TICK_COUNT = 4;

function niceStep(rough: number): number {
  if (rough <= 0) return 1;
  const exp = Math.floor(Math.log(rough) / Math.LN10);
  const pow10 = Math.pow(10, exp);
  const frac = rough / pow10;
  let niceFrac: number;
  if (frac <= 1) niceFrac = 1;
  else if (frac <= 2) niceFrac = 2;
  else if (frac <= 2.5) niceFrac = 2.5;
  else if (frac <= 5) niceFrac = 5;
  else niceFrac = 10;
  return niceFrac * pow10;
}

export function niceAxisBounds(
  values: number[],
  minSpanRatio = GUN_ICI_ASGARI_BANT_ORANI,
): { min: number; max: number } {
  if (values.length === 0) return { min: 0, max: 1 };
  const rawMin = Math.min(...values);
  const rawMax = Math.max(...values);
  const scale = Math.abs(rawMax);
  let span = Math.abs(rawMax - rawMin);
  const minSpan = scale * minSpanRatio;
  if (span < minSpan) span = minSpan;
  if (span <= 0) span = scale > 0 ? scale * minSpanRatio : 1;
  const padded = span * 1.25;
  const mid = (rawMax + rawMin) / 2;
  const step = niceStep(padded / TICK_COUNT);
  let lo = Math.floor((mid - padded / 2) / step) * step;
  let hi = Math.ceil((mid + padded / 2) / step) * step;
  while (lo > rawMin) lo -= step;
  while (hi < rawMax) hi += step;
  if (hi - lo < 1e-9) return { min: lo - 1, max: lo + 1 };
  return { min: lo, max: hi };
}

export function isVisuallyFlat(values: number[]): boolean {
  if (values.length < 2) return true;
  const minV = Math.min(...values);
  const maxV = Math.max(...values);
  const span = Math.abs(maxV - minV);
  const scale = Math.abs(maxV);
  if (scale < 1e-9) return span < 1e-9;
  return span / scale < 1e-6;
}

export function normalizeSparkline(values: number[]): number[] {
  if (values.length < 2) return [];
  if (isVisuallyFlat(values)) {
    return new Array(Math.min(Math.max(values.length, 2), 40)).fill(0.5);
  }
  const bounds = niceAxisBounds(values);
  const lo = bounds.min;
  const axisSpan = bounds.max - bounds.min;
  const maxPoints = 40;
  const step = values.length <= maxPoints ? 1 : Math.ceil(values.length / maxPoints);
  const out: number[] = [];
  for (let i = 0; i < values.length; i += step) out.push((values[i] - lo) / axisSpan);
  const lastNorm = (values[values.length - 1] - lo) / axisSpan;
  if (out.length === 0 || Math.abs(out[out.length - 1] - lastNorm) > 1e-9) out.push(lastNorm);
  return out;
}

// ── Türkçe biçim (lib/utils/tr_format.dart) ──────────────────────────────

/// `fmtNum`: `1.234,56`.
export function fmtNum(value: number, digits = 2): string {
  return new Intl.NumberFormat('tr-TR', {
    minimumFractionDigits: digits,
    maximumFractionDigits: digits,
    useGrouping: true,
  }).format(value);
}

/// `fmtTRY`: `₺1.234,56` / `-₺1.234,56`.
export function fmtTRY(value: number, digits = 0): string {
  return `${value < 0 ? '-' : ''}₺${fmtNum(Math.abs(value), digits)}`;
}

/// `fmtPct`: `%1,23`.
export function fmtPct(value: number, digits = 2): string {
  return `%${fmtNum(value, digits)}`;
}

function ayirtHanesi(olcekliAdim: number): number {
  if (!(olcekliAdim > 0) || !Number.isFinite(olcekliAdim)) return 0;
  return Math.ceil(-Math.log(olcekliAdim) / Math.LN10 - 1e-9);
}

/// `eksenGovdesi`.
export function eksenGovdesi(abs: number, span: number): string {
  const s = Math.abs(span);
  const buyukTaban = (olcekli: number) => (olcekli >= 0.02 ? 2 : olcekli >= 0.002 ? 3 : 4);
  const kademe = (bolen: number, ek: string, taban: number, tavan: number): string | null => {
    const hane = Math.max(taban, ayirtHanesi(s / bolen));
    if (hane > tavan) return null;
    return `${fmtNum(abs / bolen, hane)}${ek}`;
  };
  let kisa: string | null;
  if (abs >= 1e12) kisa = kademe(1e12, 'Tn', buyukTaban(s / 1e12), 4);
  else if (abs >= 1e9) kisa = kademe(1e9, 'Mr', buyukTaban(s / 1e9), 4);
  else if (abs >= 1e6) kisa = kademe(1e6, 'M', buyukTaban(s / 1e6), 4);
  else if (abs >= 1000) kisa = kademe(1000, 'K', s / 1000 >= 0.2 ? 1 : 2, 2);
  else kisa = null;
  if (kisa !== null) return kisa;
  const hane = Math.min(8, Math.max(0, Math.max(s < 10 ? 2 : 0, ayirtHanesi(s))));
  return fmtNum(abs, hane);
}

/// `fmtTRYAxis`.
export function fmtTRYAxis(value: number, span: number): string {
  return `${value < 0 ? '-' : ''}₺${eksenGovdesi(Math.abs(value), span)}`;
}
