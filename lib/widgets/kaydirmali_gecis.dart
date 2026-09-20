// Kaydırmalı geçiş — toplam kartında Ben / ortak / Birlikte arasında.
//
// 2026-09-21: kaydırma hareketi işe yarıyordu ama görünmezdi — kart yerinde
// durup içerik bir anda değişince "ne oldu?" sorusu doğuyordu (kullanıcı).
// Etkileşimin üç görünür karşılığı var:
//   1. Sürüklerken kart parmağı takip eder (lastikli: yol yarıya iner,
//      96pt'te durur) ve hafifçe solar; kenarda gidilecek görünümün adı
//      belirir ("Ayşe ›"). Bırakmadan neye geçeceğini görürsün.
//   2. Eşiği geçip bırakınca eski içerik o yöne kayıp silinir, yenisi
//      karşı kenardan gelir (`AnimatedSwitcher`).
//   3. Eşiği geçmeden bırakınca kart yerine yaylanır — iptal.
// "Hareketi azalt" açıkken süreler sıfır: kart kaymaz, içerik anında
// değişir; hareket yine çalışır (`SandikMotion.*Of` sözleşmesi).
//
// Bu widget görünümün NE olduğunu bilmez: [anahtar] değişince içeriğin
// değiştiğini varsayar, [onGecis] ile yön bildirir, [hedefEtiketi] ile
// kenarda yazılacak adı sorar. Böylece ana ekranın kimlik sözleşmesine
// ('' / id / null) bağlanmaz ve tek başına test edilir.
import 'package:flutter/material.dart';

import '../theme/sandik.dart';

class KaydirmaliGecis extends StatefulWidget {
  const KaydirmaliGecis({
    super.key,
    required this.anahtar,
    required this.etkin,
    required this.onGecis,
    required this.hedefEtiketi,
    required this.child,
    this.ipucu = false,
    this.onIpucuGosterildi,
  });

  /// Tek seferlik "göz kırpma": ilk açılışta kart hafifçe sola kayıp geri
  /// gelir, o an kenarda hedefin adı belirir. Jestin var olduğunu kart
  /// kendisi söyler; tur metni ve alt sayfa notu okunup unutuluyordu.
  /// Gösterildiğini [onIpucuGosterildi] ile işaretler (tercih).
  final bool ipucu;
  final VoidCallback? onIpucuGosterildi;

  /// İçeriğin kimliği; değişince giriş animasyonu oynar.
  final Object? anahtar;

  /// Ortak yoksa hareket kapalı: kart sürüklenmez, jest tüketilmez.
  final bool etkin;

  /// `ileri`: sola kaydırma (sıradakine), değilse sağa (öncekine).
  final ValueChanged<bool> onGecis;

  /// Kenarda gösterilecek hedef adı; `null` ise etiket çizilmez.
  final String? Function(bool ileri) hedefEtiketi;

  final Widget child;

  /// Parmağın gidebileceği en uzak nokta (pt) — lastik sınırı.
  static const double azamiKayma = 96;

  /// Geçişi tetikleyen eşik: bu kadar sürüklenmiş ya da hızla fırlatılmış.
  static const double esikKayma = 40;
  static const double esikHiz = 300;

  /// Göz kırpma mesafesi (pt) — eşiğin altında, "kaydırılabilir" demeye yeter.
  static const double ipucuKayma = 14;

  @override
  State<KaydirmaliGecis> createState() => _KaydirmaliGecisState();
}

class _KaydirmaliGecisState extends State<KaydirmaliGecis>
    with SingleTickerProviderStateMixin {
  // `late final` ile tembel kurulmaz: hiç sürüklenmeden dispose edilirse
  // ilk erişim dispose içinde olur ve Ticker, ayrılmış ağaçta ata arar
  // ("Looking up a deactivated widget's ancestor") — taşma testinde yaşandı.
  late final AnimationController _yay;
  double _dx = 0;

  @override
  void initState() {
    super.initState();
    _yay = AnimationController(vsync: this);
    if (widget.ipucu && widget.etkin) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _gozKirp());
    }
  }

  /// [bas] → [son] arası kaymayı [sure] boyunca oynatır; süre sıfırsa
  /// (hareketi azalt) doğrudan [son]a atlar.
  Future<void> _kaydir(
      double bas, double son, Duration sure, Curve egriTuru) async {
    if (sure == Duration.zero) {
      if (mounted) setState(() => _dx = son);
      return;
    }
    _yay
      ..duration = sure
      ..reset();
    final egri = CurvedAnimation(parent: _yay, curve: egriTuru);
    void tik() => setState(() => _dx = bas + (son - bas) * egri.value);
    egri.addListener(tik);
    await _yay.forward();
    egri.removeListener(tik);
    if (mounted) setState(() => _dx = son);
  }

  /// Tek seferlik ipucu: ekran otursun, sola kay, rozet okunsun, geri gel.
  /// Kullanıcı bu sırada dokunursa `_surukle` denetleyiciyi durdurur ve
  /// hareket parmağa geçer. Hareketi azalt açıkken hiç oynamaz; tercih
  /// yine işaretlenir ki her açılışta denenmesin.
  Future<void> _gozKirp() async {
    if (!mounted) return;
    widget.onIpucuGosterildi?.call();
    final sure = SandikMotion.surfaceOf(context);
    if (sure == Duration.zero) return;
    await Future<void>.delayed(sure * 3);
    if (!mounted || _dx != 0 || _yay.isAnimating) return;
    await _kaydir(0, -KaydirmaliGecis.ipucuKayma, sure, SandikMotion.enter);
    await Future<void>.delayed(sure * 2);
    if (!mounted || _dx != -KaydirmaliGecis.ipucuKayma) return;
    await _kaydir(-KaydirmaliGecis.ipucuKayma, 0, sure, SandikMotion.move);
  }

  /// Son geçişin yönü — AnimatedSwitcher'da giren/çıkan tarafı belirler.
  bool _ileri = true;

  @override
  void dispose() {
    _yay.dispose();
    super.dispose();
  }

  void _surukle(DragUpdateDetails d) {
    if (_yay.isAnimating) _yay.stop();
    setState(() {
      // Lastik: yolun yarısı, sınırda durur.
      _dx = (_dx + d.delta.dx * 0.5)
          .clamp(-KaydirmaliGecis.azamiKayma, KaydirmaliGecis.azamiKayma);
    });
  }

  Future<void> _birak(DragEndDetails d) async {
    final hiz = d.primaryVelocity ?? 0;
    final ileri = _dx < 0 || (_dx == 0 && hiz < 0);
    final gecis = _dx.abs() >= KaydirmaliGecis.esikKayma ||
        hiz.abs() >= KaydirmaliGecis.esikHiz;
    if (gecis && _dx != 0) {
      // Eski içerik o yöne akıp gider; kaymayı sıfırlayıp içeriği
      // değiştiriyoruz, kalan yolu AnimatedSwitcher tamamlar.
      SandikHaptic.selection.perform();
      setState(() {
        _ileri = ileri;
        _dx = 0;
      });
      widget.onGecis(ileri);
      return;
    }
    // İptal: yerine yaylan.
    await _kaydir(_dx, 0, SandikMotion.stateOf(context), SandikMotion.enter);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final oran = (_dx.abs() / KaydirmaliGecis.azamiKayma).clamp(0.0, 1.0);
    final sagaGidiyor = _dx < 0; // sola kaydırınca sıradaki (sağdan) gelir
    final etiket = _dx == 0 ? null : widget.hedefEtiketi(sagaGidiyor);

    Widget govde = AnimatedSwitcher(
      duration: SandikMotion.surfaceOf(context),
      switchInCurve: SandikMotion.enter,
      switchOutCurve: SandikMotion.enter,
      transitionBuilder: (child, anim) {
        // Giren çocuk hedef yönden gelir, çıkan karşı yöne gider.
        final giren = child.key == ValueKey(widget.anahtar);
        final yon = _ileri ? 1.0 : -1.0;
        final kayma = Tween<Offset>(
          begin: Offset(giren ? 0.25 * yon : -0.25 * yon, 0),
          end: Offset.zero,
        ).animate(anim);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(position: kayma, child: child),
        );
      },
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, if (current != null) current],
      ),
      child: KeyedSubtree(key: ValueKey(widget.anahtar), child: widget.child),
    );

    if (!widget.etkin) return govde;

    final surukleniyor = _dx != 0;
    if (surukleniyor) {
      govde = Transform.translate(
        offset: Offset(_dx, 0),
        child: Opacity(opacity: 1 - 0.35 * oran, child: govde),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _surukle,
      onHorizontalDragEnd: _birak,
      onHorizontalDragCancel: () => setState(() => _dx = 0),
      child: Stack(
        alignment: Alignment.center,
        children: [
          govde,
          // Kenar ipucu: hedefin adı + ok, sürükleme arttıkça belirir.
          if (etiket != null)
            Positioned(
              left: sagaGidiyor ? null : SandikSpace.smd,
              right: sagaGidiyor ? SandikSpace.smd : null,
              child: IgnorePointer(
                child: Opacity(
                  opacity: oran,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: SandikSpace.sm2, vertical: SandikSpace.xs2),
                    decoration: BoxDecoration(
                      color: c.amberFill,
                      borderRadius: BorderRadius.circular(SandikRadius.lg),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!sagaGidiyor)
                          Icon(Icons.chevron_left_rounded,
                              size: 18, color: c.onAmber),
                        Text(
                          etiket,
                          style: context.t.labelLarge?.copyWith(
                            color: c.onAmber,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (sagaGidiyor)
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: c.onAmber),
                      ],
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
