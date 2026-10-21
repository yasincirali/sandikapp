/// Hafta sonu kapalı piyasalar (Ar-Ge 21 Eki 08:45 #3; yasin "şerh
/// düştüklerim dışında yap", 2026-10-21).
///
/// ## Neden
/// `analyze-signals` hafta sonu da her saat koşuyor ve BIST hissesi, fon,
/// BES ve eurobond için mum çekip aynı kapanışı yeniden hesaplıyordu: yeni
/// bar yok, sinyal değişmez, kaynak (Yahoo/TEFAS) hız sınırı ve işlem süresi
/// boşa gider. Cumartesi ve pazar bu türler atlanır.
///
/// Koşmaya DEVAM edenler: kripto (7/24), altın (yurt içi altın hafta sonu da
/// yazılıyor, `hafta_sonu_yurt_ici_seri`), döviz ve emtia (müşteri raporu
/// 21 Eki 09:15: hareket az ama sıfır değil). Resmî tatiller sonraki adım;
/// liste yanlışsa susmak yerine koşmak tercih edilir.
///
/// Gün Türkiye saatiyle (UTC+3, yaz saati yok) hesaplanır: gece yarısına
/// yakın bir UTC anı TR'de ertesi gün olabilir.
const HAFTA_SONU_KAPALI = new Set(['hisse', 'fon', 'bes', 'eurobond']);

export function haftaSonuKapaliMi(tur: string, simdi: Date): boolean {
  if (!HAFTA_SONU_KAPALI.has(tur)) return false;
  const tr = new Date(simdi.getTime() + 3 * 3600 * 1000);
  const g = tr.getUTCDay();
  return g === 0 || g === 6;
}
