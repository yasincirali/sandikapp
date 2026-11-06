import 'crash_reporter.dart';
import 'history_service.dart';
import 'period_summary_service.dart' show SummaryPeriod;
import 'supabase_service.dart';

/// Kıyas serisi çekici imzası — `HistoryService.getSymbolHistory` ile aynı.
/// Testler ağsız sahte seri verebilsin diye parametre.
typedef KiyasSeriGetirici = Future<Map<int, double>> Function(
  String sembol, {
  required int periodDays,
  ResolutionTier? cozunurluk,
});

/// Mevduat faiz geçmişi çekici — `SupabaseService.mevduatFaizGecmisi` ile
/// aynı. Testler ağsız sahte faiz verebilsin diye parametre.
typedef KiyasFaizGetirici = Future<List<MevduatFaizNoktasi>> Function(
    String dilim, DateTime baslangic);

/// Kıyas kartının AĞA ÇIKAN tarafı: kıyas varlıklarının TL fiyat serisi
/// (mevduatta faiz geçmişinden kurulan birikim endeksi).
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
  ///
  /// Mevduat ([KiyasSeriTuru.mevduatFaizi]) fiyat değil faiz geçmişi okur
  /// ve `mevduatKiyasSerisi` ile endekse çevirir; tablo boş/yok ya da
  /// dönemi kapsamıyorsa satır yoktur, kullanıcıya hata gösterilmez.
  static Future<Map<KiyasVarligi, Map<int, double>>> serileriGetir(
    SummaryPeriod period, {
    KiyasSeriGetirici? getir,
    KiyasFaizGetirici? faizGetir,
    DateTime? simdi,
  }) async {
    if (period.intraday) return const {};
    final g = getir ?? HistoryService.instance.getSymbolHistory;
    final fg = faizGetir ?? SupabaseService.instance.mevduatFaizGecmisi;
    final now = simdi ?? DateTime.now();
    final katman = cozunurluk(period);
    final sonuclar = await Future.wait([
      for (final v in KiyasVarligi.values)
        () async {
          try {
            if (v.tur == KiyasSeriTuru.mevduatFaizi) {
              // Dönem başından ÖNCEKİ haftanın faizi de gerekir (o gün
              // yürürlükteki oran); boşluk sınırı kadar geriden okunur.
              final bas = now.subtract(Duration(
                  days: period.days + kenarPayiGun + mevduatAzamiBoslukGun));
              return (v, mevduatKiyasSerisi(await fg(v.sembol, bas), son: now));
            }
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
