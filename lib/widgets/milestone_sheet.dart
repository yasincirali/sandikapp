import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/milestone_service.dart';
import '../theme/sandik.dart';

/// Kilometre taşı kutlaması.
///
/// **Ton kuralı:** fintech tonunda kalınır. Konfeti yağmuru, emoji seli ya da
/// oyunlaştırma dili yok — kutlanan şey ciddi bir birikim ve kullanıcı bunu
/// ciddiye alınmış hissetmeli. Marka konumu "sakin, güvenilir kasa".
///
/// **Kutlanan şey birikimdir, işlem değil.** Robinhood her işlem sonrası
/// konfeti atıyordu; Massachusetts uzlaşması (7,5M$) tam olarak bunu hedef
/// aldı. Buradaki eşiklerin hiçbiri bir işleme bağlı değil.
class MilestoneSheet extends StatelessWidget {
  final Milestone milestone;

  const MilestoneSheet({super.key, required this.milestone});

  static Future<void> show(BuildContext context, Milestone m) {
    AnalyticsService.instance
        .logMilestoneReached(kind: m.kind, value: m.value);
    return showSandikSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MilestoneSheet(milestone: m),
    );
  }

  IconData get _ikon => switch (milestone.kind) {
        'portfolio_age' => Icons.hourglass_bottom_rounded,
        'gold_count' => Icons.star_rounded,
        'diversification' => Icons.pie_chart_rounded,
        'contribution_streak' => Icons.savings_rounded,
        _ => Icons.trending_up_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: c.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, 24 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: const SandikTutamac(),
          ),
          const SizedBox(height: 24),
          Center(child: _Rozet(ikon: _ikon)),
          const SizedBox(height: 16),
          Text(
            milestone.title,
            textAlign: TextAlign.center,
            style: context.t.headlineMedium?.copyWith(color: c.text90),
          ),
          const SizedBox(height: 8),
          Text(
            milestone.body,
            textAlign: TextAlign.center,
            style: context.t.bodyLarge?.copyWith(color: c.text58),
          ),
          const SizedBox(height: 24),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: c.amberFill,
              foregroundColor: c.onAmber,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
  }
}

/// Kilometre taşı rozeti — uygulamanın nadir, duygusal anı.
///
/// Animasyon denetimi 2026-10-01 ("kaçırılmış fırsat"): kutlama sayfası
/// hareketsiz ve sessizdi. Ton kuralı (konfeti yok, oyunlaştırma yok)
/// korunur: sayfa oturduktan sonra rozet %90'dan hafif taşarak yerine
/// oturur, arkasından tek bir amber halka yayılıp söner ve orta şiddette
/// dokunsal onay gelir — "kasana bir şey eklendi" hissi, gösteri değil.
/// Yay taşması yalnız bu TEK küçük öğede ([SandikMotion.spring] kuralı).
/// Hareketi azalt açıkken rozet sabit, halka yok; dokunsal onay kalır.
class _Rozet extends StatefulWidget {
  const _Rozet({required this.ikon});

  final IconData ikon;

  @override
  State<_Rozet> createState() => _RozetState();
}

class _RozetState extends State<_Rozet> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: SandikMotion.flow * 2);
  late final Animation<double> _olcek = Tween<double>(begin: 0.9, end: 1)
      .animate(CurvedAnimation(
          parent: _c,
          curve: const Interval(0, 0.4, curve: SandikMotion.spring)));
  late final Animation<double> _halka = CurvedAnimation(
      parent: _c, curve: const Interval(0.15, 1, curve: SandikMotion.glide));

  @override
  void initState() {
    super.initState();
    // Sayfa alttan kayarken değil, oturduktan sonra.
    Future<void>.delayed(SandikMotion.surface, () {
      if (!mounted) return;
      SandikHaptic.medium.perform();
      if (!MediaQuery.disableAnimationsOf(context)) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final rozet = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: c.amberFill.withValues(alpha: 0.16),
        shape: BoxShape.circle,
      ),
      child: Icon(widget.ikon, size: 28, color: c.amberText),
    );
    if (MediaQuery.disableAnimationsOf(context)) return rozet;
    // Yerleşim rozetin 56'lık kutusu kadar — halka kutudan TAŞAR ama sayfa
    // yüksekliğini değiştirmez (hareketi azalt'taki hâliyle aynı boy).
    return SizedBox(
      width: 56,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          // Tek halka: 56'dan 96'ya yayılır, solar. Boyası kendi katmanında.
          OverflowBox(
            maxWidth: 96,
            maxHeight: 96,
            child: RepaintBoundary(
            child: AnimatedBuilder(
              animation: _halka,
              builder: (_, __) {
                final t = _halka.value;
                if (t <= 0 || t >= 1) return const SizedBox.shrink();
                final cap = 56 + 40 * t;
                return Container(
                  width: cap,
                  height: cap,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: c.amberFill.withValues(alpha: 0.45 * (1 - t)),
                      width: 2,
                    ),
                  ),
                );
              },
            ),
            ),
          ),
          ScaleTransition(scale: _olcek, child: rozet),
        ],
      ),
    );
  }
}
