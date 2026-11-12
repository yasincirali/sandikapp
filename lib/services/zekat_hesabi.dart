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
/// * Havl (Hanefi görüşü; Diyanet'in ölçüsü budur): yılın başında ve
///   sonunda nisap varsa, yıl İÇİNDE eklenenler dahil yıl sonundaki tüm
///   zekâta tabi mal hesaba girer. Lot lot "354 günü dolanı say" hesabı
///   (ilk sürüm, 2026-11-12) bu görüşle çelişip zekâtı düşük gösteriyordu.
/// * Havl ölçümü YAKLAŞIKTIR: bir kameri yıldan (354 gün) uzun süredir
///   elde tutulan lotların BUGÜNKÜ değeri nisaba ulaşıyorsa havl dolmuş
///   sayılır. Doğrusu yıl başı nisabını o günün altın ve varlık fiyatıyla
///   ölçmektir; geçmiş fiyat her varlıkta yok (uydurma sayı yasak) ve
///   tahmini hesap için bugünkü fiyat yeterli yaklaşım. Arada nisabın
///   altına düşüp çıkma (yıl içi kesinti) da izlenmez.
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
    required this.eskiTutar,
    required this.yeniTutar,
    required this.borc,
    required this.fiyatsizVarlik,
    required this.haricTurler,
    this.nisabaUlasmaTarihi,
  });

  /// Kullanılan 24 ayar gram altın fiyatı.
  final double gramFiyati;

  /// Bir kameri yıldan (≥354 gün) uzun süredir elde tutulan lotların
  /// bugünkü değeri — havl ölçümü bunun nisaba ulaşmasına bakar.
  final double eskiTutar;

  /// Yıl içinde eklenen (354 günden yeni) lotların bugünkü değeri. Havl
  /// dolmuşsa hesaba DAHİLDİR (Hanefi: yıl içi kazanç asla katılır).
  final double yeniTutar;

  /// Düşülen borç (negatif girdi 0'a çekilir).
  final double borc;

  /// Fiyatı bilinmediği için tutara girmeyen pozisyon sayısı.
  final int fiyatsizVarlik;

  /// Kullanıcının elinde olup kapsam dışı kalan türler (gösterim için).
  final Set<AssetType> haricTurler;

  /// Lotlar alış sırasıyla (bugünkü değerleriyle) toplandığında toplamın
  /// nisaba İLK ulaştığı lotun alış günü; hiç ulaşmıyorsa `null`.
  final DateTime? nisabaUlasmaTarihi;

  double get nisapTutari => ZekatOlcusu.nisapGram * gramFiyati;

  /// Havl dolmuş mu: bir yıldan eski lotların bugünkü değeri ≥ nisap.
  bool get havlDoldu => eskiTutar >= nisapTutari;

  /// Havl dolmamışsa yılın dolacağı gün (nisaba ulaşılan alış + 354 gün);
  /// toplam nisaba hiç ulaşmıyorsa ya da havl dolmuşsa `null`.
  DateTime? get havlTarihi => havlDoldu
      ? null
      : nisabaUlasmaTarihi
          ?.add(const Duration(days: ZekatOlcusu.havlGun));

  /// Zekât matrahı: tüm zekâta tabi mal (yeni lotlar dahil) − borç, en az 0.
  double get matrah =>
      (eskiTutar + yeniTutar - borc).clamp(0.0, double.infinity);

  /// Havl dolmuş VE matrah nisaba ulaşıyor (borç nisabın altına
  /// indirebilir).
  bool get nisabaUlasti => havlDoldu && matrah >= nisapTutari;

  /// Verilecek zekât; havl dolmamışsa ya da nisap altındaysa 0.
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
/// ## Satışlar ve lot yaşı — FIFO
/// Kısmi satılmış pozisyonda hangi lotun elde kaldığını defter söylemez
/// (maliyet yürüyen ortalamayla tutulur). Satışlar EN ESKİ alımdan düşülür
/// (ilk giren ilk çıkar; hisse vergisinde de yerleşik kural). Lot yaşı
/// yalnız havl ölçümünü ve havl tarihini etkiler; havl dolunca tutar
/// zaten yeni lotları da kapsar.
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
  var eski = 0.0;
  var yeni = 0.0;
  var fiyatsiz = 0;
  final haric = <AssetType>{};
  final parcalar = <({DateTime tarih, double deger})>[];
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
      parcalar.add((tarih: l.addedDate, deger: deger));
      // `isAfter` değil `!isAfter`: tam 354. gün bir yıl dolmuş sayılır.
      if (!l.addedDate.isAfter(sinir)) {
        eski += deger;
      } else {
        yeni += deger;
      }
    }
  }

  final nisap = ZekatOlcusu.nisapGram * gram;
  parcalar.sort((a, b) => a.tarih.compareTo(b.tarih));
  DateTime? ulasma;
  var birikim = 0.0;
  for (final p in parcalar) {
    birikim += p.deger;
    if (birikim >= nisap) {
      ulasma = p.tarih;
      break;
    }
  }

  return ZekatSonucu(
    gramFiyati: gram,
    eskiTutar: eski,
    yeniTutar: yeni,
    borc: borc > 0 ? borc : 0,
    fiyatsizVarlik: fiyatsiz,
    haricTurler: haric,
    nisabaUlasmaTarihi: ulasma,
  );
}
