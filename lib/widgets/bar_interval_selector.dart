import 'package:flutter/material.dart';

import '../services/history_service.dart';
import '../theme/sandik.dart';
import '../utils/chart_interval_policy.dart';
import 'sandik_segment.dart';

/// Grafik bar aralığı seçici (1dk · 5dk · 15dk · 1sa · 1G · 1H).
///
/// Liste [ChartIntervalPolicy.gecerliBarlar] tarafından belirlenir ve
/// dönemle birlikte YENİDEN KURULUR — geçersiz bir bar burada hiç
/// görünmez.
///
/// **Neden disabled değil, YOK.** TradingView/Bloomberg geçersiz barları
/// soluk gösterir; bu, aracı öğrenmeye yatırım yapmış profesyonel kullanıcı
/// için bilgidir. Sandık'ın kullanıcısı birikimine bakıyor — ona
/// tıklayamayacağı beş buton göstermek bilgi değil gürültü olurdu. Yahoo
/// Finance ve Investing.com da listeyi sessizce yeniden kurar.
///
/// Tek seçenek kalıyorsa widget kendini HİÇ çizmez: seçim sunmayan bir
/// seçici, kullanıcıya var olmayan bir karar varmış izlenimi verir.
class BarIntervalSelector extends StatelessWidget {
  const BarIntervalSelector({
    super.key,
    required this.periodDays,
    required this.secili,
    required this.onSecim,
  });

  /// Aktif dönemin gün sayısı (GÜNLÜK için `0`).
  final int periodDays;

  /// Şu an seçili bar. [ChartIntervalPolicy.uyarla]'dan geçmiş olmalı.
  final ResolutionTier secili;

  final ValueChanged<ResolutionTier> onSecim;

  @override
  Widget build(BuildContext context) {
    final barlar = ChartIntervalPolicy.gecerliBarlar(periodDays);
    if (barlar.length < 2) return const SizedBox.shrink();

    // Ortak [SandikSegment] (2026-10-01): seçim zemini kayar, dönem
    // seçicisiyle aynı dil. 52 pt: eski kabuk 4 pt iç boşluk + 44 pt hedef.
    return Semantics(
      label: 'Grafik bar aralığı',
      child: SandikSegment(
        adet: barlar.length,
        secili: barlar.indexOf(secili),
        onSec: (i) => onSecim(barlar[i]),
        yukseklik: SandikTouch.min + 8,
        icBosluk: 4,
        metinStili: context.t.bodySmall,
        oge: (_, i, __) => Text(barlar[i].etiket),
      ),
    );
  }
}
