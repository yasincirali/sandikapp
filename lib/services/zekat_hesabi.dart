import '../models/asset.dart';
import '../models/asset_type.dart';
import '../models/position.dart';

/// Zekât hesabı — portföyden, Diyanet ölçüsüyle TAHMİNİ hesap (2026-11-12).
///
/// Ücretsizdir (edinme amaçlı, bilinçli karar): Premium kilidi, bayrak ya
/// da sunucu yok; hesap cihazda, saf fonksiyonda. Kişisel veri yazılmaz,
/// "düşülecek borç" bile kaydedilmez (sheet'in belleğinde yaşar).
///
/// ## Ölçüler (Diyanet İşleri Başkanlığı)
/// * Nisap 80,18 g altın. Altın fiyatı **24 ayar** gram ile çarpılır
///   (`FiyatKaynagi.gramAltin24`): Diyanet nisabı saf altın gramıyla
///   verir; portföy durumundaki `goldGramTry` 22 ayardır (sikke ailesinin
///   ölçeği) ve yalnız baz birim altınken çekilir, bu yüzden kullanılmaz.
/// * Havl: bir kameri yıl = 354 gün. Alış tarihinden bu yana en az 354 gün
///   geçmiş lot zekâta tabi; daha yenisi ayrı satırda gösterilir.
/// * Oran %2,5.
///
/// ## Uydurma sayı yok
/// Gram fiyatı bilinmiyorsa (`null`/≤0) sonuç `null`: nisap da tutar da
/// gösterilmez (CLAUDE.md fiyat kaynağı madde 3). Fiyatı düşmüş (0) varlık
/// tutara girmez, sayısı [ZekatSonucu.fiyatsizVarlik]'ta söylenir.
class ZekatOlcusu {
  const ZekatOlcusu._();

  /// Nisap — gram (24 ayar) altın.
  static const double nisapGram = 80.18;

  /// Havl — bir kameri yıl, gün.
  static const int havlGun = 354;

  /// Zekât oranı.
  static const double oran = 0.025;

  /// Zekâta giren türler.
  ///
  /// * Altın, döviz, mevduat (nakit), hisse, fon: Diyanet'in saydığı para
  ///   ve ticari mal kalemleri; değer bugünkü piyasa değeri.
  /// * Kripto: uygulamada ayrı tür; değer saklayan ve alınıp satılan bir
  ///   varlık olarak ticari mal gibi piyasa değeriyle girer.
  /// * Eurobond: tahsili umulan alacak/borç senedi; piyasa değeriyle girer.
  /// * Emtia: portföyde değer artışı için tutulan (alınıp satılan) emtia,
  ///   ticaret malı sayılır ve girer; gümüş de bu türdedir.
  ///
  /// Girmeyenler [haricTurler]: BES (birikimin bir kısmı devlet katkısı ve
  /// erişim koşullu; tam mülkiyet şartı tartışmalı) ve Diğer (içeriği
  /// bilinmiyor — ev/araba gibi kullanım malı olabilir).
  static const Set<AssetType> dahilTurler = {
    AssetType.altin,
    AssetType.doviz,
    AssetType.mevduat,
    AssetType.hisse,
    AssetType.fon,
    AssetType.kripto,
    AssetType.eurobond,
    AssetType.emtia,
  };

  static const Set<AssetType> haricTurler = {AssetType.bes, AssetType.diger};
}

/// [zekatHesapla] çıktısı. Tutarlar TL.
class ZekatSonucu {
  const ZekatSonucu({
    required this.gramFiyati,
    required this.tabiTutar,
    required this.yeniTutar,
    required this.borc,
    required this.fiyatsizVarlik,
    required this.haricTurler,
  });

  /// Kullanılan 24 ayar gram altın fiyatı.
  final double gramFiyati;

  /// Havli dolmuş (≥354 gün) lotların bugünkü değeri, borç düşülmeden.
  final double tabiTutar;

  /// Henüz bir yılı dolmayan lotların bugünkü değeri (zekâta girmez).
  final double yeniTutar;

  /// Düşülen borç (negatif girdi 0'a çekilir).
  final double borc;

  /// Fiyatı bilinmediği için tutara girmeyen pozisyon sayısı.
  final int fiyatsizVarlik;

  /// Kullanıcının elinde olup kapsam dışı kalan türler (gösterim için).
  final Set<AssetType> haricTurler;

  double get nisapTutari => ZekatOlcusu.nisapGram * gramFiyati;

  /// Zekât matrahı: tabi tutar − borç, en az 0.
  double get matrah => (tabiTutar - borc).clamp(0.0, double.infinity);

  /// Matrah nisaba ulaşıyor mu? (Nisap miktarına sahip olan da yükümlü.)
  bool get nisabaUlasti => matrah >= nisapTutari;

  /// Verilecek zekât; nisabın altındaysa 0.
  double get zekat => nisabaUlasti ? matrah * ZekatOlcusu.oran : 0;
}

/// Portföyden tahmini zekât.
///
/// [lotlar]: kullanıcının KENDİ defteri (ortağın lotu girmemeli; çağıran
/// süzer). Bugünkü mülkiyet `aktifLotlar` ile kurulur (CLAUDE.md
/// "Kapanmış pozisyon").
///
/// [gramAltin24Try]: 24 ayar gram altın TL; yoksa sonuç `null`.
///
/// ## Satışlar ve havl — FIFO
/// Kısmi satılmış pozisyonda hangi lotun elde kaldığını defter söylemez
/// (maliyet yürüyen ortalamayla tutulur). Satışlar EN ESKİ alımdan düşülür
/// (ilk giren ilk çıkar; hisse vergisinde de yerleşik kural). Böylece
/// "bir yılı doldu" denen tutar, kullanıcının gerçekten bir yıldır tuttuğu
/// en temkinli tahmindir.
ZekatSonucu? zekatHesapla({
  required Iterable<Asset> lotlar,
  required double? gramAltin24Try,
  required double Function(double tutar, String paraBirimi) toTRY,
  required DateTime bugun,
  double borc = 0,
}) {
  final gram = gramAltin24Try;
  if (gram == null || !(gram > 0) || gram.isNaN || gram.isInfinite) {
    return null;
  }
  var tabi = 0.0;
  var yeni = 0.0;
  var fiyatsiz = 0;
  final haric = <AssetType>{};
  final sinir = bugun.subtract(const Duration(days: ZekatOlcusu.havlGun));

  for (final p in aggregatePositions(aktifLotlar(lotlar))) {
    final r = p.representative;
    if (!ZekatOlcusu.dahilTurler.contains(r.type)) {
      haric.add(r.type);
      continue;
    }
    if (!(r.currentPrice > 0) || !(p.totalQuantity > 0)) {
      fiyatsiz++;
      continue;
    }
    final alimlar = p.lots.where((l) => l.isBuy).toList()
      ..sort((a, b) => a.addedDate.compareTo(b.addedDate));
    final alinan = alimlar.fold(0.0, (s, l) => s + l.quantity);
    // Elde kalandan fazlası satılmış demektir; en eskiden düş.
    var satilan = (alinan - p.totalQuantity).clamp(0.0, alinan);
    for (final l in alimlar) {
      final dusen = satilan < l.quantity ? satilan : l.quantity;
      satilan -= dusen;
      final kalan = l.quantity - dusen;
      if (kalan <= 0) continue;
      final deger = toTRY(kalan * r.currentPrice, r.currency);
      // `isAfter` değil `!isAfter`: tam 354. gün havl dolmuş sayılır.
      if (!l.addedDate.isAfter(sinir)) {
        tabi += deger;
      } else {
        yeni += deger;
      }
    }
  }

  return ZekatSonucu(
    gramFiyati: gram,
    tabiTutar: tabi,
    yeniTutar: yeni,
    borc: borc > 0 ? borc : 0,
    fiyatsizVarlik: fiyatsiz,
    haricTurler: haric,
  );
}
