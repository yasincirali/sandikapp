import 'dart:io' show Platform;
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

/// Platforma uygun sayfa geçişi.
///
/// iOS'ta [CupertinoPageRoute] döner: sağdan-sola kayma animasyonu ve
/// kenardan içeri swipe-to-go-back jesti (HIG'in beklediği davranış).
/// Android'de [MaterialPageRoute] ile alttan-yukarı geçiş korunur.
///
/// `MaterialPageRoute(builder: ...)` yerine bunu kullan:
/// ```dart
/// Navigator.push(context, adaptiveRoute(builder: (_) => const FooScreen()));
/// ```
PageRoute<T> adaptiveRoute<T>({
  required WidgetBuilder builder,
  RouteSettings? settings,
  bool fullscreenDialog = false,
}) {
  // Platform.isIOS yalnızca mobilde güvenli; web'de bu dosya kullanılmıyor.
  if (Platform.isIOS) {
    return CupertinoPageRoute<T>(
      builder: builder,
      settings: settings,
      fullscreenDialog: fullscreenDialog,
    );
  }
  return MaterialPageRoute<T>(
    builder: builder,
    settings: settings,
    fullscreenDialog: fullscreenDialog,
  );
}

/// Tipografi erişimi — `main.dart` içindeki merkezi [TextTheme]'e kısa yol.
///
/// Hardcoded `GoogleFonts.dmSans(fontSize: 13, ...)` yerine bunu kullan:
/// ```dart
/// Text('Toplam', style: context.t.bodyMedium)
/// Text('₺1.240', style: context.t.numMedium.copyWith(color: Sandik.gain))
/// ```
///
/// Neden: hardcoded `fontSize` iOS Dynamic Type ölçeklemesini yok sayar ve
/// her çağrıda font çözümlemesi yapar. Merkezi tema her ikisini de çözer.
extension SandikTypography on BuildContext {
  /// Merkezi metin ölçeği. Tanım: `main.dart` → `_buildTheme()`.
  ///
  /// Marka eşlemesi (mevcut kullanıma göre kalibre edildi):
  /// - `headlineLarge` 24 / `headlineMedium` 20 / `headlineSmall` 18 — başlık
  /// - `titleLarge` 16 / `titleMedium` 14 / `titleSmall` 12 — kart başlığı
  /// - `bodyLarge` 15 / `bodyMedium` 13 / `bodySmall` 11 — gövde
  /// - `labelLarge` 11 / `labelMedium` 10 / `labelSmall` 9 — etiket (letterSpacing'li)
  /// - `displaySmall` 32 / `displayMedium` 40 — büyük para tutarları (gold)
  TextTheme get t => Theme.of(this).textTheme;
}

/// Finansal sayı stilleri — tabular figür hizalaması gerektiren yerler için.
///
/// Para tutarları ve yüzdeler listede alt alta geldiğinde rakamlar aynı
/// genişlikte olmalı; aksi halde kolonlar oynak görünür.
extension SandikNumericText on TextTheme {
  /// Liste satırı tutarı (13pt, w700) — [FontFeature.tabularFigures] ile.
  TextStyle get numSmall => (bodyMedium ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Kart içi tutar (16pt, w800).
  TextStyle get numMedium => (titleLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Hero/özet tutarı (24pt, w800).
  TextStyle get numLarge => (headlineLarge ?? const TextStyle()).copyWith(
        fontWeight: FontWeight.w800,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
}

/// Sandık (ex-Toka) marka renk paleti ve logo painter
class Sandik {
  // ── Core palette ────────────────────────────────────────────────────────────
  static const Color dark      = Color(0xFF112E28); // Seviye 1 — Kart yüzeyi
  static const Color background = Color(0xFF0A1E15); // Seviye 0 — Ana arka plan
  static const Color surface1  = Color(0xFF112E28); // Seviye 1
  static const Color surface2  = Color(0xFF1A3D2E); // Seviye 2 — Hero kart / elevated
  static const Color brown     = Color(0xFF2D7A60); // "Orman" — yardımcı yeşil
  
  static const Color amber     = Color(0xFFF5A623); // CTA, aktif durum, logo ikon
  static const Color gold      = Color(0xFFF5C842); // Display sayılar, logo wordmark
  static const Color bronze    = Color(0xFFF5A623); // (Legacy mapping to amber)
  static const Color adacayi   = Color(0xFFE8EDE5); // Açık zemin (light mode)

  // ── Finansal anlamsal ───────────────────────────────────────────────────────
  static const Color gain      = Color(0xFF2D9E6C); // Pozitif delta (Kazanç)
  static const Color loss      = Color(0xFFE8503A); // Negatif delta (Kayıp)

  // ── Sabit opaklıklar (dark zemin üzeri metin) ──────────────────────────────
  static const Color text90    = Color(0xE1FFFFFF); // 0.88 opak (Ana başlık)
  static const Color text58    = Color(0x8CFFFFFF); // 0.55 (İkincil etiket)
  static const Color text36    = Color(0x59FFFFFF); // 0.35 (Üçüncül yardımcı)
  static const Color text20    = Color(0x33FFFFFF); // 0.20 (Devre dışı)

  // ── Liquid Glass helpers ────────────────────────────────────────────────────

  /// Blur + translucent overlay — temel glass katmanı.
  static BoxDecoration glassDecoration({
    double radius = 18,
    Color tint = Colors.white,
    double tintOpacity = 0.07,
    Color borderColor = Colors.white,
    double borderOpacity = 0.14,
    double borderWidth = 1.0,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      color: tint.withValues(alpha: tintOpacity),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor.withValues(alpha: borderOpacity),
        width: borderWidth,
      ),
      boxShadow: shadows ??
          [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 24,
              spreadRadius: -4,
              offset: const Offset(0, 8),
            ),
          ],
    );
  }

  /// BackdropFilter + glass container. Clip gerektirir (ClipRRect ile kullan).
  static Widget glassBox({
    required Widget child,
    double radius = 18,
    double blur = 14,
    Color tint = Colors.white,
    double tintOpacity = 0.07,
    Color borderColor = Colors.white,
    double borderOpacity = 0.14,
    EdgeInsetsGeometry? padding,
    List<BoxShadow>? shadows,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          padding: padding,
          decoration: glassDecoration(
            radius: radius,
            tint: tint,
            tintOpacity: tintOpacity,
            borderColor: borderColor,
            borderOpacity: borderOpacity,
            shadows: shadows,
          ),
          child: child,
        ),
      ),
    );
  }

  static InputDecoration inputDecoration(
    String hint, {
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? labelText,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      labelText: labelText,
      errorText: errorText,
      hintStyle: const TextStyle(color: text36, fontSize: 14),
      labelStyle: const TextStyle(color: text36, fontSize: 14),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.black.withValues(alpha: 0.1),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: amber, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: loss, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: loss, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }
}

/// Sandık logo widget'ı — SVG tabanlı, kare aspect ratio (launcher icon uyumlu)
/// [withBackground] ve [color] parametreleri API uyumluluğu için korunmuştur;
/// SVG kendi gradient/renk tanımlarını içerdiğinden [color] uygulanmaz.
class SandikLogo extends StatelessWidget {
  final double size;
  final Color? color;
  final bool withBackground;

  const SandikLogo({
    super.key,
    this.size = 32,
    this.color,
    this.withBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final svg = SvgPicture.asset(
      'assets/images/sandik_logo.svg',
      width: size,
      height: size,
      fit: BoxFit.contain,
    );

    if (!withBackground) return svg;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Sandik.surface2,
        borderRadius: BorderRadius.circular(size * 0.22),
      ),
      child: svg,
    );
  }
}

/// Uygulama launcher ikonunu önizlemek için — tam kare, rounded corner
class SandikAppIcon extends StatelessWidget {
  final double size;
  const SandikAppIcon({super.key, this.size = 64});

  @override
  Widget build(BuildContext context) {
    return SandikLogo(size: size, withBackground: false);
  }
}

/// Tüm ekranlarda kullanılan standart logout butonu.
/// Tasarım dili: kırmızı/loss tonu, 36×36 rounded icon box — ProfileScreen'deki
/// _ActionIcon ile aynı görsel dil.
class SandikLogoutButton extends StatelessWidget {
  final VoidCallback onPressed;
  final bool disabled;

  const SandikLogoutButton({
    super.key,
    required this.onPressed,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? Sandik.loss.withValues(alpha: 0.35)
        : Sandik.loss;
    return CupertinoButton(
      minimumSize: Size.zero,
      padding: EdgeInsets.zero,
      onPressed: disabled ? null : onPressed,
      child: Semantics(
        button: true,
        label: 'Çıkış yap',
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.18)),
          ),
          child: Center(
            child: Icon(Icons.logout_rounded, color: color, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Tam ekran loading — gif + "sandık" yazısı. Ekran ilk açılışında kullan.
class SandikLoadingScreen extends StatefulWidget {
  const SandikLoadingScreen({super.key});

  @override
  State<SandikLoadingScreen> createState() => _SandikLoadingScreenState();
}

class _SandikLoadingScreenState extends State<SandikLoadingScreen> {
  bool _showGif = false;

  @override
  void initState() {
    super.initState();
    // Bir sonraki frame'de GIF'e geç — native splash ikon → Flutter ikon arası
    // senkron, GIF frame'i hazır olunca yerini alır
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _showGif = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sandik.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_showGif)
              Image.asset('assets/images/loading.gif', width: 140, height: 140)
            else
              const SizedBox(width: 140, height: 140),
            const SizedBox(height: 20),
            Text(
              'sandık',
              style: GoogleFonts.dmSans(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: Sandik.gold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
