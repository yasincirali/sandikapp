// Yarış snapshot'ları — SUNUCU tarafı günlük hesap (2026-09-28).
//
// ## Neden var
// `user_roi_snapshots` ve `user_allocation_snapshots` satırlarını eskiden
// yalnızca İSTEMCİ yazıyordu: opt-in yapmış kullanıcı Profil'deki yarış
// kartını ya da Yarış ekranını açınca. Küresel havuzun uygunluk kuralı
// (`leaderboard_eligible_users`, 0059) son 30 günde ≥5 farklı gün snapshot
// + son 24 saatte dağılım snapshot'ı ister; zirve portföyler RPC'si de
// ≥8 uygun kullanıcı (k_min). Onlarca portföy varken havuz 2 kişiydi —
// çünkü snapshot atmak kullanıcının o ekranı o gün açmasına bağlıydı.
// Kullanıcı kararı: snapshot'ı sunucu her gün, opt-in yapmış herkes için
// atar; havuz uygulama açılışına bağlı olmaktan çıkar.
//
// ## 2026-09-29: zirve havuzu beyana dayanmaz (0083)
// Portföyü olan HERKES ölçülür ve `zirve_*_snapshots` tablolarına yazılır
// (anonim, RLS kapalı kutu; yalnız RPC okur). Yarış tablolarına yine
// YALNIZ opt-in kullanıcılar yazılır — Yarış ekranının mekaniği değişmesin
// diye (`yazimPlani`). Aynı hesap iki yere gider; ikinci bir fiyat turu yok.
//
// ## Ne hesaplar
// Her kullanıcının (yarış tablosu için yalnız opt-in, 0081) AÇIK lotları
// (`_shared/positions.ts`, satış ve silme düşülmüş) bugünkü miktarlarıyla
// dönem başında ve bugün TL'ye değerlenir; ROI = (bugün − başlangıç) /
// başlangıç. İstemcinin yarış ROI'si de aynı tanımdır (`HistoryService`
// `simulate: true`: miktar dönem boyunca sabit, alım tarihi yok sayılır,
// yalnızca piyasa etkisi). Dağılım: bugünkü TL değerinin tür payı.
//
// ## Fiyat kaynağı
// `_shared/dated_history.ts` — Yahoo / TEFAS / Binance, tarihli. Altın:
// GC=F (USD/ons, 24 ayar) × USDTRY / 31,1035 → 24 ayar gram; ALTIN_*
// ağırlıkları 22 ayar grama göre olduğu için 1,0909'a bölünür. İstemci
// altında truncgil/XAUTRY kullanır (bkz. `fiyat_kaynagi.dart`); ORAN
// hesabında kaynak farkı iki uca da aynı uygulandığı için sönümlenir.
// Döviz/USD kote varlık: `<CUR>TRY=X` ile çevrilir. Elle fiyatlı varlık:
// iki uçta da `current_price` (getiriye etkisi sıfır, dağılımda var).
//
// ## Kapsama kuralı
// Fiyatı iki uçta da bulunan lotlar ROI'ye girer; bunlar bugünkü değerin
// %80'inden azını kapsıyorsa o dönem için satır YAZILMAZ (yarım portföy
// getirisi yanıltır — uydurma sayı yasağı). Dağılım için bugünkü fiyatı
// olanlar yeter.
//
// Güvenlik: `requireCronSecret` kalıbı (fail-closed), service role yalnızca
// burada; yanıt yalnızca sayılar taşır.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { acikPozisyonLotlari, pozisyonAnahtari, PozisyonLot } from '../_shared/positions.ts';
import { fiyatAninda, loadDatedHistories, Seri } from '../_shared/dated_history.ts';

const corsHeaders = {
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

export const DONEMLER = [7, 30, 180, 365] as const;
export const GUN_MS = 24 * 60 * 60 * 1000;
export const KAPSAMA_ESIGI = 0.8;

const GC_F = 'GC=F';
const USDTRY = 'USDTRY=X';
const ONS_GRAM = 31.1035;
/// ALTIN_* ağırlıkları 22 ayar gram tabanlıdır (`price_history.ts`); GC=F
/// 24 ayardır, gram22 = gram24 / 1,0909.
const GRAM24_BOLEN = 1.0909;

/// `price_history.ts › GOLD_WEIGHTS` ile aynı tablo (22 ayar gram = 1).
export const ALTIN_AGIRLIK: Record<string, number> = {
  ALTIN_GRAM: 1.0,
  ALTIN_CEYREK: 1.75,
  ALTIN_YARIM: 3.5,
  ALTIN_CUMHURIYET: 7.216,
  ALTIN_ATA: 7.216,
  ALTIN_RESAT: 7.216,
  ALTIN_GRAM24: 1.0909,
  ALTIN_HAS: 1.0909,
  ALTIN_18AYAR: 0.8182,
  ALTIN_14AYAR: 0.6364,
  ALTIN_TAM: 7.016,
  ALTIN_HAMIT: 7.216,
  ALTIN_IKIBUCUK: 18.04,
  ALTIN_GREMSE: 17.54,
  ALTIN_BESLI: 36.08,
};

/// İstemci `asset_categories.dart › goldTickerMap` ile aynı: alt kategori
/// adı → ALTIN_* kodu. Eski kayıtlarda `ticker` boş olabilir; ad buradan
/// çözülür.
export const ALTIN_ALT_KATEGORI: Record<string, string> = {
  'Gram Altın (24 Ayar)': 'ALTIN_GRAM24',
  '22 Ayar Gram Altın': 'ALTIN_GRAM',
  '18 Ayar Altın': 'ALTIN_18AYAR',
  '14 Ayar Altın': 'ALTIN_14AYAR',
  'Has Altın': 'ALTIN_HAS',
  'Çeyrek Altın': 'ALTIN_CEYREK',
  'Yarım Altın': 'ALTIN_YARIM',
  'Tam Altın': 'ALTIN_TAM',
  'Cumhuriyet Altını': 'ALTIN_CUMHURIYET',
  'Ata Altını': 'ALTIN_ATA',
  'Reşat Altını': 'ALTIN_RESAT',
  'Hamit Altını': 'ALTIN_HAMIT',
  'İkibuçuk Altın': 'ALTIN_IKIBUCUK',
  'Gremse Altın': 'ALTIN_GREMSE',
  'Beşli Altın': 'ALTIN_BESLI',
  'Altın (Ons)': 'XAUUSD=X',
};

export interface Lot extends PozisyonLot {
  is_manual_price?: boolean | null;
  current_price?: number | null;
}

/// Altın lotunun kodu: ticker ALTIN_* ise o; değilse alt kategori adından.
export function altinKodu(lot: Lot): string | null {
  const t = (lot.ticker ?? '').trim();
  if (t.startsWith('ALTIN_') || t === 'XAUUSD=X') return t;
  const sub = (lot.sub_category ?? '').trim();
  return ALTIN_ALT_KATEGORI[sub] ?? null;
}

function paraBirimi(lot: Lot): string {
  return (lot.currency ?? 'TRY').trim().toUpperCase() || 'TRY';
}

/// Fon kodu bazı kayıtlarda öneksiz ("AFT"); seri kaynağı `TEFAS:` ister.
/// İstemci eşi `lib/models/asset_type.dart` › `kanonikTicker` (okuma
/// sınırında, `Asset.fromSupabase`; 2026-09-29'a kadar istemcide YOKTU ve
/// öneksiz fon hiç fiyatlanmıyordu). İstemci bilerek daha dar: yalnızca
/// 3 harf/rakamlı TEFAS kodunu ve elle fiyatlı olmayan lot'u çevirir.
/// Diğer türlerde ticker olduğu gibi.
export function seriSembolu(lot: Lot): string {
  const t = (lot.ticker ?? '').trim();
  if (t === '') return '';
  if (lot.type === 'fon' && !t.startsWith('TEFAS:') && !t.includes(':')) {
    return `TEFAS:${t.toUpperCase()}`;
  }
  return t;
}

/// Lotun değerlenmesi için gereken seriler. Elle fiyatlı lot hiçbir seri
/// istemez.
export function lotSembolleri(lot: Lot): string[] {
  if (lot.is_manual_price === true) return [];
  if (lot.type === 'altin') {
    const kod = altinKodu(lot);
    if (kod === null) return [];
    if (kod === 'XAUUSD=X') return ['XAUUSD=X', USDTRY];
    return [GC_F, USDTRY];
  }
  const t = seriSembolu(lot);
  if (t === '') return [];
  const out = [t];
  const cur = paraBirimi(lot);
  if (cur !== 'TRY') out.push(`${cur}TRY=X`);
  return out;
}

/// Lotun `t` anındaki BİRİM TL fiyatı; hesaplanamıyorsa null.
export function lotTryFiyati(
  lot: Lot,
  seriler: Map<string, Seri>,
  tMs: number,
): number | null {
  if (lot.is_manual_price === true) {
    const p = Number(lot.current_price ?? 0);
    return Number.isFinite(p) && p > 0 ? p : null;
  }
  const fiyat = (s: string) => {
    const seri = seriler.get(s);
    return seri ? fiyatAninda(seri, tMs) : null;
  };
  if (lot.type === 'altin') {
    const kod = altinKodu(lot);
    if (kod === null) return null;
    const kur = fiyat(USDTRY);
    if (kur === null) return null;
    if (kod === 'XAUUSD=X') {
      const ons = fiyat('XAUUSD=X');
      return ons === null ? null : ons * kur;
    }
    const agirlik = ALTIN_AGIRLIK[kod];
    if (agirlik === undefined) return null;
    const gc = fiyat(GC_F);
    if (gc === null) return null;
    const gram22 = gc * kur / ONS_GRAM / GRAM24_BOLEN;
    return gram22 * agirlik;
  }
  const t = seriSembolu(lot);
  if (t === '') return null;
  const p = fiyat(t);
  if (p === null) return null;
  const cur = paraBirimi(lot);
  if (cur === 'TRY') return p;
  const kur = fiyat(`${cur}TRY=X`);
  return kur === null ? null : p * kur;
}

/// Açık pozisyonları NET miktarlı tek lota indirger.
///
/// `acikPozisyonLotlari` bir FİLTREDİR: pozisyon açıksa onun bütün alım
/// lotlarını döndürür, satışı lot miktarından düşmez (push için "açık mı"
/// yeter). Değerleme için yanlış: 1000+620+620 alım, 1620 satış → 620 net,
/// ama üç lot toplamı 2240 sayılırdı (a968, 2026-09-29 kuru koşu). İstemci
/// `aggregatePositions` net = Σbuy − Σsell ile tek görünüm kurar; burada da
/// pozisyon başına tek lot: şablon en yeni alım (ticker/tür/para birimi/
/// current_price), miktar net. Hangi lotun satıldığı değeri değiştirmez —
/// aynı pozisyonun lotları aynı fiyattan değerlenir.
export function netLotlar<T extends Lot>(acikLotlar: T[], tumSatirlar: T[]): T[] {
  const net = new Map<string, number>();
  for (const r of tumSatirlar) {
    const kind = r.kind ?? 'buy';
    if (kind !== 'buy' && kind !== 'sell') continue;
    const q = Number(r.quantity ?? 0);
    if (!Number.isFinite(q)) continue;
    const key = pozisyonAnahtari(r);
    net.set(key, (net.get(key) ?? 0) + (kind === 'sell' ? -q : q));
  }
  const sablon = new Map<string, T>();
  for (const l of acikLotlar) {
    const key = pozisyonAnahtari(l);
    const mevcut = sablon.get(key);
    if (!mevcut || String(l.added_date ?? '') > String(mevcut.added_date ?? '')) {
      sablon.set(key, l);
    }
  }
  const out: T[] = [];
  for (const [key, l] of sablon) {
    const q = net.get(key) ?? 0;
    if (q <= 1e-7) continue;
    out.push({ ...l, quantity: q });
  }
  return out;
}

export interface Degerleme {
  /// Fiyatı bulunan lotların toplam TL değeri.
  deger: number;
  /// Fiyatı bulunan lot kimlikleri.
  kapsanan: Set<string>;
  /// Serisi olmayan lotların `current_price` ile tahmini TL değeri — kapsama
  /// kararı için (bugünkü değerin ne kadarı karanlıkta?).
  karanlik: number;
}

/// Serisi olmayan lot için uygulamanın son bilinen fiyatı (`current_price`,
/// TL'ye çevrilmiş sayılır — istemci `current_price`'ı varlığın para
/// biriminde tutar; TRY dışı için kur bilinmiyorsa 0). Yalnız kapsama ve
/// dağılım için; ROI'ye girmez (geçmişi yok).
export function yedekTryFiyati(lot: Lot, seriler: Map<string, Seri>, tMs: number): number {
  const p = Number(lot.current_price ?? 0);
  if (!Number.isFinite(p) || p <= 0) return 0;
  const cur = paraBirimi(lot);
  if (cur === 'TRY') return p;
  const kurSeri = seriler.get(`${cur}TRY=X`);
  const kur = kurSeri ? fiyatAninda(kurSeri, tMs) : null;
  return kur === null ? 0 : p * kur;
}

/// Portföyün `t` anındaki TL değeri. Fiyatı olmayan lot atlanır (kapsama
/// kararı çağıranda).
export function portfoyDegeri(
  lots: Lot[],
  seriler: Map<string, Seri>,
  tMs: number,
  yalnizca?: Set<string>,
): Degerleme {
  let deger = 0;
  let karanlik = 0;
  const kapsanan = new Set<string>();
  for (const lot of lots) {
    if (yalnizca && !yalnizca.has(lot.id)) continue;
    const miktar = Number(lot.quantity ?? 0);
    if (!Number.isFinite(miktar) || miktar <= 0) continue;
    const p = lotTryFiyati(lot, seriler, tMs);
    if (p === null) {
      karanlik += miktar * yedekTryFiyati(lot, seriler, tMs);
      continue;
    }
    deger += miktar * p;
    kapsanan.add(lot.id);
  }
  return { deger, kapsanan, karanlik };
}

export function donemBaslangici(nowMs: number, gun: number): number {
  return nowMs - gun * GUN_MS;
}

/// Dönem getirisi (%): iki uçta da fiyatlanan lotlar üzerinden. Serisi
/// olmayan lotlar (`karanlik`, current_price tahmini) bugünkü toplamın
/// [KAPSAMA_ESIGI] dışında kalan payını aşıyorsa null — yarım portföyün
/// getirisi yazılmaz. Sonuç tablonun CHECK aralığına kırpılır.
export function donemRoi(
  lots: Lot[],
  seriler: Map<string, Seri>,
  nowMs: number,
  gun: number,
): number | null {
  const simdi = portfoyDegeri(lots, seriler, nowMs);
  if (simdi.deger <= 0) return null;
  if (simdi.deger < (simdi.deger + simdi.karanlik) * KAPSAMA_ESIGI) return null;
  const t0 = donemBaslangici(nowMs, gun);
  const bas = portfoyDegeri(lots, seriler, t0, simdi.kapsanan);
  if (bas.kapsanan.size === 0 || bas.deger <= 0) return null;
  // Ortak küme: iki uçta da fiyatlı lotlar; bugünkü değer o kümeyle.
  const ortak = portfoyDegeri(lots, seriler, nowMs, bas.kapsanan);
  if (ortak.deger < simdi.deger * KAPSAMA_ESIGI) return null;
  const roi = (ortak.deger - bas.deger) / bas.deger * 100;
  if (!Number.isFinite(roi)) return null;
  return Math.max(-100, Math.min(100000, roi));
}

export interface Dagilim {
  allocation_pct: Record<string, number>;
  type_count: number;
}

/// Bugünkü TL değerinin tür payı (%, 1 ondalık). Serisi olmayan lot
/// `current_price` yedeğiyle girer (bugünkü değer için yeterli). Hiçbir
/// lot değerlenemiyorsa null.
export function dagilim(
  lots: Lot[],
  seriler: Map<string, Seri>,
  nowMs: number,
): Dagilim | null {
  const turDegeri = new Map<string, number>();
  let toplam = 0;
  for (const lot of lots) {
    const miktar = Number(lot.quantity ?? 0);
    if (!Number.isFinite(miktar) || miktar <= 0) continue;
    const p = lotTryFiyati(lot, seriler, nowMs) ?? yedekTryFiyati(lot, seriler, nowMs);
    if (p <= 0) continue;
    const v = miktar * p;
    toplam += v;
    turDegeri.set(lot.type, (turDegeri.get(lot.type) ?? 0) + v);
  }
  if (toplam <= 0) return null;
  const allocation_pct: Record<string, number> = {};
  let type_count = 0;
  for (const [tur, v] of turDegeri) {
    const pct = Math.round(v / toplam * 1000) / 10;
    if (pct <= 0) continue;
    allocation_pct[tur] = pct;
    type_count++;
  }
  return { allocation_pct, type_count };
}

/// TEFAS fon kodu: 3 büyük harf/rakam (AFT, TTE, IPB…). Kamuya açık
/// kimlik; kullanıcının elle yazdığı serbest metin (ad, not) bu kalıba
/// uymaz ve ASLA taşınmaz — "diğer"e düşer.
export const TEFAS_KODU = /^[A-Z0-9]{3}$/;
export const FON_DIGER = 'DIGER';

/// Payı bu yüzdenin altındaki fon adıyla yazılmaz, "diğer"e katılır.
/// Küçük kalemler parmak izini keskinleştirir, bilgi katmaz.
export const FON_ESIGI_PCT = 1;

/// Fon türünün kod bazında kırılımı, TOPLAM portföyün yüzdesi olarak
/// (Σ ≈ `allocation_pct.fon`). Kullanıcı kararı 2026-09-29: "sadece kategori
/// yerine fonda hangi fonlar olduğu ve oranları da yazmalı".
///
/// Yalnızca ZİRVE tablosuna gider (0084); Yarış'ın dağılım satırı aynen
/// kalır. Fon yoksa ya da değerlenemiyorsa null.
export function fonDetayi(
  lots: Lot[],
  seriler: Map<string, Seri>,
  nowMs: number,
): Record<string, number> | null {
  const kodDegeri = new Map<string, number>();
  let toplam = 0;
  for (const lot of lots) {
    const miktar = Number(lot.quantity ?? 0);
    if (!Number.isFinite(miktar) || miktar <= 0) continue;
    const p = lotTryFiyati(lot, seriler, nowMs) ?? yedekTryFiyati(lot, seriler, nowMs);
    if (p <= 0) continue;
    const v = miktar * p;
    toplam += v;
    if (lot.type !== 'fon') continue;
    const kod = String(lot.ticker ?? '').trim().toUpperCase().replace(/^TEFAS:/, '');
    const anahtar = TEFAS_KODU.test(kod) ? kod : FON_DIGER;
    kodDegeri.set(anahtar, (kodDegeri.get(anahtar) ?? 0) + v);
  }
  if (toplam <= 0 || kodDegeri.size === 0) return null;
  const out: Record<string, number> = {};
  let diger = 0;
  for (const [kod, v] of kodDegeri) {
    const pct = v / toplam * 100;
    if (kod === FON_DIGER || pct < FON_ESIGI_PCT) {
      diger += pct;
      continue;
    }
    out[kod] = Math.round(pct * 10) / 10;
  }
  if (diger > 0) {
    const d = Math.round(diger * 10) / 10;
    if (d > 0) out[FON_DIGER] = d;
  }
  return Object.keys(out).length > 0 ? out : null;
}

/// Portföydeki FARKLI varlık sayısı: bugün değeri olan açık pozisyonların
/// tekil anahtarı (`pozisyonAnahtari` — aynı sembolün lotları tek sayılır).
///
/// Kullanıcı kararı (2026-09-29): "portföyde minimum 2 farklı varlık varsa
/// [zirve havuzuna] eklenmeli". Defterdeki (kapanmış pozisyonlar dahil)
/// kayıt sayısı değil, bugünkü portföy — satılmış bir hisse sayılmaz.
export function varlikSayisi(
  lots: Lot[],
  seriler: Map<string, Seri>,
  nowMs: number,
): number {
  const anahtarlar = new Set<string>();
  for (const lot of lots) {
    const miktar = Number(lot.quantity ?? 0);
    if (!Number.isFinite(miktar) || miktar <= 0) continue;
    const p = lotTryFiyati(lot, seriler, nowMs) ?? yedekTryFiyati(lot, seriler, nowMs);
    if (p <= 0) continue;
    anahtarlar.add(pozisyonAnahtari(lot));
  }
  return anahtarlar.size;
}

type AssetRow = Lot & { deleted_at?: string | null };

/// 0073 tetikleyicisinin reddi: dakikada bir snapshot. Mesaj metnine bakılır
/// çünkü PostgREST hata kodu (P0001) her `raise exception` için aynı.
export function throttleMu(mesaj: string | null | undefined): boolean {
  return (mesaj ?? '').includes('snapshot_throttled');
}

/// Hangi satır hangi tabloya (0083, 2026-09-29).
///
/// Zirve havuzu BEYANA DAYANMAZ: ölçülen herkes `zirve_*` tablolarına
/// yazılır. Yarış tabloları (`user_*_snapshots`) yalnızca yarışa katılanlar
/// için yazılır — Yarış ekranının mekaniği değişmesin (kullanıcı kararı):
/// katılmamış bir ortak sıralamada görünmez, genel yüzdelik havuzu
/// genişlemez.
export function yazimPlani<R extends { user_id: string }, A extends { user_id: string }>(
  roiRows: R[],
  allocRows: A[],
  optIn: Set<string>,
): { zirveRoi: R[]; zirveAlloc: A[]; yarisKullanicilari: string[] } {
  const olculen = new Set<string>();
  for (const r of roiRows) olculen.add(r.user_id);
  for (const a of allocRows) olculen.add(a.user_id);
  return {
    zirveRoi: roiRows,
    zirveAlloc: allocRows,
    yarisKullanicilari: [...olculen].filter((u) => optIn.has(u)),
  };
}

const VARLIK_SUTUNLARI =
  'id, user_id, name, ticker, type, is_manual_price, current_price, kind, quantity, sub_category, currency, added_date, ref_asset_id';

/// PostgREST tek yanıtta en fazla `max_rows` (varsayılan 1000) satır döner.
/// Sayfalamasız okuma, defter büyüdükçe kullanıcıları SESSİZCE düşürürdü —
/// zirve artık yalnız yarışanları değil herkesi okuduğu için sınır yakın.
async function tumAktifVarliklar(admin: SupabaseClient): Promise<AssetRow[]> {
  const SAYFA = 1000;
  const out: AssetRow[] = [];
  for (let bas = 0; ; bas += SAYFA) {
    const { data, error } = await admin
      .from('assets')
      .select(VARLIK_SUTUNLARI)
      .is('deleted_at', null)
      .order('id')
      .range(bas, bas + SAYFA - 1);
    if (error) throw new Error(`Varliklar alinamadi: ${error.message}`);
    const satirlar = (data ?? []) as AssetRow[];
    out.push(...satirlar);
    if (satirlar.length < SAYFA) break;
  }
  return out;
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cronSecret = Deno.env.get('LEADERBOARD_SNAPSHOT_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503; sonra header kontrolü (cron_auth.ts).
    const eksik = cronSecretZorunlu(cronSecret, 'LEADERBOARD_SNAPSHOT_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error(
        'SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.',
      );
    }

    let dryRun = false;
    try {
      const body = await request.json();
      dryRun = body?.dry_run === true;
    } catch (_) { /* gövde yok */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // 1) Yarışa katılanlar — yalnız Yarış tablolarına kimin yazılacağını
    // belirler. Ölçülecek küme bu DEĞİL: zirve havuzu beyana dayanmaz
    // (0083), portföyü olan herkes ölçülür.
    const { data: profilRows, error: profilError } = await admin
      .from('profiles')
      .select('id')
      .eq('leaderboard_opt_in', true);
    if (profilError) throw new Error(`Profiller alinamadi: ${profilError.message}`);
    const optIn = new Set((profilRows ?? []).map((r: { id: string }) => String(r.id)));

    // 2) Herkesin aktif defteri (sayfalı).
    // Mezar taşı YOK: kullanıcının ekranda gördüğü portföy `deleted_at` +
    // buy/sell netlemesidir (istemci `aggregatePositions`); "sil → geri al"
    // sonrası defterde kalan mezar taşı lotu öldürmez (bkz. positions.ts).
    const tum = await tumAktifVarliklar(admin);
    const userIds = [...new Set(tum.map((a) => String(a.user_id)))];
    if (userIds.length === 0) {
      return jsonResponse({ ok: true, reason: 'Portfoyu olan kullanici yok.', users: 0 });
    }
    const acik = netLotlar(acikPozisyonLotlari(tum, { mezarTasi: false }), tum);
    const lotlariOf = new Map<string, Lot[]>();
    for (const a of acik) {
      const list = lotlariOf.get(a.user_id) ?? [];
      list.push(a);
      lotlariOf.set(a.user_id, list);
    }

    // 3) Seriler (kullanıcılar arası paylaşımlı).
    const semboller = new Set<string>();
    for (const a of acik) for (const s of lotSembolleri(a)) semboller.add(s);
    const seriler = await loadDatedHistories(admin, semboller);

    // 4) Kullanıcı başına ROI + dağılım.
    const nowMs = Date.now();
    const roiRows: Array<{ user_id: string; period_days: number; roi_pct: number }> = [];
    const allocRows: Array<{ user_id: string; allocation_pct: Record<string, number>; type_count: number }> = [];
    // Zirve satırı = Yarış satırı + fon kırılımı. Ayrı dizi: Yarış tablosunda
    // `fon_detay` sütunu yok ve olmamalı (Yarış mekaniği değişmez).
    const zirveAllocRows: Array<{
      user_id: string;
      allocation_pct: Record<string, number>;
      type_count: number;
      fon_detay: Record<string, number> | null;
      varlik_sayisi: number;
    }> = [];
    let atlanan = 0;
    for (const uid of userIds) {
      const lots = lotlariOf.get(uid) ?? [];
      if (lots.length === 0) { atlanan++; continue; }
      let yazildi = false;
      for (const gun of DONEMLER) {
        const roi = donemRoi(lots, seriler, nowMs, gun);
        if (roi === null) continue;
        roiRows.push({ user_id: uid, period_days: gun, roi_pct: Math.round(roi * 10000) / 10000 });
        yazildi = true;
      }
      const d = dagilim(lots, seriler, nowMs);
      if (d !== null) {
        allocRows.push({ user_id: uid, ...d });
        zirveAllocRows.push({
          user_id: uid,
          ...d,
          fon_detay: fonDetayi(lots, seriler, nowMs),
          varlik_sayisi: varlikSayisi(lots, seriler, nowMs),
        });
        yazildi = true;
      }
      if (!yazildi) atlanan++;
    }

    // Yazım KULLANICI BAŞINA (2026-09-29): 0073 tetikleyicisi kullanıcı ×
    // dönem için dakikada bir satıra izin verir (`snapshot_throttled`) ve
    // service role'ü de kapsar. Tek toplu insert'te bir kullanıcının o
    // dakikada attığı istemci snapshot'ı (Yarış ekranı açık) BÜTÜN partiyi
    // düşürüyordu — ilk canlı koşuda görüldü. Throttle "atlandı" sayılır
    // (o dakikadaki değer zaten taze), başka hata yükselir.
    const plan = yazimPlani(roiRows, zirveAllocRows, optIn);
    let throttled = 0;
    let yazilanRoi = 0;
    let yazilanAlloc = 0;
    if (!dryRun) {
      // Zirve tabloları: throttle tetikleyicisi yok (yalnız bu cron yazar),
      // toplu insert güvenli.
      if (plan.zirveRoi.length > 0) {
        const { error } = await admin.from('zirve_roi_snapshots').insert(plan.zirveRoi);
        if (error) throw new Error(`Zirve ROI yazilamadi: ${error.message}`);
      }
      if (plan.zirveAlloc.length > 0) {
        const { error } = await admin.from('zirve_allocation_snapshots').insert(plan.zirveAlloc);
        if (error) throw new Error(`Zirve dagilim yazilamadi: ${error.message}`);
      }
      for (const uid of plan.yarisKullanicilari) {
        const roi = roiRows.filter((r) => r.user_id === uid);
        const alloc = allocRows.filter((r) => r.user_id === uid);
        if (roi.length > 0) {
          const { error } = await admin.from('user_roi_snapshots').insert(roi);
          if (error && !throttleMu(error.message)) {
            throw new Error(`ROI snapshot yazilamadi: ${error.message}`);
          }
          if (error) throttled++; else yazilanRoi += roi.length;
        }
        if (alloc.length > 0) {
          const { error } = await admin.from('user_allocation_snapshots').insert(alloc);
          if (error && !throttleMu(error.message)) {
            throw new Error(`Dagilim snapshot yazilamadi: ${error.message}`);
          }
          if (error) throttled++; else yazilanAlloc += alloc.length;
        }
      }
    }

    return jsonResponse({
      ok: true,
      users: userIds.length,
      opt_in_users: plan.yarisKullanicilari.length,
      zirve_roi_rows: plan.zirveRoi.length,
      zirve_alloc_rows: plan.zirveAlloc.length,
      roi_rows: dryRun ? roiRows.length : yazilanRoi,
      alloc_rows: dryRun ? allocRows.length : yazilanAlloc,
      skipped: atlanan,
      throttled,
      symbols: semboller.size,
      series_loaded: seriler.size,
      dry_run: dryRun,
    });
  } catch (error) {
    // Ayrıntı yalnızca günlüğe; yanıt tablo/sütun/secret adı sızdırmaz.
    console.error('[leaderboard-snapshot] hata:', error);
    return jsonResponse({ error: 'Yaris snapshot hesabi basarisiz.' }, 500);
  }
});
