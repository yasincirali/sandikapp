import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/history_service.dart';
import '../theme/sandik.dart';
import '../utils/chart_interval_policy.dart';

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

    return Semantics(
      label: 'Grafik bar aralığı',
      child: Container(
        decoration: BoxDecoration(
          color: context.c.surface1,
          borderRadius: BorderRadius.circular(SandikRadius.md),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (final bar in barlar)
              Expanded(
                child: _BarDugmesi(
                  bar: bar,
                  isSelected: bar == secili,
                  onPressed: () => onSecim(bar),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BarDugmesi extends StatelessWidget {
  const _BarDugmesi({
    required this.bar,
    required this.isSelected,
    required this.onPressed,
  });

  final ResolutionTier bar;
  final bool isSelected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return CupertinoButton(
      minimumSize: SandikTouch.minSize,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      child: Semantics(
        selected: isSelected,
        button: true,
        child: Container(
          // Dokunma hedefi en az 44px yüksekliğinde kalsın (HIG/Material).
          constraints: const BoxConstraints(minHeight: SandikTouch.min),
          decoration: BoxDecoration(
            color: isSelected ? context.c.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(SandikRadius.sm),
          ),
          child: Center(
            child: Text(
              bar.etiket,
              style: context.t.bodySmall?.copyWith(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? context.c.amberText : context.c.text36,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
