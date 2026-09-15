import 'package:flutter/material.dart';

import '../models/price_alert_notification.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';

/// Fiyat alarmı satırı — `_SignalTile` ile AYNI görsel dil.
///
/// Ayrı bir widget olması, `_SignalTile`'ı iki modele birden hizmet eder
/// hâle getirmemek için: o sınıf `SignalAlert`'in al/sat/nötr ve güven
/// alanlarına dayanıyor, alarmda ikisi de yok. Ortak olan kart iskeleti
/// (yuvarlak ikon + ad + rozet + alt satır + sağdaki eylem) burada
/// tekrarlanıyor; tekrar bilinçli, çünkü alternatifi iki farklı anlamı tek
/// parametreleştirilmiş widget'a sıkıştırmaktı.
class PriceAlertTile extends StatelessWidget {
  final PriceAlertNotification bildirim;
  final bool faded;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onDelete;

  const PriceAlertTile({
    super.key,
    required this.bildirim,
    required this.faded,
    required this.onTap,
    required this.onDismiss,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    // Yön rengi sinyaldekiyle AYNI sözleşme: yukarı = gain, aşağı = loss.
    // Alarm "iyi haber" demek değil (kullanıcı düşüşe de alarm kurar) ama
    // ok yönü ile renk tutarlı olmalı, aksi halde ikisi çelişir.
    final yukari = bildirim.yukari;
    final Color color = yukari ? context.c.gain : context.c.loss;
    final IconData icon = yukari
        ? Icons.notifications_active_rounded
        : Icons.notifications_active_outlined;

    final double alphaFactor = faded ? 0.45 : 1.0;
    final double bgAlpha = faded ? 0.05 : 0.10;
    final double borderAlpha = faded ? 0.12 : 0.28;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: bgAlpha),
          borderRadius: BorderRadius.circular(SandikRadius.md),
          border: Border.all(
              color: color.withValues(alpha: borderAlpha), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18 * alphaFactor),
                shape: BoxShape.circle,
              ),
              child: Icon(icon,
                  color: color.withValues(alpha: alphaFactor), size: 20),
            ),
            const SizedBox(width: SandikSpace.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          bildirim.label,
                          overflow: TextOverflow.ellipsis,
                          style: context.t.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: context.c.text90
                                  .withValues(alpha: alphaFactor),
                              decoration: TextDecoration.none),
                        ),
                      ),
                      const SizedBox(width: SandikSpace.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.18 * alphaFactor),
                          borderRadius: BorderRadius.circular(SandikRadius.sm),
                        ),
                        child: Text('ALARM',
                            style: context.t.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: color.withValues(alpha: alphaFactor),
                                decoration: TextDecoration.none)),
                      ),
                    ],
                  ),
                  const SizedBox(height: SandikSpace.xs),
                  // Kullanıcının görmek istediği sayı TETİKLENME fiyatıdır,
                  // hedef değil: hedefi zaten kendisi koydu.
                  Text(
                    faded
                        ? _tarih(bildirim.sentAt)
                        : '${fmtTRY(bildirim.triggeredPrice)} · hedef '
                            '${fmtTRY(bildirim.targetPrice)}',
                    style: context.t.bodySmall?.copyWith(
                        color: context.c.text58.withValues(alpha: alphaFactor),
                        decoration: TextDecoration.none),
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                icon: Icon(Icons.close_rounded,
                    size: 18, color: context.c.text36),
                onPressed: onDismiss,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              )
            else if (onDelete != null)
              IconButton(
                icon: Icon(Icons.delete_outline_rounded,
                    size: 18, color: context.c.text36),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
          ],
        ),
      ),
    );
  }

  String _tarih(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Bugün ${d.hour.toString().padLeft(2, '0')}:'
          '${d.minute.toString().padLeft(2, '0')}';
    }
    return '${d.day}.${d.month}.${d.year}';
  }
}

