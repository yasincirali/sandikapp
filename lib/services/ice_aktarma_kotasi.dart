import '../providers/bulk_cart_provider.dart';
import '../providers/portfolio_provider.dart' show kotaAnahtari;

/// Toplu kayıttan ÖNCE kota planı (paywall incelemesi, 2026-10-20).
///
/// ## Neden
/// Toplu Ekle / ekstre içe aktarma kalemleri paralel yazıyor ve kota kapısı
/// (`addAsset` → `kotaDolu`) kalem kalem çalışıyordu: 10'luk ücretsiz kotada
/// 15 kalemlik ekstre yarıda kesiliyor, ilk 10'u (sepet sırasına göre)
/// yazılıp gerisi sepette kalıyordu; kullanıcı sonucu ancak hata özetinden
/// öğreniyordu. Kayda başlamadan "N kalem var, M'si sığıyor" demek
/// kullanıcıya seçim bırakır: Premium'a geçip hepsini ekle, sığanları
/// kaydet ya da vazgeç. Kalem kalem kapı yine durur (yarış koşulu ağı).
///
/// ## Sayım `addAsset` ile AYNI anahtar
/// Aynı varlığa ikinci lot yeni varlık sayılmaz ([kotaAnahtari]); satış
/// kota yemez; ekstreden gelen vadeli mevduat sözleşme açar, her biri bir
/// varlıktır. Sıra sepet sırasıdır: kullanıcı neyin sığdığını sepette
/// görebilsin diye ilk gelen sığar.
class IceAktarmaKotaPlani {
  const IceAktarmaKotaPlani({
    required this.sigan,
    required this.sigmayan,
    required this.yeniVarlik,
  });

  /// Kaydedilecek kalemler (sepet sırasıyla).
  final List<BulkCartItem> sigan;

  /// Kotaya sığmayan kalemler; sepette kalır.
  final List<BulkCartItem> sigmayan;

  /// Sepetin eklediği YENİ varlık sayısı (sığan + sığmayan).
  final int yeniVarlik;

  bool get asiyor => sigmayan.isNotEmpty;
}

/// Saf: [kalemler] sepet sırasıyla, [kayitli] bugünkü kota anahtarları
/// (`kotaAnahtarlari`), [sinir] ücretsiz sınır. Sınırsızda (`null`) her
/// şey sığar.
IceAktarmaKotaPlani iceAktarmaKotaPlani({
  required List<BulkCartItem> kalemler,
  required Set<String> kayitli,
  required int? sinir,
}) {
  final sigan = <BulkCartItem>[];
  final sigmayan = <BulkCartItem>[];
  // Bu turda yer ayrılan yeni anahtarlar.
  final ayrilan = <String>{};
  // Kotaya sığmayan ALIMLARIN anahtarları: aynı varlığın satışı da
  // kaydedilmez (defterde alımı olmayan satış zaten reddedilirdi, ama
  // nedeni "kota" olarak söylenir, "elindekinden fazla" değil).
  final disarida = <String>{};

  for (final k in kalemler) {
    final anahtar = k.mevduat != null
        ? 'mevduat|${k.id}'
        : kotaAnahtari(k.type, k.ticker, k.currency);
    if (k.satis) {
      (disarida.contains(anahtar) && !kayitli.contains(anahtar)
              ? sigmayan
              : sigan)
          .add(k);
      continue;
    }
    if (kayitli.contains(anahtar) || ayrilan.contains(anahtar)) {
      sigan.add(k);
      continue;
    }
    if (sinir == null || kayitli.length + ayrilan.length < sinir) {
      ayrilan.add(anahtar);
      sigan.add(k);
    } else {
      disarida.add(anahtar);
      sigmayan.add(k);
    }
  }
  return IceAktarmaKotaPlani(
    sigan: sigan,
    sigmayan: sigmayan,
    yeniVarlik: ayrilan.length + disarida.length,
  );
}
