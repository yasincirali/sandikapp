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
// ## 2026-09-29: zirve havuzu beyana dayanmaz (0083) → 2026-10-01: açık rıza (0091)
// 0083'te portföyü olan HERKES ölçülüp `zirve_*_snapshots`'a yazılıyordu;
// 0091'den beri yalnız `zirve_rizalari`'nda geçerli rızası olanlar yazılır
// (anonim, RLS kapalı kutu; yalnız RPC okur). Yarış tablolarına yine
// YALNIZ opt-in kullanıcılar yazılır — Yarış ekranının mekaniği değişmesin
// diye (`yazimPlani`). Aynı hesap iki yere gider; ikinci bir fiyat turu yok.
//
// ## Ne hesaplar
// Getiri 2026-10-01'den (0095) beri SEÇİMLERİNİN GETİRİSİ — zaman
// ağırlıklı (TWR, `donemTwr`): defterin tamamından günlük miktar geçmişi
// kurulur, her gün piyasa fiyatıyla değerlenir, günlerin getirisi çarpılır.
// Öncesinde simülasyondu (bugünkü sepet dönem başından beri tutulmuş
// sayılırdı); gerekçe `donemTwr` üstünde. İstemci eşi
// `lib/services/secim_getirisi.dart`. Dağılım: bugünkü TL değerinin tür payı
// (açık lotlar, `_shared/positions.ts`, satış ve silme düşülmüş).
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

/// Mevduat sembol öneki (0088). İstemci eşi `asset_type.dart` ›
/// `mevduatOneki`.
export const MEVDUAT_ONEKI = 'MEVDUAT:';

/// Değeri piyasadan değil sözleşmeden gelen lot mu (mevduat)?
///
/// Birim değer istemcide sözleşmenin dönemlerinden hesaplanır ve her fiyat
/// turunda `current_price`'a yazılır. Sunucu faiz motorunu KOPYALAMAZ
/// (iki motor ayrışırdı — 0058'in dersi); elle fiyatlı lot gibi
/// `current_price` ile değerler. Bayatlık payı küçük: mevduat günde
/// binde bir mertebesinde değişir.
export function sozlesmeFiyatli(lot: Lot): boolean {
  return (lot.ticker ?? '').trim().toUpperCase().startsWith(MEVDUAT_ONEKI);
}

/// Lotun değerlenmesi için gereken seriler. Elle fiyatlı lot hiçbir seri
/// istemez.
export function lotSembolleri(lot: Lot): string[] {
  if (lot.is_manual_price === true || sozlesmeFiyatli(lot)) return [];
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
  if (lot.is_manual_price === true || sozlesmeFiyatli(lot)) {
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

// ── Seçimlerinin getirisi (TWR, 0095) ───────────────────────────────────────
//
// Kullanıcı kararı R1 (2026-10-01, "Yarış Ölçüsü Kıyası"): sıralama ve
// Zirve ZAMAN AĞIRLIKLI getiriyle. Dönem günlere bölünür; her gün, o günün
// BAŞINDAKİ miktarlar piyasa fiyatıyla değerlenir ve günün getirisi
// `Σ q·p(gün sonu) / Σ q·p(gün başı)` olur; günler çarpılır. Para ne zaman,
// ne kadar eklenmiş sonucu etkilemez — yalnız neyin tutulduğu.
//
// Eski ölçü simülasyondu (`donemRoi`: bugünkü sepet dönem başından beri
// tutulmuş sayılırdı). Satıp başka varlık alan "hep yeniyi tutmuş", ay
// sonunda giren "bütün yılı kazanmış" görünüyordu. TWR'de satılan varlık
// satılana kadar sayılır, alınan alındığı günden; geç katılan yalnız
// tuttuğu süre kadar ölçülür.
//
// Kullanıcının girdiği alış/satış FİYATI hiç kullanılmaz (senaryoda
// "Hakan" fiyatı 1 TL girip %1.439.900 gösterebiliyordu); değerleme her
// zaman piyasa serisinden. Kayıt TARİHİ ise `yarisAni` kuralıyla sınırlı.
//
// İstemci eşi: `lib/services/secim_getirisi.dart` (Yarış'ta ortaklar
// cihazda ölçülür). İki taraf AYNI senaryo testlerini geçer
// (`leaderboard_snapshot_test.ts` ↔ `test/secim_getirisi_test.dart`).

/// `added_date` girişten bu kadar gün gerideyse kayıt GİRİLDİĞİ anda
/// yapılmış sayılır (0095). Pay, "dün aldım bugün giriyorum" kullanıcısını
/// cezalandırmasın diye.
export const GERI_TARIH_PAYI_GUN = 3;

/// Sıralamaya girmek için gereken en kısa süre — VARSAYILAN (R1: "asgari
/// 30 gün"). Gerçek değer `siralama_ayar.asgari_olcum_gun`'dan okunur
/// (0128, kullanıcı kararı 2026-10-09: "parametrik olsun"); tablo yoksa
/// ya da okunamazsa bu. Dönemden bağımsız: on günlük bir hesap 7 günlük
/// sıralamada da görünmez.
///
/// Sayaç ilk varlığın EDİNME tarihinden (`added_date`) başlar, uygulamaya
/// giriş anından değil (2026-10-09, aynı karar: "uygulamaya değil varlığı
/// elde ediş tarihi"). 0095–0127 arası [yarisAni]'ndan sayılıyordu; geçmişini
/// içe aktaran kullanıcı 30 gün bekliyordu (Tokyo'da 6 rızalıdan 2'si).
/// Getiri yine [yarisAni]'ndan ölçülür: geriye tarih hilesi kapıyı açar ama
/// dipten kazanç yazdırmaz.
export const ASGARI_OLCUM_GUN = 30;

/// Defterdeki ilk alımın edinme anı (`added_date`, epoch ms); yoksa null.
/// Satılmış pozisyon da sayılır — "ilk varlık" ne zaman edinildiyse odur.
export function ilkEdinmeAni(satirlar: DefterSatiri[]): number | null {
  let ilk: number | null = null;
  for (const r of satirlar) {
    if ((r.kind ?? 'buy') !== 'buy') continue;
    const q = Number(r.quantity ?? 0);
    if (!Number.isFinite(q) || q <= 0) continue;
    const t = zamanMs(r.added_date) ?? zamanMs(r.created_at);
    if (t !== null && (ilk === null || t < ilk)) ilk = t;
  }
  return ilk;
}

/// Defter satırı + sunucunun giriş anı (0095 `assets.created_at`).
export interface DefterSatiri extends Lot {
  created_at?: string | null;
}

function zamanMs(v: string | null | undefined): number | null {
  if (!v) return null;
  const t = new Date(v).getTime();
  return Number.isFinite(t) ? t : null;
}

/// Satırın yarışta sayılan anı: `added_date`; ama girişten
/// [GERI_TARIH_PAYI_GUN] günden fazla gerideyse giriş anı (`created_at`).
/// Senaryoda "Gül" Ay 12'de aldığı X'i Ay 6'ya (dip) giriyordu; bu kuralla
/// alım Ay 12'de sayılır, dipten kazanç yazılmaz. Satış için de aynı:
/// çöküşten önceye geriye tarihli satış, girildiği gün yapılmış sayılır.
/// Giriş anı yoksa tarih olduğu gibi (0095 öncesi satırlar ona eşitlendi).
///
/// Bu fonksiyonun yazdığı her yüzey ANONİM (Zirve, genel yüzdelik), kural
/// burada hep uygulanır. Ortaklar arası Yarış cihazda ölçülür ve beyan
/// edilen tarihe güvenir (kullanıcı kararı 2026-10-01; istemci
/// `SiralamaKapsami.ortaklar`): herkes birbirini tanır, buna karşılık
/// geçmişini içe aktaran kullanıcı 30 gün beklemez.
export function yarisAni(r: DefterSatiri): number | null {
  const eklenme = zamanMs(r.added_date);
  const giris = zamanMs(r.created_at);
  if (eklenme === null) return giris;
  if (giris === null) return eklenme;
  return eklenme < giris - GERI_TARIH_PAYI_GUN * GUN_MS ? giris : eklenme;
}

/// Bir pozisyonun miktar geçmişi: fiyatlama şablonu + zamana göre sıralı
/// hareketler (alım +, satış −).
export interface PozisyonGecmisi {
  sablon: Lot;
  hareketler: Array<{ an: number; miktar: number }>;
}

/// Kullanıcının defterini pozisyon geçmişlerine böler. Yalnız buy/sell;
/// `delete_log` ve temettü miktara girmez (`netLotlar` ile aynı). Şablon
/// pozisyonun EN YENİ alımı — `netLotlar` ile aynı seçim.
export function pozisyonGecmisleri<T extends DefterSatiri>(satirlar: T[]): PozisyonGecmisi[] {
  const gruplar = new Map<string, PozisyonGecmisi>();
  const sablonTarihi = new Map<string, string>();
  for (const r of satirlar) {
    const kind = r.kind ?? 'buy';
    if (kind !== 'buy' && kind !== 'sell') continue;
    const q = Number(r.quantity ?? 0);
    const an = yarisAni(r);
    if (!Number.isFinite(q) || q <= 0 || an === null) continue;
    const key = pozisyonAnahtari(r);
    let g = gruplar.get(key);
    if (!g) {
      g = { sablon: r, hareketler: [] };
      gruplar.set(key, g);
    }
    g.hareketler.push({ an, miktar: kind === 'sell' ? -q : q });
    if (kind === 'buy') {
      const tarih = String(r.added_date ?? '');
      const onceki = sablonTarihi.get(key);
      if (onceki === undefined || tarih > onceki) {
        sablonTarihi.set(key, tarih);
        g.sablon = r;
      }
    }
  }
  for (const g of gruplar.values()) g.hareketler.sort((a, b) => a.an - b.an);
  return [...gruplar.values()];
}

/// Pozisyonun `t` anındaki miktarı (`an ≤ t` hareketlerin toplamı, en az 0).
export function miktarAninda(p: PozisyonGecmisi, tMs: number): number {
  let q = 0;
  for (const h of p.hareketler) {
    if (h.an > tMs) break;
    q += h.miktar;
  }
  return q > 1e-7 ? q : 0;
}

/// Dönemin ölçüm anları: başlangıç (dönem başı ya da ilk alım, hangisi
/// sonraysa), sonra bugünden geriye tam günler, en sonda bugün. Izgara
/// bugüne hizalı: iki koşu aynı günleri aynı anlarda ölçer.
export function olcumAnlari(basMs: number, nowMs: number): number[] {
  if (nowMs <= basMs) return [];
  const anlar = [basMs];
  for (let k = Math.floor((nowMs - basMs) / GUN_MS); k >= 1; k--) {
    const t = nowMs - k * GUN_MS;
    if (t > basMs) anlar.push(t);
  }
  anlar.push(nowMs);
  return anlar;
}

/// Seçimlerinin getirisi (%) — zaman ağırlıklı, piyasa fiyatıyla.
///
/// Kapılar (sayı uydurulmaz):
///   · ilk varlığın edinme tarihi [asgariGun] günden yeniyse null
///     ([ilkEdinmeAni]; varsayılan [ASGARI_OLCUM_GUN]);
///   · bugünkü portföyün [KAPSAMA_ESIGI]'nden azı fiyatlanabiliyorsa null
///     (yarım portföyün getirisi yazılmaz — eski kural aynen);
///   · hiçbir gün ölçülemediyse null.
/// Bir gün yalnız iki ucunda da fiyatı olan pozisyonlarla ölçülür. Elle
/// fiyatlı ve sözleşmeli (mevduat) lot iki uçta aynı fiyatla girer:
/// getiriyi sulandırır ama yönünü değiştirmez (eski kuralla aynı).
/// Sonuç tablonun CHECK aralığına kırpılır.
export function donemTwr(
  satirlar: DefterSatiri[],
  seriler: Map<string, Seri>,
  nowMs: number,
  gun: number,
  asgariGun: number = ASGARI_OLCUM_GUN,
): number | null {
  const edinme = ilkEdinmeAni(satirlar);
  if (edinme === null || nowMs - edinme < asgariGun * GUN_MS) return null;
  const gecmis = pozisyonGecmisleri(satirlar);
  // Ölçümün başladığı an: ilk alımın YARIŞ anı (geriye tarih kuralı).
  let ilk = Infinity;
  for (const p of gecmis) {
    for (const h of p.hareketler) if (h.miktar > 0 && h.an < ilk) ilk = h.an;
  }
  if (!Number.isFinite(ilk)) return null;

  const bugun = gecmis
    .map((p) => ({ ...p.sablon, quantity: miktarAninda(p, nowMs) }))
    .filter((l) => l.quantity > 0);
  const simdi = portfoyDegeri(bugun, seriler, nowMs);
  if (simdi.deger <= 0) return null;
  if (simdi.deger < (simdi.deger + simdi.karanlik) * KAPSAMA_ESIGI) return null;

  const anlar = olcumAnlari(Math.max(donemBaslangici(nowMs, gun), ilk), nowMs);
  let carpim = 1;
  let olculdu = false;
  for (let i = 1; i < anlar.length; i++) {
    const a = anlar[i - 1];
    const b = anlar[i];
    let pay = 0;
    let payda = 0;
    for (const p of gecmis) {
      const q = miktarAninda(p, a);
      if (q <= 0) continue;
      const pa = lotTryFiyati(p.sablon, seriler, a);
      const pb = lotTryFiyati(p.sablon, seriler, b);
      if (pa === null || pb === null) continue;
      payda += q * pa;
      pay += q * pb;
    }
    if (payda <= 0) continue;
    carpim *= pay / payda;
    olculdu = true;
  }
  if (!olculdu) return null;
  const roi = (carpim - 1) * 100;
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

type AssetRow = DefterSatiri & { deleted_at?: string | null };

/// 0073 tetikleyicisinin reddi: dakikada bir snapshot. Mesaj metnine bakılır
/// çünkü PostgREST hata kodu (P0001) her `raise exception` için aynı.
export function throttleMu(mesaj: string | null | undefined): boolean {
  return (mesaj ?? '').includes('snapshot_throttled');
}

/// Hangi satır hangi tabloya.
///
/// Zirve havuzu AÇIK RIZAYA dayanır (0091, 2026-10-01; 0083'te beyansızdı):
/// `zirve_*` tablolarına yalnız [zirveRiza] kümesindekiler yazılır —
/// rızası olmayanın getirisi ve dağılımı zirve için saklanmaz (veri
/// minimizasyonu). Yarış tabloları (`user_*_snapshots`) yalnızca yarışa
/// katılanlar için yazılır — Yarış ekranının mekaniği değişmesin: katılmamış
/// bir ortak sıralamada görünmez, genel yüzdelik havuzu genişlemez.
export function yazimPlani<R extends { user_id: string }, A extends { user_id: string }>(
  roiRows: R[],
  allocRows: A[],
  optIn: Set<string>,
  zirveRiza: Set<string>,
): { zirveRoi: R[]; zirveAlloc: A[]; yarisKullanicilari: string[] } {
  const olculen = new Set<string>();
  for (const r of roiRows) olculen.add(r.user_id);
  for (const a of allocRows) olculen.add(a.user_id);
  return {
    zirveRoi: roiRows.filter((r) => zirveRiza.has(r.user_id)),
    zirveAlloc: allocRows.filter((a) => zirveRiza.has(a.user_id)),
    yarisKullanicilari: [...olculen].filter((u) => optIn.has(u)),
  };
}

/// Tek kullanıcılık ölçüm isteği (0094, 2026-10-01): gövdede geçerli bir
/// `user_id` varsa yalnız o kullanıcı ölçülür. Geçersiz/boş → null, yani
/// bildiğimiz tam (cron) koşu — bozuk bir gövde herkesi ölçmeye düşer ama
/// asla başka birini "tek kullanıcı" diye ölçmez.
export function tekKullanici(body: unknown): string | null {
  const v = (body as { user_id?: unknown } | null)?.user_id;
  if (typeof v !== 'string') return null;
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(v)
    ? v.toLowerCase()
    : null;
}

// `created_at` (0095): yarış anı kuralı için. Sütun yoksa sorgu düşer —
// migration bu fonksiyondan ÖNCE dağıtılır.
const VARLIK_SUTUNLARI =
  'id, user_id, name, ticker, type, is_manual_price, current_price, kind, quantity, sub_category, currency, added_date, created_at, ref_asset_id';

/// PostgREST tek yanıtta en fazla `max_rows` (varsayılan 1000) satır döner.
/// Sayfalamasız okuma, defter büyüdükçe kullanıcıları SESSİZCE düşürürdü —
/// zirve artık yalnız yarışanları değil herkesi okuduğu için sınır yakın.
/// `siralama_ayar.asgari_olcum_gun` (0128); okunamazsa [ASGARI_OLCUM_GUN].
async function asgariOlcumGunu(admin: SupabaseClient): Promise<number> {
  const { data, error } = await admin
    .from('siralama_ayar')
    .select('asgari_olcum_gun')
    .eq('tek', true)
    .maybeSingle();
  const v = Number((data as { asgari_olcum_gun?: unknown } | null)?.asgari_olcum_gun);
  if (error || !Number.isFinite(v) || v < 0) {
    if (error) console.warn('siralama_ayar okunamadi; varsayilan kullaniliyor');
    return ASGARI_OLCUM_GUN;
  }
  return v;
}

async function tumAktifVarliklar(
  admin: SupabaseClient,
  yalniz: string | null = null,
): Promise<AssetRow[]> {
  const SAYFA = 1000;
  const out: AssetRow[] = [];
  for (let bas = 0; ; bas += SAYFA) {
    let q = admin
      .from('assets')
      .select(VARLIK_SUTUNLARI)
      .is('deleted_at', null);
    if (yalniz) q = q.eq('user_id', yalniz);
    const { data, error } = await q
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
    // Tek kullanıcı modu (0094): `zirve_rizasi_ayarla` rıza verilince
    // çağırır ki kullanıcı akşamki cron'u (18:40) beklemeden havuza girsin
    // (kullanıcı kararı 2026-10-01, "Anında ölçüm"). Bu modda YALNIZ zirve
    // tablolarına yazılır: Yarış'ın günlük ritmi ve 0073 throttle'ı
    // değişmesin diye yarış tablosuna dokunulmaz.
    let tek: string | null = null;
    try {
      const body = await request.json();
      dryRun = body?.dry_run === true;
      tek = tekKullanici(body);
    } catch (_) { /* gövde yok */ }

    const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // 0b) Asgari ölçüm süresi (0128). Okunamazsa varsayılan — koşu durmaz:
    // tablo henüz yoksa (migration fonksiyondan sonra gittiyse) eski 30 gün.
    const asgariGun = await asgariOlcumGunu(admin);

    // 1) Yarışa katılanlar — yalnız Yarış tablolarına kimin yazılacağını
    // belirler. Zirve kümesi ayrı: açık rıza verenler (1b, 0091).
    const { data: profilRows, error: profilError } = await admin
      .from('profiles')
      .select('id')
      .eq('leaderboard_opt_in', true);
    if (profilError) throw new Error(`Profiller alinamadi: ${profilError.message}`);
    const optIn = tek
      ? new Set<string>()
      : new Set((profilRows ?? []).map((r: { id: string }) => String(r.id)));

    // 1b) Zirve açık rızası (0091) — zirve tablolarına kimin yazılacağı.
    const { data: rizaRows, error: rizaError } = await admin
      .from('zirve_rizalari')
      .select('user_id')
      .is('geri_cekildi_at', null);
    if (rizaError) throw new Error(`Zirve rizalari alinamadi: ${rizaError.message}`);
    const zirveRiza = new Set(
      (rizaRows ?? []).map((r: { user_id: string }) => String(r.user_id)),
    );

    // 2) Herkesin aktif defteri (sayfalı).
    // Mezar taşı YOK: kullanıcının ekranda gördüğü portföy `deleted_at` +
    // buy/sell netlemesidir (istemci `aggregatePositions`); "sil → geri al"
    // sonrası defterde kalan mezar taşı lotu öldürmez (bkz. positions.ts).
    const tum = await tumAktifVarliklar(admin, tek);
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
    // TWR için defterin TAMAMI (alım + satış): bugün kapalı bir pozisyon
    // dönem içinde tutulduğu günlerde sayılır.
    const defteriOf = new Map<string, AssetRow[]>();
    for (const a of tum) {
      const list = defteriOf.get(a.user_id) ?? [];
      list.push(a);
      defteriOf.set(a.user_id, list);
    }

    // 3) Seriler (kullanıcılar arası paylaşımlı). Kapalı pozisyonların
    // serisi de gerekir — dönem içinde tutuldukları günler ölçülür.
    const semboller = new Set<string>();
    for (const a of tum) {
      const kind = a.kind ?? 'buy';
      if (kind !== 'buy' && kind !== 'sell') continue;
      for (const s of lotSembolleri(a)) semboller.add(s);
    }
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
      const defter = defteriOf.get(uid) ?? [];
      for (const gun of DONEMLER) {
        const roi = donemTwr(defter, seriler, nowMs, gun, asgariGun);
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
    const plan = yazimPlani(roiRows, zirveAllocRows, optIn, zirveRiza);
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
      asgari_olcum_gun: asgariGun,
      series_loaded: seriler.size,
      dry_run: dryRun,
      tek_kullanici: tek !== null,
    });
  } catch (error) {
    // Ayrıntı yalnızca günlüğe; yanıt tablo/sütun/secret adı sızdırmaz.
    console.error('[leaderboard-snapshot] hata:', error);
    return jsonResponse({ error: 'Yaris snapshot hesabi basarisiz.' }, 500);
  }
});
