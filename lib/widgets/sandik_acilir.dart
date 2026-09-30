import 'package:flutter/widgets.dart';

import '../theme/sandik.dart';

/// Aç/kapa paneli — uygulamanın TEK katlanır bölüm hareketi.
///
/// ## Neden (animasyon denetimi 2026-10-01)
/// Katlanır bölümler `AnimatedSize` + `acik ? Panel : SizedBox` ile
/// yazılmıştı. Kapanışta panel İLK KAREDE ağaçtan çıkıyor, ardından boş bir
/// kutu 240 ms küçülüyordu: içerik göz önünde bir anda siliniyor, sonra
/// boşluk kapanıyordu. Ok ile panel de her yerde başka süre/eğrideydi
/// (ok 180 ms `enter`, panel 240 ms `move`).
///
/// Burada:
///   · panel kapanırken SOLARAK ağaçta kalır, yükseklik onunla birlikte
///     kapanır; kapanış bitince ağaçtan çıkar (kapalıyken hesap/çizim
///     maliyeti yine sıfır — `period_summary_view` Derinlik kararı);
///   · süre ve eğri tek yerde: [sure] / [egri]. Oku döndüren çağıran
///     aynılarını kullanır ([SandikAcilirOk]) — hareket tek parça okunur;
///   · açılırken aynı katman ters oynar; yarıda tersine dokunmak kaldığı
///     yerden döner (denetleyici, `forward(from: 0)` değil).
///
/// Hareketi azalt açıkken süre sıfır: panel anında açılır/kapanır.
class SandikAcilir extends StatefulWidget {
  const SandikAcilir({super.key, required this.acik, required this.child});

  final bool acik;
  final Widget child;

  /// Panel ve ok süresi (hareketi azalt'ta sıfır).
  static Duration sure(BuildContext context) =>
      SandikMotion.surfaceOf(context);

  /// Yükseklik eğrisi: ekranda biçim değiştiren eleman → `move`.
  static const Curve egri = SandikMotion.move;

  @override
  State<SandikAcilir> createState() => _SandikAcilirState();
}

class _SandikAcilirState extends State<SandikAcilir>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, value: widget.acik ? 1 : 0);
  late final Animation<double> _boy =
      CurvedAnimation(parent: _c, curve: SandikAcilir.egri);
  // Saydamlık: açılırken ease-out ile belirir, kapanırken ilk anda hızla
  // solar (`exit` ters yuvada) — boy kapanırken içerik çoktan silikleşmiş.
  late final Animation<double> _saydam = CurvedAnimation(
    parent: _c,
    curve: SandikMotion.enter,
    reverseCurve: SandikMotion.exit,
  );

  @override
  void initState() {
    super.initState();
    // Kapanış bitince paneli ağaçtan çıkarmak için yeniden kur.
    _c.addStatusListener((s) {
      if (s == AnimationStatus.dismissed && mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(SandikAcilir eski) {
    super.didUpdateWidget(eski);
    if (eski.acik == widget.acik) return;
    final sure = SandikAcilir.sure(context);
    if (sure == Duration.zero) {
      _c.value = widget.acik ? 1 : 0;
      return;
    }
    _c.duration = sure;
    widget.acik ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.acik && _c.isDismissed) {
      return const SizedBox(width: double.infinity);
    }
    return SizeTransition(
      sizeFactor: _boy,
      alignment: Alignment.topCenter,
      child: FadeTransition(opacity: _saydam, child: widget.child),
    );
  }
}

/// Katlanır bölümün oku — panelle AYNI süre ve eğride döner.
class SandikAcilirOk extends StatelessWidget {
  const SandikAcilirOk({
    super.key,
    required this.acik,
    required this.child,
    this.tur = 0.5,
  });

  final bool acik;
  final Widget child;

  /// Açıkken dönüş (tur). Aşağı ok → yukarı: 0,5; sağ ok → aşağı: 0,25.
  final double tur;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        turns: acik ? tur : 0,
        // = SandikAcilir.sure (panelle aynı süre).
        duration: SandikMotion.surfaceOf(context),
        curve: SandikAcilir.egri,
        child: child,
      );
}
