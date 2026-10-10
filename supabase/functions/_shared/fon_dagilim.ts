// Fon X-Ray, Katman B — TEFAS varlık sınıfı dağılımı, SAF yardımcılar (0131).
//
// `fon-dagilim/index.ts` ağ + veritabanı işini yapar; buradakiler girdi alıp
// çıktı döner ki `supabase/tests/fon_dagilim_test.ts` TEFAS'a ve Postgres'e
// dokunmadan sınayabilsin. `fon-kalem-raporu` da ay sonu TEFAS satırını
// aynı ayrıştırıcıyla okur (beş kontrolün üçüncüsü).
//
// ── Uç ───────────────────────────────────────────────────────────────────────
// `POST https://www.tefas.gov.tr/api/funds/dagilimSiraliGetirT` (eski
// `BindHistoryAllocation` 2026'da yeniden adlandırıldı, kaldırılmadı).
// Ayrıntı: tmp/arastirma/research_notes/Fon XRay veri kaynakları/kamu_kaynaklari.md.
//   · Tek fon süzgeci `fonKod`. Yalnız `fonKodu` verilirse TÜM evren döner
//     (doğrulandı 2026-10-10): tek fon isteyen çağrı İKİSİNİ de doldurur.
//   · İstek ≤ 1 ay, geriye ≤ 5 yıl, ~6 istek/dk.
//   · Boş sonuç bazen Java istisna metni ("Index 0 out of bounds for length
//     0") ya da `errorMessage`'lı JSON — "veri yok" demektir, hata değil.
//
// ── Kaynaktan AYNEN ─────────────────────────────────────────────────────────
// Satırdaki her küçük harfli kısa kod (hs, dt, tr, vmtl, kmbyf…) yüzde
// sütunudur. Kod listesi resmî olarak belgelenmemiş ve 2021'de değişmişti;
// bu yüzden sabit bir beyaz liste yerine BİÇİMLE süzülür (`^[a-z]{1,6}$`):
// TEFAS yeni bir sınıf eklerse sayı kaybolmaz, istemci onu "Etiketsiz"
// gösterir. `bilFiyat` gibi camelCase alanlar ve metinler bu süzgece
// takılmaz. null/0 değerler düşer; değer yuvarlanmaz, toplam 100'e
// tamamlanmaz (uydurma sayı yok — fiyat kaynağı sözleşmesi madde 3).

export const TEFAS_DAGILIM_URL = 'https://www.tefas.gov.tr/api/funds/dagilimSiraliGetirT';

/// Sunucunun çektiği fon tipleri. GYF/GSYF bireysel portföylerde yok;
/// eklenirse tablo kısıtı (0131) da genişlemeli.
export const FON_TIPLERI = ['YAT', 'EMK', 'BYF'] as const;
export type FonTipi = typeof FON_TIPLERI[number];

/// Tarih penceresi (takvim günü). Hafta sonu + resmî tatil peşpeşe gelince
/// 3 iş günü boşluk olabiliyor; 5 gün en yeni satırı yakalar, yanıtı da
/// YAT için ~7 MB'ta tutar.
export const PENCERE_GUN = 5;

export type DagilimSatiri = {
  fon_kodu: string;
  fon_tipi: FonTipi;
  tarih: string; // YYYY-MM-DD
  dagilim: Record<string, number>;
  /// Fon unvanı (yasal bant kontrolü için, fon-kalem-raporu). Tabloya
  /// YAZILMAZ: yazan taraf kolonları açıkça seçer.
  fon_unvan?: string;
};

export type Ayristirma =
  | { durum: 'ok'; satirlar: DagilimSatiri[] }
  | { durum: 'bos'; satirlar: [] }
  | { durum: 'hata'; satirlar: [] };

/// Gövde. `fonKod` verilirse tek fon (iki anahtar birden — yukarıdaki not);
/// verilmezse fon tipinin bütün evreni.
export function istekGovdesi(
  fonTipi: FonTipi,
  basTarih: string,
  bitTarih: string,
  fonKod?: string,
): Record<string, unknown> {
  return {
    fonTipi,
    fonKodu: fonKod ?? null,
    aramaMetni: null,
    fonTurKod: null,
    fonGrubu: null,
    sfonTurKod: null,
    fonTurAciklama: null,
    kurucuKod: null,
    basTarih,
    bitTarih,
    basSira: 1,
    bitSira: 100000,
    dil: 'TR',
    sFonTurKod: '',
    fonKod: fonKod ?? '',
    fonGrup: '',
    fonUnvanTip: '',
  };
}

/// TEFAS'ın HTML sayfaları WAF arkasında; JSON ucu tarayıcı başlıklarıyla
/// düz POST'u kabul ediyor (borsapy, tefas-fon ve bu araştırmadaki istekler).
export const ISTEK_BASLIKLARI: Record<string, string> = {
  'Content-Type': 'application/json',
  Accept: 'application/json, text/plain, */*',
  Origin: 'https://www.tefas.gov.tr',
  Referer: 'https://www.tefas.gov.tr/tr/fon-verileri',
  'User-Agent':
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
};

/// `YYYYMMDD` (TEFAS gövdesinin tarih biçimi), Europe/Istanbul günü.
export function tefasGunu(d: Date): string {
  return trGunu(d).replaceAll('-', '');
}

/// Bir anın Europe/Istanbul takvim günü, `YYYY-MM-DD`.
export function trGunu(d: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d);
}

/// Son [gun] takvim gününün penceresi: `[bas, bit]` `YYYYMMDD`.
export function pencere(simdi: Date, gun = PENCERE_GUN): [string, string] {
  const bas = new Date(simdi.getTime() - gun * 86_400_000);
  return [tefasGunu(bas), tefasGunu(simdi)];
}

/// "Veri yok" anlamına gelen Java/TEFAS metinleri.
const BOS_METIN = /index\s+0\s+out\s+of\s+bounds|veri\s+bulunamad|kay[ıi]t\s+bulunamad/i;

const KOD = /^[a-z]{1,6}$/;
const FON_KODU = /^[A-Z0-9]{2,8}$/;

/// Ham yanıt metnini satırlara ayırır. Biçim tanınmazsa `hata` (yazılmaz,
/// mevcut satırlar korunur); Java boş metni ya da boş liste `bos`.
export function ayristir(ham: string, fonTipi: FonTipi): Ayristirma {
  const metin = (ham ?? '').trim();
  if (metin.length === 0) return { durum: 'bos', satirlar: [] };
  let json: unknown;
  try {
    json = JSON.parse(metin);
  } catch {
    return BOS_METIN.test(metin) ? { durum: 'bos', satirlar: [] } : { durum: 'hata', satirlar: [] };
  }
  if (typeof json !== 'object' || json === null) return { durum: 'hata', satirlar: [] };
  const o = json as Record<string, unknown>;
  const liste = o.resultList;
  if (!Array.isArray(liste)) {
    // `{"errorMessage":"Index 0 out of bounds…","resultList":null}`
    const hataMetni = `${o.errorMessage ?? ''} ${o.message ?? ''}`;
    return BOS_METIN.test(hataMetni) ? { durum: 'bos', satirlar: [] } : { durum: 'hata', satirlar: [] };
  }
  const satirlar: DagilimSatiri[] = [];
  for (const r of liste) {
    const s = satiriAyristir(r, fonTipi);
    if (s) satirlar.push(s);
  }
  return satirlar.length === 0 ? { durum: 'bos', satirlar: [] } : { durum: 'ok', satirlar };
}

/// Tek satır. Kod/tarih tanınmazsa ya da hiç sıfırdan farklı sınıf yoksa
/// `null` — eksik satır yazılmaz.
export function satiriAyristir(r: unknown, fonTipi: FonTipi): DagilimSatiri | null {
  if (typeof r !== 'object' || r === null) return null;
  const o = r as Record<string, unknown>;
  const kod = String(o.fonKodu ?? '').trim().toUpperCase();
  if (!FON_KODU.test(kod)) return null;
  const t = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(o.tarih ?? '').trim());
  if (!t) return null;
  const dagilim: Record<string, number> = {};
  for (const [k, v] of Object.entries(o)) {
    if (!KOD.test(k)) continue;
    if (typeof v !== 'number' || !Number.isFinite(v) || v === 0) continue;
    // Akla yatkın aralık: kaldıraçlı/borçlu fonda bir sınıf negatif ya da
    // 100'ün biraz üstü olabilir; bunun dışı biçim bozukluğudur (alan
    // yüzde değil, tutar). Böyle bir değer satırı DÜŞÜRMEZ, yalnız o
    // alan alınmaz.
    if (v < -100 || v > 200) continue;
    dagilim[k] = v;
  }
  if (Object.keys(dagilim).length === 0) return null;
  const s: DagilimSatiri = { fon_kodu: kod, fon_tipi: fonTipi, tarih: `${t[1]}-${t[2]}-${t[3]}`, dagilim };
  const unvan = typeof o.fonUnvan === 'string' ? o.fonUnvan.trim() : '';
  if (unvan.length > 0) s.fon_unvan = unvan;
  return s;
}

/// Fon başına en yeni günün satırı. Aynı fon iki tipte gelirse (olmamalı)
/// tarihi yeni olan kazanır; eşitlikte ilk görülen.
export function enYeniSatirlar(satirlar: DagilimSatiri[]): DagilimSatiri[] {
  const m = new Map<string, DagilimSatiri>();
  for (const s of satirlar) {
    const o = m.get(s.fon_kodu);
    if (!o || s.tarih > o.tarih) m.set(s.fon_kodu, s);
  }
  return [...m.values()].sort((a, b) => a.fon_kodu.localeCompare(b.fon_kodu));
}

/// Yazılacaklar: tabloda olmayan ya da tablodakinden YENİ/aynı tarihli
/// satırlar. Kaynak bir gün eski veri döndürürse (önbellek, kısmi yayın)
/// daha yeni satırın üstüne yazılmaz.
export function yazilacaklar(
  yeni: DagilimSatiri[],
  mevcut: Map<string, string>,
): DagilimSatiri[] {
  return yeni.filter((s) => {
    const t = mevcut.get(s.fon_kodu);
    return t === undefined || s.tarih >= t;
  });
}

/// Ay sonu kontrolü (fon-kalem-raporu): [satirlar] içinde [gun]'e eşit ya
/// da ondan önceki EN YENİ satır. Ay sonu tatile denk gelirse son iş günü.
export function gunVeyaOncesi(satirlar: DagilimSatiri[], gun: string): DagilimSatiri | null {
  let en: DagilimSatiri | null = null;
  for (const s of satirlar) {
    if (s.tarih > gun) continue;
    if (!en || s.tarih > en.tarih) en = s;
  }
  return en;
}
