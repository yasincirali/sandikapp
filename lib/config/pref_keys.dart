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
  static const signalNotifications = 'pref_signal_notifications';
  static const partnerNotifications = 'pref_partner_notifications';
  static const balanceHidden = 'pref_balance_hidden';
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
  static const surfaceIsLight = 'pref_surface_is_light';
  static const signalThresholdByType = 'pref_signal_threshold_by_type_v1';
  static const signalNeutralPush = 'pref_signal_neutral_push';
  static const signalFrequencyByType = 'pref_signal_frequency_by_type_v1';
  static const signalHoursByType = 'pref_signal_hours_by_type_v1';

  /// `FxRateMigrationService` en son ne zaman koştu (epoch ms). Her açılışta
  /// değil, günde bir kez sorgu atsın diye.
  static const fxMigrationLastRunMs = 'fx_migration_last_run_ms';

  /// Son bilinen varlık defteri (JSON); kullanıcı kimliği soneklenir.
  static const portfolioCachePrefix = 'portfolio_cache_v1_';
}
