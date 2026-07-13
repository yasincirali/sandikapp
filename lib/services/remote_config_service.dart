import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';

/// Firebase Remote Config wrapper.
///
/// Server-side kontrol edilebilir feature flag'ler için tek merkez. Firebase
/// init başarısız olursa (config eksik / offline) default değerlerle no-op
/// çalışır — çağıran kodun try/catch ile sarmalanmasına gerek yok.
///
/// Kullanım:
///   RemoteConfigService.instance.premiumEnabled → bool
///   RemoteConfigService.instance.freeAssetLimit → int
///
/// Değer güncellemeleri fetch-and-activate ile alınır. `init` çağrısı fetch
/// tetikler; sonrasında değişiklikler bir sonraki uygulama açılışında (veya
/// TTL dolduğunda arka planda) yansır.
class RemoteConfigService {
  RemoteConfigService._();
  static final RemoteConfigService instance = RemoteConfigService._();

  FirebaseRemoteConfig? _rc;
  bool _initialized = false;

  // ── Default değerler ─────────────────────────────────────────────────────
  // Firebase Console'dan override edilene kadar bu değerler geçerli.
  static const _defaults = <String, dynamic>{
    // Master kill switch: kullanıcının göreceği TÜM üyelik/ödeme ekranları,
    // banner, chip, kilit overlay, paywall trigger'ları buna bağlı. false ise
    // premium sistem uygulamada hiç yokmuş gibi davranır. RevenueCat entegrasyonu
    // + store onayları tamamlanana kadar kapalı tutulur.
    'paywall_enabled': false,

    // Premium feature kill switch: paywall açık olsa bile emergency rollback
    // için premium özellikleri kapatabilir.
    'premium_enabled': true,

    // Free tier varlık limiti. Launch'ta 20 ile başla, engagement düşükse
    // gerçek ürün konumlanmasına göre azalt.
    'free_asset_limit': 20,

    // Paywall UI variant'ı ('A' | 'B'). A/B test için.
    'paywall_variant': 'A',

    // Aylık fiyat gösterimi (paywall'da lokalize göstermek için).
    'premium_price_monthly': '49₺/ay',
    'premium_price_yearly': '349₺/yıl',

    // Free kullanıcıya günde kaç sinyal analiz slot'u verilsin (1 = sadece
    // sabah, 2 = sabah+öğleden sonra). Premium her zaman 2.
    'free_signal_slots_per_day': 1,

    // Free kullanıcılar için AI portföy raporu etkin mi (upsell hook).
    'free_ai_report_enabled': false,
  };

  Future<void> init() async {
    if (_initialized) return;
    try {
      _rc = FirebaseRemoteConfig.instance;
      await _rc!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Debug'da hemen; prod'da 1 saat — network trafiğini azalt.
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(hours: 1),
      ));
      await _rc!.setDefaults(_defaults);
      // Fetch başlat ama beklet — offline'da default'lar geçerli olur.
      unawaited(_rc!.fetchAndActivate());
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('RemoteConfigService init failed: $e');
    }
  }

  /// Uygulama uzun süredir açıksa (bir gün, uçuş modundan çıkma, vs.)
  /// çağrılabilir. Foreground'a döndüğünde yenile.
  Future<void> refresh() async {
    if (_rc == null) return;
    try {
      await _rc!.fetchAndActivate();
    } catch (_) {}
  }

  // ── Feature flag getter'ları ─────────────────────────────────────────────
  /// Kullanıcının göreceği tüm üyelik/ödeme UI'ları buna bağlı. false ise
  /// paywall, premium banner, kilit overlay, "Premium" chip'leri hiç render
  /// edilmez; add-asset limit'i devreye girmez. Store + RevenueCat hazır
  /// olunca Firebase Console'dan true'ya çekilecek.
  bool get paywallEnabled =>
      _rc?.getBool('paywall_enabled') ?? _defaults['paywall_enabled'] as bool;

  bool get premiumEnabled =>
      _rc?.getBool('premium_enabled') ?? _defaults['premium_enabled'] as bool;

  int get freeAssetLimit =>
      _rc?.getInt('free_asset_limit') ?? _defaults['free_asset_limit'] as int;

  String get paywallVariant =>
      _rc?.getString('paywall_variant') ??
      _defaults['paywall_variant'] as String;

  String get premiumPriceMonthly =>
      _rc?.getString('premium_price_monthly') ??
      _defaults['premium_price_monthly'] as String;

  String get premiumPriceYearly =>
      _rc?.getString('premium_price_yearly') ??
      _defaults['premium_price_yearly'] as String;

  int get freeSignalSlotsPerDay =>
      _rc?.getInt('free_signal_slots_per_day') ??
      _defaults['free_signal_slots_per_day'] as int;

  bool get freeAiReportEnabled =>
      _rc?.getBool('free_ai_report_enabled') ??
      _defaults['free_ai_report_enabled'] as bool;
}
