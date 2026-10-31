import 'altin_kisayollari.dart' show altinTuru;
import 'asset.dart';
import 'asset_type.dart';
import 'position.dart' show aktifLotlar, positionKey;
import 'tur_secici_duzeni.dart';

/// Varlık Ekle'nin "Tekrar al" çipi: daha önce alınmış bir varlık, tek
/// dokunuşla seçilmeye hazır.
class TekrarAlAdayi {
  const TekrarAlAdayi({
    required this.sonuc,
    required this.sonMiktar,
    required this.birim,
  });

  /// Arama sonucuyla AYNI biçim: ekran onu `_aramaSonucuSec`'e verir, tür
  /// ve kimlik geçişleri tek yerden yapılır.
  final TurAramaSonucu sonuc;

  /// Son alımın miktarı. Forma YAZILMAZ: yalnız çipte ipucu olarak görünür
  /// (bu ay farklı miktar alan kullanıcı eski sayıyı silmek zorunda kalmasın,
  /// dikkatsizce eski miktarla kayıt da düşmesin).
  final double sonMiktar;

  /// Miktarın birimi: `gr`, `ounce`, `piece` (`Asset.unitType`).
  final String birim;
}

/// "Tekrar al" adayları (müşteri raporu 31 Eki 13:15, yasin "yap").
///
/// ## Neden
/// Hedef kitlenin çekirdek davranışı aylık birikim: her ay aynı altını,
/// aynı fonu ekliyor. Bunun için tür → arama → sembol (4 dokunuş) ya da
/// Portföy › varlık › Al (3 dokunuş) gerekiyordu. Çip aramanın hemen
/// altında, tek dokunuşta miktar alanına götürür.
///
/// ## Kural
/// - Yalnız [sahip]'in kendi ALIŞ kayıtları sayılır (ortağın lotu "ben
///   aldım" değildir); silinmiş kayıt sayılmaz. Satılmış varlık da aday:
///   "geçen ay sattım, yine alıyorum" gerçek bir akış.
/// - Sıra: alış sayısı (en sık tekrarlanan önde), eşitlikte en son alım.
/// - Yalnız arama sonucuyla temsil edilebilen türler: BIST/ABD hissesi,
///   fon, kripto, altın, döviz. Mevduat/BES sözleşmeyle, eurobond katalogla,
///   emtia ve elle fiyatlı kayıt serbest adla girilir; çipleri olmaz.
/// - Bayrağı kapalı tür ([turAcik]) ve kapalı ABD ([abdAcik]) süzülür.
List<TekrarAlAdayi> tekrarAlAdaylari(
  Iterable<Asset> lotlar, {
  required String sahip,
  required bool Function(AssetType) turAcik,
  required bool abdAcik,
  int adet = 3,
}) {
  final sayac = <String, int>{};
  final son = <String, Asset>{};
  final sonuclar = <String, TurAramaSonucu>{};
  for (final a in lotlar) {
    if (a.userId != sahip || !a.isBuy || !a.isActive) continue;
    final s = _sonuc(a, turAcik: turAcik, abdAcik: abdAcik);
    if (s == null) continue;
    final k = '${s.kutu.tur.name}|${s.kutu.abd}|${s.sembol}';
    sayac[k] = (sayac[k] ?? 0) + 1;
    final onceki = son[k];
    if (onceki == null || !a.addedDate.isBefore(onceki.addedDate)) {
      son[k] = a;
      sonuclar[k] = s;
    }
  }
  final anahtarlar = sayac.keys.toList()
    ..sort((x, y) {
      final c = sayac[y]!.compareTo(sayac[x]!);
      return c != 0 ? c : son[y]!.addedDate.compareTo(son[x]!.addedDate);
    });
  return [
    for (final k in anahtarlar.take(adet))
      TekrarAlAdayi(
        sonuc: sonuclar[k]!,
        sonMiktar: son[k]!.quantity,
        birim: son[k]!.unitType,
      ),
  ];
}

TurAramaSonucu? _sonuc(
  Asset a, {
  required bool Function(AssetType) turAcik,
  required bool abdAcik,
}) {
  if (!turAcik(a.type)) return null;
  final ticker = a.ticker.trim();
  switch (a.type) {
    case AssetType.hisse:
      if (ticker.isEmpty) return null;
      final abd = a.abdHissesi;
      if (abd && !abdAcik) return null;
      // BIST seçicisi Yahoo biçimini (`THYAO.IS`) ister; yalnız o biçimdeki
      // kayıt katalog yolundan açılır (eski serbest sembollü kayıt değil).
      if (!abd && !ticker.toUpperCase().endsWith('.IS')) return null;
      return TurAramaSonucu(
        kutu: TurKutusu(AssetType.hisse, abd: abd),
        etiket: abd ? PazarEtiketi.abd : PazarEtiketi.bist,
        sembol: ticker.toUpperCase().replaceAll('.IS', ''),
        ad: a.name,
        ticker: ticker.toUpperCase(),
      );
    case AssetType.fon:
      if (!ticker.toUpperCase().startsWith('TEFAS:')) return null;
      final kod = ticker.substring('TEFAS:'.length).toUpperCase();
      if (kod.isEmpty) return null;
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.fon),
        etiket: PazarEtiketi.tefas,
        sembol: kod,
        ad: a.name,
        ticker: 'TEFAS:$kod',
      );
    case AssetType.kripto:
      final kod = a.kriptoKod;
      if (kod == null) return null;
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.kripto),
        etiket: PazarEtiketi.kripto,
        sembol: kod,
        ad: a.name,
        ticker: ticker,
      );
    case AssetType.altin:
      final g = altinTuru(a);
      if (g == null) return null;
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.altin),
        etiket: PazarEtiketi.altin,
        sembol: g.label,
        ad: g.label,
        altin: g,
      );
    case AssetType.doviz:
      final kod = a.subCategory?.trim();
      // TL "dövizi" fiyatsız nakittir, tekrar alınacak bir kur değil.
      if (kod == null || kod.isEmpty || kod == 'TRY') return null;
      return TurAramaSonucu(
        kutu: const TurKutusu(AssetType.doviz),
        etiket: PazarEtiketi.doviz,
        sembol: kod,
        ad: a.name,
        dovizEtiketi: kod,
      );
    default:
      return null;
  }
}

/// Kayıttan sonra "Bir tane daha ekle" mi, alarm önerisi mi (müşteri raporu
/// 31 Eki 13:15, yasin "yap").
///
/// Portföyünü KURAN kullanıcı (kendi açık pozisyonu [esik]'ten az) her
/// varlık için Ana sayfa → + → tür akışını baştan yaşıyordu; ilk oturumda
/// portföyü tamamlayan tutunuyor. Kayıt sonu tek bir bildirim gösterir
/// (`sandikSnack` öncekini kapatır): kurulum aşamasında "bir tane daha"
/// alarm önerisinden değerlidir, kurulmuş portföyde eski davranış (alarm
/// önerisi) kalır. Raporda "koşulsuz" denmişti; alarm önerisi neredeyse
/// her fiyatlı kayıtta çıktığı için koşulsuz eylem hiç görünmezdi.
bool birTaneDahaOnerilsinMi(Iterable<Asset> lotlar,
    {required String sahip, int esik = 5}) {
  // Sahip bilinmiyorsa (portföy henüz yüklenmedi) karar verilemez: eski
  // davranış (alarm önerisi) kalır.
  if (sahip.isEmpty) return false;
  final anahtarlar = <String>{
    for (final a in aktifLotlar(lotlar.where((a) => a.userId == sahip)))
      positionKey(a),
  };
  return anahtarlar.length < esik;
}
