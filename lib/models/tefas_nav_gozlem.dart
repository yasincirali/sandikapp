import '../utils/tr_format.dart';

/// Sunucuda (observe-tefas-nav) bir fonun NAV tarihinin İLK görüldüğü an.
///
/// TEFAS yayın zaman damgası vermez; bu kayıt onun yerine geçen GÖZLEM.
/// Gün içi seride fonun NAV basamağı `ilkGorulme`'ye çapalanır (bkz.
/// `HistoryService.fonBasamakAni`). Kayıt yoksa basamak eski sabit saate
/// (`tefasNavYayinSaati`) düşer — davranış değişmez, yalnızca iyileşir.
class TefasNavGozlem {
  const TefasNavGozlem({
    required this.fonKodu,
    required this.navTarihi,
    required this.ilkGorulme,
    this.oncekiKontrol,
  });

  /// TEFAS kodu, öneksiz ('AFT').
  final String fonKodu;

  /// NAV'ın TEFAS'taki tarihi — yerel takvim günü (saat 00:00).
  final DateTime navTarihi;

  /// Sunucunun bu NAV tarihini ilk gördüğü an (yerel saat).
  final DateTime ilkGorulme;

  /// Bir önceki turun zamanı (o turda bu tarih henüz YOKTU). `null` ise
  /// aralık bilinmiyor: `ilkGorulme` yalnızca üst sınır.
  final DateTime? oncekiKontrol;

  /// `tefas_nav_gozlem` satırından. `nav_tarihi` `date` kolonu
  /// (`YYYY-MM-DD`), damgalar timestamptz — ikisi de yerel saate çevrilir.
  static TefasNavGozlem? fromMap(Map<String, dynamic> m) {
    final kod = (m['fon_kodu'] as String?)?.trim();
    final tarih = DateTime.tryParse(m['nav_tarihi'] as String? ?? '');
    final ilk = DateTime.tryParse(m['ilk_gorulme'] as String? ?? '');
    if (kod == null || kod.isEmpty || tarih == null || ilk == null) return null;
    final onceki = DateTime.tryParse(m['onceki_kontrol'] as String? ?? '');
    return TefasNavGozlem(
      fonKodu: kod,
      // `date` saat taşımaz; tryParse'ın verdiği (saatsiz, yerel) anın
      // yıl/ay/günü alınır — `toLocal()` çağrılmaz, UTC'ye çevrim TR'de
      // günü geri kaydırırdı.
      navTarihi: dayKey(tarih),
      ilkGorulme: ilk.toLocal(),
      oncekiKontrol: onceki?.toLocal(),
    );
  }
}
