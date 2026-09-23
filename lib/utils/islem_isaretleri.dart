import '../models/asset.dart';

/// Grafikteki bir alım/satım işareti.
///
/// [x] eksen birimi GÜNDÜR (kesirli; gün içinde de aynı birim, bkz.
/// `AssetDetailScreen` X ekseni). [birim] işlemin kendi birim fiyatıdır (TL):
/// alımda alış, satışta satış fiyatı.
typedef IslemIsareti = ({double x, double birim, bool satis, Asset lot});

/// Varlık grafiğinin işlem işaretleri — GERÇEK işlem anında, GERÇEK işlem
/// birim fiyatında.
///
/// ## Neden (kullanıcı ekran görüntüsü, 2026-09-24)
/// *"Alış 6.163,57 olduğu gösteriliyor ancak yeşil noktaya geldiğimde değeri
/// o değil gibi gözüküyor; alış noktası hatalı yerde gösterilmemeli."*
///
/// İşaret eskiden işlemin düştüğü çubuğun ÇİZGİ ÜZERİNDEKİ noktasına
/// yapıştırılıyordu; yüksekliği o çubuğun piyasa değeriydi, alış fiyatı
/// değil. Uzun dönemlerde işlem ayrıca gece yarısına çekiliyordu (14:32'lik
/// alım 1H'de 00:00 çubuğunda). Artık X = işlem anı, Y = işlem fiyatı.
///
/// Kurallar:
///   * Temettü ve silinmiş lot işaret üretmez (`isActive` + alım/satım).
///   * [eksenBasi]'ndan önceki işlem bu dönemin işareti değildir.
///   * Veri başlamadan yapılan işlem [ilkX]..[sonX] aralığına yaslanır —
///     eksenin dışına taşmaz.
///   * Saati bilinmeyen (tarih seçiciyle girilen, 00:00) işlem o günün
///     başındadır — uydurma saat yok.
List<IslemIsareti> islemIsaretleri({
  required List<Asset> lotlar,
  required DateTime eksenBasi,
  required double ilkX,
  required double sonX,
}) {
  final out = <IslemIsareti>[];
  for (final lot in lotlar) {
    if (!lot.isActive) continue;
    if (!lot.isBuy && !lot.isSell) continue;
    final txX =
        lot.addedDate.difference(eksenBasi).inMinutes / (60.0 * 24.0);
    if (txX < 0) continue;
    final birim = (lot.isSell
            ? (lot.sellPrice ?? lot.purchasePrice)
            : lot.purchasePrice) *
        lot.purchaseFxRate;
    if (birim <= 0) continue;
    out.add((
      x: txX.clamp(ilkX, sonX).toDouble(),
      birim: birim,
      satis: lot.isSell,
      lot: lot,
    ));
  }
  return out;
}
