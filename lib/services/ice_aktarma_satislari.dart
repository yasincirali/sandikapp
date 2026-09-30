import '../models/asset.dart';
import '../models/position.dart';
import '../providers/bulk_cart_provider.dart';

/// Ekstreden gelen satış satırının deftere yazılacak hâli.
class IceAktarmaSatisi {
  const IceAktarmaSatisi({
    required this.kalem,
    required this.maliyet,
    required this.kur,
  });

  final BulkCartItem kalem;

  /// Satış günündeki ağırlıklı ortalama alış fiyatı — satış satırının
  /// `purchasePrice`'ı. Gerçekleşen kâr/zarar (`sellProceedsTRY` −
  /// maliyet) buna dayanır.
  final double maliyet;

  /// Aynı ağırlıkla alış kuru (`purchaseFxRate`); TRY varlıkta 1.
  final double kur;
}

/// Aracı kurum işlem ekstresindeki satışları deftere yazılabilir hâle
/// getirir — SAF, ağ yok (karar 5.4, 2026-09-30).
///
/// ## Neden ayrı ve saf
/// Satış, defterin tek "eksi" hareketidir: yanlış yazılırsa pozisyon eksiye
/// düşer ya da gerçekleşen kâr/zarar uydurma bir maliyetle hesaplanır. Karar
/// widget'tan ayrı olunca test edilebilir: "o gün elde kaç lot vardı",
/// "maliyet neydi" soruları Supabase'siz sınanır.
///
/// ## Kurallar
/// - Satışlar TARİH SIRASIYLA işlenir; aynı ekstredeki önceki satışlar
///   eldeki miktardan düşülür.
/// - Elde olan = satış GÜNÜ SONUNA kadarki aktif alımlar − o güne kadarki
///   satışlar (defterdekiler + bu planda kabul edilenler). Fazlası
///   REDDEDİLİR, kısmen bile yazılmaz: yarım satış kullanıcının ekstresiyle
///   uyuşmayan bir defter üretirdi.
/// - Maliyet: satış gününe kadarki alımların ağırlıklı ortalaması —
///   `aggregatePositions` ile aynı ortalama maliyet yöntemi (FIFO değil).
/// - Temettü ve silme kayıtları miktara girmez (`isActive`, `isDividend`).
///
/// Çağıran ALIMLARI önce yazar, sonra planı güncel defterle kurar: aynı
/// ekstredeki alımlar satıştan önce defterde olur.
abstract final class IceAktarmaSatislari {
  static const _eps = 1e-9;

  static ({List<IceAktarmaSatisi> yazilacak, List<BulkCartItem> reddedilen})
      planla({
    required List<Asset> defter,
    required List<BulkCartItem> satislar,
  }) {
    final sirali = [...satislar]
      ..sort((a, b) => a.addedDate.compareTo(b.addedDate));
    final kabulEdilen = <String, List<({DateTime tarih, double adet})>>{};
    final yazilacak = <IceAktarmaSatisi>[];
    final reddedilen = <BulkCartItem>[];

    for (final s in sirali) {
      final anahtar = positionKey(_varlikGibi(s));
      final gunSonu = DateTime(
          s.addedDate.year, s.addedDate.month, s.addedDate.day, 23, 59, 59);
      var alinan = 0.0, maliyetToplam = 0.0, kurluToplam = 0.0;
      var satilan = 0.0;
      for (final a in defter) {
        if (!a.isActive || a.isDividend) continue;
        if (positionKey(a) != anahtar) continue;
        if (a.addedDate.isAfter(gunSonu)) continue;
        if (a.isSell) {
          satilan += a.quantity;
        } else if (a.isBuy) {
          alinan += a.quantity;
          maliyetToplam += a.quantity * a.purchasePrice;
          kurluToplam += a.quantity * a.purchasePrice * a.purchaseFxRate;
        }
      }
      for (final k in kabulEdilen[anahtar] ??
          const <({DateTime tarih, double adet})>[]) {
        if (!k.tarih.isAfter(gunSonu)) satilan += k.adet;
      }
      final elde = alinan - satilan;
      if (alinan <= 0 || s.quantity > elde + _eps) {
        reddedilen.add(s);
        continue;
      }
      kabulEdilen
          .putIfAbsent(anahtar, () => [])
          .add((tarih: s.addedDate, adet: s.quantity));
      yazilacak.add(IceAktarmaSatisi(
        kalem: s,
        maliyet: maliyetToplam / alinan,
        kur: maliyetToplam > 0 ? kurluToplam / maliyetToplam : 1.0,
      ));
    }
    return (yazilacak: yazilacak, reddedilen: reddedilen);
  }

  /// Pozisyon anahtarı için kalemin `Asset` karşılığı — `positionKey` tek
  /// kaynak kalsın (anahtar formülü burada tekrar yazılmaz).
  static Asset _varlikGibi(BulkCartItem k) => Asset(
        id: 'pos:ice-aktarma',
        userId: '',
        name: k.name,
        ticker: k.ticker,
        type: k.type,
        quantity: k.quantity,
        purchasePrice: k.price,
        currency: k.currency,
        notes: '',
        subCategory: k.subCategory,
        unitType: k.unitType,
        addedDate: k.addedDate,
      );

  /// Satış satırının `addSellTransaction`'a verilecek pozisyon görünümü:
  /// kimlik `pos:` ile başlar (refAssetId yazılmaz), maliyet ve kur plandan.
  static Asset pozisyonGorunumu(IceAktarmaSatisi p, double satisFiyati) =>
      Asset(
        id: 'pos:ice-aktarma',
        userId: '',
        name: p.kalem.name,
        ticker: p.kalem.ticker,
        type: p.kalem.type,
        quantity: p.kalem.quantity,
        purchasePrice: p.maliyet,
        currency: p.kalem.currency,
        notes: '',
        subCategory: p.kalem.subCategory,
        unitType: p.kalem.unitType,
        purchaseFxRate: p.kur,
        currentPrice: satisFiyati,
        isManualPrice: p.kalem.isManualPrice,
      );
}
