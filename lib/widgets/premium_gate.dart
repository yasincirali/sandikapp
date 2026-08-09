import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/preferences_provider.dart';
import '../screens/paywall_screen.dart';
import '../services/analytics_service.dart';
import '../theme/sandik.dart';

/// Paywall kapalıyken kullanılabilecek statik chip. Widget'ın statelessliğini
/// bozmamak için PremiumChip'i çağıran taraf paywallVisibleProvider'ı izler.

/// Premium'a bağlı içerikleri saran widget. Kullanıcı premium ise [child]'ı
/// olduğu gibi gösterir. Değilse [child]'ı arka planda soluk bırakır,
/// üzerine kilit + "Premium'da açık" overlay koyar. Kullanıcı üzerine
/// dokununca paywall açılır.
///
/// Kullanım:
///   PremiumGate(
///     feature: 'indicator_adx',
///     source: 'signal_settings',
///     child: AdxIndicatorRow(),
///   )
class PremiumGate extends ConsumerWidget {
  final String feature;
  final String source;
  final Widget child;

  /// Fallback UI. Verilmezse default kilit overlay'i kullanılır.
  final Widget? fallback;

  const PremiumGate({
    super.key,
    required this.feature,
    required this.source,
    required this.child,
    this.fallback,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Paywall kapalıysa premium sistem hiç yokmuş gibi davran → child'ı olduğu
    // gibi göster, kilit overlay çizme, tap paywall açmasın.
    final paywallOn = ref.watch(paywallVisibleProvider);
    if (!paywallOn) return child;
    final unlocked = ref.watch(effectivePremiumProvider);
    if (unlocked) return child;

    if (fallback != null) {
      return GestureDetector(
        onTap: () => _openPaywall(context),
        child: fallback,
      );
    }

    return GestureDetector(
      onTap: () => _openPaywall(context),
      child: Stack(
        children: [
          Opacity(opacity: 0.35, child: IgnorePointer(child: child)),
          Positioned.fill(
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: context.c.background.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(SandikRadius.md),
                border: Border.all(
                  color: context.c.amberFill.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lock_rounded,
                      size: 16, color: context.c.amberText),
                  const SizedBox(width: 6),
                  Text(
                    'Premium',
                    style: context.t.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.c.amberText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openPaywall(BuildContext context) {
    AnalyticsService.instance.logPremiumGateShown(feature: feature);
    PaywallScreen.show(context, source: source);
  }
}

/// Küçük inline "Premium" chip'i — liste satırlarında premium olmayanları
/// işaretlemek için. `PremiumGate`'in içine değil, `trailing`e koyulabilir.
class PremiumChip extends StatelessWidget {
  const PremiumChip({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: context.c.amberFill.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(SandikRadius.sm),
        border: Border.all(color: context.c.amberFill.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_rounded, size: 10, color: context.c.amberText),
          const SizedBox(width: 4),
          Text('Premium',
              style: context.t.labelSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: context.c.amberText)),
        ],
      ),
    );
  }
}
