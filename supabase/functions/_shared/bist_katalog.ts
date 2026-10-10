// BIST hisse kataloğu — saf yardımcılar (0139, bist-hisse-katalog).
//
// ── Neden sunucuda (yasin, 2026-10-10) ──────────────────────────────────────
// "Eksik varlık olmasını istemiyorum, borsada işlem gören tüm hisseler
// olmalı." Liste uygulamaya gömülüyken her halka arz bir sürüm bekliyordu
// ve liste zamanla eskidi (BIST 100'ün 24'ü yoktu, KUTPO yoktu). Sunucu
// listeyi her gün borsadan tazeler; istemci okur, gömülü listeye düşer.
//
// ── Kaynaklar (GitHub runner'da ölçüldü, 2026-10-10) ────────────────────────
// · Evren: TradingView tarayıcısı (`scanner.tradingview.com/turkey/scan`),
//   anahtarsız; borsadaki her kâğıdı tür/alt türle verir (626 adi hisse,
//   4 kapalı uçlu yatırım ortaklığı, 21 BYF). XU100 üyeliği aynı uçtan.
// · Ad: KAP "BIST şirketleri" sayfası (Türkçe karakterli resmî unvan).
//   Gelmezse TradingView açıklaması (ASCII) kullanılır; ad yoksa kod.
// · Fiyat bu katalogdan GELMEZ — fiyat kaynağı sözleşmesi değişmez
//   (`.IS` Yahoo'dan); 651 sembolün 649'u Yahoo'da fiyatlı ölçüldü.

/// TradingView tarama satırı: [ad, açıklama, tür, alt tür].
export type TvSatiri = [string, string | null, string | null, string | null];

/// Bilerek dışarıda tutulanlar. Darphane sertifikaları TradingView'da
/// "adi hisse" görünür ama Yahoo fiyat vermez; "ALTIN" hisse kodu
/// sayılsaydı ekstrede altın satırı hisse diye okunurdu.
export const DISLANAN = new Set(['ALTIN', 'DMLKT']);

/// Bir turda bundan az hisse gelirse yanıt bozuk sayılır ve tablo
/// DEĞİŞTİRİLMEZ (boş/yarım yanıt yüzlerce hisseyi pasifleştirmesin).
/// Borsada ~630 hisse var; %25'ten fazla düşüş gerçek olamaz.
export const ASGARI_HISSE = 450;

const KOD = /^[A-Z0-9]{3,6}$/;

/// Katalogdaki kâğıtlar: adi hisse + kapalı uçlu yatırım ortaklığı (GYO
/// dışı yatırım ortaklıkları TradingView'da "fund/closedend"). BYF (ETF)
/// fondur, hisse değil — girmez.
export function evrenKur(satirlar: TvSatiri[]): Map<string, string | null> {
  const out = new Map<string, string | null>();
  for (const [kod, aciklama, tur, alt] of satirlar) {
    if (typeof kod !== 'string' || !KOD.test(kod) || DISLANAN.has(kod)) continue;
    const hisse = tur === 'stock' || (tur === 'fund' && alt === 'closedend');
    if (!hisse) continue;
    out.set(kod, aciklama ?? null);
  }
  return out;
}

/// KAP sayfasındaki gömülü JSON'dan kod → unvan. Sayfa Next.js yükünde
/// kaçışlı (`\"`) JSON taşır; birden çok kodlu şirket "A, B" yazılır.
/// Biçim değişirse boş harita döner — ad TradingView'dan gelir.
export function kapUnvanlari(html: string): Map<string, string> {
  const t = html.replaceAll('\\\\', '\\').replaceAll('\\"', '"');
  const out = new Map<string, string>();
  const re = /"kapMemberTitle":"([^"]*)".{0,400}?"stockCode":"([^"]*)"/gs;
  for (const m of t.matchAll(re)) {
    for (const kod of m[2].split(',')) {
      const k = kod.trim();
      if (KOD.test(k) && !out.has(k)) out.set(k, m[1]);
    }
  }
  return out;
}

// Olduğu gibi kalan kısaltmalar ("TSKB GYO", "QNB Bank").
const UST = new Set([
  'GYO', 'BYF', 'TAV', 'QNB', 'ICBC', 'TSKB', 'BBVA', 'MLP', 'TTS', 'SDT', 'TML',
  'HDFGS', 'DMS', 'MHP', 'ATP', 'CVK', 'TDG', 'ICU',
]);

// Unvanın sonundaki tüzel/sektör kuyruğu: "… Sanayi ve Ticaret A.Ş."
const KUYRUK = new RegExp(
  '(\\s+(A\\.?\\s?Ş\\.?|A\\.?O\\.?|T\\.?A\\.?Ş\\.?|AŞ|AS|A\\.S\\.?|ANONİM|ANONIM|ŞİRKETİ|SIRKETI|' +
    'ŞTİ\\.?|SANAYİ|SANAYİİ|SANAYI|SANAYII|SAN\\.?|TİCARET|TICARET|TİC\\.?|VE|İNŞAAT|' +
    'PAZARLAMA|İTHALAT|İHRACAT|DIŞ|ÜRETİM|HİZMETLERİ|YATIRIMLARI|YATIRIM))+\\s*$',
);

function kucuk(w: string): string {
  return w.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();
}

function basHarf(w: string): string {
  if (!w) return w;
  if (UST.has(w.toUpperCase()) || (w.length <= 3 && !/[AEIİOÖUÜ]/.test(w))) return w;
  const l = kucuk(w);
  const ilk = l[0] === 'i' ? 'İ' : l[0] === 'ı' ? 'I' : l[0].toUpperCase();
  // Tireli adın ikinci yarısı da büyük: "Gür-Sel".
  return (ilk + l.slice(1)).replace(/-(\p{Ll})/gu, (_, c: string) =>
    '-' + (c === 'i' ? 'İ' : c === 'ı' ? 'I' : c.toUpperCase()));
}

/// Resmî unvandan listede gösterilecek kısa ad:
/// "TÜRK HAVA YOLLARI A.O." → "Türk Hava Yolları". Uygulamadaki elle
/// yazılmış adlarla aynı üslup; "ve" küçük kalır.
export function kisaAd(unvan: string | null | undefined, kod: string): string {
  let u = (unvan ?? '').trim().replace(/\.+$/, '').toUpperCase();
  if (!u) return kod;
  u = u.replace(/GAYRİMENKUL YATIRIM ORTAKLIĞI|GAYRIMENKUL YATIRIM ORTAKLIGI/g, 'GYO');
  for (let i = 0; i < 3; i++) u = u.replace(KUYRUK, '');
  const ad = u.split(/\s+/).filter(Boolean).map(basHarf).join(' ').replace(/ Ve /g, ' ve ');
  return ad.length >= 2 ? ad.slice(0, 120) : kod;
}
