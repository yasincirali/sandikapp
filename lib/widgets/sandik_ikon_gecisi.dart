import 'package:flutter/material.dart';

import '../theme/sandik.dart';

/// Aç/kapa ikonunun yerinde değişimi: kısa çapraz sönüm + hafif büyüme.
///
/// 2026-10-20 hareket denetimi: izleme yıldızı, beğeni, karşılaştırma
/// onayı tek karede atlıyordu; doğru kalıp yalnız Ana sayfa göz ikonundaydı.
/// Ortak bileşen o kalıbın kendisi. Ölçek 0.9'dan başlar (küçükten
/// büyümek "pırtlama" gibi okunur; Emil: 0'dan/çok küçükten ölçekleme yok).
/// Bulanıklık YOK: `ImageFiltered` mobilde pahalı, sönüm + ölçek yeter.
/// Süre `state`, eğri enter/exit; hareketi azalt açıkken anında değişir.
/// Anahtar ikonun kendisi + rengi: ikisinden biri değişince geçiş oynar.
class SandikIkonGecisi extends StatelessWidget {
  const SandikIkonGecisi(
    this.ikon, {
    super.key,
    this.renk,
    this.boyut,
    this.semanticLabel,
  });

  final IconData ikon;
  final Color? renk;
  final double? boyut;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      ikon,
      key: ValueKey((ikon, renk)),
      color: renk,
      size: boyut,
      semanticLabel: semanticLabel,
    );
    if (MediaQuery.disableAnimationsOf(context)) return icon;
    return AnimatedSwitcher(
      duration: SandikMotion.stateOf(context),
      switchInCurve: SandikMotion.enter,
      switchOutCurve: SandikMotion.exit,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1).animate(a),
          child: child,
        ),
      ),
      child: icon,
    );
  }
}
