import 'package:flutter/material.dart';

import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import 'sandik_segment.dart';

/// Üç duraklı dönem seçici (1H · 1A · 1Y) — kayan hap: seçim zemini yeni
/// döneme KAYAR, uygulamanın ortak segment kontrolü (`SandikSegment`).
/// Düello arenasının onaylı prototipi böyleydi (2026-10-04).
///
/// `zirve_portfoyler_screen.dart`'tan buraya taşındı (sadeleştirme madde 8,
/// 2026-10-04): tek "Sıralama" sayfasında iki sekme (Ortaklarım · Herkes)
/// AYNI seçiciyi çizer — sekme değişince seçici yerinden, etiketinden ve
/// kabuğundan oynamaz.
///
/// 2026-10-05: bayrak `yaris_duello_arena` kalktı; eski amber dolgulu
/// seçici (Yarış'ın `_PeriodBar`'ıyla aynı dil) ve onu seçen `kayan`
/// parametresi silindi.
class ZirveDonemSecici extends StatelessWidget {
  const ZirveDonemSecici({
    super.key,
    required this.secili,
    required this.onSec,
  });

  final ZirveDonem secili;
  final ValueChanged<ZirveDonem> onSec;

  @override
  Widget build(BuildContext context) {
    const donemler = ZirveDonem.values;
    return SandikSegment(
      adet: donemler.length,
      secili: donemler.indexOf(secili),
      onSec: (i) => onSec(donemler[i]),
      yukseklik: SandikTouch.min + SandikSpace.xs,
      icBosluk: SandikSpace.xs,
      metinStili: context.t.bodyMedium,
      oge: (context, i, _) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(donemler[i].kisa, maxLines: 1, softWrap: false),
      ),
    );
  }
}
