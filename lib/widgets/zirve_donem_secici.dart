import 'package:flutter/material.dart';

import '../services/zirve_kiyas.dart';
import '../theme/sandik.dart';
import 'sandik_segment.dart';

/// Üç duraklı dönem seçici (1H · 1A · 1Y). Yarış ekranındaki `_PeriodBar`
/// ile aynı dil (amber dolgu, kaydırmalı seçim); süre `SandikMotion`
/// üzerinden ki "hareketi azalt" saygı görsün.
///
/// `zirve_portfoyler_screen.dart`'tan buraya taşındı (sadeleştirme madde 8,
/// 2026-10-04): tek "Sıralama" sayfasında iki sekme (Ortaklarım · Herkes)
/// AYNI seçiciyi çizer — sekme değişince seçici yerinden, etiketinden ve
/// kabuğundan oynamaz.
class ZirveDonemSecici extends StatelessWidget {
  const ZirveDonemSecici({
    super.key,
    required this.secili,
    required this.onSec,
    this.kayan = false,
  });

  final ZirveDonem secili;
  final ValueChanged<ZirveDonem> onSec;

  /// Kayan hap (düello arenası, bayrak `yaris_duello_arena`, 2026-10-04):
  /// seçim zemini yeni döneme KAYAR — uygulamanın ortak segment kontrolü
  /// (`SandikSegment`). Onaylı prototip böyleydi. Sıralama sayfasında iki
  /// sekme aynı bayrağı geçirir; seçici sekme değişince değişmez.
  /// Kapalıyken eski amber dolgulu seçici birebir.
  final bool kayan;

  @override
  Widget build(BuildContext context) {
    if (kayan) {
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
    return Container(
      height: SandikTouch.min + SandikSpace.xs2,
      padding: const EdgeInsets.all(SandikSpace.xs2),
      decoration: BoxDecoration(
        color: context.c.overlay,
        borderRadius: BorderRadius.circular(SandikRadius.lg),
        border: Border.all(color: context.c.hairline),
      ),
      child: Row(
        children: [
          for (final d in ZirveDonem.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: d == secili,
                label: d.ad,
                child: ExcludeSemantics(
                  child: SandikBasma(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSec(d),
                    // Zemin metinle AYNI sürede (`state`): eskiden zemin 240,
                    // metin 180 ms'de varıyordu (animasyon denetimi
                    // 2026-10-01).
                    child: AnimatedContainer(
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      margin: EdgeInsets.symmetric(
                        horizontal: d == secili ? 0 : 2,
                      ),
                      decoration: BoxDecoration(
                        gradient: d == secili ? context.c.amberGradient : null,
                        borderRadius: BorderRadius.circular(SandikRadius.md),
                        boxShadow: d == secili
                            ? [
                                BoxShadow(
                                  color: context.c.amberFill.withValues(
                                    alpha: 0.35,
                                  ),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: AnimatedDefaultTextStyle(
                          duration: SandikMotion.stateOf(context),
                          curve: SandikMotion.enter,
                          style: context.t.bodyMedium!.copyWith(
                            fontWeight: FontWeight.w800,
                            color: d == secili
                                ? context.c.onAmber
                                : context.c.text58,
                          ),
                          child: Text(d.kisa),
                        ),
                      ),
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
