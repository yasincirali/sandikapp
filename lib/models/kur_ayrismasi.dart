import 'asset.dart';

/// Döviz cinsi pozisyonun TL kâr/zararının iki kaynağı (Ar-Ge 2026-11-07 #1,
/// Premium): varlığın kendi fiyat hareketi ve kurun hareketi.
///
/// ## Tanım ve özdeşlik
/// q = miktar, P = güncel fiyat, a = ağırlıklı alış fiyatı, C = komisyon
/// (varlığın para biriminde), X0 = ağırlıklı alış kuru, X = bugünkü kur.
///
///   fiyat etkisi = (q × (P − a) − C) × X0
///   kur etkisi   = q × P × (X − X0)
///
/// Toplamları `q·P·X − (q·a + C)·X0`, yani pozisyon kartının yazdığı TL
/// kâr/zararın (`_pnlOzeti`: `toTRY(totalValue) − totalCostTRY`) KENDİSİ.
/// Fikir dosyasındaki formülde komisyon yoktu; uygulama komisyonu maliyete
/// alış kuruyla ekliyor (`Asset.totalCostTRY`), o yüzden komisyon fiyat
/// etkisinden düşülür — komisyon varlığın para biriminde ödenmiş bir
/// maliyettir, kurla ilgisi yoktur. Böylece iki sayının toplamı ekrandaki
/// kâra kuruşu kuruşuna eşit kalır (`kur_ayrismasi_test`).
///
/// ## Ne zaman yok (uydurma sayı yasak)
/// - TL cinsi varlık (BIST, fon, altın, TL kotasyonlu döviz): kur etkisi
///   tanımsız, satır çizilmez.
/// - Bugünkü kur bilinmiyor (portföy durumu yok ya da kur 0) veya para
///   birimi uygulamanın çevirdiği USD/EUR/GBP dışında (`toTRY` onları TL
///   sayar; kur etkisi yazmak yanlış olurdu).
/// - Alış kuru bilinmiyor: `purchaseFxRate` ≤ 0 ya da varsayılan 1,0.
///   Kaydedilmemiş kur `Asset`'te 1,0 olarak durur; USD/EUR/GBP'nin TL
///   karşılığı 2005'ten beri 1'in hayli üstünde, 1,0 gerçek bir kur değil
///   "bilinmiyor" demektir.
/// - Alış fiyatı ya da güncel fiyat yok (≤ 0), miktar yok.
/// - İki etki de yuvarlanınca ₺0: "+₺0 · +₺0" bilgi taşımaz.
///
/// [pozisyon] AÇIK pozisyonun görünüm varlığıdır
/// (`aggregatePositions(...)` → `Position.asDisplayAsset`; `aktifLotlar` ile
/// aynı süzgeç). Kapanmış pozisyonun bugünkü kârı yoktur.
typedef KurAyrismasi = ({double fiyatEtkisi, double kurEtkisi});

KurAyrismasi? kurAyrismasi(Asset pozisyon, {required double? guncelKur}) {
  final q = pozisyon.quantity;
  final p = pozisyon.currentPrice;
  final a = pozisyon.purchasePrice;
  final x0 = pozisyon.purchaseFxRate;
  final x = guncelKur;
  if (pozisyon.currency.toUpperCase() == 'TRY') return null;
  if (x == null || !(x > 0)) return null;
  if (!(x0 > 0) || x0 == 1.0) return null;
  if (!(q > 0) || !(p > 0) || !(a > 0)) return null;
  final fiyat = (q * (p - a) - pozisyon.commission) * x0;
  final kur = q * p * (x - x0);
  if (fiyat.abs().round() == 0 && kur.abs().round() == 0) return null;
  return (fiyatEtkisi: fiyat, kurEtkisi: kur);
}

/// Bugünkü kur: portföyün TL'ye çevirdiği AYNI kur (`PortfolioState.toTRY`
/// ile birebir — özdeşlik ancak iki taraf aynı kuru kullanırsa tutar).
/// Uygulamanın çevirmediği para biriminde `null`.
double? pozisyonKuru(String currency,
        {required double usdTry,
        required double eurTry,
        required double gbpTry}) =>
    switch (currency.toUpperCase()) {
      'USD' => usdTry,
      'EUR' => eurTry,
      'GBP' => gbpTry,
      _ => null,
    };
