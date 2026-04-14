import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: PortfoyApp()));
}

class PortfoyApp extends StatelessWidget {
  const PortfoyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Portföy',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    // Renk paleti — koyu indigo/mor tabanlı
    const seedColor = Color(0xFF4F46E5);

    final cs = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    ).copyWith(
      // Daha zengin vurgular
      primary: isDark ? const Color(0xFF818CF8) : const Color(0xFF4F46E5),
      secondary: isDark ? const Color(0xFF34D399) : const Color(0xFF059669),
    );

    return ThemeData(
      colorScheme: cs,
      useMaterial3: true,
      brightness: brightness,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: cs.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness:
              isDark ? Brightness.light : Brightness.dark,
        ),
      ),

      // Card
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: cs.outlineVariant.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        color: cs.surface,
        margin: EdgeInsets.zero,
      ),

      // Input dekorasyon
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.4)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.outline.withValues(alpha: 0.3)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: cs.error),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        labelStyle: TextStyle(color: cs.onSurfaceVariant, fontSize: 14),
        hintStyle: TextStyle(
            color: cs.onSurfaceVariant.withValues(alpha: 0.6), fontSize: 14),
      ),

      // Elevated / Filled buttons
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12)),
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(
              fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        minVerticalPadding: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0)),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: cs.outlineVariant.withValues(alpha: 0.35),
        thickness: 1,
        space: 1,
      ),

      // FAB
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
      ),

      // Chip
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        labelStyle:
            const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      ),

      // Typography
      textTheme: TextTheme(
        displayLarge: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -1.5,
            color: cs.onSurface),
        headlineLarge: TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: cs.onSurface),
        headlineMedium: TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
            color: cs.onSurface),
        headlineSmall: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            color: cs.onSurface),
        titleLarge: TextStyle(
            fontWeight: FontWeight.w700, color: cs.onSurface),
        titleMedium: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: cs.onSurface),
        titleSmall: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: cs.onSurface),
        bodyLarge: TextStyle(color: cs.onSurface),
        bodyMedium: TextStyle(color: cs.onSurface),
        bodySmall: TextStyle(color: cs.onSurfaceVariant),
        labelLarge: TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
            color: cs.onSurface),
        labelSmall: TextStyle(
            letterSpacing: 0.6,
            color: cs.onSurfaceVariant),
      ),
    );
  }
}
