import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

/// Merkezi analytics servisi. Tüm event log'ları buradan geçer.
///
/// Firebase init başarısız olursa (debug build veya config eksik) sessizce
/// no-op çalışır — çağıran kodun try/catch ile sarmalanmasına gerek yok.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  FirebaseAnalytics? _analytics;
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    try {
      _analytics = FirebaseAnalytics.instance;
      // Debug build'de analytics collection'ı kapat — gürültü olmasın
      await _analytics!.setAnalyticsCollectionEnabled(!kDebugMode);
      _initialized = true;
    } catch (e) {
      if (kDebugMode) debugPrint('AnalyticsService init failed: $e');
    }
  }

  FirebaseAnalyticsObserver? get navigatorObserver =>
      _analytics == null ? null : FirebaseAnalyticsObserver(analytics: _analytics!);

  Future<void> setUserId(String? userId) async {
    if (_analytics == null) return;
    try {
      await _analytics!.setUserId(id: userId);
    } catch (_) {}
  }

  Future<void> setUserProperty({required String name, String? value}) async {
    if (_analytics == null) return;
    try {
      await _analytics!.setUserProperty(name: name, value: value);
    } catch (_) {}
  }

  Future<void> _log(String name, [Map<String, Object>? params]) async {
    if (_analytics == null) return;
    try {
      await _analytics!.logEvent(name: name, parameters: params);
    } catch (_) {}
  }

  // ── Auth ────────────────────────────────────────────────────────────────
  Future<void> logLogin({required String method}) =>
      _log('login', {'method': method});

  Future<void> logSignup({required String method}) =>
      _log('sign_up', {'method': method});

  Future<void> logLogout() => _log('logout');

  // ── Onboarding ──────────────────────────────────────────────────────────
  Future<void> logOnboardingStep(int step) =>
      _log('onboarding_step', {'step': step});

  Future<void> logOnboardingCompleted() => _log('onboarding_completed');

  Future<void> logOnboardingSkipped(int atStep) =>
      _log('onboarding_skipped', {'at_step': atStep});

  // ── Portföy ─────────────────────────────────────────────────────────────
  Future<void> logAssetAdded({
    required String type,
    String? subCategory,
  }) =>
      _log('asset_added', {
        'asset_type': type,
        if (subCategory != null) 'sub_category': subCategory,
      });

  Future<void> logAssetUpdated({required String type}) =>
      _log('asset_updated', {'asset_type': type});

  Future<void> logAssetDeleted({required String type}) =>
      _log('asset_deleted', {'asset_type': type});

  // ── Sinyal / Teknik analiz ──────────────────────────────────────────────
  Future<void> logSignalReceived({
    required String ticker,
    required String action,
    required double confidence,
    required String slot,
  }) =>
      _log('signal_received', {
        'ticker': ticker,
        'action': action,
        'confidence': confidence.round(),
        'slot': slot, // morning | afternoon | manual
      });

  Future<void> logSignalViewed({required String ticker, required String action}) =>
      _log('signal_viewed', {'ticker': ticker, 'action': action});

  Future<void> logSignalDismissed({required String ticker}) =>
      _log('signal_dismissed', {'ticker': ticker});

  // ── Premium / Paywall (Faz 1'e hazırlık) ────────────────────────────────
  Future<void> logPremiumGateShown({required String feature}) =>
      _log('premium_gate_shown', {'feature': feature});

  Future<void> logPremiumUpgradeStarted({required String source}) =>
      _log('premium_upgrade_started', {'source': source});

  Future<void> logPremiumUpgradeCompleted({required String plan}) =>
      _log('premium_upgrade_completed', {'plan': plan});

  // ── Sosyal ──────────────────────────────────────────────────────────────
  Future<void> logPartnerInviteSent() => _log('partner_invite_sent');
  Future<void> logPartnerInviteAccepted() => _log('partner_invite_accepted');

  // ── Genel ekran görüntüleme (manuel — observer olmayan yerler için) ────
  Future<void> logScreenView({required String screenName}) => _log(
        'screen_view',
        {'screen_name': screenName, 'screen_class': screenName},
      );

  // ══ Tutunma ölçümü ═══════════════════════════════════════════════════════
  //
  // Durum tutan taraf [RetentionTracker]'dır; buradaki metotlar yalnızca
  // gönderir. Tekrar eleme, kurulum tarihi ve "bir kez" mantığı orada.
  //
  // İSİMLENDİRME UYARISI — Firebase bazı event adlarını kendisi kullanır ve
  // bu adlarla gönderilen özel event'ler ya reddedilir ya da otomatik
  // toplananla karışır. Bu yüzden bilerek şu adlardan KAÇINILDI:
  //   session_start → app_launch
  //   notification_open / notification_receive → push_opened
  //   first_open → activation_milestone (milestone: first_asset)
  // Yeni event eklerken Firebase'in ayrılmış adlar listesini kontrol et.

  // ── Ritim ───────────────────────────────────────────────────────────────
  /// [source]: cold | resume | push | widget | live_activity
  Future<void> logAppLaunch({
    required String source,
    required int daysSinceInstall,
  }) =>
      _log('app_launch', {
        'source': source,
        'days_since_install': daysSinceInstall,
      });

  Future<void> logSessionDepth({
    required int screensViewed,
    required int secondsActive,
  }) =>
      _log('session_depth', {
        'screens_viewed': screensViewed,
        'seconds_active': secondsActive,
      });

  /// [kind]: data_freshness | monthly_contribution | partner
  Future<void> logStreakDay({
    required String kind,
    required int currentStreak,
  }) =>
      _log('streak_day', {'kind': kind, 'current_streak': currentStreak});

  // ── Aktivasyon ──────────────────────────────────────────────────────────
  /// [milestone]: first_asset | three_assets | push_granted | widget_used |
  /// first_week_survived
  Future<void> logActivationMilestone({
    required String milestone,
    required int daysSinceInstall,
  }) =>
      _log('activation_milestone', {
        'milestone': milestone,
        'days_since_install': daysSinceInstall,
      });

  // ── Bildirim yaşam döngüsü ──────────────────────────────────────────────
  /// `granted` int olarak gönderilir: Firebase bool parametreyi saklamaz,
  /// dashboard'da 0/1 ile filtrelemek gerekir.
  Future<void> logPushPermission({
    required bool granted,
    required String promptContext,
  }) =>
      _log('push_permission', {
        'granted': granted ? 1 : 0,
        'prompt_context': promptContext,
      });

  /// [type]: signal_alert | partner_invite | daily_brief | price_alert
  Future<void> logPushOpened({required String type, int? minutesSinceSent}) =>
      _log('push_opened', {
        'type': type,
        if (minutesSinceSent != null) 'minutes_since_sent': minutesSinceSent,
      });

  Future<void> logNotificationPrefChanged({
    required String channel,
    required bool enabled,
  }) =>
      _log('notification_pref_changed', {
        'channel': channel,
        'enabled': enabled ? 1 : 0,
      });

  // ── Widget yüzeyleri ────────────────────────────────────────────────────
  Future<void> logWidgetInstalled({
    required String platform,
    required String size,
  }) =>
      _log('widget_installed', {'platform': platform, 'size': size});

  /// [surface]: home_widget | lock_widget | live_activity
  Future<void> logWidgetTapped({required String surface}) =>
      _log('widget_tapped', {'surface': surface});

  // ── Değer anları ────────────────────────────────────────────────────────
  /// [kind]: portfolio_value | gold_count | portfolio_age | diversification
  Future<void> logMilestoneReached({
    required String kind,
    required String value,
  }) =>
      _log('milestone_reached', {'kind': kind, 'value': value});

  Future<void> logPercentileViewed({
    required int bucket,
    required int periodDays,
  }) =>
      _log('percentile_viewed', {
        'bucket': bucket,
        'period_days': periodDays,
      });

  /// [period]: monthly | yearly
  Future<void> logRecapViewed({required String period}) =>
      _log('recap_viewed', {'period': period});

  Future<void> logRecapShared({
    required String period,
    required String channel,
  }) =>
      _log('recap_shared', {'period': period, 'channel': channel});
}
