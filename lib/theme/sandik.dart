import 'dart:io' show Platform;
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/cupertino.dart' show CupertinoButton, CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
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
/// Uygulama genelinde TEK tarih seçici.
///
/// `showDatePicker`'ı doğrudan çağırma — her çağrı kendi temasını kurunca
/// ekranlar arasında farklı görünüyordu (biri açık Material teması, biri
/// `ColorScheme.dark`, biri hiç tema vermiyordu). Buradaki tek tanım marka
/// renklerini ve Türkçe etiketleri her yerde aynı yapar.
///
/// [lastDate] varsayılanı bugündür: işlem/ödeme tarihleri geçmişe aittir.
/// Gelecek tarih gereken yerler (mevduat vadesi) kendi değerini verir.
Future<DateTime?> pickSandikDate(
  BuildContext context, {
  required DateTime initialDate,
  DateTime? firstDate,
  DateTime? lastDate,
  String helpText = 'Tarih seç',
}) {
  final last = lastDate ?? DateTime.now();
  // initialDate aralık dışındaysa Flutter assert atar — güvenli tarafa çek.
  var initial = initialDate;
  final first = firstDate ?? DateTime(2000);
  if (initial.isBefore(first)) initial = first;
  if (initial.isAfter(last)) initial = last;

  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: first,
    lastDate: last,
    helpText: helpText,
    cancelText: 'İptal',
    confirmText: 'Seç',
    builder: (ctx, child) => Theme(
      data: Theme.of(ctx).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Sandik.amber,
          onPrimary: Colors.black,
          surface: Sandik.surface2,
          onSurface: Colors.white,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: Sandik.surface2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(SandikRadius.md),
          ),
        ),
      ),
      child: child!,
    ),
  );
}

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

/// Aynı sayfanın çift açılmasını engelleyen güvenli push.
///
/// Sorun: hızlı iki dokunuş iki route iter; kullanıcı geri dönerken aynı
/// ekranı iki kez kapatmak zorunda kalır. `Navigator.push` bunu kendisi
/// engellemez — geçiş animasyonu sürerken buton hâlâ dokunulabilirdir.
///
/// Çözüm: son push'un zaman damgası tutulur; [window] içinde gelen ikinci
/// çağrı yok sayılır ve `null` döner. Pencere, geçiş animasyonundan
/// (~300ms) biraz uzun tutulmuştur.
///
/// İş mantığını değiştirmez: ilk push aynen çalışır, dönüş değeri aynen
/// iletilir. Yalnızca yinelenen ikinci çağrı düşer.
DateTime? _lastPushAt;

Future<T?> pushGuarded<T>(
  BuildContext context,
  Route<T> route, {
  Duration window = const Duration(milliseconds: 350),
}) {
  final now = DateTime.now();
  final last = _lastPushAt;
  if (last != null && now.difference(last) < window) {
    return Future<T?>.value(null);
  }
  _lastPushAt = now;
  return Navigator.of(context).push<T>(route);
}

/// Köşe yarıçapı ölçeği — üç kademe.
///
/// Denetim öncesi projede 17 farklı radius değeri vardı (2,4,5,6,7,8,9,10,
/// 12,14,16,18,20,22,24,28); aynı ekranda dört farklı yuvarlaklık yan yana
/// gelebiliyordu. Göz bunu "özensiz" okur ama sebebini adlandıramaz.
///
/// Kademeler bir hiyerarşi taşır — büyüdükçe eleman "daha üstte" durur:
/// - [sm] rozet, çip, küçük ikon kutusu
/// - [md] liste satırı, input, ikincil kart
/// - [lg] hero kart, bottom sheet, modal
abstract final class SandikRadius {
  static const double sm = 8;
  static const double md = 14;
  static const double lg = 20;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);

  /// Bottom sheet üst köşeleri.
  static const BorderRadius sheetTop =
      BorderRadius.vertical(top: Radius.circular(lg));
}

/// 8'lik boşluk ızgarası.
///
/// Önceki durumda ana sayfada SizedBox yükseklikleri 3,4,8,10,12,16,24,40
/// gibi keyfi değerlerdi — hiyerarşi boşlukla değil yalnızca yazı tipiyle
/// kuruluyordu. Bu ölçek dikey ritmi tek bir tabana oturtur.
///
/// [xs] ölçeğin dışında kalan tek değer (4): ikon–metin gibi sıkı
/// eşleşmelerde 8 fazla geliyor.
abstract final class SandikSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;

  /// Ekran kenar boşluğu — dar cihazlarda daralır.
  static double screenH(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 360 ? md : lg;
}

/// Marka hareket dili — süre ve eğri birlikte seçilir, ayrı ayrı değil.
///
/// Neden gerekli: Flutter'da `AnimatedContainer.curve` varsayılanı
/// [Curves.linear]'dır. Doğrusal hareket fiziksel dünyada yoktur; göz bunu
/// "özensiz" okur ama sebebini adlandıramaz. Denetim öncesi projedeki 18
/// `AnimatedContainer`'ın 16'sı eğri vermiyordu — süreler doğru seçilmişti,
/// eksik olan yalnızca eğriydi.
///
/// `duration:` yazdığın her yerde [enter] veya [move] ile eşleştir:
/// ```dart
/// AnimatedContainer(
///   duration: SandikMotion.state,
///   curve: SandikMotion.enter,
///   ...
/// )
/// ```
abstract final class SandikMotion {
  /// Basma geri bildirimi (110ms) — [SandikTappable] kullanır.
  static const Duration press = Duration(milliseconds: 110);

  /// Durum geçişi: çip, sekme, seçim (180ms). En sık kullanılan.
  static const Duration state = Duration(milliseconds: 180);

  /// Giren/çıkan yüzey: sheet, dialog, ekran geçişi (240ms).
  static const Duration surface = Duration(milliseconds: 240);

  /// Giren, çıkan veya durum değiştiren her şey.
  ///
  /// `ease-out` hızlı başlar: kullanıcının en dikkatli baktığı ilk anda
  /// hareket zaten olmuştur. `ease-in` asla kullanılmaz — yavaş başlayıp
  /// tam o anı geciktirir ve arayüzü ağır hissettirir.
  static const Curve enter = Curves.easeOutCubic;

  /// Ekranda yer değiştiren / biçim değiştiren eleman.
  static const Curve move = Curves.easeInOutCubic;
}

/// Dokunsal geri bildirim ölçeği.
///
/// Mobilde dokunsal geri bildirim, web'deki `:active` scale'in karşılığıdır —
/// hareketin ulaşamadığı bir kanal. Finansal bir uygulamada "işlem gerçekten
/// kaydedildi" hissi için özellikle değerlidir.
///
/// Ton seçimi sıklığa göre yapılır: günde onlarca kez tekrarlanan bir eylem
/// (sekme değişimi, çip seçimi) en hafif tonu alır; nadir ve kalıcı sonuçlu
/// olan (varlık kaydedildi, silindi) daha belirgin olanı.
enum SandikHaptic {
  /// Geri bildirim yok. Sürükleme sırasında sürekli tetiklenen ya da
  /// zaten kendi geri bildirimi olan hedefler için.
  none,

  /// Seçim değişti — çip, sekme, filtre. Ölçeğin en hafifi.
  selection,

  /// Ana eylem veya kalıcı sonuç — kaydet, ekle, onayla.
  medium,

  /// Yıkıcı işlem veya hata. Kullanıcı ekrana bakmıyorken bile fark edilir.
  heavy;

  /// Platform çağrısına çevirir. [none] hiçbir şey yapmaz.
  void perform() {
    switch (this) {
      case SandikHaptic.none:
        break;
      case SandikHaptic.selection:
        HapticFeedback.selectionClick();
      case SandikHaptic.medium:
        HapticFeedback.mediumImpact();
      case SandikHaptic.heavy:
        HapticFeedback.heavyImpact();
    }
  }
}

/// Dokunma geri bildirimi — basılınca hafifçe küçülür.
///
/// Neden: iOS'ta Material ripple yabancı durur, ama hiç geri bildirim
/// olmaması da uygulamayı "ölü" hissettirir. Scale-down her iki platformda
/// da doğal karşılanan nötr bir tepkidir.
///
/// [scale] 0.97 ve 110ms bilinçli seçim: daha derin/yavaş bir animasyon
/// listede hızlı gezinirken yorucu oluyor, daha sığı fark edilmiyor.
///
/// ```dart
/// SandikTappable(
///   onTap: () => Navigator.push(...),
///   child: Container(...),
/// )
/// ```
class SandikTappable extends StatefulWidget {
  const SandikTappable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.scale = 0.97,
    this.semanticLabel,
    this.haptic = SandikHaptic.selection,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  final String? semanticLabel;

  /// Dokunuşta verilecek dokunsal geri bildirim.
  ///
  /// Varsayılan [SandikHaptic.selection] — ölçeğin en hafif tonu. Ana
  /// eylemler ([SandikHaptic.medium]) ve yıkıcı onaylar için yükseltilir;
  /// [SandikHaptic.none] ile tamamen kapatılabilir.
  final SandikHaptic haptic;

  @override
  State<SandikTappable> createState() => _SandikTappableState();
}

class _SandikTappableState extends State<SandikTappable> {
  bool _down = false;

  void _set(bool v) {
    if (widget.onTap == null && widget.onLongPress == null) return;
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    // Erişilebilirlik: "hareketi azalt" açıkken scale uygulanmaz.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget result = AnimatedScale(
      scale: (_down && enabled && !reduceMotion) ? widget.scale : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: widget.child,
    );

    if (widget.semanticLabel != null) {
      result = Semantics(
        button: true,
        label: widget.semanticLabel,
        child: result,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // Haptic yalnızca eylem gerçekten varken tetiklenir; onTap null ise
      // GestureDetector'a da null gider ve hedef pasif kalır (mevcut davranış).
      onTap: widget.onTap == null
          ? null
          : () {
              widget.haptic.perform();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress == null
          ? null
          : () {
              // Uzun basma her zaman daha belirgin: kullanıcı bir eşiği
              // geçtiğini bilmeli, aksi halde ne zaman bırakacağını kestiremez.
              SandikHaptic.medium.perform();
              widget.onLongPress!();
            },
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: result,
    );
  }
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

  // ── Yüzey dekorasyonları (Yön A) ───────────────────────────────────────────
  //
  // Cam efekti (BackdropFilter) bir vurgu aracıdır — her yerde kullanılınca
  // vurgu olmaktan çıkar, geriye yalnızca katman kompozisyon maliyeti kalır.
  // Ana sayfada 7 ayrı blur vardı; artık yalnızca hero kart bulanıklaştırılır,
  // diğer yüzeyler aşağıdaki opak dekorasyonları kullanır.

  /// Liste satırı / ikincil kart — düz yüzey, kenarlıksız.
  ///
  /// Kenarlık yerine zeminden hafif açık bir dolgu kullanılır: 23 ayrı
  /// çerçeve "kart içinde kart" hissi veriyordu.
  static BoxDecoration surfaceCard({double radius = SandikRadius.md}) {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.045),
      borderRadius: BorderRadius.circular(radius),
    );
  }

  /// Dokunulabilir ikon kutusu / çip — seçili durumda amber'e döner.
  static BoxDecoration chip({
    required bool selected,
    Color accent = amber,
    double radius = SandikRadius.md,
  }) {
    return BoxDecoration(
      color: selected
          ? accent.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.055),
      borderRadius: BorderRadius.circular(radius),
      border: selected
          ? Border.all(color: accent.withValues(alpha: 0.42), width: 1)
          : null,
    );
  }

  // ── Liquid Glass helpers ────────────────────────────────────────────────────

  /// Blur + translucent overlay — temel glass katmanı.
  static BoxDecoration glassDecoration({
    double radius = SandikRadius.lg,
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
    double radius = SandikRadius.lg,
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
        borderRadius: SandikRadius.mdAll,
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: SandikRadius.mdAll,
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.05)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: SandikRadius.mdAll,
        borderSide: const BorderSide(color: amber, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: SandikRadius.mdAll,
        borderSide: const BorderSide(color: loss, width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: SandikRadius.mdAll,
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
            borderRadius: SandikRadius.mdAll,
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
///
/// Zemin [Sandik.background] ile aynı; GIF'in kendi arka planı şeffaf olduğu
/// için çerçeve/renk uyuşmazlığı oluşmaz. GIF içeriği 200×200 tuvalin
/// ortasındaki 150×150'de durduğundan, görünen boyutu istenen ölçüye
/// oturtmak için [_gifOverdraw] kadar büyütülüp ortalanır.
class SandikLoadingScreen extends StatefulWidget {
  const SandikLoadingScreen({super.key});

  /// GIF'in şeffaf kenar dolgusunu telafi eden çarpan (200/150).
  /// Bu değer [CustomLoadingIndicator] ile bilinçli olarak aynıdır — açılıştaki
  /// görsel ile uygulama içi göstergenin oranı birebir tutsun diye.
  static const double _gifOverdraw = 200 / 150;
  static const double _logoSize = 140;

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
    const size = SandikLoadingScreen._logoSize;
    const drawSize = size * SandikLoadingScreen._gifOverdraw;

    return Scaffold(
      backgroundColor: Sandik.background,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kutu her iki durumda da aynı ölçüde — GIF belirince "sandık"
            // yazısı yerinden zıplamaz.
            SizedBox(
              width: size,
              height: size,
              // GIF hazır olana kadar boş kalır, sonra yumuşakça belirir:
              // ani "pat" diye görünme yerine 220ms fade.
              child: AnimatedOpacity(
                opacity: _showGif ? 1 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                child: _showGif
                    ? Center(
                        child: SizedBox(
                          width: drawSize,
                          height: drawSize,
                          child: Image.asset(
                            'assets/images/loading.gif',
                            width: drawSize,
                            height: drawSize,
                            fit: BoxFit.contain,
                            // GIF alfası 1-bit; yüksek kalite ölçekleme
                            // kenardaki testere dişini yumuşatır.
                            filterQuality: FilterQuality.high,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: SandikSpace.lg),
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
