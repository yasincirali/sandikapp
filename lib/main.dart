import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'models/user_model.dart';
import 'providers/auth_provider.dart';
import 'screens/disclaimer_acceptance_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'services/disclaimer_service.dart';
import 'services/notification_service.dart';
import 'services/partner_invite_listener_service.dart';
import 'services/remote_push_service.dart';
import 'theme/sandik.dart';

final appNavigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  try {
    await Firebase.initializeApp();
    await RemotePushService.instance.init();
  } catch (_) {
    // Firebase config dosyalari eklenene kadar uygulama remote push olmadan calisabilir.
  }
  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );
  await NotificationService.instance.init(navigatorKey: appNavigatorKey);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light, // koyu zemin = açık ikonlar
    statusBarBrightness: Brightness.dark,
  ));
  runApp(const ProviderScope(child: SandikApp()));
}

class SandikApp extends StatelessWidget {
  const SandikApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'sandık',
      debugShowCheckedModeBanner: false,
      navigatorKey: appNavigatorKey,
      theme: _buildTheme(),
      themeMode: ThemeMode.dark, // sandık dark-mode öncelikli
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

  AppUser? _previousUser;

  // null = henüz kontrol edilmedi, false = onaylanmamış, true = onaylandı
  bool? _disclaimerChecked;
  String? _checkedUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authSubscription = ref.listenManual(authProvider, (_, next) {
      final user = next.valueOrNull;

      if (_previousUser != null && user == null && !next.isLoading) {
        // Oturum kapandı — sıfırla ve login ekranına git
        _disclaimerChecked = null;
        _checkedUserId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          appNavigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        });
      } else if (user != null && user.id != _checkedUserId) {
        // Yeni kullanıcı oturum açtı — disclaimer kontrol et
        _disclaimerChecked = null;
        _checkedUserId = user.id;
        debugPrint('[DisclaimerCheck] Sorgu başlatılıyor: ${user.id}');
        DisclaimerService.instance.hasAccepted(user.id).then((accepted) {
          debugPrint('[DisclaimerCheck] Sonuç: $accepted');
          if (!mounted) return;
          if (!accepted) {
            // Onaylanmamış — disclaimer ekranına yönlendir
            appNavigatorKey.currentState?.pushAndRemoveUntil(
              MaterialPageRoute(
                builder: (_) => DisclaimerAcceptanceScreen(
                  userId: user.id,
                  onAccepted: () {
                    setState(() => _disclaimerChecked = true);
                    appNavigatorKey.currentState?.pushAndRemoveUntil(
                      MaterialPageRoute(
                          builder: (_) => const MainNavigationScreen()),
                      (_) => false,
                    );
                  },
                ),
              ),
              (_) => false,
            );
          } else {
            setState(() => _disclaimerChecked = true);
          }
        });
      }

      _previousUser = user;
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

  Future<void> _syncInviteDelivery(String? userId) async {
    try {
      if (userId == null || userId.isEmpty) {
        await RemotePushService.instance.stop();
        await PartnerInviteListenerService.instance.stop();
        return;
      }

      if (RemotePushService.instance.isAvailable) {
        await PartnerInviteListenerService.instance.stop();
        await RemotePushService.instance.start(userId);
        return;
      }

      await RemotePushService.instance.stop();
      await PartnerInviteListenerService.instance.start(userId);
    } catch (_) {
      // Firebase/push servisi hazır değilse auth akışını engelleme
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
    if (auth.isLoading && !auth.hasValue) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final user = auth.valueOrNull;
    if (user == null) return const LoginScreen();

    // Disclaimer kontrol edilirken spinner göster
    if (_disclaimerChecked == null) {
      return const Scaffold(
        backgroundColor: Colors.transparent,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return const MainNavigationScreen();
  }
}
