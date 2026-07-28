import 'dart:async';
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
import 'services/remote_config_service.dart';
import 'services/db_logger.dart';
import 'services/disclaimer_service.dart';
import 'services/fx_rate_migration_service.dart';
import 'services/notification_service.dart';
import 'services/leaderboard_service.dart';
import 'services/partner_invite_listener_service.dart';
import 'services/remote_push_service.dart';
import 'theme/sandik.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  // Crashlytics + tüm async hatalar tek `runZonedGuarded` içinde toplanır
  await runZonedGuarded<Future<void>>(() async {
    WidgetsFlutterBinding.ensureInitialized();
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

      await RemotePushService.instance.init();
      await AnalyticsService.instance.init();
      await RemoteConfigService.instance.init();
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
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
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
    // UH1 fix: Light theme implementasyonu yok — dark'a sabitliyoruz.
    // themeModeProvider kalsa da kullanılmıyor; ileride light theme
    // eklendiğinde geri bağlanabilir.
    return MaterialApp(
      title: 'sandık',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: _buildTheme(),
      darkTheme: _buildTheme(),
      themeMode: ThemeMode.dark,
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

  ThemeData _buildTheme() {
    // ── ColorScheme (Sandık / Toka Spec) ────────────────────────────────────
    const cs = ColorScheme(
      brightness: Brightness.dark,
      // Primary — Amber (CTA, aktif, logo ikon)
      primary: Sandik.amber,
      onPrimary: Sandik.dark,
      primaryContainer: Sandik.surface2,
      onPrimaryContainer: Sandik.gold,
      // Secondary — Altın (display sayılar)
      secondary: Sandik.gold,
      onSecondary: Sandik.dark,
      secondaryContainer: Color(0xFF1A3D2E),
      onSecondaryContainer: Sandik.gold,
      // Tertiary — Kazanç yeşili
      tertiary: Sandik.gain,
      onTertiary: Sandik.dark,
      tertiaryContainer: Color(0xFF1E3B1C),
      onTertiaryContainer: Sandik.gain,
      // Error — Kayıp kırmızısı
      error: Sandik.loss,
      onError: Sandik.dark,
      errorContainer: Color(0xFF4A1A14),
      onErrorContainer: Sandik.loss,
      // Surfaces
      surface: Sandik.surface1,
      onSurface: Sandik.text90,
      surfaceContainerLowest: Sandik.background,
      surfaceContainerLow: Sandik.background,
      surfaceContainer: Sandik.surface1,
      surfaceContainerHigh: Sandik.surface2,
      surfaceContainerHighest: Color(0xFF1A3D2E),
      onSurfaceVariant: Sandik.text58,
      // Outline
      outline: Sandik.brown,
      outlineVariant: Color(0xFF112E28),
      // Inverse
      inverseSurface: Colors.white,
      onInverseSurface: Sandik.dark,
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
            color: Sandik.text90);

    final textTheme = baseText.copyWith(
      // Display — büyük sayılar
      displayLarge:
          dm(52, FontWeight.w700, -0.03 * 52).copyWith(color: Sandik.gold),
      displayMedium:
          dm(40, FontWeight.w700, -0.03 * 40).copyWith(color: Sandik.gold),
      displaySmall:
          dm(32, FontWeight.w700, -0.02 * 32).copyWith(color: Sandik.gold),
      // Headline — başlıklar
      headlineLarge: dm(24, FontWeight.w700, -0.01 * 24),
      headlineMedium: dm(20, FontWeight.w700, -0.01 * 20),
      headlineSmall: dm(18, FontWeight.w600, -0.01 * 18),
      // Title — navigasyon ve kart başlıkları
      titleLarge: GoogleFonts.dmSans(
          fontSize: 16, fontWeight: FontWeight.w600, color: Sandik.text90),
      titleMedium: GoogleFonts.dmSans(
          fontSize: 14, fontWeight: FontWeight.w500, color: Sandik.text90),
      titleSmall: GoogleFonts.dmSans(
          fontSize: 12, fontWeight: FontWeight.w500, color: Sandik.text90),
      // Body — gövde metin
      bodyLarge: GoogleFonts.dmSans(
          fontSize: 15, fontWeight: FontWeight.w500, color: Sandik.text90),
      bodyMedium: GoogleFonts.dmSans(
          fontSize: 13, fontWeight: FontWeight.w400, color: Sandik.text90),
      bodySmall: GoogleFonts.dmSans(
          fontSize: 11, fontWeight: FontWeight.w400, color: Sandik.text58),
      // Label — etiket
      labelLarge: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.06 * 11,
          color: Sandik.text90),
      labelMedium: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06 * 10,
          color: Sandik.text58),
      labelSmall: GoogleFonts.dmSans(
          fontSize: 9,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.06 * 9,
          color: Sandik.text36),
    );

    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Sandik.background,
      textTheme: textTheme,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Sandik.surface1,
        foregroundColor: Sandik.text90,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.dmSans(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.02 * 22,
          color: Sandik.text90,
        ),
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),

      // Card
      cardTheme: CardThemeData(
        elevation: 0,
        color: Sandik.surface1,
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
          borderSide: const BorderSide(color: Sandik.amber, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Sandik.loss, width: 1),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: GoogleFonts.dmSans(color: Sandik.text58, fontSize: 14),
        hintStyle: GoogleFonts.dmSans(color: Sandik.text36, fontSize: 14),
      ),

      // Filled button — Amber CTA
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Sandik.amber,
          foregroundColor: Sandik.dark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.dmSans(
              fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Sandik.amber,
          side: const BorderSide(color: Sandik.amber, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Sandik.amber,
          textStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // FAB — Amber
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Sandik.amber,
        foregroundColor: Sandik.dark,
        elevation: 0,
        shape: CircleBorder(),
      ),

      // Chip
      chipTheme: ChipThemeData(
        backgroundColor: Colors.white.withOpacity(0.05),
        selectedColor: Sandik.amber,
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
        backgroundColor: Sandik.surface1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle: GoogleFonts.dmSans(
            fontSize: 18, fontWeight: FontWeight.w700, color: Sandik.text90),
        contentTextStyle: GoogleFonts.dmSans(fontSize: 14, color: Sandik.text58),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Sandik.surface2,
        contentTextStyle: GoogleFonts.dmSans(color: Sandik.text90, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
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

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) setState(() => _splashDone = true);
    });
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = ref.listenManual(authProvider, (_, next) {
      final user = next.valueOrNull;

      if (user == null && !next.isLoading) {
        _checkedUserId = null;
        _onboardingDone = null;
        AnalyticsService.instance.setUserId(null);
        if (mounted) setState(() {});
      } else if (user != null && user.id != _checkedUserId) {
        _checkedUserId = user.id;
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
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final user = auth.valueOrNull;

    // Portföy varlık sayısı değişince analytics user property'sini güncelle.
    // Analytics dashboard'ta cohort analizi için gerekli.
    ref.listen<AsyncValue<PortfolioState>>(portfolioProvider, (prev, next) {
      final prevCount = prev?.valueOrNull?.assets
              .where((a) => a.isBuy)
              .length ??
          -1;
      final currCount =
          next.valueOrNull?.assets.where((a) => a.isBuy).length ?? 0;
      if (prevCount != currCount) {
        AnalyticsService.instance.setUserProperty(
          name: 'asset_count',
          value: _bucketAssetCount(currCount),
        );
      }
    });

    // Splash minimum süresi veya auth/disclaimer/onboarding yükleniyorsa loading göster
    if (!_splashDone ||
        (auth.isLoading && !auth.hasValue) ||
        (user != null &&
            (_disclaimerAccepted == null || _onboardingDone == null))) {
      return const SandikLoadingScreen();
    }

    if (user == null) return const LoginScreen();

    if (_disclaimerAccepted == false) {
      return DisclaimerAcceptanceScreen(
        userId: user.id,
        onAccepted: () => setState(() => _disclaimerAccepted = true),
      );
    }

    if (_onboardingDone == false) {
      return OnboardingScreen(
        userId: _checkedUserId!,
        onComplete: () => setState(() => _onboardingDone = true),
      );
    }

    return const MainNavigationScreen();
  }
}

