import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';

/// Filtre alt sayfasındaki kategori döşemelerinin sayısı ve payı.
///
/// Performans › Filtre (bayrak `goz_alici`) her türü "kaç varlık, portföyün
/// ne kadarı" ile gösterir; kullanıcı neyi süzeceğini seçmeden önce görür
/// (boş türü seçip boş grafikle karşılaşmaz). Hesap ekranın grafiğiyle AYNI
/// kümeden yapılır: kişi kapsamının sahip grupları, `isActive` lot'lar, net
/// pozisyon (`aggregatePositionsByOwner`) — satılıp bitmiş pozisyon ve
/// temettü satırı "varlık" sayılmaz, boş durum mesajıyla aynı cevap.
///
/// Değer TL'ye çevrilir ([toTRY], `PortfolioState.toTRY`). Fiyatı
/// bilinmeyen (değeri 0) pozisyon sayıya girer, paya girmez; toplam değer
/// 0 ise pay hiç yoktur ([TurFiltreOzeti.payVar] false) — uydurma oran
/// çizilmez.
class TurFiltreOzeti {
  const TurFiltreOzeti({required this.adet, required this.deger});

  final Map<AssetType, int> adet;
  final Map<AssetType, double> deger;

  int get toplamAdet => adet.values.fold(0, (a, b) => a + b);
  double get toplamDeger => deger.values.fold(0.0, (a, b) => a + b);
  bool get payVar => toplamDeger > 0;

  /// [tur]'ün değer payı (0–1); pay yoksa 0.
  double pay(AssetType tur) =>
      payVar ? (deger[tur] ?? 0) / toplamDeger : 0;

  static TurFiltreOzeti hesapla(
    List<List<Asset>> sahipLotlari,
    double Function(double tutar, String paraBirimi) toTRY,
  ) {
    final adet = <AssetType, int>{};
    final deger = <AssetType, double>{};
    final aktif = [
      for (final l in sahipLotlari) [for (final a in l) if (a.isActive) a],
    ];
    for (final p in aggregatePositionsByOwner(aktif)) {
      final a = p.asDisplayAsset();
      adet[a.type] = (adet[a.type] ?? 0) + 1;
      final v = toTRY(a.totalValue, a.currency);
      if (v > 0) deger[a.type] = (deger[a.type] ?? 0) + v;
    }
    return TurFiltreOzeti(adet: adet, deger: deger);
  }
}
