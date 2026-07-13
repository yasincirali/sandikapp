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
}
