import 'package:flutter/material.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';

/// Hata görünümü.
///
/// Hata anı, arayüzün en çok güven vermesi gereken andır: içerik ani biçimde
/// yerine geçerse "bozuldu" hissi verir. Bu yüzden görünüm sert değil,
/// kısa bir fade + yukarı kayma ile belirir.
class SandikErrorView extends StatelessWidget {
  final Object error;
  final VoidCallback? onRetry;

  const SandikErrorView({super.key, required this.error, this.onRetry});

  @override
  Widget build(BuildContext context) {
    // Erişilebilirlik: "hareketi azalt" açıkken içerik doğrudan görünür.
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final content = Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, color: context.c.loss, size: 40),
            const SizedBox(height: 16),
            Text(
              friendlyError(error),
              textAlign: TextAlign.center,
              style: context.t.titleMedium?.copyWith(color: context.c.text58),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              // SandikTappable sarmalı: her basılabilir eleman basıldığını
              // hissettirmeli. Tekrar deneme bir yeniden-yükleme eylemi,
              // seçim değil — bu yüzden medium ton.
              SandikTappable(
                onTap: onRetry,
                haptic: SandikHaptic.medium,
                semanticLabel: 'Tekrar dene',
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SandikSpace.lg,
                    vertical: SandikSpace.sm + 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.c.amberFill.withValues(alpha: 0.12),
                    borderRadius: SandikRadius.mdAll,
                    border: Border.all(
                      color: context.c.amberFill.withValues(alpha: 0.28),
                    ),
                  ),
                  child: Text(
                    'Tekrar Dene',
                    style: context.t.titleMedium?.copyWith(
                      color: context.c.amberText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (reduceMotion) return content;

    // 0 → 1 tek atış: hata görünümü bir kez belirir, tekrar animasyonlanmaz.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: SandikMotion.surface,
      curve: SandikMotion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: content,
    );
  }
}
