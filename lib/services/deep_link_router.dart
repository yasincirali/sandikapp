import '../screens/main_navigation_screen.dart';

/// Uygulama DIŞI yüzeylerden (ana ekran widget'ı, iOS Canlı Etkinlik)
/// gelen dokunuşları hedef sekmeye çeviren SAF eşleme.
///
/// ## Neden ayrı ve saf
/// Eşleme kararı, onu uygulayan koddan (navigator, `ValueNotifier`,
/// `HomeWidget` akışı) ayrı duruyor: bu sayede "hangi URI nereye gider"
/// sorusu widget ağacı ya da platform kanalı kurmadan test edilebiliyor.
/// Kararı akışın içine gömseydik, yalnızca gerçek cihazda doğrulanabilirdi
/// — Canlı Etkinlik'te bu pratikte hiç doğrulanamamak demek.
///
/// ## Desteklenen hedefler
/// Üç yüzey de AYNI yere gider: performans ekranı, günlük (intraday)
/// grafik. Kullanıcı isteği (2026-09-12): "hem widget hem de canlı
/// aktivitelerde tıklandığında performans ekranı günlük grafik açılmalı."
///
/// Günlük grafik için ayrı bir parametre GEREKMEZ:
/// `PortfolioPerformanceScreen` zaten `_selectedPeriodIdx = 0` (intraday)
/// ile açılıyor. Buraya bir "dönem" bilgisi eklemek, iki yerde yaşayan
/// ikinci bir varsayılan üretirdi.
class DeepLinkRouter {
  const DeepLinkRouter._();

  /// Ana ekran widget'ı dokunuşu — Kotlin `WIDGET_CLICK_URI` ve Swift
  /// `widgetClickURL` ile birebir aynı.
  static const widgetHost = 'widget';

  /// iOS Canlı Etkinlik (kilit ekranı / Dynamic Island) dokunuşu.
  static const liveActivityHost = 'live-activity';

  /// Belirli bir varlığın detayı — `sandik://asset/<id>`.
  ///
  /// Push bildirimleri zaten `asset_id` ile bu ekrana gidiyor
  /// (`NotificationService.openAssetPerformance`); bu host aynı hedefi
  /// URI ile adreslenebilir yapar (widget, paylaşılan bağlantı, App Links).
  static const assetHost = 'asset';

  /// `sandik://asset/<id>` → `<id>`; değilse null.
  static String? hedefVarlikId(Uri? uri) {
    if (uri == null || uri.scheme != 'sandik' || uri.host != assetHost) {
      return null;
    }
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segs.length != 1) return null;
    return segs.first;
  }

  /// URI'yi hedef sekme indeksine çevirir; tanınmayan URI için `null`.
  ///
  /// `null` dönmesi "hiçbir şey yapma" demektir — uygulama yine açılır,
  /// yalnızca sekme değişmez. Tanınmayan bir derin bağlantıda kullanıcıyı
  /// rastgele bir ekrana atmak, hiç yönlendirmemekten daha kötüdür.
  static int? hedefSekme(Uri? uri) {
    if (uri == null) return null;
    if (uri.scheme != 'sandik') return null;

    return switch (uri.host) {
      widgetHost || liveActivityHost => MainNavigationScreen.performansSekmesi,
      _ => null,
    };
  }

  /// Metin biçimindeki URI için [hedefSekme].
  ///
  /// Native taraf bazen `String` gönderir (Canlı Etkinlik `userInfo`),
  /// bazen `Uri` (HomeWidget akışı). Ayrıştırma hatası çökmemeli:
  /// bozuk bir derin bağlantı uygulamayı açmayı engellememeli.
  static int? hedefSekmeMetin(String? deger) {
    if (deger == null || deger.isEmpty) return null;
    return hedefSekme(Uri.tryParse(deger));
  }
}
