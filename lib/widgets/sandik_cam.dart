import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../services/remote_config_service.dart';
import '../theme/sandik.dart';

/// Cam malzeme ve kaydırma kenarı (cam/HIG incelemesi, 2026-10-12; bayrak
/// `goz_alici`).
///
/// ## Neden yalnız burada cam var
/// 30 Eylül'de yedi bulanıklık kaldırıldı: arkalarından içerik geçmiyordu,
/// görünmüyorlardı ama her karede arka plan okuması ödetiyorlardı. Cam ancak
/// İÇERİK ALTINDAN AKARKEN anlam taşır. Bu dosya o iki yeri kurar: sekme
/// başlığı (kaydırınca) ve yüzen eylem kapsülü. Rakamın arkasına cam
/// konmaz (9 Ekim kararı); camın üstünde yalnız başlık, ikon ve etiket olur.
///
/// ## Kimde cam, kimde opak
/// - **iOS:** buzlu cam (`BackdropFilter`, sigma 20). Apple'ın Liquid Glass
///   kırılması taklit EDİLMEZ (özel shader, pil ve kare maliyeti).
/// - **Android:** aynı yüzey OPAK çizilir; kaydırınca zemin bir ton yükselir
///   (Material 3 "scrolled under" davranışı). Eski cihazda blur kaydırmayı
///   takıltırdı; Material'de beklenen de bu.
/// - **Yüksek kontrast açık:** her platformda opak (iOS "Saydamlığı azalt"
///   Flutter'a gelmiyor; yakın vekili yüksek kontrast).
///
/// Bayrak kapalıyken hiçbir şey değişmez: [SandikKaydirmaBasligi] eski
/// `SafeArea > Column` düzenini birebir kurar.
abstract final class SandikCam {
  /// Cam/kaydırma kenarı davranışı açık mı (bayrak).
  static bool get acik => RemoteConfigService.instance.gozAlici;

  /// Bu cihazda gerçek bulanıklık çizilir mi.
  static bool bulanik(BuildContext context) =>
      defaultTargetPlatform == TargetPlatform.iOS &&
      !MediaQuery.highContrastOf(context);

  /// Bulanıklık gücü — iOS "regular material"a yakın.
  static const double sigma = 20;

  /// Cam zeminin örtücülüğü: üstündeki metin her iki temada AA (4.5:1)
  /// kalsın diye zemin rengi bu kadar baskın tutulur.
  static const double ortu = 0.78;
}

/// Bulanık (iOS) ya da opak (Android, yüksek kontrast) yüzey.
///
/// [bulaniklikAcik] `false` iken filtre hiç kurulmaz: hareketsiz başlıkta
/// arkada içerik yoktur, blur boşuna ödenmez.
class SandikCamYuzey extends StatelessWidget {
  const SandikCamYuzey({
    super.key,
    required this.child,
    this.borderRadius,
    this.renk,
    this.opakRenk,
    this.bulaniklikAcik = true,
    this.kenar,
  });

  final Widget child;
  final BorderRadius? borderRadius;

  /// Cam zemin tonu; varsayılan ekran zemini [SandikCam.ortu] örtücülükte.
  final Color? renk;

  /// Opak yoldaki zemin; varsayılan ekran zemini.
  final Color? opakRenk;
  final bool bulaniklikAcik;
  final BoxBorder? kenar;

  @override
  Widget build(BuildContext context) {
    final cam = SandikCam.bulanik(context);
    final zemin = cam
        ? (renk ?? context.c.background.withValues(alpha: SandikCam.ortu))
        : (opakRenk ?? context.c.background);
    Widget icerik = DecoratedBox(
      decoration: BoxDecoration(
        color: zemin,
        borderRadius: borderRadius,
        border: kenar,
      ),
      child: child,
    );
    if (cam && bulaniklikAcik) {
      icerik = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: SandikCam.sigma, sigmaY: SandikCam.sigma),
        child: icerik,
      );
    }
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: icerik);
    }
    return ClipRect(child: icerik);
  }
}

/// Sekme ekranının başlık + gövde iskeleti.
///
/// Bayrak kapalı: `SafeArea(child: Column([baslik, Expanded(govde)]))` —
/// ekranların bugünkü yapısıyla BİREBİR.
///
/// Bayrak açık: gövde tüm yüksekliği alır, başlık üstünde yüzer; içerik
/// başlığın (ve durum çubuğunun) altından akar. Kaydırınca:
/// - başlığın altına ince çizgi gelir (kaydırma kenarı),
/// - zemin iOS'ta buzlu cama, Android'de bir ton yüksek opak zemine döner,
/// - [SandikKucululenBaslik] ile sarılan başlık metni %88'e iner.
/// Hepsi KAYDIRMA KONUMUNA bağlı, zamana değil: parmağı izler, kesilmez,
/// geri gelir. Yerleşim hiç değişmez (yalnız boya ve dönüşüm), yani
/// kaydırmada yeniden yerleşim maliyeti yok.
///
/// Gövdedeki ilk dikey kaydırıcı, içeriğinin üstüne
/// [SandikKaydirmaBasligi.ustPay] kadar dolgu verir; `RefreshIndicator`
/// `edgeOffset` olarak aynı değeri alır.
class SandikKaydirmaBasligi extends StatelessWidget {
  const SandikKaydirmaBasligi({
    super.key,
    required this.kimlik,
    required this.baslik,
    required this.govde,
  });

  /// Ölçülen başlık yüksekliğinin önbellek anahtarı: sekmeye ikinci
  /// gelişte ilk kare doğru dolguyla çizilir.
  final String kimlik;
  final Widget baslik;
  final Widget govde;

  /// Gövde içeriğinin başlığın altında başlaması için gereken üst dolgu.
  /// Bayrak kapalıyken (ya da iskelet dışında) 0.
  static double ustPay(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_BaslikPayi>()
          ?.notifier
          ?.value ??
      0;

  /// [ustPay]'ı gövdenin İÇİNDEN okur. Ekranın `State.context`'i bu
  /// iskeletin ÜSTÜNDE kalır (orada pay hep 0 çıkar ve içerik başlığın
  /// altında kalır); gövdeyi kuran yöntemler payı bununla alır.
  static Widget payIle(Widget Function(double pay) kur) =>
      Builder(builder: (ic) => kur(ustPay(ic)));

  @override
  Widget build(BuildContext context) {
    if (!SandikCam.acik) {
      return SafeArea(
        child: Column(children: [baslik, Expanded(child: govde)]),
      );
    }
    return _AcikIskelet(kimlik: kimlik, baslik: baslik, govde: govde);
  }
}

class _AcikIskelet extends StatefulWidget {
  const _AcikIskelet({
    required this.kimlik,
    required this.baslik,
    required this.govde,
  });

  final String kimlik;
  final Widget baslik;
  final Widget govde;

  @override
  State<_AcikIskelet> createState() => _AcikIskeletState();
}

class _AcikIskeletState extends State<_AcikIskelet> {
  static final Map<String, double> _boyOnbellegi = {};

  late final ValueNotifier<double> _boy =
      ValueNotifier(_boyOnbellegi[widget.kimlik] ?? 0);
  final ValueNotifier<double> _ofset = ValueNotifier(0);

  @override
  void dispose() {
    _boy.dispose();
    _ofset.dispose();
    super.dispose();
  }

  bool _kaydirmaGeldi(ScrollNotification n) {
    _metrikGeldi(n.depth, n.metrics);
    return false;
  }

  // Sekme değişince (Varlıklarım ↔ Takip) yeni liste ilk yerleşiminde
  // metrik bildirir: başlık o listenin konumuna geçer, eskisinde kalmaz.
  bool _olcuGeldi(ScrollMetricsNotification n) {
    _metrikGeldi(n.depth, n.metrics);
    return false;
  }

  void _metrikGeldi(int derinlik, ScrollMetrics m) {
    // Yalnız gövdenin kendi dikey listesi (iç içe yatay şeritler değil).
    if (derinlik != 0 || m.axis != Axis.vertical) return;
    final p = m.pixels - m.minScrollExtent;
    if ((p - _ofset.value).abs() > 0.5 || p <= 0) _ofset.value = p;
  }

  void _boyOlculdu(double h) {
    if ((h - _boy.value).abs() < 0.5) return;
    _boyOnbellegi[widget.kimlik] = h;
    _boy.value = h;
  }

  @override
  Widget build(BuildContext context) {
    final ustBosluk = MediaQuery.viewPaddingOf(context).top;
    return SafeArea(
      top: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: _BaslikPayi(
                notifier: _boy,
                child: NotificationListener<ScrollMetricsNotification>(
                  onNotification: _olcuGeldi,
                  child: NotificationListener<ScrollNotification>(
                  onNotification: _kaydirmaGeldi,
                  child: _KaydirmaOfseti(
                    notifier: _ofset,
                    // Başlık ilk kez ölçülene kadar (yalnız uygulama
                    // açılışından sonra sekmeye ilk gelişte, tek kare)
                    // gövde görünmez: dolgusuz çizilip bir kare sonra
                    // aşağı zıplaması görülmesin.
                    child: ValueListenableBuilder<double>(
                      valueListenable: _boy,
                      child: widget.govde,
                      builder: (context, h, govde) => Opacity(
                        opacity: h > 0 ? 1 : 0,
                        child: govde,
                      ),
                    ),
                  ),
                ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: _BoyBildiren(
              onBoy: _boyOlculdu,
              child: _KaydirmaOfseti(
                notifier: _ofset,
                child: _CamBaslikZemini(
                  ofset: _ofset,
                  child: Padding(
                    padding: EdgeInsets.only(top: ustBosluk),
                    child: widget.baslik,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Kaydırma konumuna bağlı zemin: çizgi, cam ve opak ton geçişi.
///
/// Android/yüksek kontrastta zemin `background` → `surface1` arasında
/// ilerler (Material'in kaydırınca yükselen üst çubuğu). iOS'ta zemin
/// hep yarı saydamdır; bulanıklık yalnız içerik başlığın altına girince
/// kurulur.
class _CamBaslikZemini extends StatelessWidget {
  const _CamBaslikZemini({required this.ofset, required this.child});

  final ValueListenable<double> ofset;
  final Widget child;

  /// Kenar efektinin tam oturduğu kaydırma mesafesi (pt).
  static const double _esik = 24;

  @override
  Widget build(BuildContext context) {
    final cam = SandikCam.bulanik(context);
    return ValueListenableBuilder<double>(
      valueListenable: ofset,
      child: child,
      builder: (context, o, child) {
        final t = (o / _esik).clamp(0.0, 1.0);
        final cizgi = Border(
          bottom: BorderSide(
            color: context.c.hairline.withValues(
                alpha: context.c.hairline.a * t),
            width: 1,
          ),
        );
        return SandikCamYuzey(
          bulaniklikAcik: cam && o > 0.5,
          opakRenk: Color.lerp(
              context.c.background, context.c.surface1, t * 0.6),
          kenar: cizgi,
          child: child!,
        );
      },
    );
  }
}

/// `SliverAppBar` kullanan ekran (Ana sayfa) için aynı zemin: çubuğun
/// `flexibleSpace`'ine konur, ofseti ekranın kendi kaydırma
/// denetleyicisinden okur. Çubuk sabit (`pinned`) olduğu için içerik zaten
/// altından geçiyor; eksik olan yalnız malzemeydi.
class SandikCamCubukZemini extends StatefulWidget {
  const SandikCamCubukZemini({super.key, required this.kontrol});

  final ScrollController kontrol;

  @override
  State<SandikCamCubukZemini> createState() => _SandikCamCubukZeminiState();
}

class _SandikCamCubukZeminiState extends State<SandikCamCubukZemini> {
  final ValueNotifier<double> _ofset = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    widget.kontrol.addListener(_guncelle);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _guncelle();
    });
  }

  @override
  void didUpdateWidget(SandikCamCubukZemini old) {
    super.didUpdateWidget(old);
    if (old.kontrol != widget.kontrol) {
      old.kontrol.removeListener(_guncelle);
      widget.kontrol.addListener(_guncelle);
    }
  }

  @override
  void dispose() {
    widget.kontrol.removeListener(_guncelle);
    _ofset.dispose();
    super.dispose();
  }

  void _guncelle() {
    final k = widget.kontrol;
    _ofset.value = k.hasClients && k.positions.length == 1
        ? k.position.pixels.clamp(0.0, double.infinity)
        : 0;
  }

  @override
  Widget build(BuildContext context) => _CamBaslikZemini(
        ofset: _ofset,
        child: const SizedBox.expand(),
      );
}

/// Sekme başlığı metni: kaydırınca %88'e iner (sola yaslı). "Hareketi
/// azalt" açıkken ölçek değişmez, yalnız çizgi ve zemin.
///
/// İskelet dışında ya da bayrak kapalıyken çocuğu olduğu gibi döner.
class SandikKucululenBaslik extends StatelessWidget {
  const SandikKucululenBaslik({super.key, required this.child});

  final Widget child;

  static const double _enKucuk = 0.88;
  static const double _mesafe = 40;

  @override
  Widget build(BuildContext context) {
    // Bağımlılık KURULMAZ (get, depend değil): ofset her karede değişir,
    // dinleme aşağıdaki builder'da; başlık ağacının geri kalanı kurulmaz.
    final ofset =
        context.getInheritedWidgetOfExactType<_KaydirmaOfseti>()?.notifier;
    if (ofset == null || MediaQuery.disableAnimationsOf(context)) return child;
    return ValueListenableBuilder<double>(
      valueListenable: ofset,
      child: child,
      builder: (context, o, child) {
        final t = (o / _mesafe).clamp(0.0, 1.0);
        final olcek = 1 - (1 - _enKucuk) * t;
        return Transform.scale(
          scale: olcek,
          alignment: AlignmentDirectional.centerStart,
          child: child,
        );
      },
    );
  }
}

class _BaslikPayi extends InheritedNotifier<ValueNotifier<double>> {
  const _BaslikPayi({required super.notifier, required super.child});
}

class _KaydirmaOfseti extends InheritedNotifier<ValueNotifier<double>> {
  const _KaydirmaOfseti({required super.notifier, required super.child});

  // Kimse `depend` etmez (bkz. [SandikKucululenBaslik]); yalnız taşıyıcı.
}

/// Çocuğunun yüksekliğini yerleşimden sonra bildirir (gövdenin üst dolgusu).
class _BoyBildiren extends SingleChildRenderObjectWidget {
  const _BoyBildiren({required this.onBoy, super.child});

  final ValueChanged<double> onBoy;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _BoyBildirenRender(onBoy);

  @override
  void updateRenderObject(
      BuildContext context, _BoyBildirenRender renderObject) {
    renderObject.onBoy = onBoy;
  }
}

class _BoyBildirenRender extends RenderProxyBox {
  _BoyBildirenRender(this.onBoy);

  ValueChanged<double> onBoy;
  double? _son;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (_son == h) return;
    _son = h;
    // Yerleşim sırasında başka bir ağacı kirletmek yasak; kare sonunda.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onBoy(h);
    });
  }
}
