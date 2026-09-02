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

// ─── Kullanıcıya özel tercih anahtarları ─────────────────────────────────────
//
// Sinyal tercihleri KİŞİYE özeldir ama SharedPreferences cihaz genelindedir.
// Anahtarlar sabit olduğunda A kullanıcısı çıkıp B girdiğinde B, A'nın
// ayarlarını görüyordu. Daha kötüsü: B'nin sunucuda kaydı yoksa
// `syncSignalPreferencesOnLogin` yereldekileri "ilk kurulum" sanıp
// B'nin satırına A'nın ayarlarını YAZIYORDU.
//
// Çözüm: sinyal anahtarları aktif kullanıcı id'siyle ön eklenir.
// Tema/bakiye gizleme gibi cihaz tercihleri ön eksiz kalır — onların
// kullanıcıya bağlı olması beklenmez.
String? _aktifKullaniciId;

/// Tercih anahtarlarının hangi kullanıcıya ait olduğunu belirler.
/// Auth durumu değişince çağrılır (bkz. `_AuthGate`).
void setPreferencesUser(String? userId) {
  _aktifKullaniciId = userId;
}

/// Kullanıcıya özel anahtar üretir. Oturum yoksa ön eksiz döner —
/// giriş öncesi okunan değerler zaten kimseye ait değildir.
String _userKey(String base) =>
    _aktifKullaniciId == null ? base : '${base}_$_aktifKullaniciId';

const _kThemeModeKey = 'pref_theme_mode'; // 'system' | 'light' | 'dark'
const _kSignalNotificationsKey = 'pref_signal_notifications';
const _kPartnerNotificationsKey = 'pref_partner_notifications';
const _kBalanceHiddenKey = 'pref_balance_hidden';
const _kLockScreenAmountsKey = 'pref_lockscreen_amounts';
const _kLiveActivityStartKey = 'pref_live_activity_start_min';
const _kLiveActivityEndKey = 'pref_live_activity_end_min';
const _kLiveActivityWeekendKey = 'pref_live_activity_weekend';

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    // SENKRON okuma. Eskiden `build()` koşulsuz `ThemeMode.dark` döndürüp
    // kaydedilmiş tercihi async yüklüyordu: light seçmiş bir kullanıcı
    // uygulamayı her açtığında önce KOYU bir kare görüp sonra aydınlığa
    // atlıyordu. `_prefsSync` main.dart'ta ilk frame'den önce hazırlanıyor
    // (`initPreferencesCache`), bu yüzden burada gerçek değeri hemen
    // verebiliyoruz — bool tercihlerinde zaten uygulanan desenin aynısı.
    final prefs = _prefsSync;
    if (prefs != null) {
      final parsed = _parse(prefs.getString(_kThemeModeKey));
      if (parsed != null) return parsed;
    } else {
      // Cache init edilmemişse (test, beklenmedik sıra) async'e düş.
      _loadAsync();
    }
    // Tercih KAYDEDİLMEMİŞSE cihazı takip et. Eskiden burası `ThemeMode.dark`
    // idi: cihazı light olan kullanıcı, ayarlara girip elle "açık" seçmediği
    // sürece uygulamayı koyu görüyordu — splash dahil. Marka dark-first
    // olabilir ama bu, sistem seçimini yok saymanın gerekçesi değil.
    //
    // Kullanıcının AÇIK tercihi bu satıra hiç ulaşmaz (yukarıda `parsed`
    // döner); burası yalnızca "henüz seçim yapılmadı" hâlidir.
    return ThemeMode.system;
  }

  /// Kayıtlı metni [ThemeMode]'a çevirir; tanınmayan/eksik değerde null.
  static ThemeMode? _parse(String? raw) {
    switch (raw) {
      case 'system':
        return ThemeMode.system;
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return null;
    }
  }

  Future<void> _loadAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final parsed = _parse(prefs.getString(_kThemeModeKey));
      if (parsed != null) state = parsed;
    } catch (_) {}
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = _prefsSync ?? await SharedPreferences.getInstance();
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

/// Tamsayı tercih — [_BoolPrefNotifier] ile aynı desen.
///
/// Live Activity saat penceresi için eklendi; saat "dakika cinsinden gün
/// başlangıcından ofset" olarak saklanır (ör. 10:00 → 600). Tek bir int
/// hem saati hem dakikayı taşır ve karşılaştırması ucuzdur.
class _IntPrefNotifier extends Notifier<int> {
  final String key;
  final int defaultValue;
  final bool perUser;

  _IntPrefNotifier(this.key, this.defaultValue, {this.perUser = false});

  String get _key => perUser ? _userKey(key) : key;

  @override
  int build() {
    final prefs = _prefsSync;
    if (prefs != null) {
      final v = prefs.getInt(_key);
      if (v != null) return v;
    } else {
      _loadAsync();
    }
    return defaultValue;
  }

  Future<void> _loadAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_key);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(int value) async {
    state = value;
    try {
      final prefs = _prefsSync ?? await SharedPreferences.getInstance();
      await prefs.setInt(_key, value);
    } catch (_) {}
  }
}

class _BoolPrefNotifier extends Notifier<bool> {
  final String key;
  final bool defaultValue;

  /// Anahtar kullanıcıya göre ayrılsın mı. Sinyal tercihleri için true
  /// (kişiye özel), tema/bakiye gizleme gibi cihaz tercihleri için false.
  final bool perUser;

  _BoolPrefNotifier(this.key, this.defaultValue, {this.perUser = false});

  String get _key => perUser ? _userKey(key) : key;

  @override
  bool build() {
    // Senkron okuma — cache yoksa default. Cache init edilmişse gerçek değer.
    final prefs = _prefsSync;
    if (prefs != null) {
      final v = prefs.getBool(_key);
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
      final v = prefs.getBool(_key);
      if (v != null) state = v;
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      final prefs = _prefsSync ?? await SharedPreferences.getInstance();
      await prefs.setBool(_key, value);
    } catch (_) {}
  }

  /// Sunucudan gelen değeri yerele uygular.
  ///
  /// Davranışı [set] ile aynı (bu notifier zaten sunucuya yazmaz); ayrı isim
  /// çağrı yerinde yönü açık kılmak içindir — sunucudan İNEN veri, kullanıcı
  /// dokunuşu değil.
  Future<void> applyFromServer(bool value) => set(value);
}

// Sinyal bildirim ana anahtarı KİŞİYE özel: push'u sunucu gönderiyor ve
// karar kullanıcının satırına bakılarak veriliyor.
final signalNotificationsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kSignalNotificationsKey, true, perUser: true));

final partnerNotificationsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kPartnerNotificationsKey, true));

final balanceHiddenProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kBalanceHiddenKey, false));

/// Kilit ekranı Live Activity'sinde para tutarı gösterilsin mi?
///
/// **Varsayılan KAPALI.** Kilit ekranı telefon açılmadan görülebilen bir
/// yüzeydir; tutar orada varsayılan olarak durmamalı. Kapalıyken günlük
/// yüzde ve grafik yine görünür — ikisi de portföy BÜYÜKLÜĞÜNÜ ele vermez.
///
/// Not: iOS "kilitli mi, açık mı" bilgisini vermez (ActivityKit'te böyle
/// bir sinyal yok), bu yüzden "kilitliyken gizle, açılınca göster"
/// davranışı kurulamaz — tercih her iki durumda da geçerlidir.
/// Kişiye özel: aynı cihazı paylaşan iki kullanıcının tercihi karışmasın.
final lockScreenAmountsProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kLockScreenAmountsKey, false, perUser: true));

/// Live Activity penceresi — başlangıç/bitiş, gün içi DAKİKA cinsinden.
///
/// Varsayılan BIST seansı (10:00–18:10) ama kullanıcı değiştirebilir:
/// yurt dışı piyasa takip eden ya da kriptoda gece hareket izleyen biri
/// için sabit bir borsa saati anlamsızdır.
///
/// **Neden dakika:** tek bir int hem saati hem dakikayı taşır ve
/// karşılaştırması ucuzdur (`600` = 10:00). İki ayrı tercih tutmak
/// tutarsız duruma (bitiş < başlangıç) daha kolay düşerdi.
///
/// ⚠️ Apple oturumu **8 saat** sonra zorla kapatır. Daha geniş bir
/// pencere seçilirse oturum otomatik yenilenir (bkz.
/// `LiveActivityService.sessionEnd`), ama kullanıcı uygulamayı gün boyu
/// hiç açmazsa banner yine de düşer — bu Apple'ın kuralı, aşılamaz.
final liveActivityStartProvider = NotifierProvider<_IntPrefNotifier, int>(
    () => _IntPrefNotifier(_kLiveActivityStartKey, 10 * 60, perUser: true));

final liveActivityEndProvider = NotifierProvider<_IntPrefNotifier, int>(
    () => _IntPrefNotifier(_kLiveActivityEndKey, 18 * 60 + 10, perUser: true));

/// Hafta sonu da gösterilsin mi? **Varsayılan AÇIK.**
///
/// Önceden kapalıydı ("BIST kapalı, rakam donuk kalır" gerekçesiyle) ama
/// bu yanlış bir varsayımdı: kullanıcı hafta sonu da portföyünü görmek
/// isteyebilir — banner zaten "Piyasa kapalı" etiketiyle rakamın neden
/// sabit olduğunu söylüyor. Kısıtlamak yerine bilgilendirmek doğru olan.
final liveActivityWeekendProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kLiveActivityWeekendKey, true, perUser: true));

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

/// Free tier takip listesi limiti — `assetLimitProvider` ile AYNI kalıp.
///
/// **Paywall kapalıyken sınırsız.** `paywall_enabled` şu an `false`; limiti
/// koşulsuz uygulamak, satın alınabilir bir premium yokken kullanıcıyı 5
/// varlıkta durdurup çıkışsız bırakırdı. Paywall açıldığında limit kendiliğinden
/// devreye girer — burada değişiklik gerekmez.
final watchlistLimitProvider = Provider<int>((ref) {
  final paywallOn = ref.watch(paywallVisibleProvider);
  if (!paywallOn) return 1 << 30;
  final premium = ref.watch(effectivePremiumProvider);
  if (premium) return 1 << 30;
  return RemoteConfigService.instance.freeWatchlistLimit;
});

// ─── Per-category göstergeler ─────────────────────────────────────────────────
// Kullanıcı her varlık türü için hangi göstergelerin sinyal üretmesini istediğini
// seçebilir. Kalıcı: SharedPreferences.

const _kIndicatorPrefsKey = 'pref_indicators_by_type_v1';

class IndicatorPrefsNotifier extends Notifier<Map<AssetType, Set<String>>> {
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
      final raw = prefs.getStringList(_userKey(_kIndicatorPrefsKey));
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
      await prefs.setStringList(_userKey(_kIndicatorPrefsKey), entries);
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
      final raw = prefs.getStringList(_userKey(_kSignalThresholdKey));
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
      await prefs.setStringList(_userKey(_kSignalThresholdKey), entries);
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
      final freqRaw =
          prefs.getStringList(_userKey(_kSignalFrequencyKey)) ?? const [];
      final hoursRaw =
          prefs.getStringList(_userKey(_kSignalHoursKey)) ?? const [];

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
        _userKey(_kSignalFrequencyKey),
        state.entries
            .map((e) => '${e.key.name}:${e.value.frequency.id}')
            .toList(),
      );
      await prefs.setStringList(
        _userKey(_kSignalHoursKey),
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
      type: (
        frequency: freq,
        hours: hours.isEmpty ? kDefaultSchedule.hours : hours
      ),
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
    () => _BoolPrefNotifier(_kSignalNeutralPushKey, false, perUser: true));

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
    await ref
        .read(signalNotificationsProvider.notifier)
        .applyFromServer(enabled);
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
