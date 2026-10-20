import 'package:flutter/widgets.dart';

import 'analytics_service.dart';

/// Hangi ekran açılıyor — sadeleştirme kararlarının ölçüsü (2026-10-19).
///
/// ## Neden
/// yasin (müşteri gözüyle rapor, 2026-10-19): "Hangi ekranı kimin
/// kullandığını bilmeden sadeleştirme yapılamaz." `AnalyticsService` bir
/// `FirebaseAnalyticsObserver` sunuyordu ama hiçbir yere bağlı değildi;
/// elle `logScreenView` yalnız dört yerdeydi. Firebase'in kendi otomatik
/// ekran kaydı iOS'ta tek `FlutterViewController` görür, işe yaramaz.
///
/// ## Neden kendi gözlemcimiz (FirebaseAnalyticsObserver değil)
/// 1. Analytics açılışta BEKLENMEDEN kurulur (`main._initDeferredServices`);
///    `MaterialApp` kurulurken `navigatorObserver` henüz `null` olabilir.
///    Bu gözlemci her olayda servisi o an çağırır, servis hazır değilse
///    olay sessizce düşer (servisin kendi sözleşmesi).
/// 2. Adı olmayan rota (dialog, sheet, sistem rotası) sayılmaz: Firebase
///    gözlemcisi onları `null` adla gönderirdi, rapor gürültüye boğulurdu.
/// 3. Alt menü sekmeleri rota değildir; [sekmeDegisti] onları da aynı
///    olayla sayar (`MainNavigationScreen.aktifSekme`).
///
/// ## Ad nereden gelir
/// `adaptiveRoute(settings: RouteSettings(name: …))`. Sınıf adından
/// türetmek işe yaramaz: Android sürümü `--obfuscate` ile derlenir,
/// `runtimeType` karartılır. Her `adaptiveRoute` çağrısının ad taşıdığını
/// `ekran_olcumu_test` kilitler.
///
/// ## Gizlilik
/// Yalnız ekran adı gider (`screen_view`); tutar, sembol, içerik yok.
/// Analytics yasal metinde zaten var, yeni alıcı ya da amaç yok.
class EkranOlcumu extends NavigatorObserver {
  EkranOlcumu({void Function(String ad)? gonder})
      : _gonder = gonder ??
            ((ad) => AnalyticsService.instance.logScreenView(screenName: ad));

  static final EkranOlcumu instance = EkranOlcumu();

  final void Function(String ad) _gonder;

  /// Alt menü sekmelerinin ölçüdeki adları (`MainNavigationScreen._screens`
  /// sırasıyla; 2 = ortadaki Ekle düğmesi, sekme değil).
  static const sekmeAdlari = <int, String>{
    0: 'sekme_ana',
    1: 'sekme_portfoy',
    3: 'sekme_performans',
    4: 'sekme_profil',
  };

  /// Son gönderilen ad: aynı ekran arka arkaya iki kez sayılmasın (ör.
  /// aynı sekmeye yeniden dokunma, aynı ekranın üstünde sheet kapanması).
  String? _son;

  void _kaydet(String? ad) {
    if (ad == null || ad.isEmpty || ad == _son) return;
    _son = ad;
    _gonder(ad);
  }

  /// Açık sekme; ana rotaya dönüşte o sekme yeniden sayılır.
  int _sekme = 0;

  /// Kök rota (`MaterialApp.home`, adı `/`) sekmelerin kabuğudur: adı
  /// ekran adı değildir, açık sekme sayılır.
  static String? _ad(Route<dynamic>? r) {
    if (r is! PageRoute) return null;
    final ad = r.settings.name;
    return ad == null || ad.startsWith('/') ? null : ad;
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _kaydet(_ad(route));

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _kaydet(_ad(newRoute));

  /// Geri dönülen ekran da bir görüntülemedir (Firebase gözlemcisiyle aynı
  /// anlam). Sheet/dialog kapanışı sayılmaz (altındaki ekran hiç gitmedi).
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! PageRoute || previousRoute is! PageRoute) return;
    _kaydet(_ad(previousRoute) ?? (_sekmelerAcik ? sekmeAdlari[_sekme] : null));
  }

  /// Sekme kabuğu (`MainNavigationScreen`) ağaçta mı. Oturum kapalıyken kök
  /// rota giriş ekranıdır; ona dönüş sekme sayılmaz.
  bool _sekmelerAcik = false;

  /// Alt menüde sekme değişti (kabuk açılırken de bir kez çağrılır).
  void sekmeDegisti(int indeks) {
    if (!sekmeAdlari.containsKey(indeks)) return;
    _sekmelerAcik = true;
    _sekme = indeks;
    _kaydet(sekmeAdlari[indeks]);
  }

  /// Sekme kabuğu ağaçtan çıktı (çıkış yapıldı).
  void sekmelerKapandi() {
    _sekmelerAcik = false;
    _son = null;
  }
}
