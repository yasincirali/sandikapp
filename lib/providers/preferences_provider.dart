import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/asset_type.dart';
import '../models/signal_frequency.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/technical_analysis_service.dart';
import 'auth_provider.dart';

/// Kullanıcı tercihleri (tema, bildirim, vb.) için merkezi state.
/// SharedPreferences ile kalıcı.
///
/// Kullanım:
///   ref.watch(themeModeProvider) → ThemeMode
///   ref.read(themeModeProvider.notifier).set(ThemeMode.light)

const _kThemeModeKey = 'pref_theme_mode'; // 'system' | 'light' | 'dark'
const _kSignalNotificationsKey = 'pref_signal_notifications';
const _kPartnerNotificationsKey = 'pref_partner_notifications';
const _kBalanceHiddenKey = 'pref_balance_hidden';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.dark; // sandık dark-first
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kThemeModeKey);
      switch (raw) {
        case 'system':
          state = ThemeMode.system;
          break;
        case 'light':
          state = ThemeMode.light;
          break;
        case 'dark':
          state = ThemeMode.dark;
          break;
      }
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kThemeModeKey, _toString(mode));
    } catch (_) {}
  }

  String _toString(ThemeMode m) {
    switch (m) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// Bildirim kategorileri için tek tip notifier
/// Uygulama başlarken bir kere warm-up edilen SharedPreferences instance.
/// Böylece `_BoolPrefNotifier.build()` senkron okuyabilir, ilk render'da
/// "loading → gerçek değer" flash'ı olmaz. main.dart bunu init eder.
SharedPreferences? _prefsSync;

Future<void> initPreferencesCache() async {
  _prefsSync = await SharedPreferences.getInstance();
}

class _BoolPrefNotifier extends Notifier<bool> {
  final String key;
  final bool defaultValue;

  _BoolPrefNotifier(this.key, this.defaultValue);

  @override
  bool build() {
    // Senkron okuma — cache yoksa default. Cache init edilmişse gerçek değer.
    final prefs = _prefsSync;
    if (prefs != null) {
      final v = prefs.getBool(key);
      if (v != null) return v;
    } else {
      // Fallback: cache init değilse eskisi gibi async load et.
      _loadAsync();
    }
    return defaultValue;
  }

  Future<void> _loadAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(key);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = _prefsSync ?? await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {}
  }

  /// Sunucudan gelen değeri yerele uygular.
  ///
  /// Davranışı [set] ile aynı (bu notifier zaten sunucuya yazmaz); ayrı isim
  /// çağrı yerinde yönü açık kılmak içindir — sunucudan İNEN veri, kullanıcı
  /// dokunuşu değil.
  Future<void> applyFromServer(bool value) => set(value);
}

final signalNotificationsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kSignalNotificationsKey, true));

final partnerNotificationsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kPartnerNotificationsKey, true));

final balanceHiddenProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kBalanceHiddenKey, false));

// ─── Premium (in-app purchase stub) ───────────────────────────────────────────
// Şimdilik SharedPreferences ile local toggle. Gerçek IAP entegrasyonu
// yapılana kadar test amaçlı Ayarlar ekranından açılıp kapatılabilir.

const _kPremiumUnlockedKey = 'pref_premium_unlocked';

final premiumUnlockedProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kPremiumUnlockedKey, false));

/// Kullanıcının göreceği tüm üyelik/ödeme UI'ları buna bağlı. false ise
/// paywall, premium banner, kilit overlay, "Premium" chip'leri hiç render
/// edilmez. Store + RevenueCat entegrasyonu hazır olunca Remote Config'ten
/// true'ya çekilir.
final paywallVisibleProvider = Provider<bool>((_) {
  return RemoteConfigService.instance.paywallEnabled;
});

/// UI'da kullanılması gereken effective premium bayrağı:
///  - Paywall açık mı (master switch)? AND
///  - Kullanıcı premium mu (satın aldı / test toggle açık)? AND
///  - Remote Config premium_enabled kill switch true mu?
///
/// Paywall kapalıyken herkes free olarak davranır — kilit UI'ları render
/// edilmediği için bu değerin false olması bir premium özelliği görünür
/// kılmaz, yalnızca "premium açıldı" state'ini uygulamaz.
///
/// Faz 1'de `premiumUnlockedProvider` RevenueCat CustomerInfo'ya bağlanacak.
/// Bu provider'ı kullanan kodun değişmesi gerekmez.
final effectivePremiumProvider = Provider<bool>((ref) {
  final paywallOn = ref.watch(paywallVisibleProvider);
  if (!paywallOn) return false;
  final unlocked = ref.watch(premiumUnlockedProvider);
  return unlocked && RemoteConfigService.instance.premiumEnabled;
});

/// Free tier varlık limiti — Remote Config'ten dinamik.
/// Paywall kapalıyken sınırsız (limit devreye girmez).
/// Premium ise limit yoktur (int.max ile temsil edilir).
final assetLimitProvider = Provider<int>((ref) {
  final paywallOn = ref.watch(paywallVisibleProvider);
  if (!paywallOn) return 1 << 30;
  final premium = ref.watch(effectivePremiumProvider);
  if (premium) return 1 << 30; // pratik olarak sınırsız
  return RemoteConfigService.instance.freeAssetLimit;
});

// ─── Per-category göstergeler ─────────────────────────────────────────────────
// Kullanıcı her varlık türü için hangi göstergelerin sinyal üretmesini istediğini
// seçebilir. Kalıcı: SharedPreferences.

const _kIndicatorPrefsKey = 'pref_indicators_by_type_v1';

class IndicatorPrefsNotifier
    extends Notifier<Map<AssetType, Set<String>>> {
  @override
  Map<AssetType, Set<String>> build() {
    _load();
    // Varsayılan: her tür için tüm temel göstergeler açık
    return {
      for (final t in AssetType.values)
        t: TechnicalAnalysisService.defaultEnabledFor(t),
    };
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kIndicatorPrefsKey);
      if (raw == null) return;
      // Format: "typeName:id1,id2,id3"
      final next = <AssetType, Set<String>>{};
      for (final entry in raw) {
        final parts = entry.split(':');
        if (parts.length != 2) continue;
        final type = AssetType.fromString(parts[0]);
        final ids = parts[1]
            .split(',')
            .where((s) => s.isNotEmpty && IndicatorId.all.contains(s))
            .toSet();
        next[type] = ids;
      }
      // Eksik türler için varsayılan
      for (final t in AssetType.values) {
        next.putIfAbsent(
            t, () => TechnicalAnalysisService.defaultEnabledFor(t));
      }
      state = next;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = state.entries
          .map((e) => '${e.key.name}:${e.value.join(',')}')
          .toList();
      await prefs.setStringList(_kIndicatorPrefsKey, entries);
    } catch (_) {}
  }

  Future<void> toggle(AssetType type, String indicatorId) async {
    final current = Set<String>.from(state[type] ?? <String>{});
    if (current.contains(indicatorId)) {
      current.remove(indicatorId);
    } else {
      current.add(indicatorId);
    }
    state = {...state, type: current};
    await _persist();
    await _syncSignalPreferenceWith(ref.read, type);
  }

  Future<void> setForType(AssetType type, Set<String> ids) async {
    state = {...state, type: ids};
    await _persist();
    await _syncSignalPreferenceWith(ref.read, type);
  }

  /// Sunucudan gelen değeri yerele uygular.
  ///
  /// [setForType]'dan farkı: sunucuya GERİ yazmaz. Aksi halde indirdiğimiz
  /// değeri aynı satıra tekrar upsert eder, gereksiz yazma yaratırdık.
  Future<void> applyFromServer(AssetType type, List<String> ids) async {
    final valid = ids.where(IndicatorId.all.contains).toSet();
    if (valid.isEmpty) return; // bozuk/boş kayıt — yereli koru
    state = {...state, type: valid};
    await _persist();
  }

  Set<String> forType(AssetType type) =>
      state[type] ?? TechnicalAnalysisService.defaultEnabledFor(type);
}

final indicatorPrefsProvider =
    NotifierProvider<IndicatorPrefsNotifier, Map<AssetType, Set<String>>>(
  IndicatorPrefsNotifier.new,
);

/// Bir varlık türünün sinyal tercihini sunucuya yazar.
///
/// Sinyal analizi sunucuda çalıştığı için (bkz. `analyze-signals` edge
/// function) eşik ve gösterge seçimi orada da bilinmeli. Eşik ve gösterge
/// ayrı notifier'larda tutulduğundan, hangisi değişirse değişsin satırın
/// TAMAMI birlikte yazılır — aksi halde upsert diğer alanı varsayılana
/// döndürürdü.
///
/// Hata durumunda sessizce geçilir: tercih zaten SharedPreferences'a
/// yazıldı, kullanıcı akışı bloklanmamalı. Bir sonraki değişiklikte
/// yeniden denenir.
/// [ref] hem [Ref] (provider içi) hem [WidgetRef] (ekran) olabilir; ikisi de
/// `read` sunar ama ortak bir arayüzleri yok. Bu yüzden gereken tek yetenek
/// olan `read` bir fonksiyon olarak alınır.
typedef _Reader = T Function<T>(ProviderListenable<T> provider);

Future<void> _syncSignalPreferenceWith(_Reader read, AssetType type) async {
  try {
    final user = read(authProvider).valueOrNull;
    if (user == null) return;

    final threshold =
        read(signalThresholdProvider)[type] ?? kSignalThresholdDefault;
    final indicators = read(indicatorPrefsProvider)[type] ??
        TechnicalAnalysisService.defaultEnabledFor(type);
    final neutralPush = read(signalNeutralPushProvider);
    final signalsEnabled = read(signalNotificationsProvider);

    final schedule = read(signalScheduleProvider)[type] ?? kDefaultSchedule;

    await SupabaseService.instance.upsertSignalPreference(
      userId: user.id,
      assetType: type.name,
      threshold: threshold,
      indicators: indicators.toList(),
      neutralPush: neutralPush,
      signalsEnabled: signalsEnabled,
      frequency: schedule.frequency,
      notifyHours: schedule.hours,
    );
  } catch (e, st) {
    // Sunucu senkronu başarısız olsa da yerel tercih geçerli kalır —
    // kullanıcıyı ayar ekranında hata diyaloğuyla durdurmak doğru değil.
    //
    // AMA sessizce yutmak da olmaz: push kararını SUNUCU veriyor, yani bu
    // yazma düşerse kullanıcının seçtiği eşik/sıklık hiç uygulanmaz ve
    // hiçbir belirti görünmez. Debug'da konsola, üretimde Crashlytics'e
    // düşsün ki teşhis edilebilsin.
    if (kDebugMode) {
      debugPrint('[signal_pref] ${type.name} sunucuya yazılamadı: $e');
    }
    FirebaseCrashlytics.instance.recordError(
      e,
      st,
      reason: 'signal_preferences upsert (${type.name})',
      fatal: false,
    );
  }
}

// ─── Sinyal bildirim eşiği (per asset type) ───────────────────────────────────
// Kullanıcı her varlık türü için confidence eşiğini seçer:
//   50 → düşük (daha çok push)
//   70 → orta (default)
//   85 → yüksek (sadece güçlü sinyaller)
// Eşiğin altında kalan sinyaller push gönderilmez.

const _kSignalThresholdKey = 'pref_signal_threshold_by_type_v1';
const _kSignalNeutralPushKey = 'pref_signal_neutral_push';

const kSignalThresholdOptions = <int>[50, 70, 85];
const kSignalThresholdDefault = 70;

class SignalThresholdNotifier extends Notifier<Map<AssetType, int>> {
  @override
  Map<AssetType, int> build() {
    _load();
    return {for (final t in AssetType.values) t: kSignalThresholdDefault};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kSignalThresholdKey);
      if (raw == null) return;
      // Format: "typeName:70"
      final next = <AssetType, int>{};
      for (final entry in raw) {
        final parts = entry.split(':');
        if (parts.length != 2) continue;
        final type = AssetType.fromString(parts[0]);
        final v = int.tryParse(parts[1]) ?? kSignalThresholdDefault;
        next[type] =
            kSignalThresholdOptions.contains(v) ? v : kSignalThresholdDefault;
      }
      for (final t in AssetType.values) {
        next.putIfAbsent(t, () => kSignalThresholdDefault);
      }
      state = next;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries =
          state.entries.map((e) => '${e.key.name}:${e.value}').toList();
      await prefs.setStringList(_kSignalThresholdKey, entries);
    } catch (_) {}
  }

  Future<void> setForType(AssetType type, int threshold) async {
    if (!kSignalThresholdOptions.contains(threshold)) return;
    state = {...state, type: threshold};
    await _persist();
    await _syncSignalPreferenceWith(ref.read, type);
  }

  /// Sunucudan gelen eşiği yerele uygular (geri yazmaz).
  ///
  /// Sunucu 0-100 aralığını kabul ediyor ama UI yalnızca 50/70/85 sunuyor.
  /// Aradaki bir değer gelirse (ileride kaydırmalı seçici eklenirse)
  /// olduğu gibi saklanır — UI o değeri seçili göstermese de sunucu
  /// kararı bozulmaz.
  Future<void> applyFromServer(AssetType type, int threshold) async {
    if (threshold < 0 || threshold > 100) return;
    state = {...state, type: threshold};
    await _persist();
  }

  int forType(AssetType type) => state[type] ?? kSignalThresholdDefault;
}

final signalThresholdProvider =
    NotifierProvider<SignalThresholdNotifier, Map<AssetType, int>>(
  SignalThresholdNotifier.new,
);

// ─── Sinyal bildirim sıklığı (per asset type) ────────────────────────────────
// Kullanıcı her varlık türü için ayrı sıklık ve saat seçer. Sunucu saatbaşı
// çalışıp bu tercihe göre karar verir (bkz. `shouldNotifyNow`).
// Bildirimler TR 10:00–18:00 penceresi dışına asla çıkmaz.

const _kSignalFrequencyKey = 'pref_signal_frequency_by_type_v1';
const _kSignalHoursKey = 'pref_signal_hours_by_type_v1';

/// Bir varlık türünün sıklık ayarı: sıklık + seçilen saatler.
typedef SignalSchedule = ({SignalFrequency frequency, List<int> hours});

const kDefaultSchedule = (
  frequency: SignalFrequency.twiceDaily,
  hours: <int>[11, 15],
);

class SignalScheduleNotifier extends Notifier<Map<AssetType, SignalSchedule>> {
  @override
  Map<AssetType, SignalSchedule> build() {
    _load();
    return {for (final t in AssetType.values) t: kDefaultSchedule};
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final freqRaw = prefs.getStringList(_kSignalFrequencyKey) ?? const [];
      final hoursRaw = prefs.getStringList(_kSignalHoursKey) ?? const [];

      final freqByType = <AssetType, SignalFrequency>{};
      for (final e in freqRaw) {
        final p = e.split(':');
        if (p.length != 2) continue;
        freqByType[AssetType.fromString(p[0])] = SignalFrequency.fromId(p[1]);
      }
      final hoursByType = <AssetType, List<int>>{};
      for (final e in hoursRaw) {
        // Format: "typeName:11,15"
        final p = e.split(':');
        if (p.length != 2) continue;
        hoursByType[AssetType.fromString(p[0])] = p[1]
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .where((h) => h >= kSignalWindowStart && h <= kSignalWindowEnd)
            .toList();
      }

      final next = <AssetType, SignalSchedule>{};
      for (final t in AssetType.values) {
        next[t] = (
          frequency: freqByType[t] ?? kDefaultSchedule.frequency,
          hours: hoursByType[t]?.isNotEmpty == true
              ? hoursByType[t]!
              : kDefaultSchedule.hours,
        );
      }
      state = next;
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kSignalFrequencyKey,
        state.entries.map((e) => '${e.key.name}:${e.value.frequency.id}').toList(),
      );
      await prefs.setStringList(
        _kSignalHoursKey,
        state.entries
            .map((e) => '${e.key.name}:${e.value.hours.join(",")}')
            .toList(),
      );
    } catch (_) {}
  }

  /// Sıklığı değiştirir. Saat seçimi gerektiren bir sıklığa geçilirken
  /// mevcut saat sayısı uymuyorsa makul bir varsayılan atanır — kullanıcı
  /// "günde 2"den "günde 1"e geçince elde 2 saat kalması sunucuda
  /// tutarsızlık yaratırdı.
  Future<void> setFrequency(AssetType type, SignalFrequency freq) async {
    final mevcut = state[type] ?? kDefaultSchedule;
    var hours = mevcut.hours;
    if (freq.needsHourPicker && hours.length != freq.hourCount) {
      hours = freq.hourCount == 1 ? const [11] : const [11, 15];
    }
    state = {...state, type: (frequency: freq, hours: hours)};
    await _persist();
    await _syncSignalPreferenceWith(ref.read, type);
  }

  /// Seçilen saatleri değiştirir. Pencere dışındaki saatler yok sayılır.
  Future<void> setHours(AssetType type, List<int> hours) async {
    final temiz = hours
        .where((h) => h >= kSignalWindowStart && h <= kSignalWindowEnd)
        .toSet()
        .toList()
      ..sort();
    if (temiz.isEmpty) return;
    final mevcut = state[type] ?? kDefaultSchedule;
    state = {...state, type: (frequency: mevcut.frequency, hours: temiz)};
    await _persist();
    await _syncSignalPreferenceWith(ref.read, type);
  }

  /// Sunucudan gelen değeri yerele uygular (geri yazmaz).
  Future<void> applyFromServer(
    AssetType type,
    SignalFrequency freq,
    List<int> hours,
  ) async {
    state = {
      ...state,
      type: (frequency: freq, hours: hours.isEmpty ? kDefaultSchedule.hours : hours),
    };
    await _persist();
  }

  SignalSchedule forType(AssetType type) => state[type] ?? kDefaultSchedule;
}

final signalScheduleProvider =
    NotifierProvider<SignalScheduleNotifier, Map<AssetType, SignalSchedule>>(
  SignalScheduleNotifier.new,
);

/// Nötr sinyaller de push olarak gönderilsin mi (default: false).
final signalNeutralPushProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kSignalNeutralPushKey, false));

/// "Nötr sinyalleri de bildir" tercihi tüm varlık türleri için geçerlidir,
/// ama sunucudaki tablo tür başına satır tutar — bu yüzden değişince
/// hepsi güncellenir.
///
/// Ayrı bir fonksiyon olmasının sebebi: `signalNeutralPushProvider` genel
/// amaçlı [_BoolPrefNotifier] kullanıyor; ona sinyale özel senkron mantığı
/// gömmek diğer bool tercihleri de (tema, bakiye gizleme) gereksiz yere
/// ağa çıkarırdı.
Future<void> syncNeutralPushPreference(WidgetRef ref) async {
  for (final type in AssetType.values) {
    await _syncSignalPreferenceWith(ref.read, type);
  }
}

/// Sinyal bildirimleri ana anahtarını sunucuya yazar.
///
/// [syncNeutralPushPreference] ile aynı sebeple tüm türleri günceller:
/// tercih uygulama genelinde tek, tabloda ise tür başına satır.
///
/// Bu senkron ŞART: push'u sunucu gönderiyor. Anahtar yalnızca cihazda
/// kalırsa kullanıcı bildirimleri kapatsa bile sunucu göndermeye devam eder.
Future<void> syncSignalsEnabledPreference(WidgetRef ref) async {
  for (final type in AssetType.values) {
    await _syncSignalPreferenceWith(ref.read, type);
  }
}

/// Oturum açıldığında sinyal tercihlerini sunucuyla eşitler.
///
/// Yön kritik: sunucuda satır **varsa** o kazanır ve cihaza indirilir.
/// Yalnızca sunucuda hiç kayıt yoksa yerel değerler yukarı yazılır.
///
/// Neden: tersi (her girişte yereli yukarı basmak) kullanıcının ayarını
/// sessizce siliyordu. Yeni bir cihaza giriş yapıldığında — ya da uygulama
/// yeniden kurulduğunda — `SharedPreferences` boş olduğu için VARSAYILANLAR
/// (eşik 70) sunucudaki gerçek tercihin üzerine yazılıyordu. Kullanıcı
/// telefonunu değiştirince "ayarlarım sıfırlandı" derdi.
///
/// Not: uygulama içi tek-tek değişiklikler zaten anında sunucuya yazılıyor
/// (`_syncSignalPreferenceWith`); bu fonksiyon sadece oturum başlangıcı
/// içindir.
Future<void> syncSignalPreferencesOnLogin(WidgetRef ref) async {
  try {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final remote =
        await SupabaseService.instance.fetchSignalPreferences(user.id);

    if (remote.isEmpty) {
      // Sunucuda hiç kayıt yok → ilk kurulum. Yerelleri yukarı taşı.
      for (final type in AssetType.values) {
        await _syncSignalPreferenceWith(ref.read, type);
      }
      return;
    }

    // Sunucu doğruluk kaynağı → cihaza indir.
    final thresholds = ref.read(signalThresholdProvider.notifier);
    final indicators = ref.read(indicatorPrefsProvider.notifier);
    final schedules = ref.read(signalScheduleProvider.notifier);

    for (final row in remote) {
      final type = AssetType.fromString(row.assetType);
      await thresholds.applyFromServer(type, row.threshold);
      await indicators.applyFromServer(type, row.indicators);
      await schedules.applyFromServer(type, row.frequency, row.notifyHours);
    }

    // `neutralPush` ve `signalsEnabled` tür başına DEĞİL, uygulama genelinde
    // tek anahtardır; sunucuda ise her satırda tekrarlanır. Satırlar teoride
    // ayrışabilir (ör. yarıda kalmış yazma), bu yüzden "herhangi biri açıksa
    // açık" kuralı uygulanır: kullanıcıyı sessizce bildirimsiz bırakmak,
    // fazladan bildirim göndermekten daha kötü bir hata.
    final neutral = remote.any((r) => r.neutralPush);
    final enabled = remote.any((r) => r.signalsEnabled);
    await ref.read(signalNeutralPushProvider.notifier).applyFromServer(neutral);
    await ref.read(signalNotificationsProvider.notifier).applyFromServer(enabled);
  } catch (_) {
    // Ağ hatasında yerel tercihler geçerli kalır.
  }
}

// ─── Chart overlay tercihleri ─────────────────────────────────────────────────
// Grafik üzerine çizilecek göstergeler. Sinyal göstergelerinden ayrı: burası
// sadece görsel overlay (MA20, MA50, Bollinger vs.). Faz 4'te MA20 ile başlar.

const _kChartMA20Key = 'pref_chart_overlay_ma20';
const _kChartLogScaleKey = 'pref_chart_log_scale';

final chartMA20Provider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kChartMA20Key, false));

/// Y ekseni log10 mı? Uzun dönem fiyat serilerinde yüzde-bazlı değişim
/// eşit görünür. Default kapalı — linear.
final chartLogScaleProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kChartLogScaleKey, false));

// ─── Leaderboard opt-in ───────────────────────────────────────────────────────
// Kullanıcı yarış (partner leaderboard) özelliğine katılmak için explicit
// consent verir. Default kapalı (KVKK). Ortakların yarış'ında görünmek için
// bu true olmalı; false ise kendisi de leaderboard'u göremez.

const _kLeaderboardOptInKey = 'pref_leaderboard_opt_in';

final leaderboardOptInProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kLeaderboardOptInKey, false));
