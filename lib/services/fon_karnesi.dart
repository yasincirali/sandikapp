import '../models/asset_type.dart';
import 'tefas_service.dart';

/// Fon karnesi (F4, 2026-09-29) — "bu fon kendi kategorisinde nerede?"
///
/// ## Neden
/// Fon sahibi bugün yalnızca fonunun kendi getirisini görüyor. "1 yılda
/// %38" iyi mi kötü mü, aynı işi yapan fonlar yanında anlaşılmıyor. Karne
/// fonu YALNIZCA kendi kategorisindeki fonlarla kıyaslar: TEFAS'ın
/// `fonTurAciklama` alanı ("Hisse Senedi Şemsiye Fonu" …).
///
/// ## Kararlar
///   · **Kıyas grubu = aynı fon tipi (YAT/EMK/BYF) + aynı kategori.**
///     Emeklilik fonu ile yatırım fonu aynı kategori adını taşısa bile
///     maliyet yapısı ve vergisi farklıdır; aynı yarışa sokulmaz.
///   · **Sıra "yarışma sırası"dır (1, 2, 2, 4):** eşit getirili fonlar aynı
///     sırayı paylaşır; sıradaki fon, önündeki fon SAYISI + 1'dir. Eşitlerden
///     birini keyfî olarak öne almak kullanıcıya uydurma bir üstünlük söylerdi.
///   · **Getirisi bilinmeyen fon o dönemin sırasına girmez** (yeni kurulmuş
///     fonun 1 yıllık getirisi yoktur). Her dönemin kendi "kaç fondan"
///     sayısı vardır; başlıktaki kategori sayısı ise kategorideki TÜM fonlar.
///   · **Uydurma yok:** kategori bilinmiyorsa, fon katalogda yoksa ya da hiçbir
///     dönemde en az [asgariKiyasSayisi] fonluk kıyas kurulamıyorsa `null`.
///     Tek fonlu kategoride "1 fondan 1." bir bilgi değildir.
///   · **Ortancaya fark yüzde PUAN'dır** (getiri − ortanca), yüzde değil:
///     %30 ile %25 arası 5 puandır, "%20 daha iyi" değil.
///
/// Saf fonksiyon: ağ yok, önbellek yok, `build()` dışında çağrılır
/// (provider'da). Test: `test/fon_karnesi_test.dart`.

/// Karnede gösterilen dönemler. TEFAS 3a/6a/3y/5y de veriyor; kart sade
/// kalsın diye kısa (1 ay), orta (yılbaşından beri) ve uzun (1 yıl) yeter.
enum KarneDonemi { ay1, yilBasi, yil1 }

/// Bir dönemde fonun kategorisindeki yeri.
class DonemSirasi {
  const DonemSirasi({
    required this.donem,
    required this.sira,
    required this.kiyasSayisi,
    required this.getiri,
    required this.ortanca,
  });

  final KarneDonemi donem;

  /// 1 = kategorinin en yüksek getirisi.
  final int sira;

  /// Bu dönemde getirisi bilinen, kategorideki fon sayısı (fon dahil).
  final int kiyasSayisi;

  /// Fonun dönem getirisi, yüzde (`38.5` = %38,5).
  final double getiri;

  /// Kategori ortancası, yüzde.
  final double ortanca;

  /// Ortancaya fark, yüzde PUAN. Pozitif = ortancanın üstünde.
  double get ortancayaFark => getiri - ortanca;
}

class FonKarnesi {
  const FonKarnesi({
    required this.fonKodu,
    required this.kategori,
    required this.kategoriFonSayisi,
    required this.donemler,
  });

  final String fonKodu;
  final String kategori;

  /// Kategorideki (aynı fon tipinde) toplam fon sayısı — fon dahil.
  final int kategoriFonSayisi;

  /// Kıyası kurulabilen dönemler, [KarneDonemi] sırasıyla. Boş olmaz.
  final List<DonemSirasi> donemler;

  DonemSirasi? donem(KarneDonemi d) {
    for (final s in donemler) {
      if (s.donem == d) return s;
    }
    return null;
  }

  /// Tek satırlık özetin dönemi: 1 yıl varsa o (fon karşılaştırmasında
  /// en çok bakılan pencere), yoksa yılbaşından beri, yoksa 1 ay.
  DonemSirasi get ozetDonemi =>
      donem(KarneDonemi.yil1) ?? donem(KarneDonemi.yilBasi) ?? donemler.first;
}

/// Bir dönemde sıraya girmek için gereken asgari fon sayısı (fon dahil).
const int asgariKiyasSayisi = 2;

double? _getiri(TefasFund f, KarneDonemi d) {
  final v = switch (d) {
    KarneDonemi.ay1 => f.return1m,
    KarneDonemi.yilBasi => f.returnYtd,
    KarneDonemi.yil1 => f.return1y,
  };
  if (v == null || v.isNaN || v.isInfinite) return null;
  return v;
}

double _ortanca(List<double> sirali) {
  final n = sirali.length;
  final orta = n ~/ 2;
  return n.isOdd ? sirali[orta] : (sirali[orta - 1] + sirali[orta]) / 2;
}

/// [fonKodu]nun kategorisindeki karnesi; kurulamıyorsa `null`.
FonKarnesi? fonKarnesi(String fonKodu, List<TefasFund> tumFonlar) {
  final kod = fonKodu.trim().toUpperCase();
  if (kod.isEmpty) return null;
  TefasFund? fon;
  for (final f in tumFonlar) {
    if (f.code.trim().toUpperCase() == kod) {
      fon = f;
      break;
    }
  }
  final kategori = fon?.kategori;
  if (fon == null || kategori == null) return null;

  final grup = [
    for (final f in tumFonlar)
      if (f.kategori == kategori && f.fundType == fon.fundType) f,
  ];

  final donemler = <DonemSirasi>[];
  for (final d in KarneDonemi.values) {
    final benim = _getiri(fon, d);
    if (benim == null) continue;
    final degerler = <double>[
      for (final f in grup)
        if (_getiri(f, d) case final v?) v,
    ]..sort();
    if (degerler.length < asgariKiyasSayisi) continue;
    final onde = degerler.where((v) => v > benim).length;
    donemler.add(DonemSirasi(
      donem: d,
      sira: onde + 1,
      kiyasSayisi: degerler.length,
      getiri: benim,
      ortanca: _ortanca(degerler),
    ));
  }
  if (donemler.isEmpty) return null;

  return FonKarnesi(
    fonKodu: fon.code,
    kategori: kategori,
    kategoriFonSayisi: grup.length,
    donemler: donemler,
  );
}

/// Varlığın TEFAS fon kodu — fon değilse ya da kod yoksa `null`.
///
/// Eski kayıtlar kodu `TEFAS:IJC` biçiminde, yeniler öneksiz (`DLY`)
/// taşıyor (bkz. `Asset.displayTicker`); ikisi de aynı koda iner.
String? fonKoduOf({required AssetType tur, required String ticker}) {
  if (tur != AssetType.fon) return null;
  final kod = ticker
      .trim()
      .replaceFirst(RegExp(r'^TEFAS:', caseSensitive: false), '')
      .trim()
      .toUpperCase();
  return kod.isEmpty ? null : kod;
}
