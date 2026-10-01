import 'crash_reporter.dart';
import 'history_service.dart';
import 'period_summary_service.dart' show SummaryPeriod;

/// Kıyas serisi çekici imzası — `HistoryService.getSymbolHistory` ile aynı.
/// Testler ağsız sahte seri verebilsin diye parametre.
typedef KiyasSeriGetirici = Future<Map<int, double>> Function(
  String sembol, {
  required int periodDays,
  ResolutionTier? cozunurluk,
});

/// Kıyas kartının AĞA ÇIKAN tarafı: üç kıyas varlığının TL fiyat serisi.
///
/// Hesap burada YOK — saf hesap `KiyasService`'te. Bu ayrım `RecapService`
/// / `PeriodSummaryService` deseni: ağ çağıranın işi, hesap ağsız test
/// edilebilir.
///
/// ## Kaynak (fiyat kaynağı sözleşmesi)
/// Sembolü `KiyasVarligi.sembol` belirler (`fiyat_kaynagi.dart`), seri
/// `HistoryService.getSymbolHistory`'den gelir — takip listesinin ve
/// Karşılaştır ekranının yolu. Altın orada `altinGramSerisi` merdiveniyle
/// kurulur ve canlı kotasyona kalibre edilir; burada ikinci bir merdiven
/// YOKTUR.
class KiyasYukleyici {
  KiyasYukleyici._();

  /// Serinin dönemin SOLUNA taşması için eklenen gün.
  ///
  /// `getSymbolHistory` seriyi son noktadan geriye `periodDays` gün kırpar
  /// (`clipToPeriod`); dönem başı ise takvimden gelir (1A = önceki ayın
  /// aynı günü, 31 gün olabilir) ve hafta sonuna/tatile denk gelebilir.
  /// Pay olmadan dönem başı fiyatı serinin dışında kalıyor ve ilk
  /// ölçüm İLERİDEN alınıyordu. 10 gün: `KiyasService.geriTolerans`.
  static const kenarPayiGun = 10;

  /// Kıyas için çözünürlük: dönemin varsayılan katmanı, ama HAFTALIKTAN
  /// kaba değil.
  ///
  /// Haftalık kova haftanın kapanışını pazartesi damgasıyla taşır; akış
  /// gününe fiyat bağlayan PME'de bu, çarşamba alımını cuma fiyatıyla
  /// eşlemek demekti (bkz. `getSymbolHistory` [cozunurluk] notu).
  static ResolutionTier cozunurluk(SummaryPeriod period) {
    final v = ResolutionTierMeta.pickForSpan(period.days.toDouble());
    return v == ResolutionTier.weekly ? ResolutionTier.daily : v;
  }

  /// Üç kıyas serisini PARALEL çeker. Boş dönen varlık haritada YOKTUR
  /// (kart o satırı çizmez). GÜNLÜK'te boş harita.
  ///
  /// Bir sembolün hatası diğerlerini düşürmez; Crashlytics'e non-fatal
  /// gider (servis katmanı catch'i sessiz kalmaz).
  static Future<Map<KiyasVarligi, Map<int, double>>> serileriGetir(
    SummaryPeriod period, {
    KiyasSeriGetirici? getir,
  }) async {
    if (period.intraday) return const {};
    final g = getir ?? HistoryService.instance.getSymbolHistory;
    final katman = cozunurluk(period);
    final sonuclar = await Future.wait([
      for (final v in KiyasVarligi.values)
        () async {
          try {
            final s = await g(v.sembol,
                periodDays: period.days + kenarPayiGun, cozunurluk: katman);
            return (v, s);
          } catch (e, st) {
            CrashReporter.report(e, st,
                reason: 'KiyasYukleyici.serileriGetir(${v.name})');
            return (v, const <int, double>{});
          }
        }(),
    ]);
    return {
      for (final (v, s) in sonuclar)
        if (s.isNotEmpty) v: s,
    };
  }
}
