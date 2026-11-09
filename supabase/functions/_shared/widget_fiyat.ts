// Tek varlık widget'ının uygulama açılmadan tazelenmesi — saf yardımcılar
// (`widget-fiyat`, yasin onayı 2026-10-26: "Tek varlık widget'ı uygulama
// açılmadan da tazelensin").
//
// ── Neden sunucu, neden yalnız bu semboller ─────────────────────────────────
// Widget uzantısı oturum jetonu TAŞIMAZ (karar): yalnız uygulamada zaten
// gömülü olan public URL + anon anahtarla bu fonksiyonu çağırır. Bu yüzden
// fonksiyon yalnız sunucunun ZATEN tuttuğu kamu piyasa fiyatlarını döner:
//   · altın ayarları + TL dövizler → `yurt_ici_kotasyon` (0101; truncgil,
//     `Buying` önce — uygulamanın gösterdiği alan; `degisim_pct` truncgil'in
//     `Change`'i — uygulamanın gösterdiği günlük yüzde, `PriceService
//     ._truncgilChange`)
//   · kripto → `kripto_fiyat` (0074; Binance TL fiyatı, yüzde İstanbul günü
//     açılışına göre — uygulama ve fiyat alarmıyla aynı hesap,
//     `live_prices.ts › kriptoSatiriKotasyon`)
//   · fon → `tefas_nav_gozlem` (0063; `observe-tefas-nav` iş günleri yarım
//     saatte bir TEFAS'ın son NAV'ını yazar). Müşteri raporu 2026-10-26
//     21:15 #2 (yasin "yap"): fon günde bir değişir, widget da günde bir
//     tazelenir (ritim native tarafta). Yüzde son iki NAV'dan — uygulamanın
//     `fonGunlukYuzdesi` kuralı (Dart) ile aynı.
// BIST hisse, endeks, emtia sunucuda canlı tutulmuyor: kapsam DIŞI.
// Fonksiyon başka bir sağlayıcıya GİTMEZ (açık proxy değil); sembol beyaz
// listede değilse yok sayılır.
//
// ── Uydurma sayı yok (fiyat_kaynagi.dart madde 3) ───────────────────────────
// Bayat satır dönmez: yurt içi kaydı 2 saatten, kripto 30 dakikadan eskiyse
// sembol yanıtta YOKTUR ve widget uygulamanın son yazdığı değeri (saatiyle)
// göstermeye devam eder. Dönen her değer kendi `zaman`ını taşır; widget o
// anı gösterir. Yüzde bilinmiyorsa alan yazılmaz (widget satırı gizler).

import { kriptoKodu } from './kripto.ts';
import { isFxSymbol, isGoldSymbol } from './live_prices.ts';

/// Bir istekte en çok kaç sembol. Widget yalnız SEÇİLİ varlıkları sorar
/// (çoğunlukla bir); sınır kötüye kullanıma karşı.
export const WIDGET_AZAMI_SEMBOL = 5;

/// İstek gövdesinin bayt sınırı — beş sembol ve JSON'u rahat sığar.
export const WIDGET_AZAMI_GOVDE = 1024;

/// Yurt içi kotasyon 5 dakikada bir yazılır (0101); 2 saat sessizlik =
/// cron/kaynak durmuş, sayı artık "şimdi" değil.
export const WIDGET_YURT_ICI_BAYATLIK_MS = 2 * 60 * 60_000;

/// Kripto dakikada bir yazılır (0074); 30 dk sessizlik = Binance/cron durmuş.
export const WIDGET_KRIPTO_BAYATLIK_MS = 30 * 60_000;

/// Fon NAV'ı iş günü başına bir kez görülür; uzun bayram tatili dahil
/// 5 günden eski gözlem = fon artık gözlenmiyor (portföylerden çıktı) ya da
/// gözlem durmuş. Widget uygulamanın son yazdığıyla kalır.
export const WIDGET_FON_BAYATLIK_MS = 5 * 24 * 60 * 60_000;

/// İki NAV arasında en çok bu kadar gün varsa yüzde hesaplanır (hafta sonu
/// + bir tatil). Daha geniş aralık = arada gözlenmemiş gün(ler) var; o
/// "günlük" değişim değildir, yazılmaz (uydurma sayı yok).
export const WIDGET_FON_YUZDE_AZAMI_GUN = 4;

/// Yanıt önbelleği (istemci ve isolate içi): truncgil kaydı 5 dk'da,
/// kripto 1 dk'da bir değişir.
export const WIDGET_ONBELLEK_SN = 60;

export type WidgetSembolTuru = 'yurt_ici' | 'kripto' | 'fon';

/// TEFAS fon kimliği: `TEFAS:` + 3 harf/rakam (uygulamadaki kanonik biçim).
const FON_KIMLIGI = /^TEFAS:[A-Z0-9]{3}$/;

/// `TEFAS:AFT` → `AFT`; fon kimliği değilse `null`.
export function fonKodu(sembol: string): string | null {
  return FON_KIMLIGI.test(sembol) ? sembol.slice('TEFAS:'.length) : null;
}

/// Sembol beyaz listede mi; öyleyse hangi tablodan okunur. Bilinmeyen
/// sembol `null` — yok sayılır, sorguya hiç girmez.
///
/// İstemci eşi: `FiyatKaynagi.widgetSunucuKapsamindaMi` (Dart). İki liste
/// `varlik_widget_sozlesmesi_test` ile kilitli.
export function widgetSembolTuru(sembol: string): WidgetSembolTuru | null {
  if (isGoldSymbol(sembol) || isFxSymbol(sembol)) return 'yurt_ici';
  // `kriptoKodu` küçük harfi büyütür; kimlik tam büyük harfli gelmeli ki
  // yanıt anahtarı istekteki sembolle aynı olsun.
  if (
    sembol === sembol.trim().toUpperCase() && kriptoKodu(sembol) !== null
  ) return 'kripto';
  if (fonKodu(sembol) !== null) return 'fon';
  return null;
}

/// İstek gövdesini çözer: `{ semboller: string[] }`.
///
/// Geçersiz gövde `null` (400). Beyaz liste dışı semboller sessizce düşer;
/// tekrarlar tekilleşir; sınırı aşan istek reddedilir (kısaltılmaz — kötü
/// niyetli olmayan istemci zaten beşten fazla sormaz).
export function widgetIstegiCoz(govde: unknown): string[] | null {
  if (typeof govde !== 'object' || govde === null || Array.isArray(govde)) return null;
  const ham = (govde as Record<string, unknown>)['semboller'];
  if (!Array.isArray(ham) || ham.length === 0 || ham.length > WIDGET_AZAMI_SEMBOL) {
    return null;
  }
  const out: string[] = [];
  for (const s of ham) {
    if (typeof s !== 'string' || s.length > 40) continue;
    if (widgetSembolTuru(s) === null || out.includes(s)) continue;
    out.push(s);
  }
  return out;
}

/// Yanıttaki tek sembol. `zaman` epoch ms (kaynağın yazım anı);
/// `degisim` günlük yüzde (bilinmiyorsa alan yok).
export type WidgetFiyat = { fiyat: number; zaman: number; degisim?: number };

function sayi(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}

/// `yurt_ici_kotasyon` satırı → yanıt öğesi. Bayat ya da geçersizse `null`.
export function yurtIciWidgetFiyati(
  satir: { ts: unknown; fiyat: unknown; degisim_pct: unknown },
  simdiMs: number,
): WidgetFiyat | null {
  const fiyat = sayi(satir.fiyat);
  if (fiyat === null || fiyat <= 0) return null;
  const zaman = Date.parse(String(satir.ts));
  if (!Number.isFinite(zaman) || simdiMs - zaman > WIDGET_YURT_ICI_BAYATLIK_MS) return null;
  const degisim = sayi(satir.degisim_pct);
  return degisim === null ? { fiyat, zaman } : { fiyat, zaman, degisim };
}

/// `kripto_fiyat` satırı → yanıt öğesi. Bayat ya da geçersizse `null`.
/// Yüzde yalnız günün açılışı biliniyorsa (uygulamayla aynı hesap).
export function kriptoWidgetFiyati(
  satir: { fiyat_try: unknown; gun_acilis_try: unknown; guncellendi: unknown },
  simdiMs: number,
): WidgetFiyat | null {
  const fiyat = sayi(satir.fiyat_try);
  if (fiyat === null || fiyat <= 0) return null;
  const zaman = Date.parse(String(satir.guncellendi));
  if (!Number.isFinite(zaman) || simdiMs - zaman > WIDGET_KRIPTO_BAYATLIK_MS) return null;
  const acilis = sayi(satir.gun_acilis_try);
  if (acilis === null || acilis <= 0) return { fiyat, zaman };
  return { fiyat, zaman, degisim: (fiyat / acilis - 1) * 100 };
}

/// `tefas_nav_gozlem`in bir fona ait en yeni iki satırı (yeniden eskiye)
/// → yanıt öğesi. `zaman` NAV'ın sunucuda İLK görüldüğü an: widget ritmi
/// "bugünün NAV'ı alındı mı"yı buna bakarak verir. Bayat ya da geçersizse
/// `null`.
export function fonWidgetFiyati(
  satirlar: { nav_tarihi: unknown; ilk_gorulme: unknown; nav: unknown }[],
  simdiMs: number,
): WidgetFiyat | null {
  const [son, onceki] = satirlar;
  if (!son) return null;
  const fiyat = sayi(son.nav);
  if (fiyat === null || fiyat <= 0) return null;
  const zaman = Date.parse(String(son.ilk_gorulme));
  if (!Number.isFinite(zaman) || simdiMs - zaman > WIDGET_FON_BAYATLIK_MS) return null;
  if (!onceki) return { fiyat, zaman };
  const oncekiNav = sayi(onceki.nav);
  const g1 = Date.parse(String(son.nav_tarihi));
  const g0 = Date.parse(String(onceki.nav_tarihi));
  if (
    oncekiNav === null || oncekiNav <= 0 || !Number.isFinite(g1) || !Number.isFinite(g0) ||
    g1 <= g0 || (g1 - g0) / 86_400_000 > WIDGET_FON_YUZDE_AZAMI_GUN
  ) return { fiyat, zaman };
  return { fiyat, zaman, degisim: (fiyat - oncekiNav) / oncekiNav * 100 };
}
