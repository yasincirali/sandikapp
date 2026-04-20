import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'providers/auth_provider.dart';
import 'screens/home_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/login_screen.dart';
import 'theme/sandik.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('tr_TR');
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
      surfaceContainerLow:    Sandik.background,
      surfaceContainer:       Sandik.surface1,
      surfaceContainerHigh:   Sandik.surface2,
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

    // ── Typography (Plus Jakarta Sans + Inter + JetBrains Mono) ─────────────
    final baseText = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    TextStyle pjs(double size, FontWeight weight, double ls) =>
        GoogleFonts.plusJakartaSans(
            fontSize: size, fontWeight: weight, letterSpacing: ls, color: Sandik.text90);

    final textTheme = baseText.copyWith(
      // Display — büyük sayılar (Plus Jakarta Sans)
      displayLarge:  pjs(52, FontWeight.w700, -0.03 * 52).copyWith(color: Sandik.gold),
      displayMedium: pjs(40, FontWeight.w700, -0.03 * 40).copyWith(color: Sandik.gold),
      displaySmall:  pjs(32, FontWeight.w700, -0.02 * 32).copyWith(color: Sandik.gold),
      // Headline — başlıklar (Plus Jakarta Sans)
      headlineLarge:  pjs(24, FontWeight.w600, -0.01 * 24),
      headlineMedium: pjs(20, FontWeight.w600, -0.01 * 20),
      headlineSmall:  pjs(18, FontWeight.w600, -0.01 * 18),
      // Title — navigasyon ve kart başlıkları
      titleLarge:  GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w600, color: Sandik.text90),
      titleMedium: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Sandik.text90),
      titleSmall:  GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: Sandik.text90),
      // Body — gövde metin (Inter)
      bodyLarge:   GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, color: Sandik.text90),
      bodyMedium:  GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w400, color: Sandik.text90),
      bodySmall:   GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w400, color: Sandik.text58),
      // Label — etiket
      labelLarge:  GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.08 * 11, color: Sandik.text90),
      labelMedium: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w500, letterSpacing: 0.08 * 10, color: Sandik.text58),
      labelSmall:  GoogleFonts.inter(fontSize: 9,  fontWeight: FontWeight.w500, letterSpacing: 0.08 * 9,  color: Sandik.text36),
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
        titleTextStyle: GoogleFonts.plusJakartaSans(
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: GoogleFonts.inter(color: Sandik.text58, fontSize: 14),
        hintStyle: GoogleFonts.inter(color: Sandik.text36, fontSize: 14),
      ),

      // Filled button — Amber CTA
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Sandik.amber,
          foregroundColor: Sandik.dark,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14, letterSpacing: 0.2),
        ),
      ),

      // Outlined button
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Sandik.amber,
          side: const BorderSide(color: Sandik.amber, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),

      // Text button
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Sandik.amber,
          textStyle: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 14),
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
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500),
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
        titleTextStyle: GoogleFonts.plusJakartaSans(
          fontSize: 18, fontWeight: FontWeight.w700, color: Sandik.text90),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14, color: Sandik.text58),
      ),

      // SnackBar
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Sandik.surface2,
        contentTextStyle: GoogleFonts.inter(color: Sandik.text90, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

// ── Auth Gate ─────────────────────────────────────────────────────────────────

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final user = auth.valueOrNull;
    return user != null ? const MainNavigationScreen() : const LoginScreen();
  }
}
