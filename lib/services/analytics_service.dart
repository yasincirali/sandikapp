import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';
import 'huni_kaydi.dart';

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

  FirebaseAnalyticsObserver? get navigatorObserver => _analytics == null
      ? null
      : FirebaseAnalyticsObserver(analytics: _analytics!);

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

  // ── Tam tanıtım turu (Ayarlar › "Tanıtım turunu yeniden izle") ─────────
  //
  // Neden ayrı olaylar (2026-10-20, Ar-Ge 17:15 #2): yukarıdaki üç olay
  // kısa (ilk açılış) ve tam turu AYIRMIYOR. "28 adımlık turu ekran başı
  // ipucuna çevirelim mi" kararı yalnız tam turun kaç kişi tarafından
  // başlatılıp kaçıncı adımda bırakıldığını soruyor. Davranış değişmez;
  // `adim` 0 tabanlı (`onboarding_skipped.at_step` ile aynı), `adim_sayisi`
  // turun o sürümdeki uzunluğu (adımlar eklenip çıktıkça oran okunabilsin).
  Future<void> logTamTurBasladi({required int adimSayisi}) =>
      _log('tam_tur_basladi', {'adim_sayisi': adimSayisi});

  Future<void> logTamTurAtlandi(
          {required int adim, required int adimSayisi}) =>
      _log('tam_tur_atlandi', {'adim': adim, 'adim_sayisi': adimSayisi});

  Future<void> logTamTurBitti({required int adimSayisi}) =>
      _log('tam_tur_bitti', {'adim_sayisi': adimSayisi});

  // ── Portföy ─────────────────────────────────────────────────────────────
  /// [yol]: varlığın hangi ekleme yolundan geldiği (2026-10-20, Ar-Ge
  /// 13:15 #4 "ekleme yollarını say"; 19 Kasım sadeleştirme kararını
  /// besler). Değerler [eklemeYollari]; kişisel veri yok.
  Future<void> logAssetAdded({
    required String type,
    String? subCategory,
    String? yol,
  }) =>
      _log('asset_added', {
        'asset_type': type,
        if (subCategory != null) 'sub_category': subCategory,
        if (yol != null) 'yol': yol,
      });

  /// `asset_added.yol` değer kümesi — sabit ve küçük, Analytics panosunda
  /// kırılım olarak okunur. Sesli giriş ayrı bir yol değildir: klavye
  /// diktesi Hızlı Giriş'e yazar (`hizli_metin`).
  static const eklemeYollari = {
    'form', // Varlık Ekle formu (+ Al/Sat hızlı düzeltme, "Varlığı güncelle")
    'hizli_metin', // "Yazarak ekle" çok satırlı hızlı giriş
    'toplu', // Toplu Ekle'de elle eklenen kalem
    'ekstre', // Ekstre / metin / dosya içe aktarma
    'ekran_goruntusu', // Aracı kurum ekranının görüntüsünden
    'arama', // Arama sonucu / Karşılaştır'dan "Portföyüme ekle"
    'takip', // Takip listesi satırından
    'halka_arz', // Halka arz katılım kaydından
    'otomatik', // BES otomatik katkısı (kullanıcı eylemi değil)
  };

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

  Future<void> logSignalViewed(
          {required String ticker, required String action}) =>
      _log('signal_viewed', {'ticker': ticker, 'action': action});

  Future<void> logSignalDismissed({required String ticker}) =>
      _log('signal_dismissed', {'ticker': ticker});

  // ── Yenilikler (What's New) ─────────────────────────────────────────────
  //
  // Hangi sürümün notunun kaç kişiye ulaştığını ölçer. `adet` birikmiş
  // sürüm sayısı: 1'den büyükse kullanıcı aradaki sürümleri hiç açmamış.
  Future<void> logWhatsNewShown({
    required String surum,
    required int adet,
  }) =>
      _log('whats_new_shown', {'surum': surum, 'adet': adet});

  // ── Premium / Paywall (Faz 1'e hazırlık) ────────────────────────────────
  Future<void> logPremiumGateShown({required String feature}) =>
      _log('premium_gate_shown', {'feature': feature});

  Future<void> logPremiumUpgradeStarted({required String source}) =>
      _log('premium_upgrade_started', {'source': source});

  /// Huni kapı → paywall → satın alma TEK kaynak parametresiyle bağlanır
  /// (paywall incelemesi, 2026-10-20): `premium_gate_shown.feature` =
  /// `premium_upgrade_started.source` = buradaki `source`. Böylece hangi
  /// kilidin para ettiği kaynak başına okunur; `deneme` mağazanın deneme
  /// süresiyle başladığını söyler (deneme → ücretli dönüşüm ayrı sorulur).
  Future<void> logPremiumUpgradeCompleted({
    required String plan,
    String source = '',
    bool deneme = false,
  }) =>
      _log('premium_upgrade_completed', {
        'plan': plan,
        if (source.isNotEmpty) 'source': source,
        'deneme': deneme ? 1 : 0,
      });

  /// Paywall satın alınmadan kapandı (huni sızıntısı, kaynak başına).
  Future<void> logPremiumPaywallKapandi({required String source}) =>
      _log('premium_paywall_closed', {'source': source});

  /// Premium dışa aktarım (2026-10-10): hangi belge, hangi biçim. Tutar ya
  /// da içerik gönderilmez.
  Future<void> logDisaAktarim({required String tur, required String bicim}) =>
      _log('disa_aktarim', {'tur': tur, 'bicim': bicim});

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

  // ── Teşhis ──────────────────────────────────────────────────────────────

  /// Yavaş fiyat geçmişi çekimi (`HistoryService._fetchSafe`).
  ///
  /// Altın grafiğinin gecikmesi yapısal olarak düzeltildi ama gerçek ağda
  /// ölçülmedi; bu olay "hâlâ yavaş mı, hangi sembolde, zaman aşımı mı"
  /// sorusunu Firebase'den cevaplar. Yalnızca eşiği aşan çekimler gelir.
  Future<void> logSlowHistoryFetch({
    required String symbol,
    required int ms,
    required int points,
    required bool timedOut,
  }) =>
      _log('slow_history_fetch', {
        'symbol': symbol,
        'ms': ms,
        'points': points,
        'timed_out': timedOut ? 1 : 0,
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

  /// Mağaza değerlendirme istemi hunisi.
  ///
  /// [action]: `shown` | `later` | `feedback` | `review`.
  /// [moment]: `ReviewAni.name` ya da `settings`. Hangi anın puana
  /// dönüştüğü buradan okunur; dönüşmeyen an listeden çıkarılır.
  Future<void> logReviewPrompt({
    required String action,
    required String moment,
    String? source,
  }) =>
      _log('review_prompt', {
        'action': action,
        'moment': moment,
        if (source != null) 'source': source,
      });

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

  /// [period]: gunluk | birHafta | birAy | altiAy | birYil
  ///
  /// Hangi dönemin gerçekten okunduğunu ölçer. Faz 2'de haftalık push
  /// kararı buna dayanacak: 1H sekmesi hiç açılmıyorsa o push'un
  /// gönderilecek bir karşılığı yok demektir.
  Future<void> logPeriodSummaryViewed({required String period}) =>
      _log('period_summary_viewed', {'period': period});

  // ── "Bugün" kartı ve hedef (2026-09-20) ─────────────────────────────────
  //
  // Kart "her gün değişen yüzey" olarak kuruldu; hangi satırın gerçekten
  // dokunulduğunu bilmeden hangisinin kalacağına karar verilemez. Gösterim
  // günde bir kez (kart her build'de yeniden kurulur, her build ayrı olay
  // olmamalı — tekrar eleme `BugunKarti`'nda).
  //
  // [kind]: degisim | kapali | yesil | hedef | hedef_yok | olay_tuik |
  //         olay_tatil | olay_aysonu | aylik
  Future<void> logTodayRowShown({required String kind}) =>
      _log('today_row_shown', {'kind': kind});

  Future<void> logTodayRowTapped({required String kind}) =>
      _log('today_row_tapped', {'kind': kind});

  /// Hedef belirlendi / kaldırıldı. Tutar gönderilmez (mahremiyet);
  /// yalnızca büyüklük kovası — "kim ne kadar" değil "kaç kişi kullanıyor".
  // ── Büyüme özellikleri (plan 2026-09-29) ────────────────────────────────
  // Olay adları sabit: Firebase panoları bunlara bağlanır, değiştirme.

  /// Kayıt/ilk açılış hunisinin adımı: form_opened, otp_sent, otp_verified,
  /// disclaimer_accepted, username_set, tour_done, home_first_seen.
  ///
  /// Aynı adım kontrol paneli için sunucuya da yazılır ([HuniKaydi], 0097):
  /// panel Firebase'i okuyamaz. Çağrı yerleri tek kalsın diye ikinci hedef
  /// burada — yeni bir adım eklerken `HuniKaydi.signupStepten`'e de ekle.
  Future<void> logSignupStep(String step) async {
    final adim = HuniKaydi.signupStepten(step);
    if (adim != null) {
      CrashReporter.arkaPlan(HuniKaydi.instance.kaydet(adim),
          reason: 'HuniKaydi.kaydet');
    }
    await _log('signup_step', {'step': step});
  }

  Future<void> logDemoOpened() => _log('demo_opened');

  /// Demo'dan hesap oluşturmaya geçti (`from`: hangi eylem tetikledi).
  Future<void> logDemoConverted({required String from}) =>
      _log('demo_converted', {'from': from});

  Future<void> logFundCardViewed({required String category}) =>
      _log('fund_card_viewed', {'category': category});

  /// Temettü önerisi: shown / recorded / dismissed.
  Future<void> logDividendSuggestion({required String action}) =>
      _log('dividend_suggestion', {'action': action});

  Future<void> logIpoViewed({required String surface}) =>
      _log('ipo_viewed', {'surface': surface});

  Future<void> logIpoParticipationRecorded() =>
      _log('ipo_participation_recorded');

  Future<void> logGoalSet({required int amountTRY}) => _log(
        'goal_set',
        {
          'bucket': amountTRY <= 0
              ? 'removed'
              : amountTRY < 500000
                  ? 'lt_500k'
                  : amountTRY < 2000000
                      ? 'lt_2m'
                      : 'gte_2m',
        },
      );
}
