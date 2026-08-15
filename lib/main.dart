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
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'models/asset.dart';
import 'models/user_model.dart';
import 'providers/auth_provider.dart';
import 'providers/portfolio_provider.dart';
import 'providers/preferences_provider.dart';
import 'providers/signal_provider.dart';
import 'screens/disclaimer_acceptance_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/analytics_service.dart';
import 'services/auth_service.dart';
import 'services/remote_config_service.dart';
import 'services/db_logger.dart';
import 'services/disclaimer_service.dart';
import 'services/fx_rate_migration_service.dart';
import 'services/home_widget_service.dart';
import 'services/live_activity_service.dart';
import 'services/notification_service.dart';
import 'services/leaderboard_service.dart';
import 'services/partner_invite_listener_service.dart';
import 'services/remote_push_service.dart';
import 'theme/sandik.dart';
import 'widgets/sandik_error_view.dart';

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
  ]) {
    try {
      await step.$2();
    } catch (e, st) {
      if (kDebugMode) debugPrint('${step.$1} init failed: $e');
      FirebaseCrashlytics.instance
          .recordError(e, st, reason: '${step.$1} deferred init');
    }
  }
}

void main() async {
  // Crashlytics + tüm async hatalar tek `runZonedGuarded` içinde toplanır
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // DM Sans `assets/fonts/` altında gömülü (bkz. pubspec.yaml `fonts:`).
    // Bu bayrak olmadan google_fonts fontu her cihazda bir kez
    // fonts.gstatic.com'dan indirmeye çalışır: ilk açılış ağa bağımlı olur,
    // offline'da sistem fontuna düşer. Gömülü aile adı ("DM Sans")
    // google_fonts'un aradığıyla aynı olduğu için paket indirme yerine
    // asset'i bulur.
    GoogleFonts.config.allowRuntimeFetching = false;

    await initializeDateFormatting('tr_TR');
    // SharedPreferences warm-up — _BoolPrefNotifier'lar ilk render'da
    // senkron okuyabilsin, "yarışa katıl" prompt'u flash olmasın.
    await initPreferencesCache();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    try {
      await Firebase.initializeApp();

      // Crashlytics — debug build'de gönderim kapalı (gürültü olmasın)
      await FirebaseCrashlytics.instance
          .setCrashlyticsCollectionEnabled(!kDebugMode);

      // Senkron Flutter framework hataları
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        final sanitized = DbLogger.sanitize(details.exceptionAsString());
        FirebaseCrashlytics.instance.recordError(
          sanitized, details.stack, fatal: true,
          reason: details.context?.toDescription(),
        );
      };

      // Native platform hataları (engine seviyesi)
      PlatformDispatcher.instance.onError = (error, stack) {
        final sanitized = DbLogger.sanitize(error.toString());
        FirebaseCrashlytics.instance
            .recordError(sanitized, stack, fatal: true);
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
      unawaited(_initDeferredServices());
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
    );
    await NotificationService.instance.init(navigatorKey: appNavigatorKey);
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
    // Zone-level: yakalanmayan async hataları
    try {
      FirebaseCrashlytics.instance.recordError(
        DbLogger.sanitize(error.toString()), stack, fatal: true);
    } catch (_) {
      // Crashlytics hazır değilse swallow
    }
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

    return MaterialApp(
      title: 'sandık',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: _buildTheme(SandikPalette.light, Brightness.light),
      darkTheme: _buildTheme(SandikPalette.dark, Brightness.dark),
      themeMode: themeMode,
      // Türkçe locale — showDatePicker, showTimePicker vb. tüm Material
      // widget'ları için dd/MM/yyyy formatı, Türkçe ay/gün adları, virgüllü
      // ondalık ayırıcı. İngilizce yedek locale olarak kalır.
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr', 'TR'), Locale('en', 'US')],
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
    final baseText = GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme);

    TextStyle dm(double size, FontWeight weight, double ls) =>
        GoogleFonts.dmSans(
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
      titleLarge: GoogleFonts.dmSans(
          fontSize: 16, fontWeight: FontWeight.w600, color: p.text90),
      titleMedium: GoogleFonts.dmSans(
          fontSize: 14, fontWeight: FontWeight.w500, color: p.text90),
      titleSmall: GoogleFonts.dmSans(
          fontSize: 12, fontWeight: FontWeight.w500, color: p.text90),
      // Body — gövde metin
      bodyLarge: GoogleFonts.dmSans(
          fontSize: 15, fontWeight: FontWeight.w500, color: p.text90),
      bodyMedium: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w400, color: p.text90),
      bodySmall: GoogleFonts.dmSans(
          fontSize: 11, fontWeight: FontWeight.w400, color: p.text58),
      // Label — etiket
      labelLarge: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.06 * 11,
          color: p.text90),
      labelMedium: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06 * 10,
          color: p.text58),
      labelSmall: GoogleFonts.dmSans(
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
          textStyle: GoogleFonts.dmSans(color: p.text90, fontSize: 15),
        ),
      ),

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: p.surface1,
        foregroundColor: p.text90,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSans(
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
          side: BorderSide(color: Colors.white.withOpacity(0.05), width: 1),
        ),
        margin: EdgeInsets.zero,
      ),

      // Input
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withOpacity(0.05),
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
        labelStyle: GoogleFonts.dmSans(color: p.text58, fontSize: 14),
        hintStyle: GoogleFonts.dmSans(color: p.text36, fontSize: 14),
      ),

      // Filled button — Amber CTA
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.amberFill,
          foregroundColor: p.onAmber,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.dmSans(
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
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: p.amberFill,
          textStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
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
        backgroundColor: Colors.white.withOpacity(0.05),
        selectedColor: p.amberFill,
        labelStyle:
            GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w500),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: Colors.white.withOpacity(0.07),
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
        titleTextStyle: GoogleFonts.dmSans(
            fontSize: 18, fontWeight: FontWeight.w700, color: p.text90),
        contentTextStyle: GoogleFonts.dmSans(fontSize: 14, color: p.text58),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: p.surface2,
        contentTextStyle: GoogleFonts.dmSans(color: p.text90, fontSize: 13),
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
        textStyle: GoogleFonts.dmSans(color: p.text90, fontSize: 14),
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

class _AuthGateState extends ConsumerState<_AuthGate>
    with WidgetsBindingObserver {
  late final ProviderSubscription<AsyncValue<AppUser?>> _authSubscription;
  DateTime? _backgroundedAt;
  static const _sessionTimeout = Duration(minutes: 10);

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
  void _invalidateUserPrefs() {
    ref.invalidate(signalThresholdProvider);
    ref.invalidate(indicatorPrefsProvider);
    ref.invalidate(signalScheduleProvider);
    ref.invalidate(signalNeutralPushProvider);
    ref.invalidate(signalNotificationsProvider);
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
        setPreferencesUser(user.id);
        _invalidateUserPrefs();
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
        unawaited(syncSignalPreferencesOnLogin(ref));
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _backgroundedAt = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final bg = _backgroundedAt;
      if (bg != null && DateTime.now().difference(bg) >= _sessionTimeout) {
        _backgroundedAt = null;
        // Oturumu kapat — auth state değişince LoginScreen'e döner
        ref.read(authProvider.notifier).logout();
      } else {
        _backgroundedAt = null;
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
      final snapshot = next.valueOrNull;
      if (snapshot != null && snapshot.assets.isNotEmpty) {
        final hideBalance = ref.read(balanceHiddenProvider);
        unawaited(HomeWidgetService.instance.updateWithChart(
          snapshot,
          hideBalance: hideBalance,
        ));
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
        unawaited(LiveActivityService.instance.sync(
          snapshot,
          hideBalance: hideBalance,
        ));
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

    if (user == null) return const LoginScreen(key: ValueKey('login'));

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

    return const MainNavigationScreen(key: ValueKey('main'));
  }
}

