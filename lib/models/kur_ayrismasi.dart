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
///
/// ## Kaynak sayılar (açıklama sayfası, 2026-11-13)
/// Satıra dokununca açılan sayfa iki etkinin nereden geldiğini GERÇEK
/// sayılarla yazar; o sayılar burada, hesabın kendisinden çıkar — sayfa
/// formülü yeniden kurmaz (hesap `build()`'e girmez, iki yer ayrışamaz):
/// [alisKuru] X0, [guncelKur] X, [dovizKar] `q × (P − a) − C` (varlığın para
/// biriminde kâr), [dovizDeger] `q × P` (bugünkü döviz değeri), [sembol]
/// o para biriminin işareti (yalnız USD/EUR/GBP buraya ulaşır), [kurFarki]
/// `X − X0`, [toplam] iki etkinin toplamı (= kartın TL kârı).
typedef KurAyrismasi = ({
  double fiyatEtkisi,
  double kurEtkisi,
  double alisKuru,
  double guncelKur,
  double dovizKar,
  double dovizDeger,
  String sembol,
  double kurFarki,
  double toplam,
});

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
  final dovizKar = q * (p - a) - pozisyon.commission;
  final fiyat = dovizKar * x0;
  final kur = q * p * (x - x0);
  if (fiyat.abs().round() == 0 && kur.abs().round() == 0) return null;
  return (
    fiyatEtkisi: fiyat,
    kurEtkisi: kur,
    alisKuru: x0,
    guncelKur: x,
    dovizKar: dovizKar,
    dovizDeger: q * p,
    sembol: _sembol(pozisyon.currency),
    kurFarki: x - x0,
    toplam: fiyat + kur,
  );
}

String _sembol(String currency) => switch (currency.toUpperCase()) {
      'USD' => r'$',
      'EUR' => '€',
      'GBP' => '£',
      _ => currency.toUpperCase(),
    };

/// Ayrışma YALNIZ alış kuru eksik olduğu için mi çıkmıyor (2026-11-13)?
///
/// Eskiden satır sessizce kayboluyordu; Premium kullanıcı nedenini hiç
/// öğrenmiyordu. Bu kapı [kurAyrismasi]'nın öteki koşullarının HEPSİ
/// sağlanıp tek eksiğin `purchaseFxRate` (≤ 0 ya da varsayılan 1,0)
/// olduğu durumu ayırır — TL varlıkta, bilinmeyen bugünkü kurda ya da
/// fiyatı/miktarı olmayan pozisyonda "alış kurunu ekle" demek yanlış
/// yönlendirme olurdu (ekleseler de satır çıkmazdı). Seriden kur önermek
/// kapsam dışı: önerilen kur kullanıcının gerçek alış kuru değildir.
bool kurAyrismasiAlisKuruEksik(Asset pozisyon, {required double? guncelKur}) {
  final x0 = pozisyon.purchaseFxRate;
  final x = guncelKur;
  if (pozisyon.currency.toUpperCase() == 'TRY') return false;
  if (x == null || !(x > 0)) return false;
  if (x0 > 0 && x0 != 1.0) return false;
  return pozisyon.quantity > 0 &&
      pozisyon.currentPrice > 0 &&
      pozisyon.purchasePrice > 0;
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
