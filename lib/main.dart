import 'dart:async';
import 'package:flutter/cupertino.dart'
    show CupertinoThemeData, CupertinoTextThemeData;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'l10n/l10n.dart';
import 'models/asset.dart';
import 'models/user_model.dart';
import 'providers/price_alert_notification_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/portfolio_provider.dart';
import 'providers/preferences_provider.dart';
import 'providers/signal_provider.dart';
import 'screens/disclaimer_acceptance_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/lock_offer_screen.dart';
import 'services/biometric_lock_service.dart' show KilitYontemi;
import 'screens/lock_screen.dart';
import 'utils/sandik_snack.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'widgets/yenilikler_sheet.dart';
import 'services/surum_notu_service.dart';
import 'services/deep_link_service.dart';
import 'services/analytics_service.dart';
import 'services/auth_service.dart';
import 'services/remote_config_service.dart';
import 'services/daily_summary.dart';
import 'services/crash_reporter.dart';
import 'config/pref_keys.dart';
import 'services/disclaimer_service.dart';
import 'services/secure_session_storage.dart';
import 'services/fx_rate_migration_service.dart';
import 'services/home_widget_service.dart';
import 'services/live_activity_service.dart';
import 'services/notification_service.dart';
import 'services/leaderboard_service.dart';
import 'services/partner_invite_listener_service.dart';
import 'services/remote_push_service.dart';
import 'services/milestone_repository.dart';
import 'services/milestone_service.dart';
import 'services/review_prompt_service.dart';
import 'services/retention_tracker.dart';
import 'services/surface_theme.dart';
import 'theme/sandik.dart';
import 'widgets/sandik_error_view.dart';
import 'widgets/milestone_sheet.dart';
import 'widgets/review_prompt_sheet.dart';
import 'widgets/widget_install_sheet.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

/// Splash'in ana ekrana geçmesi için veri yeterince hazır mı?
///
/// Saf fonksiyon — `_AuthGateState._veriHazir()` provider'ları `watch` edip
/// sonuçları buraya aktarır. Ayrı durmasının sebebi test edilebilirlik:
/// kullanıcının bildirdiği "ana ekran 2 kez load oluyor" hatasının kökü bu
/// karar tablosuydu ve zamanlamaya bağlı olduğu için elle test kırılgan.
///
/// [partnerListSettled] ortak LİSTESİNİN çözülmüş olması. Kritik: liste
/// yüklenirken `activePartnersProvider` boş döner, yani "ortak yok" ile
/// "ortaklar henüz bilinmiyor" ayırt edilemez. Beklenmezse kapı erken açılır,
/// liste sonradan dolunca HomeScreen ortak varlıkları için kendi loading'ini
/// açar — ikinci loading budur.
bool splashVeriHazir({
  required bool portfolioSettled,
  required bool partnerListSettled,
  required bool ortakVar,
  required bool partnerAssetsSettled,
}) {
  if (!partnerListSettled) return false;
  if (!portfolioSettled) return false;
  if (!ortakVar) return true; // Ortak yoksa ortak varlığı da beklenmez.
  return partnerAssetsSettled;
}

/// İlk frame'i beklemesi gerekmeyen Firebase servisleri.
///
/// Arka planda sırayla kurulur; biri patlarsa diğerleri yine denenir ve
/// hata Crashlytics'e düşer — `main` içinde sessizce yutulmaz.
Future<void> _initDeferredServices() async {
  for (final step in <(String, Future<void> Function())>[
    ('RemotePushService', () => RemotePushService.instance.init()),
    ('AnalyticsService', () => AnalyticsService.instance.init()),
    ('RemoteConfigService', () => RemoteConfigService.instance.init()),
    // AnalyticsService'ten SONRA: kurulum günü yazılırken ve ilk açılış
    // event'i giderken gönderici hazır olmalı, yoksa uygulamanın ömrü
    // boyunca bir kez üretilen bu event sessizce düşerdi.
    ('RetentionTracker', () async {
      await RetentionTracker.instance.init();
      // Kaynak, açılış YAZILMADAN ÖNCE belirlenir: önce 'cold' yazıp sonra
      // widget atfını eklemek aynı açılışı iki kez saydırırdı.
      final widgetten = await HomeWidgetService.instance.launchedFromWidget();
      await RetentionTracker.instance
          .recordLaunch(source: widgetten ? 'widget' : 'cold');
      // Uygulama açıkken widget'a dokunulması ayrı bir akıştan gelir.
      await HomeWidgetService.instance.startClickAttribution();
    }),
  ]) {
    try {
      await step.$2();
    } catch (e, st) {
      // `CrashReporter` üzerinden: ham hata metni PII taşıyabiliyordu
      // (e-posta/UUID/JWT). `report` sanitize eder ve debug'da zaten yazar.
      CrashReporter.report(e, st, reason: '${step.$1} deferred init');
    }
  }
}

void main() async {
  // Crashlytics + tüm async hatalar tek `runZonedGuarded` içinde toplanır
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // DM Sans `assets/fonts/` altında gömülü (bkz. pubspec.yaml `fonts:`);
    // `kSandikFontFamily` ile doğrudan kullanılır. google_fonts kaldırıldı
    // (2026-09-14) — ağ bağımlılığı ve aile adı eşleşme tuzağı da gitti.

    await initializeDateFormatting('tr_TR');
    // SharedPreferences warm-up — _BoolPrefNotifier'lar ilk render'da
    // senkron okuyabilsin, "yarışa katıl" prompt'u flash olmasın.
    await initPreferencesCache();
    // Uygulama dışı yüzeylerin (kilit ekranı + widget) son tema kararı.
    //
    // Süreç yeniden başladığında servis singleton'ları `false` (koyu)
    // varsayılanıyla doğar; açık temalı kullanıcı, portföy ilk kez
    // yayınlanana kadar koyu palet görüyordu. Karar diskten okunur —
    // yeniden ÇÖZÜLMEZ (bkz. `SurfaceTheme`).
    await SurfaceTheme.instance.restore();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await Firebase.initializeApp();

      // Crashlytics — debug build'de gönderim kapalı (gürültü olmasın)
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      // Senkron Flutter framework hataları
      //
      // `fatal` kararı `CrashReporter.agHatasiMi`'den gelir: timeout/soket
      // hatası kullanıcının BAĞLANTISIDIR, uygulamanın çökmesi değil. Hepsini
      // `fatal: true` yazmak "çökmesiz kullanıcı" oranını olmayan çökmelerle
      // düşürüyor ve gerçek çökmeleri gürültüde gizliyordu (2026-09-19).
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        CrashReporter.report(
          // Metin `exceptionAsString()` (FlutterError'ın kendi biçimi
          // korunsun), sınıflandırma TİP üzerinden.
          details.exceptionAsString(),
          details.stack,
          reason: details.context?.toDescription() ?? 'FlutterError.onError',
          fatal: !CrashReporter.agHatasiMi(details.exception),
        );
      };

      // Native platform hataları (engine seviyesi)
      PlatformDispatcher.instance.onError = (error, stack) {
        CrashReporter.report(
          error,
          stack,
          reason: 'PlatformDispatcher.onError',
          fatal: !CrashReporter.agHatasiMi(error),
        );
        return true;
      };

      // Bu üçü ilk frame'i BEKLETMEZ — hiçbiri açılış ekranını çizmek için
      // gerekli değil:
      //   - RemotePushService: `start(userId)` zaten kendi içinde init()
      //     çağırıyor (auth gate'te, ilk frame'den sonra).
      //   - AnalyticsService: `navigatorObserver` hiçbir yerde kullanılmıyor;
      //     ilk event'e kadar hazır olması yeterli.
      //   - RemoteConfigService: getter'ları init edilmemişken default'lara
      //     düşer, yani erken okuma güvenli.
      // Hataları yutmuyoruz; yalnızca beklemiyoruz.
      CrashReporter.arkaPlan(_initDeferredServices(), reason: 'main._initDeferredServices');
    } catch (e, st) {
      // Firebase config dosyalari yoksa veya init başarısızsa
      // sessizce devam et; uygulama remote push + crashlytics olmadan çalışır.
      if (kDebugMode) {
        debugPrint('Firebase init failed: $e\n$st');
      }
    }

    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      runApp(_ConfigErrorApp(
        urlEmpty: supabaseUrl.isEmpty,
        keyEmpty: supabaseAnonKey.isEmpty,
      ));
      return;
    }
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      // Oturum token'ı Keychain/Keystore'da (bkz. SecureSessionStorage).
      authOptions: FlutterAuthClientOptions(
        localStorage: SecureSessionStorage(
          persistSessionKey: SecureSessionStorage.defaultKeyFor(supabaseUrl),
        ),
      ),
    );
    await NotificationService.instance.init(navigatorKey: appNavigatorKey);
    // Dış kaynaklı sandik:// bağlantıları (3.8). Bildirim servisinden SONRA:
    // hedefe gidiş `openAssetPerformance` üzerinden, o da navigatorKey ister.
    CrashReporter.arkaPlan(DeepLinkService.instance.init(), reason: 'main.DeepLinkService.init');
    // Yalnızca zemini şeffaf yap. İkon parlaklığı BURADA sabitlenmez:
    // `Brightness.light` (beyaz ikon) light temada açık zemin üzerinde
    // okunmuyordu. İkon rengi tema ile birlikte değişmeli, bu yüzden
    // `SandikLoadingScreen` ve AppBar'lar `systemOverlayStyle` üzerinden
    // moda göre kendi değerini verir.
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
    ));
    runApp(const ProviderScope(child: SandikApp()));
  }, (error, stack) {
    // Zone-level: yakalanmayan async hataları.
    // `CrashReporter` Firebase kurulu değilse sessizce no-op'tur; ağ hatası
    // burada da non-fatal (yukarıdaki gerekçe).
    CrashReporter.report(
      error,
      stack,
      reason: 'runZonedGuarded',
      fatal: !CrashReporter.agHatasiMi(error),
    );
  });
}

/// Fail-fast screen shown when Supabase build-time constants are empty.
/// Signals a broken CI configuration (--dart-define / DART_DEFINES not
/// forwarded to the Dart compiler) instead of silently failing every
/// network call at runtime.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp({required this.urlEmpty, required this.keyEmpty});
  final bool urlEmpty;
  final bool keyEmpty;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: const Color(0xFF1A0000),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Uygulama yapılandırma hatası',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Bu build eksik Supabase kimlik bilgileriyle derlenmiş. '
                  'Sorun geliştirici tarafında; yeni bir sürüm bekleyin.',
                  style: TextStyle(color: Colors.white70, fontSize: 15),
                ),
                const SizedBox(height: 24),
                Text(
                  'SUPABASE_URL: ${urlEmpty ? "BOŞ" : "OK"}\n'
                  'SUPABASE_ANON_KEY: ${keyEmpty ? "BOŞ" : "OK"}',
                  style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 13,
                      fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class SandikApp extends ConsumerWidget {
  const SandikApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Tema modu kullanıcı tercihinden gelir (SharedPreferences'a yazılır).
    // Tercih yoksa varsayılan `ThemeMode.system` — cihaz/IDE seçimi takip
    // edilir. Marka dark-first'tür ama bu, seçim yapmamış kullanıcıya koyu
    // tema dayatmanın gerekçesi değildi (splash dahil her şey koyu açılıyordu).
    final themeMode = ref.watch(themeModeProvider);
    // Arayüz dili (3.20): varsayılan tr_TR; `null` = sistem (kullanıcı
    // seçtiyse). İngilizce BETA — bkz. `LocaleNotifier`.
    final locale = ref.watch(localeProvider);

    return MaterialApp(
      title: 'sandık',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: _buildTheme(SandikPalette.light, Brightness.light),
      darkTheme: _buildTheme(SandikPalette.dark, Brightness.dark),
      themeMode: themeMode,
      // Türkçe locale — showDatePicker, showTimePicker vb. tüm Material
      // widget'ları için dd/MM/yyyy formatı, Türkçe ay/gün adları, virgüllü
      // ondalık ayırıcı. Kullanıcı İngilizce seçerse en_US.
      locale: locale,
      localizationsDelegates: const [
        ...AppLocalizations.localizationsDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // tr_TR + en_US (3.20). en_US 2026-09 denetiminde çıkarılmıştı ("arb yok");
      // artık .arb var. Varsayılan dil yine Türkçe (`LocaleNotifier`): İngilizce
      // cihaz, kullanıcı seçmeden İngilizce açılmaz — beta karışıklığı olmasın.
      supportedLocales: AppLocalizations.supportedLocales,
      // Tanıtım turu Navigator'ın ÜSTÜNDE yaşar: her rota açılıp kapansa da
      // karartma ve kart en üstte kalır (bkz. OnboardingTourHost).
      builder: (context, child) => OnboardingTourHost(child: child!),
      home: const _AuthGate(),
    );
  }

  ThemeData _buildTheme(SandikPalette p, Brightness brightness) {
    // ── ColorScheme (Sandık / Toka Spec) ────────────────────────────────────
    final cs = ColorScheme(
      brightness: brightness,
      // Primary — Amber (CTA, aktif, logo ikon)
      primary: p.amberFill,
      onPrimary: p.onAmber,
      primaryContainer: p.surface2,
      onPrimaryContainer: p.gold,
      // Secondary — Altın (display sayılar)
      secondary: p.gold,
      onSecondary: p.onAmber,
      secondaryContainer: p.surface2,
      onSecondaryContainer: p.gold,
      // Tertiary — Kazanç yeşili
      tertiary: p.gain,
      onTertiary: p.onAmber,
      tertiaryContainer: p.gain.withValues(alpha: 0.18),
      onTertiaryContainer: p.gain,
      // Error — Kayıp kırmızısı
      error: p.loss,
      onError: p.onAmber,
      errorContainer: p.loss.withValues(alpha: 0.16),
      onErrorContainer: p.loss,
      // Surfaces
      surface: p.surface1,
      onSurface: p.text90,
      surfaceContainerLowest: p.background,
      surfaceContainerLow: p.background,
      surfaceContainer: p.surface1,
      surfaceContainerHigh: p.surface2,
      surfaceContainerHighest: p.surface2,
      onSurfaceVariant: p.text58,
      // Outline
      outline: Sandik.brown,
      outlineVariant: p.surface1,
      // Inverse
      inverseSurface: p.text90,
      onInverseSurface: p.onAmber,
      inversePrimary: Sandik.brown,
      // Scrim / shadow
      scrim: Colors.black,
      shadow: Colors.black,
    );

    // ── Typography (DM Sans — tek font) ──────────────────────────────────────
    final baseText = ThemeData.dark().textTheme.apply(fontFamily: kSandikFontFamily);

    TextStyle dm(double size, FontWeight weight, double ls) =>
        sandikFont(
            fontSize: size,
            fontWeight: weight,
            letterSpacing: ls,
            color: p.text90);

    final textTheme = baseText.copyWith(
      // Display — büyük sayılar
      displayLarge:
          dm(52, FontWeight.w700, -0.03 * 52).copyWith(color: p.gold),
      displayMedium:
          dm(40, FontWeight.w700, -0.03 * 40).copyWith(color: p.gold),
      displaySmall:
          dm(32, FontWeight.w700, -0.02 * 32).copyWith(color: p.gold),
      // Headline — başlıklar
      headlineLarge: dm(24, FontWeight.w700, -0.01 * 24),
      headlineMedium: dm(20, FontWeight.w700, -0.01 * 20),
      headlineSmall: dm(18, FontWeight.w600, -0.01 * 18),
      // Title — navigasyon ve kart başlıkları
      titleLarge: sandikFont(
          fontSize: 16, fontWeight: FontWeight.w600, color: p.text90),
      titleMedium: sandikFont(
          fontSize: 14, fontWeight: FontWeight.w500, color: p.text90),
      titleSmall: sandikFont(
          fontSize: 12, fontWeight: FontWeight.w500, color: p.text90),
      // Body — gövde metin
      bodyLarge: sandikFont(
          fontSize: 15, fontWeight: FontWeight.w500, color: p.text90),
      bodyMedium: sandikFont(
          fontSize: 13, fontWeight: FontWeight.w400, color: p.text90),
      bodySmall: sandikFont(
          fontSize: 11, fontWeight: FontWeight.w400, color: p.text58),
      // Label — etiket
      labelLarge: sandikFont(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.06 * 11,
          color: p.text90),
      labelMedium: sandikFont(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06 * 10,
          color: p.text58),
      labelSmall: sandikFont(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06 * 9,
          color: p.text36),
    );

    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: p.background,
      textTheme: textTheme,

      // Cupertino köprüsü.
      //
      // `CupertinoAlertDialog` / `showCupertinoModalPopup` Material temasını
      // OKUMAZ; kendi `CupertinoTheme`'ine bakar. Bağlanmazsa bu dialog'lar
      // Flutter'ın varsayılan Cupertino paletiyle çizilir ve uygulama light
      // moddayken koyu (ya da tersi) açılabilir. Uygulamada 3 Cupertino
      // dialog + 1 modal popup var; hepsi buradan beslenir.
      cupertinoOverrideTheme: CupertinoThemeData(
        brightness: brightness,
        primaryColor: p.amberFill,
        scaffoldBackgroundColor: p.background,
        barBackgroundColor: p.surface1,
        textTheme: CupertinoTextThemeData(
          primaryColor: p.amberFill,
          textStyle: sandikFont(color: p.text90, fontSize: 15),
        ),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface1,
        foregroundColor: p.text90,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: sandikFont(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02 * 22,
          color: p.text90,
        ),
        // Status bar ikonları zeminin TERSİ olmalı: koyu temada açık
        // ikon, açık temada koyu ikon. Sabit bırakılırsa light modda
        // beyaz ikonlar beyaz zeminde kaybolur.
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              brightness == Brightness.light ? Brightness.dark : Brightness.light,
          statusBarBrightness: brightness,
        ),
      ),

      // Card
      cardTheme: CardThemeData(
        elevation: 0,
        color: p.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          // Paletten: dark'ta beyaz %7, light'ta siyah %9. Sabit beyaz
          // kenarlık AÇIK TEMADA görünmezdi — kart zeminden hiç ayrılmıyor,
          // arayüz "kutuları kaybolmuş" gibi okunuyordu.
          side: BorderSide(color: p.hairline, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // Dolgu da yön değiştirir: dark'ta zeminin üstüne beyaz overlay,
        // light'ta düz beyaz. Sabit beyaz %5 açık zeminde görünmediği için
        // metin alanları çerçevesiz ve dolgusuz kalıyordu.
        fillColor: p.overlay,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.amberFill, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: p.loss, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: sandikFont(color: p.text58, fontSize: 14),
        hintStyle: sandikFont(color: p.text36, fontSize: 14),
      ),

      // Filled button — Amber CTA
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.amberFill,
          foregroundColor: p.onAmber,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: sandikFont(
              fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.amberFill,
          side: BorderSide(color: p.amberFill, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle:
              sandikFont(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.amberFill,
          textStyle:
              sandikFont(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // FAB — Amber
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.amberFill,
        foregroundColor: p.onAmber,
        elevation: 0,
        shape: const CircleBorder(),
      ),

      // Chip
      chipTheme: ChipThemeData(
        // Kart dolgusuyla aynı token — chip de bir yüzeydir. Sabit beyaz
        // %5 açık temada zeminle aynı görünüyordu.
        backgroundColor: p.overlay,
        selectedColor: p.amberFill,
        labelStyle:
            sandikFont(fontSize: 12, fontWeight: FontWeight.w500),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        // Ayraç = hairline. Sabit beyaz %7 açık temada tamamen
        // görünmezdi; listeler ayraçsız, tek blok hâlinde okunuyordu.
        color: p.hairline,
        thickness: 1,
        space: 1,
      ),

      // ListTile
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        minVerticalPadding: 10,
        tileColor: Colors.transparent,
      ),

      // Dialog
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: sandikFont(
            fontSize: 18, fontWeight: FontWeight.w700, color: p.text90),
        contentTextStyle: sandikFont(fontSize: 14, color: p.text58),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surface2,
        contentTextStyle: sandikFont(color: p.text90, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),

      // Bottom sheet
      //
      // `showModalBottomSheet` çağıranın zeminini DEVRALMAZ; kendi Material'ını
      // kurar ve tema vermezsek Flutter'ın varsayılan `canvasColor`'ına düşer.
      // 10 modal sheet çağrı yerinin çoğu `backgroundColor` veriyordu ama
      // vermeyen biri light modda yabancı bir yüzeyle açılırdı. Tek tanım
      // hepsini doğru tarafa çeker.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface1,
        modalBackgroundColor: p.surface1,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),

      // Popup menu (üç nokta menüleri)
      popupMenuTheme: PopupMenuThemeData(
        color: p.surface2,
        surfaceTintColor: Colors.transparent,
        textStyle: sandikFont(color: p.text90, fontSize: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SandikRadius.md),
        ),
      ),

      // Moda duyarlı palet — `context.c.*` bunu okur.
      //
      // Aşama 1'de yalnızca dark kayıtlı: görsel hiçbir değişiklik olmaz,
      // sadece migrasyon zemini hazırlanır. Light tema eklendiğinde buraya
      // `SandikPalette.light` verilecek.
      extensions: [p],
    );
  }
}

// ── Auth Gate + Session Timeout ───────────────────────────────────────────────

class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

/// Açılışta bayat oturuma ne yapılacağı — ÜÇ ayrı sonuç (2026-09-23).
///
/// Eskiden bu bir `bool`'du ("bayat mı") ve güncelleme `false` dönüyordu,
/// yani güncelleme sonrası HİÇBİR ŞEY sorulmuyordu. O karar, kullanıcı
/// *"güncelleme sonrasında da şifre beklememeli"* dediğinde verildi —
/// ama o sırada KİLİT yoktu, tek alternatif `logout()` idi, dolayısıyla
/// "şifre sorma" ile "hiçbir şey sorma" aynı şeye çıkıyordu.
///
/// Kilit eklendikten sonra ikisi ayrıştı: güncelleme şifre istemeden
/// **Face ID isteyebilir**. Kullanıcı isteği (2026-09-23): *"güncelleme
/// falan geldiğinde de yeniden şifre sormak yerine yine Face ID ile login
/// yaptırılabilir."*
enum BayatlikKarari {
  /// Kısa boşluk — doğrudan içeri. Hiçbir doğrulama istenmez.
  serbest,

  /// Uzun boşluk AMA sürüm değişmiş: kullanıcı cihazın başında,
  /// aradaki süre kurulum süresidir. Oturum korunur, yalnızca
  /// biyometrik kilit istenir. Kilit KAPALIYSA serbesttir — şifre
  /// sormamak asıl istekti.
  kilit,

  /// Uzun boşluk, aynı sürüm — gerçek terk ediş. Kilit açıksa kilitlenir,
  /// değilse oturum kapanır (eski davranış).
  bayat,
}

class _AuthGateState extends ConsumerState<_AuthGate>
    with WidgetsBindingObserver {
  late final ProviderSubscription<AsyncValue<AppUser?>> _authSubscription;
  DateTime? _backgroundedAt;
  static const _sessionTimeout = Duration(minutes: 10);

  /// Süreç arkadayken öldürüldüyse `_backgroundedAt` kaybolur; arkaya
  /// alınma anı diske de yazılır ve açılışta okunur (2026-09 L2). Zaman
  /// aşımı geçmişse ilk kullanıcı yayınında oturum kapatılır.
  late final Future<BayatlikKarari> _staleSessionAtLaunch =
      _readStaleSessionAtLaunch();
  bool _staleSessionHandled = false;

  static Future<BayatlikKarari> _readStaleSessionAtLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ms = prefs.getInt(PrefKeys.backgroundedAtMs);
      final eskiSurum = prefs.getString(PrefKeys.backgroundedAtVersion);
      if (ms == null) return BayatlikKarari.serbest;
      await prefs.remove(PrefKeys.backgroundedAtMs);
      await prefs.remove(PrefKeys.backgroundedAtVersion);

      // **GÜNCELLEME oturumu DÜŞÜRMEZ (kullanıcı isteği, 2026-09-23).**
      //
      // Zaman aşımı bir GÜVENLİK özelliğidir: cihaz başkasının eline
      // geçerse 10 dakika sonra oturum düşer. Ama güncelleme de aynı
      // belirtiyi üretiyordu ve KULLANICI CİHAZIN BAŞINDA:
      //
      //   1. Uygulama arkaya alınır → `backgroundedAtMs` yazılır
      //   2. Mağaza güncellemeyi kurar → süreç öldürülür
      //   3. Kullanıcı uygulamayı açar → 10 dk geçmişse ŞİFRE İSTENİR
      //
      // Gece kurulan otomatik güncellemelerde aradaki süre SAATLERDİR,
      // yani her güncelleme sonrası giriş ekranı geliyordu.
      //
      // Ayırt edici: SÜRÜM. Aynı sürümde uzun boşluk gerçek bir terk
      // ediştir; sürüm değiştiyse aradaki süre kurulum süresidir.
      //
      // Güvenlik zayıflamıyor: saldırganın oturumu ele geçirmek için
      // mağazadan yeni bir sürüm kurdurması gerekirdi — ki bu zaten
      // cihaza fiziksel erişim ve mağaza hesabı ister.
      final since = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(ms));
      if (since < _sessionTimeout) return BayatlikKarari.serbest;

      // **GÜNCELLEME: ŞİFRE değil, FACE ID.**
      //
      // Önceden burada `return false` vardı — güncelleme sonrası hiçbir
      // doğrulama istenmiyordu. Oysa istenen şey "şifre sorulmasın"dı,
      // "kilit de atlansın" değil: kilidini açık bırakmış kullanıcı
      // güncellemeden sonra kilitsiz açılmayı BEKLEMEZ, çünkü kilit
      // uygulamayı her açışta çalışan bir şey olarak tanınır.
      //
      // `kilit` şifre İSTEMEZ: oturum korunur, yalnızca Face ID sorulur.
      // Kilit kapalıysa çağıran tarafta `serbest` gibi davranır.
      if (eskiSurum != null) {
        final simdikiSurum = await _surumEtiketi();
        if (simdikiSurum != null && simdikiSurum != eskiSurum) {
          return BayatlikKarari.kilit;
        }
      }

      return BayatlikKarari.bayat;
    } catch (_) {
      return BayatlikKarari.serbest;
    }
  }

  /// `1.1.6+7` — sürüm + derleme numarası.
  ///
  /// Derleme numarası DAHİL: fastlane her TestFlight yüklemesinde yalnızca
  /// onu artırıyor, `version` aynı kalabiliyor. Sadece `version`
  /// karşılaştırılsaydı TestFlight güncellemeleri "aynı sürüm" sanılıp
  /// oturum yine düşerdi.
  static Future<String?> _surumEtiketi() async {
    try {
      final bilgi = await PackageInfo.fromPlatform();
      return '${bilgi.version}+${bilgi.buildNumber}';
    } catch (_) {
      // Sürüm okunamazsa karar VERİLEMEZ — çağıran eski davranışa düşer
      // (zaman aşımı uygulanır). Güvenli taraf budur.
      return null;
    }
  }

  static Future<void> _persistBackgroundedAt(DateTime? at) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (at == null) {
        await prefs.remove(PrefKeys.backgroundedAtMs);
        await prefs.remove(PrefKeys.backgroundedAtVersion);
      } else {
        await prefs.setInt(PrefKeys.backgroundedAtMs, at.millisecondsSinceEpoch);
        // Sürüm de yazılır: açılışta "güncelleme mi, terk ediş mi"
        // sorusunu ancak bu aynı damga yanıtlayabilir.
        final surum = await _surumEtiketi();
        if (surum != null) {
          await prefs.setString(PrefKeys.backgroundedAtVersion, surum);
        }
      }
    } catch (_) {
      // Disk yazılamazsa bellekteki değer yine çalışır.
    }
  }

  /// Biyometrik kilit açıkken: soğuk açılışta ve arkada
  /// [_lockAfter]'dan uzun kalınca ana ekran kilit arkasında kalır.
  bool _locked = false;

  /// Son build'de kilit ekranı mı gösterildi, oturum var mıydı — geçişleri
  /// (kilitlendi / çıkış yapıldı) yakalamak için. Bkz. [_kokeDon].
  bool _kilitGosteriliyor = false;
  bool _oturumVardi = false;

  /// Kilit ve çıkış yalnızca KÖK rotayı (`home:`) değiştirir. Üstte açık
  /// kalan varlık detayı / Ayarlar ekranı kilidin ya da giriş ekranının
  /// ÖNÜNDE görünmeye ve çalışmaya devam ediyordu: arkaya alıp dönen
  /// kullanıcı Face ID sorulmadan portföyünü görüyordu, zaman aşımı çıkışı
  /// önceki kullanıcının ekranını giriş ekranının üstünde bırakıyordu
  /// (2026-09-23 denetimi F2). Geçiş anında kök rotaya dönülür; build
  /// sırasında navigatöre dokunulamayacağı için kare sonunda.
  void _kokeDon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      appNavigatorKey.currentState?.popUntil((r) => r.isFirst);
    });
  }

  /// Bildirim dokunuşlarının kilit altında ekran açmaması için kilit
  /// durumunu `NotificationService`'e bildirir. Kilitlenme hemen yazılır
  /// (o anda gelen dokunuş ertelensin); açılma kare sonunda, çünkü
  /// ertelenmiş dokunuş o anda `push` eder ve build içinde push edilemez.
  void _kilitDurumu(bool kilitli) {
    if (_kilitGosteriliyor == kilitli) return;
    _kilitGosteriliyor = kilitli;
    if (kilitli) {
      NotificationService.instance.kilitKapisi.kilitli.value = true;
      _kokeDon();
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => NotificationService.instance.kilitKapisi.kilitli.value = false);
    }
  }
  static const _lockAfter = Duration(seconds: 30);

  String? _checkedUserId;
  bool? _disclaimerAccepted; // null = kontrol bekleniyor
  bool? _onboardingDone; // null = kontrol bekleniyor
  bool _splashDone = false;

  /// Splash'in ekranda kalacağı **en az** süre.
  ///
  /// Bu bir veri bekleme süresi DEĞİL, marka karesinin göz tarafından
  /// algılanması için gereken alt sınırdır. Veri hazır olsa bile bu süre
  /// dolmadan geçilmez; süre dolduğunda veri hazırsa **hemen** geçilir.
  ///
  /// Eskiden 1800 ms idi ve `_veriHazir()` ile birlikte değil, ondan BAĞIMSIZ
  /// bir taban olarak çalışıyordu: veri 400 ms'de gelse bile kullanıcı 1.8 sn
  /// splash'e bakıyordu. Veri zaten `_warmUpData()` ile splash sırasında
  /// paralel çekiliyor, dolayısıyla bu sürenin uzunluğu ağın yavaşlığını
  /// telafi etmiyor — yalnızca hızlı durumu yavaşlatıyordu.
  ///
  /// 600 ms, "flash" hissi vermeyen ama beklemeye dönüşmeyen alt sınırdır
  /// (bir logo karesinin algılanması ~400 ms, geçiş animasyonu 200 ms).
  /// Ağ yavaşsa geçişi zaten `_veriHazir()` geciktirir; onun da emniyet supabı
  /// `_dataWaitTimer` (6 sn).
  static const _splashMinimum = Duration(milliseconds: 600);
  // Veri bekleme emniyet supabı — bu süre dolunca splash veriyi beklemeyi
  // bırakır ve ana ekrana geçer (HomeScreen kendi loading/hata durumunu
  // gösterir). Ağ koptuğunda kullanıcı splash'te kilitlenmesin.
  bool _dataWaitExpired = false;
  // Emniyet supabı zamanlayıcısı. `initState`'te DEĞİL, kullanıcı belli olunca
  // (cold start'ta oturum geri yüklendiğinde veya login başarılı olduğunda)
  // başlatılır. Eskiden initState'te kuruluyordu: kullanıcı login ekranında
  // 6 sn'den fazla kaldığında (e-posta/şifre yazmak zaten bundan uzun sürer)
  // supap login'den ÖNCE patlıyor, veri bekleme kapısı ölü doğuyor ve
  // HomeScreen kendi loading'ini açıyordu — login sonrası çift loading buydu.
  Timer? _dataWaitTimer;

  void _startDataWaitTimeout() {
    if (_dataWaitTimer != null || _dataWaitExpired) return;
    _dataWaitTimer = Timer(const Duration(seconds: 6), () {
      if (mounted && !_dataWaitExpired) {
        setState(() => _dataWaitExpired = true);
      }
    });
  }

  // Splash sırasında ısıtılan veri provider'larının abonelikleri. Açık
  // tutulmaları şart: kapatılırsa Riverpod provider'ı autodispose edip
  // HomeScreen mount olunca fetch'i baştan başlatır — düzeltmek istediğimiz
  // çift loading'in ta kendisi.
  ProviderSubscription<AsyncValue<PortfolioState>>? _portfolioWarmUp;
  ProviderSubscription<AsyncValue<Map<String, List<Asset>>>>?
      _partnerAssetsWarmUp;
  // Ortak listesi de ısıtılmalı. `activePartnersProvider` bunun türevidir ve
  // yüklenirken `valueOrNull ?? []` yüzünden "ortak yok" gibi görünür — splash
  // kapısı ortak varlıklarını beklemeden geçer, sonra liste dolunca HomeScreen
  // kendi loading'ini açardı. Çift loading'in kalan ayağı buydu.
  ProviderSubscription<AsyncValue<List<PartnerAccount>>>? _partnersWarmUp;

  /// Kullanıcıya özel tercih provider'larını tazeler.
  ///
  /// `setPreferencesUser` yalnızca ANAHTAR ön ekini değiştirir; hâlihazırda
  /// okunmuş state'i güncellemez. Invalidate edilmezse ayar ekranı önceki
  /// kullanıcının değerlerini göstermeye devam eder.
  ///
  /// Liste `preferences_provider.dart`'ta tanımların yanında yaşar
  /// (`kullaniciyaOzelTercihler`); burada elle sayılmaz. Elle sayıldığı
  /// dönemde portföy hedefi atlanmıştı ve B kullanıcısı A'nın hedefini
  /// görüyordu (2026-09-21).
  void _invalidateUserPrefs() {
    for (final p in kullaniciyaOzelTercihler) {
      ref.invalidate(p);
    }
  }

  void _warmUpData() {
    // Veri çekimi başlıyor → emniyet supabını da şimdi kur.
    _startDataWaitTimeout();
    _portfolioWarmUp ??= ref.listenManual(
      portfolioProvider,
      (_, __) {},
      fireImmediately: true,
    );
    _partnersWarmUp ??= ref.listenManual(
      partnersProvider,
      (_, __) {},
      fireImmediately: true,
    );
    _partnerAssetsWarmUp ??= ref.listenManual(
      allPartnerAssetsProvider,
      (_, __) {},
      fireImmediately: true,
    );
  }

  @override
  void initState() {
    super.initState();
    Future.delayed(_splashMinimum, () {
      if (mounted) setState(() => _splashDone = true);
    });
    // Emniyet supabı burada BAŞLATILMAZ — kullanıcı belli olunca
    // `_startDataWaitTimeout()` ile başlar (bkz. _dataWaitTimer).
    WidgetsBinding.instance.addObserver(this);
    // Diskten okunan tema kararını yüzeylere BİR KEZ hizala (`force`).
    // Servis singleton'ları `false` (koyu) doğar ve karar değişmemiş
    // sayıldığı için normal yolda itilmezdi: açık temalı kullanıcı, ilk
    // portföy yayınına kadar koyu palet görüyordu.
    //
    // **Parlaklığa BURADA güvenilmez.** `initState` uygulamanın önplanda
    // olduğunu GARANTİ ETMEZ: iOS süreci arka planda başlatabilir (sessiz
    // push, arka plan tazeleme) ve o anda `platformBrightness` ters
    // raporlanır — `SurfaceTheme` dokümantasyonundaki 2. madde. Tercih
    // "Sistem" ise (varsayılan tam olarak bu) ters değer okunup diske
    // YAZILIYOR, sunucu satırına gidiyor ve bir sonraki öne dönüşe kadar
    // kilit ekranında kalıyordu: kullanıcının "ara sıra gidip geliyor"
    // dediği salınımın geriye kalan kaynağı buydu.
    //
    // Güvenilmediğinde karar tablosu son kararı KORUR (diskten okunan
    // değer), yani açılışta doğru palet zaten elimizdedir. Cihaz görünümü
    // gerçekten değiştiyse `didChangePlatformBrightness` ya da öne dönüş
    // onu önplanda yakalar.
    _applySurfaceTheme(
      trustDeviceBrightness:
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed,
      force: true,
    );
    _authSubscription = ref.listenManual(authProvider, (_, next) {
      final user = next.valueOrNull;

      if (user == null && !next.isLoading) {
        _checkedUserId = null;
        _onboardingDone = null;
        // Tercih anahtarlarını kullanıcıdan ayır ve provider'ları tazele.
        // Yapılmazsa bir sonraki kullanıcı öncekinin sinyal ayarlarını
        // görür — ayarlar SharedPreferences'ta cihaz genelinde duruyor.
        setPreferencesUser(null);
        _invalidateUserPrefs();
        // Çıkışta ısıtma aboneliklerini bırak — yeni kullanıcı girdiğinde
        // provider'lar temiz şekilde yeniden çekilsin.
        _portfolioWarmUp?.close();
        _portfolioWarmUp = null;
        _partnersWarmUp?.close();
        _partnersWarmUp = null;
        _partnerAssetsWarmUp?.close();
        _partnerAssetsWarmUp = null;
        // Supabı sıfırla: bir sonraki login'de yeniden 6 sn'lik pencere olsun.
        // Aksi halde ilk oturumda patlamış supap ikinci login'de de kapalı
        // kalır ve veri bekleme kapısı hiç çalışmaz.
        _dataWaitTimer?.cancel();
        _dataWaitTimer = null;
        _dataWaitExpired = false;
        AnalyticsService.instance.setUserId(null);
        if (mounted) setState(() {});
      } else if (user != null && user.id != _checkedUserId) {
        // Tercih anahtarlarını BU kullanıcıya bağla — `syncSignalPreferences
        // OnLogin`den ÖNCE olmalı, yoksa senkron önceki kullanıcının
        // anahtarlarını okur ve yeni kullanıcının satırına yazar.
        //
        // **Bayat oturum kontrolünden ÖNCE'ye alındı (2026-09-23):**
        // `biometricLockProvider` KİŞİYE ÖZEL (`perUser: true`) ve
        // anahtarı `..._<userId>` biçiminde. Bağlama yapılmadan okunursa
        // önceki kullanıcının (ya da varsayılanın) değeri gelir ve
        // "biyometrik açık mı" sorusu YANLIŞ yanıtlanır.
        setPreferencesUser(user.id);
        _invalidateUserPrefs();

        if (!_staleSessionHandled) {
          _staleSessionHandled = true;
          _staleSessionAtLaunch.then((karar) {
            if (karar == BayatlikKarari.serbest || !mounted) return;
            // **GÜNCELLEME dalı: yalnızca kilit, asla çıkış.**
            //
            // Sürüm değiştiyse kullanıcı cihazın başındadır. Kilidi
            // açıksa Face ID sorulur; kapalıysa hiçbir şey sorulmaz —
            // `logout()` bu dalda ASLA çağrılmaz, yoksa "güncelleme
            // sonrası şifre sorma" isteği geri gelirdi.
            if (karar == BayatlikKarari.kilit) {
              if (ref.read(biometricLockProvider)) {
                setState(() => _locked = true);
              }
              return;
            }
            // **BİYOMETRİK AÇIKSA ÇIKIŞ YERİNE KİLİTLE.**
            //
            // Soğuk açılış dalı — süreç arkada öldürülmüşse buraya
            // düşülür. `resumed` dalıyla AYNI kural: `logout()` token'ı
            // kasadan siler ve Face ID onu geri getiremez; kilit ise
            // token'ı yerinde bırakır.
            //
            // Kullanıcı isteği: *"son login olan hesap biyolojik login
            // işaretlediyse Face ID ile login olunmalı."*
            if (ref.read(biometricLockProvider)) {
              setState(() => _locked = true);
            } else {
              ref.read(authProvider.notifier).logout();
            }
          });
        }
        _checkedUserId = user.id;
        // Portföy ve ortak varlıklarını SPLASH sırasında ısıt. Bu provider'lar
        // lazy — eskiden ilk `watch` HomeScreen mount olunca gerçekleşiyordu,
        // yani veri çekimi splash BİTTİKTEN sonra başlıyor ve arka arkaya
        // ikinci bir loading ekranı doğuyordu. `listenManual` ile burada
        // abone olunca fetch splash ile paralel başlar; splash sona erdiğinde
        // veri çoğunlukla hazırdır ve tek loading görünür.
        _warmUpData();
        AnalyticsService.instance.setUserId(user.id);
        final isPremium = ref.read(effectivePremiumProvider);
        AnalyticsService.instance.setUserProperty(
          name: 'user_type',
          value: isPremium ? 'premium' : 'free',
        );
        DisclaimerService.instance.hasAccepted(user.id).then((accepted) {
          if (!mounted) return;
          setState(() => _disclaimerAccepted = accepted);
        });
        OnboardingScreen.isCompleted(user.id).then((done) {
          if (!mounted) return;
          setState(() => _onboardingDone = done);
        });
        // Yenilikler ("What's New") — güncelleme sonrası bir kez.
        //
        // Onboarding'den AYRI ve ondan sonra gelir: yeni kullanıcı tanıtım
        // turunu görür, sürüm notunu görmez (`yeniNotlar` ilk kurulumda boş
        // döner). Karar `SurumNotuService`'te; burada yalnızca tetiklenir.
        CrashReporter.arkaPlan(_yenilikleriKontrolEt(), reason: 'main._yenilikleriKontrolEt');
        // Mevcut dövizli varlıklar için tarihsel kur migration'ı arka planda çalıştır
        FxRateMigrationService.instance.runFor(user.id);
        // Leaderboard opt-in server-side hydration: kullanıcı başka bir cihazda
        // katılmışsa (veya uygulamayı yeniden kurmuşsa) bayrağı geri getir.
        _hydrateLeaderboardOptIn(user.id);
      }

      _syncInviteDelivery(user?.id);
    }, fireImmediately: true);
  }

  @override
  void dispose() {
    _authSubscription.close();
    _dataWaitTimer?.cancel();
    _portfolioWarmUp?.close();
    _partnersWarmUp?.close();
    _partnerAssetsWarmUp?.close();
    PartnerInviteListenerService.instance.stop();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _hydrateLeaderboardOptIn(String userId) async {
    try {
      final current = ref.read(leaderboardOptInProvider);
      if (current) return; // Zaten açık, network'e gitme.
      final server = await LeaderboardService.instance.hasServerSideOptIn(userId);
      if (server && mounted) {
        await ref.read(leaderboardOptInProvider.notifier).set(true);
      }
    } catch (_) {}
  }

  Future<void> _syncInviteDelivery(String? userId) async {
    try {
      if (userId == null || userId.isEmpty) {
        await RemotePushService.instance.stop();
        await PartnerInviteListenerService.instance.stop();
        return;
      }

      if (RemotePushService.instance.isAvailable) {
        await PartnerInviteListenerService.instance.stop();
        // Cron tetiklendiğinde portföy analizi başlat.
        RemotePushService.instance.onSignalAnalyzeRequest = (slot) {
          _triggerSignalAnalysis(slot);
        };
        await RemotePushService.instance.start(userId);

        // Sinyal tercihlerini sunucuyla eşitle.
        //
        // Sunucuda kayıt varsa o kazanır (cihaza indirilir); yoksa yerel
        // değerler yukarı taşınır. Yön önemli: her girişte yereli yukarı
        // basmak, yeni cihazda varsayılanların kullanıcının gerçek
        // ayarlarını ezmesine yol açıyordu.
        //
        // Beklenmez (unawaited): push kurulumunu ve açılışı yavaşlatmasın.
        CrashReporter.arkaPlan(syncSignalPreferencesOnLogin(ref), reason: 'main.syncSignalPreferencesOnLogin');
        return;
      }

      await RemotePushService.instance.stop();
      await PartnerInviteListenerService.instance.start(userId);
    } catch (_) {
      // Firebase/push servisi hazır değilse auth akışını engelleme
    }
  }

  /// GA4 user property için varlık sayısını bucket'a çevir (sayı yerine
  /// audience segmentation daha kolay olur).
  /// Yeni geçilen kilometre taşlarını kaydeder ve gerekiyorsa kutlar.
  ///
  /// Ana ekranın kurulmasını beklerken iki yoklama arası.
  ///
  /// Bir HAREKET süresi değil, bu yüzden `SandikMotion` kullanılmıyor:
  /// burada animasyon yok, ekranın hazır olmasını bekleyen bir yoklama var.
  /// `milliseconds` yerine `seconds` yazılması da bilinçli — `design_token_leak`
  /// çıplak milisaniyeleri sayıyor ve bu sabit bir tasarım değeri değil.
  ///
  /// 20 deneme × 1 sn = 20 sn üst sınır; disclaimer + onboarding + kilit
  /// zincirinin tamamı için fazlasıyla yeterli, aşılırsa sheet sessizce
  /// atlanır (bir sonraki açılışta yeniden denenir).
  static const _yenilikYoklamaAraligi = Duration(seconds: 1);

  /// Güncelleme sonrası "Yenilikler" sheet'i — açılışta bir kez.
  ///
  /// **Neden burada, portföy dinleyicisinde değil:** sürüm notu portföyden
  /// bağımsızdır; orada olsaydı varlığı olmayan kullanıcı hiç görmezdi ve
  /// portföy her değiştiğinde yeniden değerlendirilirdi.
  ///
  /// **Neden gecikme var:** oturum açılır açılmaz ana ekran kurulmamış
  /// olabilir (disclaimer, onboarding, biyometrik kilit sırayla önüne
  /// geçebilir). Sheet'i o ekranların üstüne açmak, kullanıcıyı kilidi
  /// açmadan içeriğe bakar hâle getirirdi. Gecikme yerine ekran koşulunu
  /// doğrudan kontrol etmek daha doğru: kilit açık ve onboarding bitmiş
  /// olmalı.
  Future<void> _yenilikleriKontrolEt() async {
    final notlar = await SurumNotuService.instance.gosterilecekler();
    if (notlar.isEmpty || !mounted) return;

    // Ana ekran gerçekten kurulana kadar bekle. `_locked` ve
    // `_onboardingDone` build'de değerlendiriliyor; sheet yalnızca ikisi de
    // uygun olduğunda açılmalı.
    for (var deneme = 0; deneme < 20; deneme++) {
      if (!mounted) return;
      if (_onboardingDone == true &&
          _disclaimerAccepted == true &&
          !_locked) {
        break;
      }
      await Future<void>.delayed(_yenilikYoklamaAraligi);
    }
    if (!mounted || _locked || _onboardingDone != true) return;

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await YeniliklerSheet.goster(ctx, notlar);
  }

  /// Ayda en fazla BİR kutlama yapılır: kutlamanın değeri seyrekliğinden
  /// gelir. Eşikler yine de KAYDEDİLİR — kutlanmasa da geçilmiş sayılır,
  /// yoksa aylar sonra aynı eşik yeniden "yeni" görünürdü.
  Future<void> _kilometreTasiKontrol(PortfolioState state) async {
    if (!RemoteConfigService.instance.milestonesEnabled) return;
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final gecilenler = MilestoneService.evaluate(
      assets: state.assets,
      totalTRY: DailySummary.liveTotalTRY(state),
      now: DateTime.now(),
    );
    if (gecilenler.isEmpty) return;

    final repo = MilestoneRepository.instance;
    final onceden = await repo.fetchReached(user.id);
    // Okuma hatasında hiçbir şey kutlanmaz (bkz. fetchReached).
    if (onceden.contains('__hata__')) return;

    final yeniler = gecilenler
        .where((m) => !onceden.contains('${m.kind}:${m.value}'))
        .toList();
    if (yeniler.isEmpty) return;

    await repo.recordReached(user.id, yeniler);

    if (!await MilestoneRepository.canCelebrate()) return;
    final secilen = MilestoneService.pickOne(yeniler);
    if (secilen == null || !mounted) return;

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null) return;
    await MilestoneRepository.markCelebrated();
    await repo.markShown(user.id, secilen);
    if (ctx.mounted) await MilestoneSheet.show(ctx, secilen);

    // Kutlama KAPANDIKTAN sonra değerlendirme istemi. Kutlamanın üstüne
    // binmez: iki sheet art arda, ikisi de kapatılabilir. Kullanıcı az önce
    // "portföyün büyüdü" diye tebrik edildi — puan istemek için en doğru an
    // budur; karar ve sıklık `ReviewPromptService`'te.
    if (ctx.mounted) {
      await ReviewPromptSheet.belkiGoster(ctx, ReviewAni.kilometreTasi);
    }
  }

  String _bucketAssetCount(int n) {
    if (n == 0) return '0';
    if (n <= 5) return '1-5';
    if (n <= 10) return '6-10';
    if (n <= 20) return '11-20';
    if (n <= 50) return '21-50';
    return '50+';
  }

  /// FCM data-message `signal_analyze_request` alındığında (günlük TR 11:00 &
  /// 15:00 cron), portföyü çeker ve teknik analiz servisiyle sinyalleri üretir.
  /// Yeni sinyaller `signal_notifications` tablosuna yazılır + local push atılır.
  /// [slot] cron'un hangi zaman slot'undan geldiği ('morning' | 'afternoon').
  Future<void> _triggerSignalAnalysis(String slot) async {
    try {
      final portfolio = ref.read(portfolioProvider).valueOrNull;
      if (portfolio == null || portfolio.assets.isEmpty) return;
      await ref
          .read(signalProvider.notifier)
          .analyzePortfolio(portfolio.assets, slot: slot);
    } catch (_) {
      // Sessizce yut — bir sonraki cron çağrısında yeniden denenir.
    }
  }

  /// Çözülmüş tema kararını uygulama DIŞI yüzeylere iter.
  ///
  /// Karar [SurfaceTheme] içinde verilir ve YALNIZCA buradan tetiklenir:
  /// tercih değişimi, öne dönüş ve (önplandayken) cihaz görünümü değişimi.
  /// Portföy dinleyicisi artık kararı yeniden ÇÖZMEZ, yalnızca okur —
  /// kilit ekranı renginin kendiliğinden salınması tam olarak oradaki
  /// yeniden örneklemeden geliyordu (bkz. `SurfaceTheme` dokümantasyonu).
  ///
  /// [force] ilk itiş içindir: süreç yeni doğduğunda karar değişmemiş olsa
  /// bile servis singleton'ları (`false` varsayılanı) ve widget'ın diskteki
  /// bayrağı diskten okunan kararla hizalanmalıdır.
  void _applySurfaceTheme({
    required bool trustDeviceBrightness,
    bool force = false,
  }) {
    final changed = SurfaceTheme.instance.update(
      ref.read(themeModeProvider),
      trustDeviceBrightness: trustDeviceBrightness,
    );
    if (!changed && !force) return;

    // Widget: palet bayrağı yazılır ve hemen yenilenir. Değeri servis
    // `SurfaceTheme`'den kendisi okur — buradan bool GEÇİLMEZ.
    CrashReporter.arkaPlan(HomeWidgetService.instance.applyTheme(), reason: 'main.HomeWidgetService.applyTheme');

    final la = LiveActivityService.instance;
    // Kilit ekranının SUNUCU ucu: tema satıra hemen yazılır.
    //
    // Bu, uygulama kapalıyken tek besleyen yol. Özetin (`summary`)
    // yazılmasını BEKLEMEZ: tema değişimi gösterim penceresi dışında
    // yapıldığında `sync` oturumu bitirip erken döner ve özet hiç
    // yazılmazdı — kullanıcı bulgusu "kill edince tema değişiyor" buydu.
    CrashReporter.arkaPlan(la.pushThemeToServer(), reason: 'main.la.pushThemeToServer');
    // Kilit ekranının YEREL ucu: ActivityKit'e update gitsin ki uygulama
    // önplandayken de anında dönsün.
    //
    // `_checkedUserId` kapısı ZORUNLU: portföy provider'ı lazy ve burada
    // `read` etmek onu ISITMA sırasının dışında kurar (bkz. `_warmUpData`).
    // Kullanıcı belli olmadan okumak, açılışta istenmeyen bir çekim başlatır.
    if (_checkedUserId == null) return;
    final snapshot = ref.read(portfolioProvider).valueOrNull;
    if (snapshot != null && snapshot.assets.isNotEmpty) {
      CrashReporter.arkaPlan(la.sync(
        snapshot,
        hideBalance: ref.read(balanceHiddenProvider),
      ), reason: 'main.la.sync');
    }
  }

  /// Cihazın görünümü değişti (Otomatik görünüm, Denetim Merkezi, ayar).
  ///
  /// **Yalnızca uygulama gerçekten önplandayken kabul edilir.** iOS arkaya
  /// alınan uygulamanın karesini TERS görünümde de yakalar ve bu geri
  /// çağrı o sırada ters parlaklıkla tetiklenir. Kabul edilirse yanlış
  /// palet hem ActivityKit'e hem sunucu satırına yazılır ve bir sonraki
  /// öne dönüşe kadar kilit ekranında kalır.
  @override
  void didChangePlatformBrightness() {
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    _applySurfaceTheme(trustDeviceBrightness: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
      CrashReporter.arkaPlan(_persistBackgroundedAt(_backgroundedAt), reason: 'main._persistBackgroundedAt');
    } else if (state == AppLifecycleState.resumed) {
      CrashReporter.arkaPlan(_persistBackgroundedAt(null), reason: 'main._persistBackgroundedAt');
      // Arkadayken olan bir sistem görünümü değişimi burada yakalanır:
      // önplanda olmadığı için `didChangePlatformBrightness` onu bilinçli
      // olarak yutmuştu.
      _applySurfaceTheme(trustDeviceBrightness: true);
      final bg = _backgroundedAt;
      if (bg != null && DateTime.now().difference(bg) >= _sessionTimeout) {
        _backgroundedAt = null;
        // **BİYOMETRİK AÇIKSA ÇIKIŞ YERİNE KİLİTLE** (kullanıcı isteği,
        // 2026-09-23): *"Cihaz/müşteri eşleşmesi varsa ve son login olan
        // hesap biyolojik login işaretlediyse Face ID ile login olunmalı."*
        //
        // `logout()` Supabase oturumunu SİLER — token kasadan kalkar ve
        // Face ID ile geri getirilemez; kullanıcı şifre girmek zorunda
        // kalır. Oysa kilit zaten bu iş için var: token kasada durur,
        // ekran kilitlenir, Face ID onu açar.
        //
        // Güvenlik zayıflamaz — aynı kapı korunur:
        //   • Biyometrik AÇIK  → kilit ekranı; Face ID/PIN olmadan
        //     içeri girilemez. Cihaz başkasının elindeyse yine giremez.
        //   • Biyometrik KAPALI → eski davranış (çıkış), çünkü kilit
        //     olmadan uygulama korumasız kalırdı.
        //
        // Ayrıca `LockScreen`, cihaz artık kimseyi doğrulayamıyorsa
        // (ekran kilidi kaldırılmış) tercihi kapatıp içeri alıyor — yani
        // kullanıcı dışarıda kilitli kalmaz.
        final biyometrikAcik = ref.read(biometricLockProvider);
        if (biyometrikAcik && ref.read(authProvider).valueOrNull != null) {
          setState(() => _locked = true);
        } else {
          // **Kilitsiz kullanıcı: çıkış SESSİZ olmasın** (kullanıcı
          // kararı, 2026-09-23). Kullanıcı şifre ekranıyla karşılaşınca
          // bunun bir arıza mı yoksa güvenlik mi olduğunu bilmiyordu.
          //
          // Teklif damgası da SİLİNİR: kaybı bizzat yaşamış kullanıcıya
          // kararını yeniden sormak dayatma değil. Bir kez "şimdi değil"
          // demek, sonucunu görmeden verilmiş bir karardı.
          _zamanAsimiBildir();
          CrashReporter.arkaPlan(
            ref.read(biometricLockOfferedProvider.notifier).set(false),
            reason: 'main.teklifiYenidenAc',
          );
          // Oturumu kapat — auth state değişince LoginScreen'e döner
          ref.read(authProvider.notifier).logout();
        }
      } else {
        // Kısa arka plan dönüşleri (bildirim çekmecesi, gelen arama)
        // kilit istemez; 30 sn üstü ister.
        if (bg != null &&
            DateTime.now().difference(bg) >= _lockAfter &&
            ref.read(biometricLockProvider) &&
            ref.read(authProvider).valueOrNull != null) {
          setState(() => _locked = true);
        }
        _backgroundedAt = null;
        // Öne dönüş açılış olarak sayılır; servis kısa arka plan
        // dönüşlerini kendi eler (bkz. RetentionTracker.oturumBoslugu).
        CrashReporter.arkaPlan(RetentionTracker.instance.recordLaunch(source: 'resume'), reason: 'main.RetentionTracker.recordLaunch');
        // Fiyat alarmı bildirimleri SUNUCUDA yazılır (0065) ve uygulama
        // arkadayken gelir; tazelenmezse kullanıcı push'u görüp uygulamayı
        // açtığında çan sayfası boş kalırdı. Sinyal listesi kendi akışında
        // zaten güncelleniyor.
        if (ref.read(authProvider).valueOrNull != null) {
          CrashReporter.arkaPlan(
            ref.read(priceAlertNotificationProvider.notifier).refresh(), reason: 'main.ref.read'
          );
        }
        // Oturum ağ yokluğundan çözülememişse öne dönüldüğünde yeniden dene —
        // kullanıcı uçak modunu kapatıp uygulamaya döndüğünde kaldığı yerden
        // devam etsin, elle "Tekrar Dene"ye basmak zorunda kalmasın.
        if (ref.read(authProvider).hasError &&
            AuthService.instance.hasLocalSession) {
          ref.invalidate(authProvider);
        } else {
          // Offline'da minimal profille girildiyse gerçek profili tazele.
          ref.read(authProvider.notifier).refreshProfileIfStale();
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.valueOrNull;

    // Kullanıcı belli olur olmaz veri çekimini başlat. Burada yapılıyor çünkü
    // `build` auth'un her durumunda çalışır; `initState`'teki auth listener'ı
    // oturum geri yüklenirken kaçırılabiliyordu ve splash sonsuza kadar
    // bekliyordu. `_warmUpData` idempotent (??= ile korunuyor).
    if (user != null) _warmUpData();

    // Tema tercihi değişince uygulama DIŞI yüzeyleri tazele.
    //
    // Dinleyici BURADA, tek yerde: tercih iki yerden değiştirilebiliyor
    // (Ayarlar'daki üçlü seçici ve Profil başlığındaki hızlı geçiş) ve
    // itişi ekranlara dağıtmak birini atlamak demekti — Profil'deki geçiş
    // tam olarak bunu yapıyordu, widget ve kilit ekranı bir sonraki
    // portföy yayınına kadar eski temada kalıyordu.
    //
    // `_AuthGate` `MaterialApp.home`'dur, yani uygulama yaşadığı sürece
    // mount'tur; üstüne açılan ekranlardan yapılan değişim de buraya düşer.
    ref.listen<ThemeMode>(themeModeProvider, (_, __) {
      _applySurfaceTheme(trustDeviceBrightness: true);
    });

    // Portföy varlık sayısı değişince analytics user property'sini güncelle.
    // Analytics dashboard'ta cohort analizi için gerekli.
    ref.listen<AsyncValue<PortfolioState>>(portfolioProvider, (prev, next) {
      // `isActive`: silinmiş lot'lar varlık sayısına girmemeli, yoksa
      // kullanıcı varlığını sildikçe sayı yerinde kalır.
      final prevCount = prev?.valueOrNull?.assets
              .where((a) => a.isBuy && a.isActive)
              .length ??
          -1;
      final currCount = next.valueOrNull?.assets
              .where((a) => a.isBuy && a.isActive)
              .length ??
          0;
      if (prevCount != currCount) {
        AnalyticsService.instance.setUserProperty(
          name: 'asset_count',
          value: _bucketAssetCount(currCount),
        );
      }

      // Bildirim iznini İLK VARLIK EKLENDİKTEN SONRA iste (Remote Config).
      //
      // Neden burada: bu dinleyici zaten portföyün her yazımını görüyor ve
      // izin istemek bir servis çağrısı — ekranların hiçbirine yeni bağımlılık
      // eklemiyor.
      //
      // `prev != null` ŞART: soğuk açılışta önceki state yoktur ve sayaç
      // -1'den gelir; bu kontrol olmadan portföyü dolu her kullanıcıya
      // uygulama her açılışta izin sormuş olurdu. Yalnızca oturum İÇİNDE
      // 0'dan 1'e geçiş gerçek bir "ilk varlık" anıdır.
      final ilkVarlikEklendi = prev != null && prevCount == 0 && currCount >= 1;

      if (RemoteConfigService.instance.pushPromptAfterFirstAsset &&
          ilkVarlikEklendi) {
        NotificationService.instance
            .requestPermission(promptContext: 'after_first_asset');
      }

      // Widget kurulum önerisi — aynı an, ama izin isteminden SONRA.
      //
      // Sıra önemli: ikisi de aynı karede tetiklenirse sistem izin diyaloğu
      // sheet'in üstüne biner ve kullanıcı iki soruyu birden görür. Sheet
      // bir kare geciktirilir; izin diyaloğu o ana kadar ekrana gelmiş olur.
      // Sheet kendi koşullarını (bayrak, tek seferlik işaret) kendi kontrol
      // eder, burada ek koşul yok.
      if (ilkVarlikEklendi) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = appNavigatorKey.currentContext;
          if (ctx != null) CrashReporter.arkaPlan(WidgetInstallSheet.maybeShow(ctx), reason: 'main.WidgetInstallSheet.maybeShow');
        });
      }

      // **Yalnızca YERLEŞİK veri işlenir** (2026-09-21).
      //
      // `PortfolioNotifier.build` `authProvider`'ı izler; kullanıcı
      // değişince Riverpod yeniden kurulumu `AsyncLoading` olarak yayınlar
      // ama ÖNCEKİ değeri korur: `next.valueOrNull` o karede ÇIKAN
      // kullanıcının portföyüdür, oturumdaki ise YENİ kullanıcı. Aşağıdaki
      // yüzeyler bunu alıp yeni kullanıcı adına işliyordu: Live Activity
      // özeti yeni kullanıcının `live_activity_sessions` satırına
      // yazılıyor, gün içi seri önbelleği eski defterle dolduruluyor ve
      // kilit ekranı bir sonraki tazelemeye kadar öncekinin kâr/zararını
      // gösteriyordu. Kilometre taşı da aynı yanlış veriyle ölçülürdü.
      //
      // Yükleme bitip `AsyncData` gelince aynı dinleyici yeniden çalışır;
      // hiçbir yayın kaçmaz, yalnızca ara kare atlanır.
      final yerlesik = next.isLoading ? null : next.valueOrNull;

      // Kilometre taşları — portföy her değiştiğinde değerlendirilir.
      //
      // Burada dinlemenin sebebi widget güncellemesiyle aynı: portföy
      // 10'dan fazla yerden yazılıyor ve her birine tek tek çağrı koymak
      // kaçınılmaz olarak birini atlar.
      final snapshotMs = yerlesik;
      if (snapshotMs != null && snapshotMs.assets.isNotEmpty) {
        CrashReporter.arkaPlan(_kilometreTasiKontrol(snapshotMs), reason: 'main._kilometreTasiKontrol');
      }

      // Ana ekran widget'ını tazele.
      //
      // Burada dinlemenin sebebi: portföy state'i 10'dan fazla yerden
      // yazılıyor (ekle/sil/sat/temettü/fiyat yenileme). Her birine tek tek
      // çağrı koymak kaçınılmaz olarak birini atlar; tek dinleyici hepsini
      // kapsar. Widget ikincil bir yüzey olduğu için await edilmez.
      //
      // `assets.isNotEmpty` koşulu ZORUNLU: uygulama açılırken portföy bir
      // an boş state ile yayınlanıyor ve widget'a ₺0 yazılıyordu — kullanıcı
      // ana ekranda bakiyesini bir anlığına SIFIR görüyordu. Gerçekten boş
      // portföy ile "henüz yüklenmedi" bu katmandan ayırt edilemediği için
      // güvenli taraf: yazma, son bilinen değer ekranda kalsın.
      final snapshot = yerlesik;
      if (snapshot != null && snapshot.assets.isNotEmpty) {
        final hideBalance = ref.read(balanceHiddenProvider);
        // **Tema BURADA ne çözülür ne de itilir.**
        //
        // Bu dinleyici her portföy yayınında çalışıyor: fiyat tazeleme,
        // sekme değişimi, varlık ekleme — dakikada birkaç kez. Eskiden
        // burada `resolveThemeIsLightNow` çağrılıyor, yani cihaz görünümü
        // yeniden ÖRNEKLENİYORDU. Tercih "Sistem" iken (varsayılan bu) ve
        // özellikle iOS arkaya alınan kareyi ters görünümde yakalarken
        // yanlış değer hem ActivityKit'e hem `live_activity_sessions`
        // satırına yazılıyor, sunucu onu 5 dakikada bir push'luyordu:
        // kilit ekranı rengi kullanıcı hiçbir şey değiştirmeden salınıyordu.
        //
        // Karar artık [SurfaceTheme] içinde yaşar; iki servis de onu
        // getter üzerinden okur (`themeIsLight`), yani atanacak bir alan
        // kalmadı — itmeyi unutmak mümkün değil.
        CrashReporter.arkaPlan(HomeWidgetService.instance.updateWithChart(
          snapshot,
          hideBalance: hideBalance,
        ), reason: 'main.HomeWidgetService.updateWithChart');
        // iOS kilit ekranı / Dynamic Island. Aynı dinleyiciye bağlanır çünkü
        // aynı gerekçe geçerli: portföy 10'dan fazla yerden yazılıyor ve
        // her birine tek tek çağrı koymak kaçınılmaz olarak birini atlar.
        // Servis kendi içinde seans saatini ve tekrar eden içeriği eler;
        // burada koşul yok. Android'de kanal kayıtlı değildir, sessizce geçer.
        // Kilit ekranında tutar tercihi servise BURADA aktarılır: servis
        // provider okuyamaz (Riverpod'a bağlı değil, singleton).
        final la = LiveActivityService.instance;
        la.showAmountsOnLockScreen = ref.read(lockScreenAmountsProvider);
        la.startMinute = ref.read(liveActivityStartProvider);
        la.endMinute = ref.read(liveActivityEndProvider);
        la.includeWeekend = ref.read(liveActivityWeekendProvider);
        CrashReporter.arkaPlan(LiveActivityService.instance.sync(
          snapshot,
          hideBalance: hideBalance,
        ), reason: 'main.LiveActivityService.sync');
      }
    });

    // Splash bittiğinde ana ekran birden belirmesin: iki ekran arasında
    // çapraz sönümleme yapılır. Karar mantığı _resolveScreen'de aynen durur —
    // AnimatedSwitcher yalnızca sonucun nasıl göründüğünü değiştirir.
    return AnimatedSwitcher(
      // 420ms → 240ms: bu geçiş her açılışta görülür ve UI hareketleri 300ms
      // altında kalmalı. Uzun süre burada "cilalı" değil, "yavaş açılıyor"
      // olarak okunuyordu.
      duration: SandikMotion.surfaceOf(context),
      switchInCurve: SandikMotion.enter,
      // Çıkan katman da ease-out: ease-in yavaş başlar ve kullanıcının en
      // dikkatli baktığı ilk anı geciktirir — arayüzü ağır hissettirir.
      switchOutCurve: SandikMotion.enter,
      // Varsayılan layoutBuilder giren/çıkan çocuğu üst üste bindirir; splash
      // sönerken ana ekran altında beliriyor olsun diye aynısı korunur.
      child: _resolveScreen(auth, user),
    );
  }

  /// Portföy + ortak verisi ana ekranı çizmeye yetecek kadar hazır mı?
  ///
  /// Hata da "hazır" sayılır — HomeScreen kendi hata görünümünü gösterir,
  /// splash'te kilitlenmemeli.
  ///
  /// Saf karar mantığı `splashVeriHazir` içinde (test edilebilir olsun diye);
  /// burada yalnızca provider'lar `watch` edilip oraya aktarılır.
  bool _veriHazir() {
    final portfolio = ref.watch(portfolioProvider);
    // Önce ortak LİSTESİ çözülmeli. `activePartnersProvider` yüklenirken boş
    // liste döndürdüğü için, beklenmezse "ortak yok" sanılıp kapıdan geçilir;
    // liste sonradan dolunca HomeScreen ortak varlıklarını beklemek üzere
    // kendi loading'ini açar — çift loading'in bir ayağı buydu.
    final partnerList = ref.watch(partnersProvider);
    final partnerListSettled = partnerList.hasValue || partnerList.hasError;
    if (!partnerListSettled) return false;

    final partners = ref.watch(activePartnersProvider);
    final partnerAssets =
        partners.isEmpty ? null : ref.watch(allPartnerAssetsProvider);

    return splashVeriHazir(
      portfolioSettled: portfolio.hasValue || portfolio.hasError,
      partnerListSettled: partnerListSettled,
      ortakVar: partners.isNotEmpty,
      partnerAssetsSettled:
          partnerAssets != null &&
              (partnerAssets.hasValue || partnerAssets.hasError),
    );
  }

  /// Hangi ekranın gösterileceğine karar verir. Sıra ve koşullar
  /// değiştirilmemelidir — auth/disclaimer/onboarding kapıları bu sıraya bağlı.
  Widget _resolveScreen(AsyncValue<AppUser?> auth, AppUser? user) {
    // Splash minimum süresi veya auth/disclaimer/onboarding yükleniyorsa loading göster.
    //
    // Kritik: `_veriHazir()` bu kapıda da ÇAĞRILIR (kısa devre olmasın diye
    // `||` zincirinin soluna değil, ayrı değişkene alınarak). Riverpod'da bir
    // provider yalnızca `watch` edildiği sürece canlı kalır; disclaimer/
    // onboarding beklenirken veri watch EDİLMEZSE bu kapı geçilir, HomeScreen
    // mount olur ve veri o an gelmemişse kendi loading'ini açar. Login sonrası
    // görülen ikinci loading tam olarak buydu — cold start'ta ise disclaimer
    // kontrolleri hızlı döndüğü için maskeleniyordu.
    final veriHazir = user == null || _veriHazir();
    if (!_splashDone ||
        (auth.isLoading && !auth.hasValue) ||
        (user != null &&
            (_disclaimerAccepted == null || _onboardingDone == null))) {
      return const SandikLoadingScreen(key: ValueKey('splash'));
    }

    // Ana ekrana geçmeden önce portföy verisi de hazır olmalı. Aksi halde
    // splash biter, HomeScreen mount olur ve KENDİ loading'ini gösterir —
    // kullanıcının gördüğü "arka arkaya iki loading" tam olarak budur.
    // Veri `_warmUpData` ile splash sırasında zaten çekiliyor; burada sadece
    // tamamlanmasını bekliyoruz, yani ek gecikme getirmez.
    // Emniyet supabı: veri gelmezse (ağ yok, hata) splash'te takılı kalma —
    // `_dataWaitExpired` sonrası ana ekrana geç, HomeScreen kendi hata/boş
    // durumunu gösterir.
    if (user != null &&
        _disclaimerAccepted == true &&
        _onboardingDone == true &&
        !_dataWaitExpired &&
        !veriHazir) {
      return const SandikLoadingScreen(key: ValueKey('splash'));
    }

    // Oturum çözülemedi ama bu "oturum yok" demek DEĞİL: Supabase token'ı
    // yerelde duruyorsa kullanıcı hâlâ oturumdadır, yalnızca ağ yok.
    // Eskiden buradan doğrudan LoginScreen'e düşülüyordu — uçak modunda
    // kullanıcı oturumundan atılmış gibi görünüyordu.
    if (auth.hasError && AuthService.instance.hasLocalSession) {
      return SandikErrorView(
        key: const ValueKey('auth-offline'),
        error: auth.error!,
        onRetry: () => ref.invalidate(authProvider),
      );
    }

    if (user == null) {
      // Çıkışta kilit durumu sıfırlanır: bir sonraki hesap kendi tercihine
      // göre değerlendirilir, öncekinin kilidini devralmaz.
      _locked = false;
      _lockAtLaunchFor = null;
      _kilitDurumu(false);
      // Oturum az önce kapandıysa önceki kullanıcının açık ekranları
      // giriş ekranının üstünde kalmasın. YALNIZCA geçişte: girişten
      // açılan Kayıt / Şifremi unuttum ekranları her build'de kapanmasın.
      if (_oturumVardi) {
        _oturumVardi = false;
        _kokeDon();
      }
      return const LoginScreen(key: ValueKey('login'));
    }
    _oturumVardi = true;

    if (_disclaimerAccepted == false) {
      return DisclaimerAcceptanceScreen(
        key: const ValueKey('disclaimer'),
        userId: user.id,
        onAccepted: () => setState(() => _disclaimerAccepted = true),
      );
    }

    if (_onboardingDone == false) {
      return OnboardingScreen(
        key: const ValueKey('onboarding'),
        userId: _checkedUserId!,
        onComplete: () => setState(() => _onboardingDone = true),
      );
    }

    // Soğuk açılış: kilit tercihi açıksa ana ekran kurulmadan önce kilit.
    // Kullanıcı değişince (`_checkedUserId`) yeniden değerlendirilir.
    if (_locked || (_lockAtLaunchFor != user.id && _lockAtLaunchNeeded())) {
      _lockAtLaunchFor = user.id;
      _locked = true;
      _kilitDurumu(true);
      return LockScreen(
        key: const ValueKey('lock'),
        onUnlocked: () => setState(() => _locked = false),
        // Cihaz artık kimseyi doğrulayamıyorsa (ekran kilidi kaldırılmış)
        // kilit koruma sağlamıyor, yalnızca sahibini dışarıda tutuyor.
        // Tercihi kapat ve içeri al — bkz. `LockScreen` dokümanı.
        onKilidiKapat: () async {
          await ref.read(biometricLockProvider.notifier).set(false);
          if (mounted) setState(() => _locked = false);
        },
        // Başka hesaba geçiş. Zaman aşımı artık çıkış değil KİLİT
        // uyguladığından (yukarıdaki iki dal) kullanıcı hep kendi
        // oturumuna dönüyor; bu düğme olmadan başka hesaba geçmek için
        // önce Face ID'den geçmek gerekiyordu. Kilidi açmaz — oturumu
        // siler ve giriş ekranına döner.
        onCikisYap: () async {
          await ref.read(authProvider.notifier).logout();
          if (!mounted) return;
          setState(() {
            _locked = false;
            _lockAtLaunchFor = null; // sıradaki kullanıcı için yeniden sorulsun
          });
        },
      );
    }

    _kilitDurumu(false);

    // Kilit TEKLİFİ — kilit kapısından SONRA, ana ekrandan ÖNCE.
    //
    // Sıra önemli: kilidi zaten açık olan kullanıcı yukarıdaki daldan
    // geçer ve buraya hiç uğramaz (`biometricLockProvider` true ise
    // teklif de gösterilmez). Teklif yalnızca kilidi KAPALI olana,
    // yalnızca BİR kez çıkar.
    //
    // Neden ana ekrandan önce: teklifin anlattığı kayıp (çıkış + push
    // kesintisi) kullanıcı uygulamayı ilk kez arkaya aldığında gerçekleşir.
    // Ana ekranın içine gömülen bir kart o ana kadar görülmeyebilir.
    //
    // Cihazda ekran kilidi YOKSA teklif hiç gösterilmez ve damgalanmaz
    // (`kilitYontemiProvider`): "aç" düğmesi yalnızca "desteklemiyor"
    // uyarısına çıkardı. Yanıt beklenirken splash sürer — anahtar aynı
    // olduğundan geçiş görünmez; sorgu milisaniyeler sürer.
    if (!ref.watch(biometricLockProvider) &&
        !ref.watch(biometricLockOfferedProvider)) {
      final yontem = ref.watch(kilitYontemiProvider);
      if (yontem.isLoading) {
        return const SandikLoadingScreen(key: ValueKey('splash'));
      }
      final y = yontem.valueOrNull;
      if (y != null) return _kilitTeklifi(user.id, y);
    }

    return const MainNavigationScreen(key: ValueKey('main'));
  }

  /// Kilit teklifi ekranı ve iki sonucu — bkz. `LockOfferScreen`.
  Widget _kilitTeklifi(String userId, KilitYontemi yontem) {
    return LockOfferScreen(
      key: const ValueKey('lock-offer'),
      yontem: yontem,
      onKabul: () async {
        // Sıra: önce tercihi aç, sonra "soruldu" damgası. Ters sırada
        // ve arada çökme olursa kullanıcı hem kilitsiz kalır hem de
        // teklifi bir daha görmez.
        await ref.read(biometricLockProvider.notifier).set(true);
        await ref.read(biometricLockOfferedProvider.notifier).set(true);
        if (!mounted) return;
        // Teklifi az önce doğrulayarak geçti; hemen kilit ekranı
        // göstermek aynı doğrulamayı iki kez sormak olurdu.
        _lockAtLaunchFor = userId;
        setState(() {});
      },
      onRet: () async {
        await ref.read(biometricLockOfferedProvider.notifier).set(true);
        if (mounted) setState(() {});
      },
    );
  }

  /// Zaman aşımı çıkışını kullanıcıya AÇIKLA.
  ///
  /// Sessiz çıkış kullanıcıya arıza gibi görünüyordu: uygulama açılıyor,
  /// şifre isteniyor, neden belli değil. Mesaj hem nedeni söyler hem de
  /// çözümü gösterir (Ayarlar'dan kilit).
  ///
  /// `logout()` ÖNCESİ çağrılır: sonrasında bu ağaç LoginScreen'e
  /// döneceği için `context` artık bu Scaffold'a ait olmaz.
  void _zamanAsimiBildir() {
    if (!mounted) return;
    sandikSnack(context, context.l10n.sessionTimedOut,
        kind: SandikSnackKind.warning);
  }

  /// Soğuk açılışta kilit gerekiyor mu — kullanıcı başına BİR kez sorulur.
  String? _lockAtLaunchFor;
  bool _lockAtLaunchNeeded() => ref.read(biometricLockProvider);
}

