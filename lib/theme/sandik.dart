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
    builder: (ctx, child) {
      // Palet AKTİF TEMADAN okunur. Eskiden burada sabit `ColorScheme.dark`
      // vardı: light modda uygulama aydınlıkken tarih seçici koyu açılıyor,
      // her tarih girişinde tema kırılıyordu. `copyWith` yalnızca marka
      // renklerini bindiriyor; parlaklık (brightness) temadan gelir, böylece
      // takvimin kendi iç kontrastları (bugünün halkası, devre dışı günler)
      // doğru tarafta kalır.
      final p = ctx.c;
      final base = Theme.of(ctx);
      return Theme(
        data: base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            primary: p.amberFill,
            onPrimary: p.onAmber,
            surface: p.surface2,
            onSurface: p.text90,
          ),
          dialogTheme: DialogThemeData(
            backgroundColor: p.surface2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
          ),
        ),
        child: child!,
      );
    },
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

/// Boşluk ölçeği — 2pt adımlı.
///
/// **Neden 8'lik ızgara değil:** bu sınıf başta 4/8/16/24/32/48 olarak
/// tanımlandı ve "8'lik ızgara" olduğu yazıyordu. Kod ölçüldüğünde
/// (2026-08-10, 878 boşluk kullanımı) gerçeğin farklı olduğu görüldü:
///
/// | değer | kullanım | ölçekte miydi? |
/// |---|---|---|
/// | 12 | 125 | ❌ |
/// | 8  | 125 | ✅ |
/// | 10 | 83  | ❌ |
/// | 16 | 81  | ✅ |
/// | 14 | 81  | ❌ |
/// | 6  | 80  | ❌ |
///
/// Kullanımın **%63'ü ölçek dışıydı** ve bu rastgelelik değildi — 12, 10,
/// 14, 6 tek başına 369 kullanım. Yani pratikte 2pt adımlı bir ölçek
/// zaten vardı; resmî ölçek onu karşılamıyordu.
///
/// İki seçenek vardı: 555 kullanımı ölçeğe zorlamak (görsel yerleşimi
/// bozar, riski yüksek, faydası tartışmalı) ya da ölçeği gerçeğe uydurmak.
/// İkincisi seçildi: ara adımlar eklenince token kapsamı **%37 → %84**
/// çıkıyor ve tek bir piksel bile kımıldamıyor.
///
/// Yeni kod bu ölçeğin dışına çıkmamalı; `spacing_scale_test.dart` yeni
/// ölçek-dışı değerlerin sayısının artmasını engeller.
abstract final class SandikSpace {
  static const double xxs = 2;
  static const double xs = 4;
  static const double xs2 = 6;
  static const double sm = 8;
  static const double sm2 = 10;
  static const double smd = 12;
  static const double md2 = 14;
  static const double md = 16;
  static const double lgs = 20;
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

  // ── Erişilebilirlik ───────────────────────────────────────────────────────

  /// "Hareketi azalt" sistem ayarı açıkken [Duration.zero], değilse [d].
  ///
  /// iOS HIG (Accessibility → Motion) bunu **High severity** sayar: hareket
  /// duyarlılığı olan kullanıcıda animasyon baş dönmesi ve mide bulantısı
  /// tetikleyebilir. Ayar açıkken animasyonu *kaldırmıyoruz* — süreyi sıfıra
  /// çekiyoruz. Sonuç aynı: son kare anında görünür, ama widget ağacı ve
  /// `onEnd` geri çağrıları değişmediği için çağıran tarafta hiçbir dallanma
  /// gerekmez.
  ///
  /// ```dart
  /// AnimatedContainer(
  ///   duration: SandikMotion.stateOf(context),
  ///   curve: SandikMotion.enter,
  ///   ...
  /// )
  /// ```
  ///
  /// Süreyi elle `MediaQuery.disableAnimationsOf` ile dallandırmak yerine bunu
  /// kullan: koruma tek yerde tanımlı kalır, yeni animasyon eklendiğinde
  /// unutulmaz.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

  /// [press] süresinin reduce-motion farkındalıklı hâli.
  static Duration pressOf(BuildContext context) => of(context, press);

  /// [state] süresinin reduce-motion farkındalıklı hâli. En sık kullanılan.
  static Duration stateOf(BuildContext context) => of(context, state);

  /// [surface] süresinin reduce-motion farkındalıklı hâli.
  static Duration surfaceOf(BuildContext context) => of(context, surface);
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
      duration: SandikMotion.press,
      curve: SandikMotion.enter,
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
  ///
  /// Sistem **"Kalın Metin"** (iOS Settings → Erişilebilirlik → Ekran ve
  /// Metin Boyutu → Kalın Metin) ayarı açıksa tüm ağırlıklar bir kademe
  /// yukarı çıkar. `context.c`'nin `highContrast` için yaptığının aynısı:
  /// tek bir geçiş noktasında çözülür, çağıran hiçbir şey bilmez.
  TextTheme get t {
    final base = Theme.of(this).textTheme;
    return MediaQuery.boldTextOf(this) ? base.boldened : base;
  }
}

/// Sistem "Kalın Metin" ayarı için ağırlık yükseltmesi.
extension SandikBoldText on TextTheme {
  /// Her stilin ağırlığını bir kademe artırır.
  ///
  /// Neden `FontWeight.bold` sabiti değil: marka tipografisi w500–w900
  /// arasında **beş** farklı ağırlık kullanıyor. Hepsini `bold`a (w700)
  /// eşitlemek hiyerarşiyi düzleştirir — w800 başlık ile w500 gövde aynı
  /// görünür. Kademeli artış hiyerarşiyi korur.
  ///
  /// w900 zaten en üstteki ağırlıktır; daha yukarısı yok, olduğu gibi kalır.
  TextTheme get boldened {
    TextStyle? up(TextStyle? s) {
      if (s == null) return null;
      // `FontWeight` `==`'i ezdiği için const map anahtarı olamaz;
      // sayısal ağırlık (`value`: 100–900) üzerinden ilerlenir.
      final w = s.fontWeight ?? FontWeight.w400;
      // w400 → w600 (iki kademe): normal gövde metninde tek kademe (w500)
      // gözle fark edilmiyor. Üstteki ağırlıklarda tek adım yeterli.
      final step = w.value <= FontWeight.w400.value ? 200 : 100;
      final next = (w.value + step).clamp(100, 900);
      return s.copyWith(
        fontWeight: FontWeight.values.firstWhere((f) => f.value == next),
      );
    }

    return TextTheme(
      displayLarge: up(displayLarge),
      displayMedium: up(displayMedium),
      displaySmall: up(displaySmall),
      headlineLarge: up(headlineLarge),
      headlineMedium: up(headlineMedium),
      headlineSmall: up(headlineSmall),
      titleLarge: up(titleLarge),
      titleMedium: up(titleMedium),
      titleSmall: up(titleSmall),
      bodyLarge: up(bodyLarge),
      bodyMedium: up(bodyMedium),
      bodySmall: up(bodySmall),
      labelLarge: up(labelLarge),
      labelMedium: up(labelMedium),
      labelSmall: up(labelSmall),
    );
  }
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

/// Moda duyarlı renk paleti — light/dark ayrımının tek kaynağı.
///
/// **Neden gerekli:** [Sandik] içindeki renkler `static const`'tur, yani
/// derleme zamanında sabittir ve `Theme.of(context).brightness`'a bakamaz.
/// Light mode, rengin çağrıldığı yerde context'e göre çözülmesini gerektirir.
///
/// [Sandik] sabitleri **kaldırılmadı** — 500'den fazla çağrı noktası onlara
/// bağlı. Bu sınıf onların yanına gelir; migrasyon ekran ekran ilerler:
///
/// ```dart
/// // eski (dark'a sabitli):
/// color: Sandik.surface1
/// // yeni (moda duyarlı):
/// color: context.c.surface1
/// ```
///
/// `ThemeExtension` seçilmesinin sebebi [lerp]: tema değişiminde renkler
/// zıplamaz, `MaterialApp` geçişi boyunca yumuşakça interpole olur.
@immutable
class SandikPalette extends ThemeExtension<SandikPalette> {
  const SandikPalette({
    required this.background,
    required this.surface1,
    required this.surface2,
    required this.text90,
    required this.text58,
    required this.text36,
    required this.text20,
    required this.gain,
    required this.loss,
    required this.danger,
    required this.info,
    required this.amberFill,
    required this.amberText,
    required this.gold,
    required this.onAmber,
    required this.onStatus,
    required this.hairline,
    required this.overlay,
    required this.cardShadow,
  });

  // ── Yüzeyler ──────────────────────────────────────────────────────────
  /// Seviye 0 — ekran zemini.
  final Color background;

  /// Seviye 1 — kart, liste satırı.
  final Color surface1;

  /// Seviye 2 — hero kart, elevated yüzey.
  final Color surface2;

  // ── Metin ─────────────────────────────────────────────────────────────
  final Color text90;
  final Color text58;
  final Color text36;
  final Color text20;

  // ── Anlamsal ──────────────────────────────────────────────────────────
  final Color gain;
  final Color loss;
  final Color danger;
  final Color info;

  // ── Marka ─────────────────────────────────────────────────────────────
  /// CTA butonu zemini. **Her iki modda da aynı** — amber marka kimliğidir
  /// ve üstüne koyu metin gelir (kontrast 7.99:1).
  final Color amberFill;

  /// Amber'in metin/ikon olarak kullanımı. Light modda koyulaşır: dark amber
  /// (#F5A623) beyaz zeminde yalnızca **1.94:1** verir, okunmaz.
  final Color amberText;

  /// Display sayılar ve wordmark.
  final Color gold;

  /// [amberFill] üzerine gelen metin/ikon rengi.
  ///
  /// Amber her iki modda da açık bir zemindir, bu yüzden üstüne **koyu**
  /// metin gelir — `text90` DEĞİL. Dark modda `text90` beyazdır ve amber
  /// üzerinde yalnızca 1.87:1 verir (okunmaz); doğru eşleşme koyu marka
  /// yeşilidir.
  final Color onAmber;

  /// [gain] / [loss] **dolgu olarak** kullanıldığında üstüne gelen metin/ikon.
  ///
  /// [onAmber] ile aynı tuzağı kapatır ama yönü temaya göre TERSİNİR, çünkü
  /// amber'in aksine `gain`/`loss` iki temada farklı parlaklıktadır:
  ///
  /// | | zemin | `text90` ile | doğrusu |
  /// |---|---|---|---|
  /// | light | `#0F7A4E` koyu yeşil | 3.02:1 ✗ | beyaz → 5.37:1 |
  /// | dark  | `#3DB77F` parlak yeşil | 2.54:1 ✗ | koyu → 5.73:1 |
  ///
  /// Yani sabit bir renk İKİ temada birden çalışamaz. Renkli zeminli
  /// SnackBar/rozet yaparken `text90` bırakma — o metin rengi *yüzey* için
  /// ayarlanmıştır, dolgu için değil.
  final Color onStatus;

  /// Marka rozeti / seçili pill için amber gradient. Üstüne [onAmber] gelir.
  ///
  /// Bu getter bir tuzağı kapatmak için var: rozet gradient'leri elle
  /// `[gold, amberText]` diye yazılıyordu. O ikisi METİN token'ıdır ve light
  /// palette'te ikisi de aynı koyu kahvedir (#4A3618) — gradient tek koyu
  /// bloğa çöküp üstündeki koyu yazıyı 1.41:1'e düşürüyordu (AA 4.5:1).
  /// Dolgu gerektiğinde daima bunu kullan; her iki temada amber kalır ve
  /// [onAmber] ile 7.99:1 verir.
  LinearGradient get amberGradient => LinearGradient(
        colors: [amberFill, amberFill.withValues(alpha: 0.88)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  // ── Yüzey dekorasyonu ─────────────────────────────────────────────────
  /// İnce ayırıcı / kenarlık. Dark'ta beyaz %7, light'ta siyah %9.
  final Color hairline;

  /// Kart dolgusu. **Yön değiştirir:** dark'ta zeminin üstüne beyaz overlay
  /// eklenerek yükseklik kurulur; light'ta yüzey zaten açık olduğu için
  /// overlay görünmez — orada yükseklik [cardShadow] ile kurulur.
  final Color overlay;

  /// Kart gölgesi. Dark'ta boş liste (gölge koyu zeminde görünmez),
  /// light'ta yüksekliğin tek taşıyıcısı.
  final List<BoxShadow> cardShadow;

  /// Mevcut dark palet.
  ///
  /// [gain] ve [loss] denetimde düzeltildi: eski değerler (#2D9E6C / #E8503A)
  /// `surface1` üzerinde 4.30:1 ve 3.90:1 veriyordu — WCAG AA eşiği 4.5:1.
  /// Kâr/zarar rakamları uygulamanın en kritik verisi olduğu için bu ton
  /// parlatıldı; karakter aynı kaldı.
  static const dark = SandikPalette(
    background: Color(0xFF0A1E15),
    surface1: Color(0xFF112E28),
    surface2: Color(0xFF1A3D2E),
    text90: Color(0xE1FFFFFF),
    text58: Color(0x8CFFFFFF),
    // 0x59 (0.35 opak) surface1 üzerinde yalnızca 2.91:1 veriyordu — AA'nın
    // büyük-metin eşiğinin (3:1) bile altında. Bu ton gerçek metinde
    // kullanıldığı için opaklık yükseltildi.
    text36: Color(0x94FFFFFF), // 5.17:1
    text20: Color(0x6BFFFFFF),
    gain: Color(0xFF3DB77F), // 5.73:1 (eski #2D9E6C → 4.30:1)
    loss: Color(0xFFFF6B52), // 5.17:1 (eski #E8503A → 3.90:1)
    // Eski #EF4444 METİN olarak surface1 üzerinde yalnızca 3.86:1 veriyordu
    // (AA 4.5). `gain`/`loss` denetimde düzeltilmişti ama `danger` atlanmıştı —
    // bu ton "Sil" gibi geri alınamaz aksiyonları anlatıyor, en okunur olması
    // gereken renk. #FF6B52 ile aynı aileden, 5.17:1.
    danger: Color(0xFFFF6B52), // 5.17:1 (eski #EF4444 → 3.86:1)
    info: Color(0xFF4EA8DE),
    amberFill: Color(0xFFF5A623),
    amberText: Color(0xFFF5A623),
    gold: Color(0xFFF5C842),
    onAmber: Color(0xFF112E28), // koyu marka yeşili — 7.66:1
    // Dark palette'te gain/loss PARLAK tonlardır; üstlerine koyu yazılır.
    // Beyaz 2.54:1 / 2.81:1 verirdi. Koyu: 5.73:1 / 5.17:1.
    onStatus: Color(0xFF112E28),
    hairline: Color(0x12FFFFFF), // beyaz %7
    overlay: Color(0x0BFFFFFF), // beyaz %4.5
    cardShadow: [],
  );

  /// Light palet.
  ///
  /// Zemin nötr gri değil sıcak kağıt: sandık'ın nötrleri yeşile çalar, saf
  /// gri markayı yabancılaştırırdı. Metin de saf siyah değil koyu marka
  /// yeşilidir. Tüm oranlar WCAG 2.1 ile doğrulandı (bkz.
  /// `test/light_mode_contrast_test.dart`).
  static const light = SandikPalette(
    background: Color(0xFFF4F1EA),
    surface1: Color(0xFFFBFAF6),
    surface2: Color(0xFFFFFFFF),
    text90: Color(0xFF12241E), // 15.50:1 / surface1
    text58: Color(0xFF4A5B54), // 6.90:1
    // 3.79:1'den yükseltildi: bu ton 103 yerde GERÇEK metinde kullanılıyor
    // (boş durum açıklamaları, "Tümünü Temizle" gibi eylem bağlantıları) ve
    // çoğu 10–13pt. O boyutta 3.79 okunmuyordu — kullanıcı geri bildirimi.
    text36: Color(0xFF566761), // 5.31:1
    text20: Color(0xFF7E8C86),
    gain: Color(0xFF0F7A4E), // 5.14:1
    loss: Color(0xFFC0341F), // 5.36:1
    danger: Color(0xFFC42B22), // 5.41:1
    info: Color(0xFF1B6FA8), // 5.17:1
    amberFill: Color(0xFFF5A623), // marka — değişmez
    // Sarı ailesini koyulaştırmak hue'yu çamurlu kahveye kaydırır: 5.67:1
    // AA'yı geçiyordu ama gözde "soluk sarı" olarak okunuyordu (kullanıcı
    // geri bildirimi 2026-08-09). Çözüm daha da koyulaştırıp kahve-nötre
    // taşımak — artık metin gibi okunuyor, renk gibi değil.
    amberText: Color(0xFF4A3618), // 10.98:1
    gold: Color(0xFF4A3618), // 10.98:1 — display sayılar da aynı tonda
    onAmber: Color(0xFF12241E), // 7.99:1
    // Light palette'te gain/loss KOYU tonlardır (kendileri beyaz zeminde
    // okunsun diye). Üstlerine beyaz gelir: 5.37:1 / 5.60:1.
    // `text90` (#12241E) 3.02:1 / 2.89:1 verirdi.
    onStatus: Color(0xFFFFFFFF),
    hairline: Color(0x17122419), // siyah %9
    overlay: Color(0xFFFFFFFF), // light'ta yükseklik = beyaz + gölge
    cardShadow: [
      BoxShadow(
        color: Color(0x12122419),
        blurRadius: 3,
        offset: Offset(0, 1),
      ),
      BoxShadow(
        color: Color(0x1F122419),
        blurRadius: 14,
        spreadRadius: -6,
        offset: Offset(0, 4),
      ),
    ],
  );

  /// Yüksek kontrast varyantı — sistem erişilebilirlik ayarı açıkken.
  ///
  /// Yalnızca **yardımcı metin** tonları güçlendirilir; yüzeyler ve marka
  /// renkleri değişmez (kimlik korunur). `text36` 3.79:1 → 6.95:1,
  /// `text20` 2.19:1 → 4.94:1 olur; ikisi de artık normal metin eşiğini
  /// geçer.
  ///
  /// Hangi tarafa gidileceği zemine bağlıdır: açık temada metin koyulaşır,
  /// koyu temada açılır. Ayrım [text90]'ın parlaklığından yapılır.
  SandikPalette highContrast() {
    // text90 koyuysa açık temadayız.
    final onLightGround = text90.computeLuminance() < 0.5;
    return copyWith(
      text58: onLightGround ? const Color(0xFF2F3D37) : const Color(0xFFC4CCC9),
      text36: onLightGround ? const Color(0xFF47554F) : const Color(0xFFA3ADA9),
      text20: onLightGround ? const Color(0xFF5E6B65) : const Color(0xFF8A9490),
    );
  }

  @override
  SandikPalette copyWith({
    Color? background,
    Color? surface1,
    Color? surface2,
    Color? text90,
    Color? text58,
    Color? text36,
    Color? text20,
    Color? gain,
    Color? loss,
    Color? danger,
    Color? info,
    Color? amberFill,
    Color? amberText,
    Color? gold,
    Color? onAmber,
    Color? onStatus,
    Color? hairline,
    Color? overlay,
    List<BoxShadow>? cardShadow,
  }) {
    return SandikPalette(
      background: background ?? this.background,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      text90: text90 ?? this.text90,
      text58: text58 ?? this.text58,
      text36: text36 ?? this.text36,
      text20: text20 ?? this.text20,
      gain: gain ?? this.gain,
      loss: loss ?? this.loss,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      amberFill: amberFill ?? this.amberFill,
      amberText: amberText ?? this.amberText,
      gold: gold ?? this.gold,
      onAmber: onAmber ?? this.onAmber,
      onStatus: onStatus ?? this.onStatus,
      hairline: hairline ?? this.hairline,
      overlay: overlay ?? this.overlay,
      cardShadow: cardShadow ?? this.cardShadow,
    );
  }

  @override
  SandikPalette lerp(covariant SandikPalette? other, double t) {
    if (other == null) return this;
    return SandikPalette(
      background: Color.lerp(background, other.background, t)!,
      surface1: Color.lerp(surface1, other.surface1, t)!,
      surface2: Color.lerp(surface2, other.surface2, t)!,
      text90: Color.lerp(text90, other.text90, t)!,
      text58: Color.lerp(text58, other.text58, t)!,
      text36: Color.lerp(text36, other.text36, t)!,
      text20: Color.lerp(text20, other.text20, t)!,
      gain: Color.lerp(gain, other.gain, t)!,
      loss: Color.lerp(loss, other.loss, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      amberFill: Color.lerp(amberFill, other.amberFill, t)!,
      amberText: Color.lerp(amberText, other.amberText, t)!,
      gold: Color.lerp(gold, other.gold, t)!,
      onAmber: Color.lerp(onAmber, other.onAmber, t)!,
      onStatus: Color.lerp(onStatus, other.onStatus, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      overlay: Color.lerp(overlay, other.overlay, t)!,
      cardShadow:
          BoxShadow.lerpList(cardShadow, other.cardShadow, t) ?? cardShadow,
    );
  }
}

/// Moda duyarlı palete kısa yol.
///
/// ```dart
/// Container(color: context.c.surface1)
/// Text('...', style: TextStyle(color: context.c.text90))
/// ```
///
/// Tema uzantısı kayıtlı değilse (test ortamında çıplak `ThemeData`)
/// [SandikPalette.dark] döner — uygulama dark-first olduğu için güvenli
/// varsayılan budur.
extension SandikPaletteAccess on BuildContext {
  SandikPalette get c {
    final base =
        Theme.of(this).extension<SandikPalette>() ?? SandikPalette.dark;
    // Sistem "yüksek kontrast" erişilebilirlik ayarı açıksa yardımcı metin
    // tonları koyulaşır/açılır. `text36` normalde 3.79:1'dir (yardımcı
    // metin eşiği); bu ayarı açan kullanıcı zaten okumakta zorlandığını
    // söylüyordur — orada 4.5'in de üstüne çıkarız.
    return MediaQuery.highContrastOf(this) ? base.highContrast() : base;
  }

  /// Aydınlık modda mıyız? Yüzey mantığı yön değiştirdiği için gerekir.
  bool get isLight => Theme.of(this).brightness == Brightness.light;
}

/// Moda duyarlı yüzey dekorasyonları.
///
/// [Sandik.surfaceCard] ve kardeşleri `static` olduğu için context göremez;
/// bu uzantı onların moda duyarlı karşılığıdır. Migrasyonda
/// `Sandik.surfaceCard()` → `context.surfaceCard()` şeklinde değişir.
///
/// **Yükseklik yön değiştirir.** Dark'ta kart, zeminin üstüne beyaz overlay
/// eklenerek yükselir. Light'ta yüzey zaten açıktır — orada aynı overlay
/// görünmez; yükseklik gölgeyle kurulur. Bu yüzden iki mod aynı kodu
/// paylaşamaz, `if` ile ayrılır.
extension SandikSurfaces on BuildContext {
  /// Liste satırı / ikincil kart.
  BoxDecoration surfaceCard({double radius = SandikRadius.md}) {
    final p = c;
    return BoxDecoration(
      color: p.overlay,
      borderRadius: BorderRadius.circular(radius),
      // Light'ta düz beyaz kart, zeminden yalnızca gölgeyle ayrılır;
      // ek olarak çok ince bir kenarlık kenarı netleştirir.
      border: isLight ? Border.all(color: p.hairline, width: 1) : null,
      boxShadow: p.cardShadow.isEmpty ? null : p.cardShadow,
    );
  }

  /// Hero / elevated kart — bir kademe daha yüksek.
  BoxDecoration elevatedCard({double radius = SandikRadius.lg}) {
    final p = c;
    return BoxDecoration(
      color: isLight ? p.surface2 : p.surface2.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: p.hairline, width: 1),
      boxShadow: p.cardShadow.isEmpty ? null : p.cardShadow,
    );
  }

  /// Dokunulabilir çip — seçili durumda [accent]'e döner.
  ///
  /// [accent] verilmezse moda duyarlı amber kullanılır.
  BoxDecoration chip({
    required bool selected,
    Color? accent,
    double radius = SandikRadius.md,
  }) {
    final p = c;
    final a = accent ?? p.amberText;
    return BoxDecoration(
      color: selected
          ? a.withValues(alpha: isLight ? 0.12 : 0.16)
          : p.overlay,
      borderRadius: BorderRadius.circular(radius),
      border: selected
          ? Border.all(color: a.withValues(alpha: 0.42), width: 1)
          : (isLight ? Border.all(color: p.hairline, width: 1) : null),
    );
  }

  /// Form alanı dekorasyonu — moda duyarlı.
  InputDecoration inputDecoration(
    String hint, {
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? labelText,
    String? errorText,
  }) {
    final p = c;
    OutlineInputBorder border(Color color, [double width = 1.0]) =>
        OutlineInputBorder(
          borderRadius: SandikRadius.mdAll,
          borderSide: BorderSide(color: color, width: width),
        );
    return InputDecoration(
      hintText: hint,
      labelText: labelText,
      errorText: errorText,
      hintStyle: TextStyle(color: p.text36, fontSize: 14),
      labelStyle: TextStyle(color: p.text36, fontSize: 14),
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      // Dark'ta alan zeminden KOYULAŞARAK çukurlaşır; light'ta tam tersi,
      // beyazlaşarak öne çıkar.
      fillColor: isLight ? p.surface2 : Colors.black.withValues(alpha: 0.18),
      border: border(p.hairline),
      enabledBorder: border(p.hairline),
      focusedBorder: border(p.amberFill, 1.5),
      errorBorder: border(p.loss, 1.2),
      focusedErrorBorder: border(p.loss, 1.5),
    );
  }
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
  //
  // 2026-08-09 erişilebilirlik denetimi: eski tonlar (#2D9E6C / #E8503A)
  // `surface1` üzerinde 4.30:1 ve 3.90:1 veriyordu — WCAG AA eşiği 4.5:1.
  // Kâr/zarar rakamları uygulamanın en kritik verisidir; ton parlatıldı,
  // karakter korundu. Doğrulama: test/light_mode_contrast_test.dart
  static const Color gain      = Color(0xFF3DB77F); // 5.73:1 (eski 4.30:1)
  static const Color loss      = Color(0xFFFF6B52); // 5.17:1 (eski 3.90:1)

  // ── Durum renkleri ─────────────────────────────────────────────────────────
  //
  // [loss] finansal bir anlam taşır (portföy değeri düştü); [danger] ise
  // arayüz durumudur (silme, hata, doğrulama). İkisi görsel olarak yakın ama
  // anlamları ayrı — aynı tokeni paylaşırlarsa "kayıptayım" ile "hata var"
  // ayırt edilemez hale gelir.
  static const Color danger    = Color(0xFFEF4444); // Yıkıcı eylem / hata
  static const Color info      = Color(0xFF4EA8DE); // Bilgilendirme / nötr vurgu

  // ── Madalya (leaderboard) ──────────────────────────────────────────────────
  //
  // Madalya rozetleri gradient'tir ve üzerlerinde sıra numarası yazar. Metin
  // gradient'in HER İKİ ucunda da okunabilmeli — kontrast en kötü uca göre
  // değerlendirilir. Bu yüzden tonlar bilinçli olarak AÇIK tutulur ve rakam
  // koyu ([SandikPalette.onAmber]) yazılır: hem madalya kimliği (altın/gümüş/
  // bronz ayrımı) korunur hem AA sağlanır.
  //
  // Eski değerlerde rakam açık tondaydı ve bronzun koyu ucunda 2.12:1'e
  // düşüyordu — rozetin içindeki sayı okunmuyordu.
  static const Color medalGold   = Color(0xFFF5C842); // 1. — gold ile aynı ton
  static const Color medalGoldDark   = Color(0xFFD9A520); // gradient koyu uç
  static const Color medalSilver = Color(0xFFE8E8EA); // 2.
  static const Color medalSilverDark = Color(0xFFBFC0C4);
  static const Color medalBronze = Color(0xFFE0A574); // 3.
  static const Color medalBronzeDark = Color(0xFFC07E3F);

  // ── Sabit opaklıklar (dark zemin üzeri metin) ──────────────────────────────
  static const Color text90    = Color(0xE1FFFFFF); // 0.88 opak (Ana başlık)
  static const Color text58    = Color(0x8CFFFFFF); // 0.55 (İkincil etiket)
  // 0x59 surface1 üzerinde 2.91:1 veriyordu (AA büyük-metin eşiği 3:1'in
  // bile altında) ve bu ton gerçek metinde kullanılıyor. Yükseltildi.
  static const Color text36    = Color(0x94FFFFFF); // 5.17:1
  static const Color text20    = Color(0x6BFFFFFF); // devre dışı

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

/// Standart kart kabuğu — yüzey + köşe + saç teli kenar.
///
/// **Neden gerekli:** denetimde (2026-08-10) 64 kart kabuğunun elle
/// kurulduğu, 13 farklı varyasyona dağıldığı görüldü. Ama dağılım rastgele
/// değildi — 24+13 kullanım (%58) tek bir şekle aitti ve kenar tanımlarının
/// 18'i birebir `context.c.hairline` idi.
///
/// Elle kurmanın bedeli soyut değil: "başlık + sayaç rozeti" taşma hatası
/// `performance_screen`'de düzeltildikten sonra `portfolio_performance_screen`'de
/// **yeniden yazıldı**, çünkü paylaşılan bir kabuk yoktu.
///
/// Bu widget yalnızca **düz** kartı kapsar. Seçim/hata/vurgu gibi durum
/// bildiren kenarlar (11 kullanım) bilinçli varyasyondur; onlar `Container`
/// ile kurulmaya devam eder — hepsini tek API'ye sıkıştırmak parametre
/// çorbası üretirdi.
class SandikCard extends StatelessWidget {
  const SandikCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(SandikSpace.md),
    this.elevated = false,
    this.bordered = true,
    this.radius,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  /// Seviye 2 yüzey (`surface2`) — hero kart için.
  final bool elevated;

  /// Saç teli kenar. Kartlar üst üste bindiğinde ayrım için gerekir;
  /// zemine gömülü bloklarda kapatılabilir.
  final bool bordered;

  /// Varsayılan [SandikRadius.md] — kullanımın çoğunluğu bu.
  final double? radius;

  /// Verilirse kart dokunulabilir olur. Dokunma hedefi HIG #37 gereği
  /// en az 44pt olmalı; kart zaten bundan büyüktür.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: elevated ? context.c.surface2 : context.c.surface1,
        borderRadius: BorderRadius.circular(radius ?? SandikRadius.md),
        border: bordered ? Border.all(color: context.c.hairline) : null,
      ),
      child: child,
    );
    if (onTap == null) return box;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: box,
    );
  }
}

/// Bölüm başlığı + isteğe bağlı sayaç rozeti.
///
/// **Neden gerekli:** bu desen elle yazıldığında taşıyor. Aynı hata iki
/// ekranda ayrı ayrı ortaya çıktı:
/// - `performance_screen` "TEKNİK ANALİZ" (TECHNICAL_DEBT.md'de kayıtlı)
/// - `portfolio_performance_screen` "TEKNİK SİNYALLER" (1.5×'te 61px,
///   3×'te 415px taşıyordu)
///
/// Sebep her ikisinde de aynı: başlık `Flexible` değil, büyük metin
/// ayarında genişleyip rozeti dışarı itiyor. Burada başlık daima esnek ve
/// kısaltılabilir; rozet sabit kalır.
class SandikSectionHeader extends StatelessWidget {
  const SandikSectionHeader({
    super.key,
    required this.title,
    this.count,
    this.trailing,
  });

  final String title;

  /// Verilirse başlığın yanında amber rozet gösterilir.
  final int? count;

  /// Sağa yaslanan aksiyon (ör. "Ayarla" bağlantısı).
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            style: context.t.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: context.c.text58,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: SandikSpace.sm),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 7, vertical: SandikSpace.xxs),
            decoration: BoxDecoration(
              color: context.c.amberFill.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(SandikRadius.sm),
            ),
            child: Text(
              '$count',
              style: context.t.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.c.amberText,
              ),
            ),
          ),
        ],
        if (trailing != null) ...[const Spacer(), trailing!],
      ],
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
