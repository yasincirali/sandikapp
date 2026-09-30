import 'package:flutter/widgets.dart';

import '../theme/sandik.dart';

/// Listeden çıkan satır: önce solar ve yüksekliği kapanır, altındaki
/// satırlar yukarı KAYAR — sonra silme işi koşar.
///
/// ## Neden (animasyon denetimi 2026-10-01)
/// Alarm listesinde "sil"e basınca satır tek karede yok oluyor, altındaki
/// satırlar bir anda yukarı zıplıyordu; göz neyin gittiğini kaçırıyordu.
/// Takip listesinde aynı iş kaydırarak yapılıyor ve `Dismissible` satırı
/// zaten kapatarak çıkarıyor — iki listenin "silindi" dili aynı olmalı.
///
/// ## Kullanım
/// ```dart
/// KapananSatir(
///   key: ValueKey(alarm.id),
///   child: Builder(builder: (ctx) => Satir(
///     onDelete: () => KapananSatir.kapatVeYap(ctx, () => sil(alarm.id)),
///   )),
/// )
/// ```
/// [kapatVeYap]: satır kapanır, [islem] koşar; iş hata verirse satır GERİ
/// AÇILIR ve hata çağırana iletilir — kullanıcı sildiğini sanmaz.
///
/// Hareketi azalt açıkken süre sıfır: satır anında gider (yine de önce
/// kaybolur, sonra iş koşar).
class KapananSatir extends StatefulWidget {
  const KapananSatir({super.key, required this.child});

  final Widget child;

  /// [context]'in üstündeki satırı kapatır, sonra [islem]i koşar. Satır yoksa
  /// yalnızca [islem] koşar.
  static Future<void> kapatVeYap(
      BuildContext context, Future<void> Function() islem) async {
    final s = context.findAncestorStateOfType<_KapananSatirState>();
    if (s == null) return islem();
    await s._kapat();
    try {
      await islem();
    } catch (_) {
      if (s.mounted) s._ac();
      rethrow;
    }
  }

  @override
  State<KapananSatir> createState() => _KapananSatirState();
}

class _KapananSatirState extends State<KapananSatir>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    value: 1,
    duration: SandikMotion.state,
  );
  // Kapanış ters yönde oynar: `reverseCurve` exit — ilk anda hızla solar.
  late final Animation<double> _egri = CurvedAnimation(
    parent: _c,
    curve: SandikMotion.enter,
    reverseCurve: SandikMotion.exit,
  );

  Future<void> _kapat() async {
    final sure = SandikMotion.stateOf(context);
    if (sure == Duration.zero) {
      _c.value = 0;
      return;
    }
    _c.reverseDuration = sure;
    await _c.reverse().orCancel.catchError((Object _) {});
  }

  void _ac() {
    _c.duration = SandikMotion.stateOf(context);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: _egri,
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: _egri, child: widget.child),
      );
}
