/// SharedPreferences anahtarları — TEK KAYIT.
///
/// 2026-09 denetimi: `pref_signal_notifications` ve `pref_partner_notifications`
/// iki dosyada ayrı ayrı `const` tanımlıydı (`preferences_provider.dart` ve
/// `notification_service.dart`). İki özel sabit, tek string sözleşmesi: biri
/// yeniden adlandırılsa Ayarlar'daki anahtar bildirim yolundan sessizce
/// ayrışacaktı. Buradaki sabitler o sözleşmeyi tek yerde tutar.
///
/// Kapsam dışı ve BİLİNÇLİ olarak burada olmayanlar:
/// - `sandik_*` (home_widget_service): Kotlin/Swift widget koduyla paylaşılan
///   süreçler arası sözleşme; Dart tarafında yeniden adlandırılamaz.
/// - `retention_*` (retention_tracker): kendi içinde kapalı, tek dosya.
/// - Kullanıcı kimliğiyle sonek alan anahtarlar `preferences_provider.dart`
///   içindeki `_userKey()` ile üretilir; burada YALNIZCA taban adı durur.
class PrefKeys {
  PrefKeys._();

  static const themeMode = 'pref_theme_mode'; // 'system' | 'light' | 'dark'
  /// Arayüz dili — 'tr' | 'en' | 'system' (3.20). Cihaz tercihi, kişiye özel değil.
  static const locale = 'pref_locale';
  static const signalNotifications = 'pref_signal_notifications';
  static const partnerNotifications = 'pref_partner_notifications';
  static const balanceHidden = 'pref_balance_hidden';
  /// Toplam kartı kaydırma ipucu (tek seferlik göz kırpma) gösterildi mi.
  static const kaydirmaIpucu = 'pref_kaydirma_ipucu_gosterildi';
  static const lockScreenAmounts = 'pref_lockscreen_amounts';
  static const liveActivityStartMin = 'pref_live_activity_start_min';
  static const liveActivityEndMin = 'pref_live_activity_end_min';
  static const liveActivityWeekend = 'pref_live_activity_weekend';
  static const premiumUnlocked = 'pref_premium_unlocked';
  static const indicatorsByType = 'pref_indicators_by_type_v1';
  static const chartOverlayMa20 = 'pref_chart_overlay_ma20';
  static const chartLogScale = 'pref_chart_log_scale';
  static const leaderboardOptIn = 'pref_leaderboard_opt_in';
  static const biometricLock = 'pref_biometric_lock';
  /// Baz para birimi — `BaseCurrency.index` (0 TRY, 1 USD, 2 EUR, 3 gram altın).
  static const baseCurrency = 'pref_base_currency';
  /// Yatırımcı seviyesi — `YatirimciSeviyesi.index` (0 başlangıç, 1 orta, 2 ileri).
  static const investorLevel = 'pref_investor_level';
  static const surfaceIsLight = 'pref_surface_is_light';
  static const signalThresholdByType = 'pref_signal_threshold_by_type_v1';
  static const signalNeutralPush = 'pref_signal_neutral_push';
  static const signalFrequencyByType = 'pref_signal_frequency_by_type_v1';
  static const signalHoursByType = 'pref_signal_hours_by_type_v1';

  /// Kullanıcının "Yenilikler"ini en son gördüğü uygulama sürümü ('1.2.0').
  ///
  /// Cihaza özgü ve kasıtlı: sürüm notu KURULU SÜRÜME dairdir, hesaba değil.
  /// Aynı hesapla iki cihaz farklı sürümlerde olabilir; sunucuya yazılsaydı
  /// yeni sürüme geçen cihaz notu görmezdi.
  static const sonGorulenSurumNotu = 'pref_son_gorulen_surum_notu';

  /// `FxRateMigrationService` en son ne zaman koştu (epoch ms). Her açılışta
  /// değil, günde bir kez sorgu atsın diye.
  static const fxMigrationLastRunMs = 'fx_migration_last_run_ms';

  /// Uygulama arkaya alındığı an (ms). Süreç öldürülürse bellekteki
  /// `_backgroundedAt` kaybolurdu ve 10 dk'lık oturum zaman aşımı hiç
  /// işlemezdi (2026-09 L2); açılışta buradan okunur.
  static const backgroundedAtMs = 'session_backgrounded_at_ms';

  /// `RemotePushService` cihaz kimliği; çıkışta silinir (L14).
  static const pushDeviceId = 'push_device_id';

  /// iOS bildirim izninin en son analytics'e yazılan durumu. Durum yalnızca
  /// DEĞİŞİNCE kaydedilir; yoksa her açılış bir "izin verdi" olayı olurdu.
  static const iosPushPermissionLast = 'ios_push_permission_last';

  /// Son bilinen varlık defteri (JSON); kullanıcı kimliği soneklenir.
  static const portfolioCachePrefix = 'portfolio_cache_v1_';

  /// Mağaza değerlendirme istemi (`ReviewPromptService`). Cihaza özgü ve
  /// kasıtlı: mağaza kotası cihaz+hesap başınadır, hesap değişince
  /// sıfırlansaydı aynı telefona ikinci kez sorardık.
  static const reviewDone = 'review_done'; // bool — "Değerlendir" seçildi
  static const reviewLastAskedMs = 'review_last_asked_ms'; // int
  static const reviewAskCount = 'review_ask_count'; // int
  static const reviewFeedbackMs = 'review_feedback_ms'; // int — "Sorun var"

  /// Portföy hedefi (TRY, tam sayı; 0 = hedef yok). Kullanıcı kimliği
  /// soneklenir (`perUser`): hedef kişiseldir, aynı cihazdaki başka hesaba
  /// taşınmaz. Ana ekrandaki "Bugün" kartı ilerlemeyi buradan okur.
  static const portfolioGoalTRY = 'portfolio_goal_try';
}
