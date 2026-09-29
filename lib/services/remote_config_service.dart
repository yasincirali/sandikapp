import 'dart:async';

import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'crash_reporter.dart';
import 'sunucu_secimi.dart';


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

    // Takip listesi limiti. Portföy limitinden AYRI ve paywall kapalıyken
    // de geçerli (kullanıcı kararı 2026-09-25: "şimdilik 7, ilerde paywall'la
    // artırılır"). Sunucuya yazılmadan önce istemcide kontrol edilir.
    'free_watchlist_limit': 7,

    // Paywall UI variant'ı ('A' | 'B'). A/B test için.
    'paywall_variant': 'A',

    // Aylık fiyat gösterimi (paywall'da lokalize göstermek için).
    'premium_price_monthly': '49₺/ay',
    'premium_price_yearly': '349₺/yıl',

    // Free kullanıcıya günde kaç sinyal analiz slot'u verilsin (1 = sadece
    // sabah, 2 = sabah+öğleden sonra). Premium her zaman 2.
    'free_signal_slots_per_day': 1,

    // NOT: `free_ai_report_enabled` kaldırıldı — AI portföy raporunun hiçbir
    // implementasyonu yoktu, flag var olmayan bir özelliği gate'liyordu.
    // Özellik yazıldığında flag'i geri ekle.

    // NOT: `deposits_enabled` kaldırıldı (2026-09-14) — vadeli mevduat
    // özelliği koddan tamamen çıkarıldı; flag'in gate'leyeceği bir şey yok.

    // ── Tutundurma (Sprint 1) ────────────────────────────────────────────
    // TestFlight'ta görünür olmaları için AÇIK doğuyorlar (2026-09-07,
    // kullanıcı kararı). Önceki hâl: hepsi kapalıydı ve Sprint 0'ın taban
    // çizgisi birikene kadar Firebase Console'dan açılmaları bekleniyordu.
    //
    // ⚠️ Bunun BEDELİ: bu değerler `setDefaults` ile yükleniyor, yani Firebase
    // Console'da o anahtar tanımlı DEĞİLSE varsayılan kazanır. Artık bir
    // özelliği geri kapatmanın iki yolu var — Console'a anahtarı `false`
    // olarak eklemek (uygulama yeniden yayımlanmadan çalışır, tercih edilen)
    // ya da yeni sürüm çıkmak. Uzaktan kapatma yeteneği KAYBOLMADI, ama
    // artık Console'da anahtarın var olmasına bağlı.
    //
    // ⚠️ A/B ölçümü: kapalı/açık kollarının karşılaştırması için "öncesi"
    // verisi gerekiyordu; hepsi birden açıldığı için Sprint 1'in etkisi
    // taban çizgisine karşı ölçülemeyecek.

    // Küresel yarış (haftanın/ayın portföyleri): 2026-09-21'de havuz 3
    // kişiyken parametrik KAPATILMIŞTI ("N kişi katıldı" yanlış anlaşılıyor).
    // 2026-09-28 kullanıcı kararı: AÇIK — özellik ortaktan bağımsız, kendi
    // sayfası (LeaderboardScreen) ortak şartı olmadan ulaşılabilir. Havuz
    // dolana kadar sıralama yerine "yeterli katılımcı olunca" metni çıkar;
    // k-anonimlik eşiği (k_min=8) sunucuda, bayrak onu gevşetmez.
    // Console'da parametre tanımlıysa o değer bu varsayılanı EZER —
    // YAPMAN_GEREKENLER'de kayıtlı.
    'global_leaderboard_enabled': true,
    // Ana ekranda anonim yüzdelik dilim şeridi: yalnızca yarış opt-in'i
    // açık kullanıcıya. "N kişi" sayısı sorunu bu şeritteydi; havuz dolana
    // kadar KAPALI kalır (küresel bayraktan bağımsız karar).
    'percentile_strip_enabled': false,

    // İlk varlık eklendikten sonra ana ekran widget'ı önerisi.
    'widget_prompt_enabled': true,

    // Bildirim izni ne zaman istensin?
    // false → eski davranış: ana ekran açıldıktan 2 sn sonra.
    // true  → ilk varlık eklendikten sonra ("ASELS hareket ederse haber
    //         verelim mi?"). Bağlamlı istemin kabul oranını yükseltmesi
    //         beklenir; iki kol `prompt_context` ile ayrışır.
    'push_prompt_after_first_asset': true,

    // Reel getiri (TÜFE) rozeti. `inflation_index` tablosu boşken zaten
    // hiçbir şey çizilmez — bayrak açık olsa bile tablo doldurulmadan rozet
    // GÖRÜNMEZ. Bu bir hata değil, kasıtlı: doğrulanmamış bir TÜFE değeri
    // finansal hesabı yanlış gösterirdi (bkz. YAPMAN_GEREKENLER.md).
    'real_return_enabled': true,

    // Free tier fiyat alarmı limiti. Alarm kullanıcının KENDİ istediği
    // bildirim olduğu için cömert bir sınır: 3 alarm gündelik kullanımı
    // karşılar, üstü premium için doğal bir kanca.
    'free_price_alert_limit': 3,

    // Kilometre taşı kutlamaları. Ayda en fazla bir kutlama yapılır;
    // bayrak, tonun kullanıcıda karşılık bulup bulmadığını ölçmek için.
    'milestones_enabled': true,

    // Yıllık "sandık Özeti". Diğer tutundurma bayrakları gibi AÇIK doğar
    // ama asıl kapı bayrak değil TAKVİM: ekran yalnızca 26 Aralık–10 Ocak
    // penceresinde ve anlamlı veri varken görünür
    // (bkz. RecapService.isYearlyWindow).
    'recap_enabled': true,

    // Dönem Özeti (Performans → Özet sekmesi) ve ana ekrandaki "Bu hafta"
    // kartı. TAMAMEN ÜCRETSİZ — paywall'a bağlı değil.
    //
    // Bayrak asıl olarak ana ekran kartı için var: Performans ekranındaki
    // sekme zaten kullanıcının bilinçli olarak girdiği bir yer, ama ana
    // ekrana eklenen her satır dikkat bütçesinden yiyor ve geri alınabilir
    // olması gerekiyor.
    'period_summary_enabled': true,

    // Mağaza değerlendirme istemi (`ReviewPromptService`). Kapatınca hiçbir
    // mutlu anda sorulmaz; Ayarlar'daki elle satır bayraktan bağımsızdır.
    'review_prompt_enabled': true,

    // Ön soru ("sandık'ı seviyor musun?") gösterilsin mi. Google Play
    // tasarım kılavuzu sistem kartından ÖNCE soru sormamayı önerir; mağaza
    // incelemesinde takılırsa bayrak kapatılır ve doğrudan sistem kartı
    // istenir — yayın beklemeden, aynı gün.
    'review_prompt_soft_gate': true,

    // ── Köprü sürümü (K1, 2026-09-27) ────────────────────────────────────
    // Hangi Supabase projesi: 'tokyo' | 'frankfurt'. Geçiş gecesi Console'da
    // çevrilir; açık uygulamalar gerçek zamanlı dinleyiciyle saniyeler içinde
    // "kapatıp aç" ekranına düşer. Karar `SunucuSecimi`'nde.
    SunucuSecimi.anahtar: 'tokyo',
    // Zorunlu güncelleme kapısı: bu build'in altındakiler "Güncelle"
    // ekranında kalır. 0 = kapı kapalı. Android versionCode / iOS build.
    SunucuSecimi.minBuildAndroid: 0,
    SunucuSecimi.minBuildIos: 0,

    // ── Büyüme özellikleri (docs/BUYUME_OZELLIKLERI_TEKNIK_PLAN_2026_09.md) ──
    // Debug derlemede AÇIK (emülatör/TestFlight öncesi kontrol), release'de
    // KAPALI doğar: mağazaya kapalı gider, Console'dan kademeli açılır.
    // Sorun çıkarsa yayın gerekmeden Console'da `false`.
    'demo_mode_enabled': kDebugMode,
    'lock_offer_after_first_asset': kDebugMode,
    'fund_report_card_enabled': kDebugMode,
    'dividend_capture_enabled': kDebugMode,
    'ipo_calendar_enabled': kDebugMode,
    // Temettü önerisinde stopaj oranı (0..1). -1 = bilinmiyor: öneri BRÜT
    // gösterir, net tutarı kullanıcı girer (uydurma oran yazılmaz).
    'temettu_stopaj_orani': -1.0,
  };

  Future<void> init() async {
    if (_initialized) return;
    try {
      _rc = FirebaseRemoteConfig.instance;
      await _rc!.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        // Debug'da hemen; prod'da 15 dk. Eskiden 1 saatti. Köprü sürümünde
        // (K1) bu aralık, geçiş gecesi gerçek zamanlı bildirimi KAÇIRAN açık
        // bir uygulamanın dondurulmuş Tokyo'da en fazla ne kadar kalacağıdır
        // (ön plana dönüşte `refresh()`). 2026-09-27 emülatör denemesinde
        // gerçek zamanlı yol ulaşmadı; soğuk açılış yolu ~5 sn'de çalıştı.
        // 15 dk RC kotasının çok altında (istemci başına saatte 4 fetch).
        minimumFetchInterval:
            kDebugMode ? Duration.zero : const Duration(minutes: 15),
      ));
      await _rc!.setDefaults(_defaults);
      // Fetch başlat ama beklet — offline'da default'lar geçerli olur.
      // Bitince sunucu/güncelleme kararı yeniden değerlendirilir.
      CrashReporter.arkaPlan(
        _rc!.fetchAndActivate().then((_) => _sunucuyaBildir()),
        reason: 'remote_config_service.fetchAndActivate',
      );
      // Gerçek zamanlı güncelleme: geçiş gecesi bayrak çevrildiğinde AÇIK
      // uygulamalar saatlik fetch'i beklemez. Dinleyici değişen anahtarları
      // bildirir ama ETKİNLEŞTİRMEZ — activate şart.
      _rc!.onConfigUpdated.listen(
        (_) async {
          await _rc!.activate();
          _sunucuyaBildir();
        },
        onError: (Object e, StackTrace st) =>
            CrashReporter.report(e, st, reason: 'remote_config_service.onConfigUpdated'),
      );
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
      _sunucuyaBildir();
    } catch (_) {}
  }

  void _sunucuyaBildir() {
    final rc = _rc;
    if (rc == null) return;
    SunucuSecimi.instance.rcGuncellendi(
      istenen: rc.getString(SunucuSecimi.anahtar),
      minBuild: rc.getInt(SunucuSecimi.minBuildAnahtari),
    );
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

  int get freeWatchlistLimit =>
      _rc?.getInt('free_watchlist_limit') ??
      _defaults['free_watchlist_limit'] as int;

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

  bool get percentileStripEnabled =>
      _rc?.getBool('percentile_strip_enabled') ??
      _defaults['percentile_strip_enabled'] as bool;

  /// Küresel sıralama (yüzdelik dilim, en çok kazandıranlar, solo panel,
  /// benchmark kartı). Ortaklar arası yarış bundan bağımsız.
  bool get globalLeaderboardEnabled =>
      _rc?.getBool('global_leaderboard_enabled') ??
      _defaults['global_leaderboard_enabled'] as bool;

  bool get widgetPromptEnabled =>
      _rc?.getBool('widget_prompt_enabled') ??
      _defaults['widget_prompt_enabled'] as bool;

  bool get pushPromptAfterFirstAsset =>
      _rc?.getBool('push_prompt_after_first_asset') ??
      _defaults['push_prompt_after_first_asset'] as bool;

  bool get realReturnEnabled =>
      _rc?.getBool('real_return_enabled') ??
      _defaults['real_return_enabled'] as bool;

  int get freePriceAlertLimit =>
      _rc?.getInt('free_price_alert_limit') ??
      _defaults['free_price_alert_limit'] as int;

  bool get milestonesEnabled =>
      _rc?.getBool('milestones_enabled') ??
      _defaults['milestones_enabled'] as bool;

  bool get recapEnabled =>
      _rc?.getBool('recap_enabled') ?? _defaults['recap_enabled'] as bool;

  bool get periodSummaryEnabled =>
      _rc?.getBool('period_summary_enabled') ??
      _defaults['period_summary_enabled'] as bool;

  bool get reviewPromptEnabled =>
      _rc?.getBool('review_prompt_enabled') ??
      _defaults['review_prompt_enabled'] as bool;

  bool get reviewPromptSoftGate =>
      _rc?.getBool('review_prompt_soft_gate') ??
      _defaults['review_prompt_soft_gate'] as bool;

  // ── Büyüme özellikleri ─────────────────────────────────────────────────
  bool get demoModeEnabled =>
      _rc?.getBool('demo_mode_enabled') ??
      _defaults['demo_mode_enabled'] as bool;

  bool get lockOfferAfterFirstAsset =>
      _rc?.getBool('lock_offer_after_first_asset') ??
      _defaults['lock_offer_after_first_asset'] as bool;

  bool get fundReportCardEnabled =>
      _rc?.getBool('fund_report_card_enabled') ??
      _defaults['fund_report_card_enabled'] as bool;

  bool get dividendCaptureEnabled =>
      _rc?.getBool('dividend_capture_enabled') ??
      _defaults['dividend_capture_enabled'] as bool;

  bool get ipoCalendarEnabled =>
      _rc?.getBool('ipo_calendar_enabled') ??
      _defaults['ipo_calendar_enabled'] as bool;

  /// Temettü stopaj oranı; `null` = bilinmiyor (öneri brüt kalır).
  double? get temettuStopajOrani {
    final v = _rc?.getDouble('temettu_stopaj_orani') ??
        _defaults['temettu_stopaj_orani'] as double;
    return (v >= 0 && v < 1) ? v : null;
  }
}
