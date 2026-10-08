import 'dart:async';
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
import 'premium_provider.dart';
import '../config/pref_keys.dart';
import '../demo/demo_modu.dart';
import '../models/yatirimci_seviyesi.dart';
import '../services/biometric_lock_service.dart';
import '../services/crash_reporter.dart';
import '../theme/yazi_boyutu.dart';

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

const _kThemeModeKey = PrefKeys.themeMode;
const _kSignalNotificationsKey = PrefKeys.signalNotifications;
const _kPartnerNotificationsKey = PrefKeys.partnerNotifications;
const _kBalanceHiddenKey = PrefKeys.balanceHidden;
const _kLockScreenAmountsKey = PrefKeys.lockScreenAmounts;
const _kLiveActivityStartKey = PrefKeys.liveActivityStartMin;
const _kLiveActivityEndKey = PrefKeys.liveActivityEndMin;
const _kLiveActivityWeekendKey = PrefKeys.liveActivityWeekend;

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
    // Demo (F1): değer bellekte değişir, diske yazılmaz — kabuk kapanınca
    // demonun container'ıyla birlikte biter, gerçek tercihe sızmaz.
    if (DemoModu.aktif) return;
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

/// Arayüz dili (3.20). `null` = sistem dili; aksi hâlde sabit `tr` / `en`.
///
/// **Varsayılan TÜRKÇE, sistem değil.** İngilizce henüz BETA (bazı ekranlar
/// Türkçe); İngilizce cihazlı bir kullanıcıya hiç seçmeden karışık bir
/// arayüz göstermek yerine Türkçe açılır, İngilizce'yi Ayarlar › Görünüm'den
/// bilinçli seçer. Kapsam tamamlanınca varsayılan "sistem"e çekilebilir.
///
/// Tercih diske `PrefKeys.locale` altında 'tr' | 'en' | 'system' yazılır;
/// `ThemeModeNotifier` ile aynı senkron-okuma deseni (ilk kare doğru dilde).
class LocaleNotifier extends Notifier<Locale?> {
  static const _kSystem = 'system';

  @override
  Locale? build() {
    final prefs = _prefsSync;
    if (prefs != null) {
      final raw = prefs.getString(PrefKeys.locale);
      if (raw != null) return parse(raw);
    } else {
      _loadAsync();
    }
    return const Locale('tr', 'TR');
  }

  /// 'tr' → tr_TR, 'en' → en_US, 'system' → null (sistem), tanınmayan → tr.
  static Locale? parse(String? raw) {
    switch (raw) {
      case 'en':
        return const Locale('en', 'US');
      case _kSystem:
        return null;
      case 'tr':
      default:
        return const Locale('tr', 'TR');
    }
  }

  static String encode(Locale? l) =>
      l == null ? _kSystem : (l.languageCode == 'en' ? 'en' : 'tr');

  Future<void> _loadAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(PrefKeys.locale);
      if (raw != null) state = parse(raw);
    } catch (_) {}
  }

  Future<void> set(Locale? locale) async {
    state = locale;
    // Demo (F1): değer bellekte değişir, diske yazılmaz — kabuk kapanınca
    // demonun container'ıyla birlikte biter, gerçek tercihe sızmaz.
    if (DemoModu.aktif) return;
    try {
      final prefs = _prefsSync ?? await SharedPreferences.getInstance();
      await prefs.setString(PrefKeys.locale, encode(locale));
    } catch (_) {}
  }
}

final localeProvider =
    NotifierProvider<LocaleNotifier, Locale?>(LocaleNotifier.new);

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
    // Demo (F1): değer bellekte değişir, diske yazılmaz — kabuk kapanınca
    // demonun container'ıyla birlikte biter, gerçek tercihe sızmaz.
    if (DemoModu.aktif) return;
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
    // Demo (F1): değer bellekte değişir, diske yazılmaz — kabuk kapanınca
    // demonun container'ıyla birlikte biter, gerçek tercihe sızmaz.
    if (DemoModu.aktif) return;
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

/// Toplam kartındaki kaydırma ipucu bir kez gösterildi mi (cihaz tercihi;
/// jest cihaza ait, kişiye değil). 2026-09-21.
final kaydirmaIpucuGosterildiProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(PrefKeys.kaydirmaIpucu, false));

/// Baz para birimi (Faz 3.2) — `BaseCurrency.index` olarak saklanır; model
/// ve kur eşlemesi `base_currency_provider.dart`'ta. Kişiye özel: aynı
/// cihazı paylaşan iki kullanıcının tercihi karışmasın.
final baseCurrencyIndexProvider = NotifierProvider<_IntPrefNotifier, int>(
    () => _IntPrefNotifier(PrefKeys.baseCurrency, 0, perUser: true));

/// Uygulama içi yazı boyutu kademesi (`YaziBoyutu.index`). Varsayılan 1 =
/// "Normal": ayarı hiç açmamış kullanıcı için hiçbir şey değişmez. Kişiye
/// özel değil — aynı telefonda hesap değişince punto zıplamasın.
final yaziBoyutuIndexProvider = NotifierProvider<_IntPrefNotifier, int>(
    () => _IntPrefNotifier(PrefKeys.yaziBoyutu, YaziBoyutu.normal.index));

final yaziBoyutuProvider = Provider<YaziBoyutu>(
    (ref) => YaziBoyutu.indekstenOku(ref.watch(yaziBoyutuIndexProvider)));

/// Yatırımcı seviyesi (Ayarlar › Görünüm) — `YatirimciSeviyesi.index`.
/// Varsayılan Orta = bugünkü görünüm; tercih sorulmaz, dayatılmaz (bkz.
/// `models/yatirimci_seviyesi.dart`). Kişiye özel.
/// Girişten önceki tanıtım ekranı görüldü mü (cihaz tercihi). Bkz.
/// `PrefKeys.karsilamaGoruldu`, `KarsilamaScreen`.
final karsilamaGorulduProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(PrefKeys.karsilamaGoruldu, false));

final investorLevelIndexProvider = NotifierProvider<_IntPrefNotifier, int>(
    () => _IntPrefNotifier(
        PrefKeys.investorLevel, YatirimciSeviyesi.varsayilan.index,
        perUser: true));

final yatirimciSeviyesiProvider = Provider<YatirimciSeviyesi>(
    (ref) => YatirimciSeviyesi.fromIndex(ref.watch(investorLevelIndexProvider)));

/// Seviyenin görünürlük tablosu (sade Başlangıç dahil). Yeni kapılar
/// (grafik araçları, derinlik) bunu okur.
final seviyeGorunurlukProvider = Provider<SeviyeGorunurluk>(
    (ref) => seviyeGorunurlugu(ref.watch(yatirimciSeviyesiProvider)));

// NOT: `zilGorunurProvider` 2026-10-05'te kaldırıldı. Zil yalnız
// sinyallerin değil fiyat alarmları ve ortak davetleri gibi genel
// bildirimlerin de TEK gelen kutusu; Başlangıç seviyesi zili tümden
// gizlediği için o kullanıcı alarm ve davetlerini de göremiyordu
// (sadeleştirme değerlendirmesi 2026-10-04). `seviye_anketi` ile zil her
// seviyede görünür oldu; bayrak kalkınca sağlayıcı hep `true` dönüyordu.
// Başlangıç'ta yalnızca sinyal satırları süzülür ↓.

/// Zil sayfası ve rozeti teknik sinyalleri saysın mı (Başlangıç'ta hayır).
final zilSinyalleriGosterProvider = Provider<bool>((ref) =>
    seviyeGorunurlugu(ref.watch(yatirimciSeviyesiProvider)).teknikSinyaller);

/// Biyometrik / cihaz kilidi — uygulama öne dönünce ve soğuk açılışta
/// kimlik doğrulaması ister. Varsayılan KAPALI; açarken cihaz destekliyor mu
/// diye bir kez doğrulanır (`BiometricLockService`). Kişiye özel.
final biometricLockProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(PrefKeys.biometricLock, false, perUser: true));

/// Kilit teklifi bu kullanıcıya sorulduysa `true` — kabul/ret fark etmez.
///
/// **Neden ayrı bir anahtar, neden `biometricLock == false` yetmiyor:**
/// ikisi farklı soruları yanıtlar. `biometricLock` "kilit açık mı",
/// bu ise "sorduk mu". Kilidi sonradan KAPATAN kullanıcıya teklifi
/// yeniden göstermek, verdiği kararı geri almaya çalışmak olurdu.
///
/// Varsayılan KAPALI: mevcut kullanıcılar da teklifi bir kez görür.
/// Kişiye özel.
final biometricLockOfferedProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(PrefKeys.biometricLockOffered, false,
        perUser: true));

/// Cihazın kilit yöntemi; cihazda hiç kilit yoksa `null`.
///
/// Kilit teklifinin KAPISI ve metni (2026-09-24): ekran kilidi olmayan
/// cihazda teklif gösterilmez — "aç" düğmesi yalnızca "cihaz
/// desteklemiyor" uyarısına çıkıyordu. Teklif o durumda damgalanmaz;
/// kullanıcı sonradan ekran kilidi kurarsa sonraki açılışta görür.
///
/// Uygulama ömrü boyunca bir kez sorulur (FutureProvider önbelleği):
/// cihaz kilidi ayarlardan açılıp kapanınca yeni değer bir sonraki
/// soğuk açılışta okunur — teklif için bu yeterli.
final kilitYontemiProvider = FutureProvider<KilitYontemi?>(
    (ref) => BiometricLockService.instance.yontem);

/// Portföy hedefi (TRY), Bugün kartının KAPSAMINA göre. 0 = belirlenmedi.
/// Yalnızca gösterim: hedef hiçbir hesabı değiştirmez, kartta ilerleme
/// çubuğu olur.
///
/// Anahtar (arg): `''` Ben, `'birlikte'`, `'ortak_<id>'`. Neden kapsam
/// başına (kullanıcı bulgusu 2026-09-30, "hala arada kayboluyor"): hedef
/// satırı yalnızca kendi görünümündeydi, kart Birlikte'ye/ortağa geçince
/// kayboluyordu. Kendi hedefini birleşik toplama karşı ölçmek yanlış
/// "kalan" söylerdi; her kartın kendi hedefi var. Hepsi bu cihazda, oturum
/// sahibine özel — ortağın koyduğu hedef sunucuda yok, uydurulmaz.
/// Ben'in anahtarı eskisiyle aynı (`portfolio_goal_try`), var olan hedef
/// korunur.
class KapsamHedefiNotifier extends FamilyNotifier<int, String> {
  String get _key => _userKey(arg.isEmpty
      ? PrefKeys.portfolioGoalTRY
      : '${PrefKeys.portfolioGoalTRY}_$arg');

  @override
  int build(String arg) {
    final prefs = _prefsSync;
    if (prefs != null) return prefs.getInt(_key) ?? 0;
    _loadAsync();
    return 0;
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
    if (DemoModu.aktif) return; // Demo (F1): yalnızca bellekte.
    try {
      final prefs = _prefsSync ?? await SharedPreferences.getInstance();
      await prefs.setInt(_key, value);
    } catch (_) {}
  }
}

final kapsamHedefiProvider =
    NotifierProvider.family<KapsamHedefiNotifier, int, String>(
        KapsamHedefiNotifier.new);

/// Kendi görünümünün hedefi — `kapsamHedefiProvider('')`.
final portfolioGoalProvider = kapsamHedefiProvider('');

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

// ─── Premium ─────────────────────────────────────────────────────────────────
// `premiumUnlockedProvider` cihazdaki GELİŞTİRİCİ anahtarıdır (SharedPreferences).
// 2026-10-08'e kadar Sinyal Ayarları'ndaki "Aç" düğmesi ve sahte satın alma
// onu açıyordu: paywall açıkken herkes tek dokunuşla ödemesiz Premium
// alırdı. Artık yalnız debug build'de sayılır ([gelistiriciAnahtariSayilirProvider]);
// gerçek hak mağazadan ([magazaPremiumProvider]) ve sunucudan gelir.

const _kPremiumUnlockedKey = PrefKeys.premiumUnlocked;

final premiumUnlockedProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kPremiumUnlockedKey, false));

/// Geliştirici anahtarı sayılır mı. Release'te (TestFlight dahil) HAYIR:
/// orada Premium'u görmek için sandbox satın alma ya da admin hesabı
/// (`push_admins`) kullanılır. Provider olması testin release davranışını
/// sınayabilmesi için.
final gelistiriciAnahtariSayilirProvider = Provider<bool>((_) => kDebugMode);

/// RevenueCat `CustomerInfo`'sundaki `premium` hakkı (SatinAlmaService
/// `hakDegisti` ile yazar). Satın alma anı ile webhook'un sunucuya yazması
/// arasındaki boşluğu kapatır; kalıcı kaynak yine sunucu hakkıdır.
final magazaPremiumProvider = StateProvider<bool>((_) => false);

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
/// Kaynaklar: mağaza (RevenueCat, anlık), sunucu hakkı (abonelik/hediye/
/// manuel), admin, ve yalnız debug'da geliştirici anahtarı.
final effectivePremiumProvider = Provider<bool>((ref) {
  final paywallOn = ref.watch(paywallVisibleProvider);
  if (!paywallOn) return false;
  final unlocked = ref.watch(gelistiriciAnahtariSayilirProvider) &&
      ref.watch(premiumUnlockedProvider);
  final magaza = ref.watch(magazaPremiumProvider);
  // Sunucu hakkı (0116; RevenueCat aboneliği, erken kullanıcı hediyesi,
  // manuel). Cihaz anahtarı test/geliştirici yolu olarak kalır.
  final sunucu = ref.watch(gecerliPremiumHakkiProvider) != null;
  // Admin hesabı Premium alanlarını kilitsiz görür (yasin, 2026-10-05).
  // Sunucuda aynı karar `premium_mi_kullanici` içinde (0123, push_admins).
  final admin = ref.watch(isPushAdminProvider).valueOrNull == true;
  return (unlocked || magaza || sunucu || admin) &&
      RemoteConfigService.instance.premiumEnabled;
});

/// Free tier varlık limiti — Remote Config'ten dinamik.
/// Paywall kapalıyken sınırsız (limit devreye girmez).
/// Premium ise limit yoktur (int.max ile temsil edilir).
/// Premium göstergeler (ADX, Williams %R, CCI) HESAPLANSIN mı.
///
/// Eskiden hesap yalnız cihazdaki geliştirici anahtarına bakıyordu: gerçek
/// abone (sunucu hakkı) satın aldığı göstergeyi alamazdı. Bayrak kapalıyken
/// eski davranış birebir: hesaplanmaz (anahtar canlıda kimsede açık değildi).
final premiumGostergelerHesaplanirProvider = Provider<bool>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return false;
  return ref.watch(effectivePremiumProvider);
});

final assetLimitProvider = Provider<int>((ref) {
  final paywallOn = ref.watch(paywallVisibleProvider);
  if (!paywallOn) return 1 << 30;
  final premium = ref.watch(effectivePremiumProvider);
  if (premium) return 1 << 30; // pratik olarak sınırsız
  return RemoteConfigService.instance.freeAssetLimit;
});

/// Tür başına günlük sinyal bildirimi sınırı — `assetLimitProvider` kalıbı.
/// Paywall kapalıyken ya da Premium'da pratikte sınırsız: seçilen sıklık
/// olduğu gibi kalır. Ekranda gösterilen zamanlama `slotaSigdir` ile
/// hesaplanır; sunucu aynı kuralı `SINYAL_UCRETSIZ_SLOT` ile uygular.
final sinyalSlotSiniriProvider = Provider<int>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return 1 << 30;
  if (ref.watch(effectivePremiumProvider)) return 1 << 30;
  final v = RemoteConfigService.instance.freeSignalSlotsPerDay;
  return v <= 0 ? 1 << 30 : v;
});

/// Karşılaştır grafiğindeki en fazla seri. Beş, paletin sınırıdır ve
/// Premium'un değeridir; ücretsizde `free_compare_series` (varsayılan 2 =
/// kendi serine ek bir kıyas). Paywall kapalıyken herkese 5, eskisi gibi.
const kKarsilastirmaEnFazla = 5;
final karsilastirmaSeriSiniriProvider = Provider<int>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return kKarsilastirmaEnFazla;
  if (ref.watch(effectivePremiumProvider)) return kKarsilastirmaEnFazla;
  return RemoteConfigService.instance.freeCompareSeries
      .clamp(1, kKarsilastirmaEnFazla);
});

/// Ücretsiz sürümde ortak sınırı dolu mu (yeni ortak eklemek Premium ister).
///
/// Paywall kapalıyken ya da Premium'da hep false. Ortak listesi henüz
/// yüklenmediyse false: bilinmeyen sayı yüzünden birini durdurmayız.
/// Sınır yalnız istemcide; sunucu ortaklık sayısını denetlemez (eski
/// sürümler paywall'u zaten göstermiyor, satın alınacak şey yok).
final ortakSiniriDoluProvider = Provider<bool>((ref) {
  if (!ref.watch(paywallVisibleProvider)) return false;
  if (ref.watch(effectivePremiumProvider)) return false;
  final ortaklar = ref.watch(partnersProvider).valueOrNull;
  if (ortaklar == null) return false;
  final sinir = RemoteConfigService.instance.freePartnerLimit;
  return sinir > 0 && ortaklar.length >= sinir;
});

/// Free tier fiyat alarmı limiti — `assetLimitProvider` ile AYNI kalıp.
///
/// Paywall kapalıyken sınırsız: satın alınabilir bir premium yokken
/// kullanıcıyı üçüncü alarmda durdurmak çıkışsız bir duvar olurdu.
final priceAlertLimitProvider = Provider<int>((ref) {
  final paywallOn = ref.watch(paywallVisibleProvider);
  if (!paywallOn) return 1 << 30;
  final premium = ref.watch(effectivePremiumProvider);
  if (premium) return 1 << 30;
  return RemoteConfigService.instance.freePriceAlertLimit;
});

/// Takip listesi limiti — `assetLimitProvider`'dan FARKLI kalıp.
///
/// **Paywall kapalıyken de uygulanır (kullanıcı kararı, 2026-09-25):**
/// *"şimdilik 7 adet takip limiti koyalım, ilerde paywall'la artırabiliriz."*
/// Eskiden `paywall_enabled=false` iken sınırsızdı ("satın alınacak bir şey
/// yokken kullanıcıyı çıkışsız bırakma" gerekçesiyle). Yeni gerekçe: takip
/// listesi her dönem için N seri çizer ve her varlık için fiyat çeker; liste
/// büyüdükçe grafik okunmaz, istek sayısı artar. Limit ürün sınırıdır,
/// satış kapısı değil — bu yüzden çıkış yolu paywall değil "birini çıkar"
/// (`add_watchlist_screen`). Premium yine sınırsız; değer Remote Config'ten
/// (`free_watchlist_limit`, varsayılan 7) yayın sonrası değiştirilebilir.
final watchlistLimitProvider = Provider<int>((ref) {
  final premium = ref.watch(effectivePremiumProvider);
  if (premium) return 1 << 30;
  return RemoteConfigService.instance.freeWatchlistLimit;
});

// ─── Per-category göstergeler ─────────────────────────────────────────────────
// Kullanıcı her varlık türü için hangi göstergelerin sinyal üretmesini istediğini
// seçebilir. Kalıcı: SharedPreferences.

const _kIndicatorPrefsKey = PrefKeys.indicatorsByType;

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
    if (DemoModu.aktif) return; // Demo tercihi diske yazılmaz (F1).
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

  /// [senkron] false: yalnız yerel yazılır. Ön ayar (`sinyalOnAyariUygula`)
  /// eşik + gösterge + sıklığı art arda yazar; her biri ayrı upsert atarsa
  /// 8 tür × 4 yazma = 32 istek olurdu. Orada sunucuya tür başına BİR kez,
  /// en sonda yazılır.
  Future<void> setForType(AssetType type, Set<String> ids,
      {bool senkron = true}) async {
    state = {...state, type: ids};
    await _persist();
    if (senkron) await _syncSignalPreferenceWith(ref.read, type);
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
  if (DemoModu.aktif) return; // Demo sunucuya yazmaz (F1).
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
    CrashReporter.arkaPlan(FirebaseCrashlytics.instance.recordError(
      e,
      st,
      reason: 'signal_preferences upsert (${type.name})',
      fatal: false,
    ), reason: 'preferences_provider.FirebaseCrashlytics.recordError');
  }
}

// ─── Sinyal bildirim eşiği (per asset type) ───────────────────────────────────
// Kullanıcı her varlık türü için confidence eşiğini seçer:
//   50 → düşük (daha çok push)
//   70 → orta (default)
//   85 → yüksek (sadece güçlü sinyaller)
// Eşiğin altında kalan sinyaller push gönderilmez.

const _kSignalThresholdKey = PrefKeys.signalThresholdByType;
const _kSignalNeutralPushKey = PrefKeys.signalNeutralPush;

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
    if (DemoModu.aktif) return; // Demo tercihi diske yazılmaz (F1).
    try {
      final prefs = await SharedPreferences.getInstance();
      final entries =
          state.entries.map((e) => '${e.key.name}:${e.value}').toList();
      await prefs.setStringList(_userKey(_kSignalThresholdKey), entries);
    } catch (_) {}
  }

  /// [senkron]: bkz. `IndicatorPrefsNotifier.setForType`.
  Future<void> setForType(AssetType type, int threshold,
      {bool senkron = true}) async {
    if (!kSignalThresholdOptions.contains(threshold)) return;
    state = {...state, type: threshold};
    await _persist();
    if (senkron) await _syncSignalPreferenceWith(ref.read, type);
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

const _kSignalFrequencyKey = PrefKeys.signalFrequencyByType;
const _kSignalHoursKey = PrefKeys.signalHoursByType;

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
    if (DemoModu.aktif) return; // Demo tercihi diske yazılmaz (F1).
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
  ///
  /// [senkron]: bkz. `IndicatorPrefsNotifier.setForType`.
  Future<void> setFrequency(AssetType type, SignalFrequency freq,
      {bool senkron = true}) async {
    final mevcut = state[type] ?? kDefaultSchedule;
    var hours = mevcut.hours;
    if (freq.needsHourPicker && hours.length != freq.hourCount) {
      hours = freq.hourCount == 1 ? const [11] : const [11, 15];
    }
    state = {...state, type: (frequency: freq, hours: hours)};
    await _persist();
    if (senkron) await _syncSignalPreferenceWith(ref.read, type);
  }

  /// Seçilen saatleri değiştirir. Pencere dışındaki saatler yok sayılır.
  ///
  /// [senkron]: bkz. `IndicatorPrefsNotifier.setForType`.
  Future<void> setHours(AssetType type, List<int> hours,
      {bool senkron = true}) async {
    final temiz = hours
        .where((h) => h >= kSignalWindowStart && h <= kSignalWindowEnd)
        .toSet()
        .toList()
      ..sort();
    if (temiz.isEmpty) return;
    final mevcut = state[type] ?? kDefaultSchedule;
    state = {...state, type: (frequency: mevcut.frequency, hours: temiz)};
    await _persist();
    if (senkron) await _syncSignalPreferenceWith(ref.read, type);
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

/// Verilen türlerin sinyal satırlarını sunucuya yazar — yerel yazmaları
/// `senkron: false` ile toplayan çağıranlar için (sinyal ön ayarı).
Future<void> syncSignalPreferencesFor(
    WidgetRef ref, Iterable<AssetType> turler) async {
  for (final type in turler) {
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

const _kChartMA20Key = PrefKeys.chartOverlayMa20;
const _kChartLogScaleKey = PrefKeys.chartLogScale;

final chartMA20Provider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kChartMA20Key, false));

/// Y ekseni log10 mı? Uzun dönem fiyat serilerinde yüzde-bazlı değişim
/// eşit görünür. Default kapalı — linear.
final chartLogScaleProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kChartLogScaleKey, false));

/// Performans "Bugünkü portföyle" görünümü (simülasyon: bugünkü net
/// portföy tüm dönem boyunca elde tutulmuş gibi). TEK KAYNAK — Ayarlar ›
/// Görünüm yazar, Performans okur (bayrak `performans_ayar_sade`).
///
/// Neden kalıcı (eski Performans anahtarı oturumluktu): Ayarlar'daki bir
/// anahtarın uygulama yeniden açılınca kendiliğinden kapanması "ayar
/// tutmuyor" diye okunur. Unutulup açık kalma riskine karşı Performans
/// etkinken rozet gösterir ("görünmeyen filtre" sınıfı hata, bkz.
/// `_buildScopeBar`). Varsayılan kapalı: gerçek geçmiş.
final bugunkuPortfoyleProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(PrefKeys.performansBugunkuPortfoy, false,
        perUser: true));

// ─── Balina Radarı (2026-10-05) ───────────────────────────────────────────────

/// "Nasıl okunur" gezintisi bir kez (`radar_ortak.dart`).
final radarKocuGorulduProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(PrefKeys.radarKocuGoruldu, false, perUser: true));

/// Haftanın özetinde sakin varlıklar da listelensin mi.
final haftaSakinGosterProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(PrefKeys.haftaSakinGoster, true, perUser: true));

/// Erken kullanıcı hediyesi sayfası gösterildi mi (bir kez).
final premiumHediyeGosterildiProvider =
    NotifierProvider<_BoolPrefNotifier, bool>(() => _BoolPrefNotifier(
        PrefKeys.premiumHediyeGosterildi, false,
        perUser: true));

// ─── Leaderboard opt-in ───────────────────────────────────────────────────────
// Kullanıcı yarış (partner leaderboard) özelliğine katılmak için explicit
// consent verir. Default kapalı (KVKK). Ortakların yarış'ında görünmek için
// bu true olmalı; false ise kendisi de leaderboard'u göremez.

const _kLeaderboardOptInKey = PrefKeys.leaderboardOptIn;

//
// KİŞİYE ÖZEL (2026-09-23 denetimi F6): açık rıza kişiye aittir, cihaza
// değil. Cihaz genelindeyken A'nın verdiği onay aynı telefonda giriş yapan
// B için de "açık" okunuyor, B'nin getirisi onayı olmadan sunucuya
// yazılıp karşılaştırılıyordu (KVKK). Eski cihaz geneli değer taşınmaz:
// daha önce katılmış kullanıcı `_hydrateLeaderboardOptIn` ile sunucudaki
// kaydından yeniden açılır, katılmamış olan kapalı başlar.
final leaderboardOptInProvider = NotifierProvider<_BoolPrefNotifier, bool>(
    () => _BoolPrefNotifier(_kLeaderboardOptInKey, false, perUser: true));

/// Çan rozetinin "görüldü" damgası (ms epoch; 0 = hiç açılmadı).
///
/// Rozet eskiden AKTİF (temizlenmemiş) bildirim sayısıydı: çan sayfası
/// açılıp bildirim okunsa bile "1 yeni bildirim" kalıyordu, çünkü okumak
/// hiçbir durumu değiştirmiyordu (emülatör testi #26, 2026-09-29). Aktif /
/// Geçmiş ayrımı (Temizle) kullanıcının bilinçli arşividir, okundu değil;
/// o yüzden sunucuya "okundu" yazılmaz, yalnız bu cihaz-içi damga tutulur
/// ve rozet damgadan SONRA gelen aktif kayıtları sayar
/// (`yeniBildirimSayisi`).
final bildirimSonGorulenProvider = NotifierProvider<_IntPrefNotifier, int>(
    () => _IntPrefNotifier(PrefKeys.bildirimSonGorulen, 0, perUser: true));

// ─── Kullanıcıya özel tercihlerin TAM listesi ─────────────────────────────────
//
// `setPreferencesUser` yalnızca anahtar ÖN EKİNİ değiştirir; provider'ın
// bellekteki state'i önceki kullanıcıdan kalır. `_AuthGate` kullanıcı
// değişiminde bu listeyi invalidate eder ki her tercih yeni kullanıcının
// anahtarından yeniden okunsun.
//
// Neden liste (2026-09-21): invalidate çağrıları `main.dart`'ta elle
// sıralanıyordu ve yalnızca sinyal tercihlerini kapsıyordu. Portföy hedefi
// `perUser: true` ile TANIMLANMIŞTI ama listede yoktu: A çıkıp B girince B,
// A'nın hedefini görüyordu ("hedef cihaz bazlı" bulgusu). Aynı boşluk baz
// para birimi, yatırımcı seviyesi, biyometrik kilit ve Live Activity
// tercihlerinde de vardı. Liste tanımların YANINDA durur;
// `test/kullaniciya_ozel_tercihler_test.dart` kaynağı tarayıp `perUser:
// true` / `_userKey(` kullanan her provider'ın burada olduğunu doğrular —
// yeni bir kişisel tercih eklenip listeye yazılmazsa test kırılır.
final kullaniciyaOzelTercihler = <ProviderOrFamily>[
  signalThresholdProvider,
  indicatorPrefsProvider,
  signalScheduleProvider,
  signalNeutralPushProvider,
  signalNotificationsProvider,
  baseCurrencyIndexProvider,
  investorLevelIndexProvider,
  biometricLockProvider,
  biometricLockOfferedProvider,
  kapsamHedefiProvider, // aile: Ben (`portfolioGoalProvider`) + kapsamlar
  lockScreenAmountsProvider,
  liveActivityStartProvider,
  liveActivityEndProvider,
  liveActivityWeekendProvider,
  leaderboardOptInProvider,
  bildirimSonGorulenProvider,
  bugunkuPortfoyleProvider,
  radarKocuGorulduProvider,
  haftaSakinGosterProvider,
  premiumHediyeGosterildiProvider,
];
