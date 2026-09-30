import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import '../screens/main_navigation_screen.dart';
import 'crash_reporter.dart';
import 'deep_link_router.dart';
import 'notification_service.dart';

/// Uygulama DIŞINDAN gelen `sandik://` bağlantılarını Flutter'a taşıyan köprü
/// (yol haritası 3.8).
///
/// ## Neden ayrı bir köprü
/// Ana ekran widget'ı ve Canlı Etkinlik dokunuşları `home_widget`'ın kendi
/// akışından geliyor (`HomeWidgetService`). Tarayıcıdan, paylaşılan bir
/// mesajdan ya da başka bir uygulamadan açılan `sandik://asset/<id>` o
/// akışa hiç düşmüyordu: Android manifest'te intent-filter, iOS'ta URL
/// şeması vardı ama intent'i alan Dart tarafı yoktu. `app_links` o boşluğu
/// doldurur — Navigator'ı değiştirmez, yalnızca URI akışı verir.
///
/// ## Kapsam
/// `asset`, `enflasyon` ve `yil-ozeti` host'ları ele alınır (son ikisi App
/// Store In-App Event bağlantıları, karar 6.1). `widget` / `live-activity` host'ları
/// `HomeWidgetService` tarafından zaten karşılanıyor; aynı intent'i iki
/// dinleyicinin işlemesi sekmeyi iki kez değiştirirdi (zararsız ama
/// gereksiz) — bu yüzden burada bilinçli olarak yok sayılır.
///
/// Hedefe gidiş push bildirimleriyle aynı yol: `openAssetPerformance`
/// soğuk açılışta Navigator ve portföy hazır olana kadar kendisi bekler.
class DeepLinkService {
  DeepLinkService._()
      : _openAsset = ((id) => NotificationService.instance.openAssetPerformance(
              id,
              // Sahte / başkasına ait / silinmiş id: sessiz geçme, hata
              // ekranı göster — kullanıcı bir bağlantıya dokundu.
              onNotFound: NotificationService.instance.showAssetNotFound,
            )),
        _openReel = NotificationService.instance.openReelGetiri,
        _sekmeyeGit = ((i) => MainNavigationScreen.sekmeIstegi.value = i);

  /// Test için: hedef eylemler enjekte edilebilir.
  @visibleForTesting
  DeepLinkService.withHandler(
    this._openAsset, {
    void Function()? openReel,
    void Function(int sekme)? sekmeyeGit,
  })  : _openReel = openReel ?? (() {}),
        _sekmeyeGit = sekmeyeGit ?? ((_) {});

  static final DeepLinkService instance = DeepLinkService._();

  final void Function(String assetId) _openAsset;
  final void Function() _openReel;
  final void Function(int sekme) _sekmeyeGit;
  StreamSubscription<Uri>? _sub;

  /// Köprüyü kurar.
  ///
  /// **Yalnızca akışa abone olunur; `getInitialLink()` ÇAĞRILMAZ.**
  /// (2026-09-14 incelemesi.) Eklentinin iki platformdaki kaynağı da aynı:
  /// `getInitialLink` yanıtı döndürürken `initialLinkSent` bayrağını
  /// KURMUYOR, `onListen` ise bayrak kurulu değilken soğuk açılış
  /// bağlantısını ilk aboneye yeniden veriyor
  /// (`AppLinksPlugin.java:80/130`, `AppLinksIosPlugin.swift:68/238`).
  /// İkisini birden kullanmak `sandik://asset/<id>` ile açılışta varlık
  /// ekranını ÜST ÜSTE İKİ KEZ push ediyordu. Paketin README'si de tek
  /// yol olarak akışı gösteriyor ("Subscribe to all events (initial link
  /// and further)").
  Future<void> init() async {
    if (_sub != null) return;
    final links = AppLinks();
    _sub = links.uriLinkStream.listen(
      handle,
      onError: (Object e, StackTrace st) =>
          CrashReporter.report(e, st, reason: 'deep_link_stream'),
    );
  }

  /// URI'yi eyleme çevirir. `true` → bir hedef bulundu.
  @visibleForTesting
  bool handle(Uri uri) {
    final id = DeepLinkRouter.hedefVarlikId(uri);
    if (id != null) {
      _openAsset(id);
      return true;
    }
    if (DeepLinkRouter.reelGetiriIster(uri)) {
      _openReel();
      return true;
    }
    // Yalnız etkinlik host'u: `widget` / `live-activity` sekme eşlemesi
    // HomeWidgetService'in (bkz. Kapsam) — burada ikinci kez uygulanmaz.
    if (uri.scheme == 'sandik' && uri.host == DeepLinkRouter.yilOzetiHost) {
      final sekme = DeepLinkRouter.hedefSekme(uri);
      if (sekme != null) _sekmeyeGit(sekme);
      return true;
    }
    return false;
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
