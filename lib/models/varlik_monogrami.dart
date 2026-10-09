import 'asset_type.dart';

/// Satır rozetinde gösterilecek kısa sembol (bayrak `goz_alici`).
///
/// ## Neden (göz alıcılık paketi A, yasin 2026-10-09)
/// Satır başı ikonu türden geliyordu: beş hisse beş aynı çizgi işareti,
/// ASELS ile THYAO listede ayırt edilemiyordu. Benchmark (Trade Republic,
/// Parqet, Delta) varlığın KENDİ yüzünü gösteriyor; logo kaynağı ve marka
/// izni ayrı karar olduğu için ilk adım sembolün kendisi.
///
/// ## Kural
/// - Yalnız sembolü kullanıcıya bir şey söyleyen türler: hisse (ABD dahil),
///   fon, kripto. Altın/emtia/mevduat/BES/eurobond/diğer ikonda kalır —
///   `ALTIN_CEYREK`, ISIN ya da sözleşme uuid'i rozet olarak anlamsız.
/// - Kaynak önekleri (`TEFAS:`, `KRIPTO:`) ve `.IS` atılır; ilk ÜÇ karakter
///   alınır. Üç: fon kodu ve kripto sembolü zaten üç harf, hisse kodunun ilk
///   üçü (ASE/THY/GAR/AKB) iki harften çok daha az çakışıyor (AKBNK/AKSA).
/// - Harf/rakam dışı ya da 2 karakterden kısa sembol → `null` (ikon kalır);
///   uydurma rozet yazılmaz.
String? varlikMonogrami({required AssetType type, required String ticker}) {
  switch (type) {
    case AssetType.hisse:
    case AssetType.fon:
    case AssetType.kripto:
      break;
    default:
      return null;
  }
  var t = ticker.trim().toUpperCase();
  if (t.contains(':')) t = t.split(':').last;
  if (t.endsWith('.IS')) t = t.substring(0, t.length - 3);
  t = t.replaceAll(RegExp(r'[^A-Z0-9ÇĞİÖŞÜ]'), '');
  if (t.length < 2) return null;
  return t.length <= 3 ? t : t.substring(0, 3);
}
