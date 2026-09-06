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
    return showModalBottomSheet<void>(
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
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.text20,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: c.amberFill.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(_ikon, size: 28, color: c.amberText),
            ),
          ),
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
