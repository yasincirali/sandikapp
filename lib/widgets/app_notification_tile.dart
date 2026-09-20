import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../theme/sandik.dart';

/// Genel bildirim satırı — `PriceAlertTile` / `_SignalTile` ile AYNI görsel
/// dil (yuvarlak ikon + başlık + tür rozeti + alt satır + sağda eylem).
///
/// Tür yalnızca ikonu ve rozet metnini belirler; sayısal bir alan yok, o
/// yüzden tek widget dört türe hizmet edebiliyor (alarm/sinyalde durum
/// farklıydı — bkz. `PriceAlertTile` notu).
class AppNotificationTile extends StatelessWidget {
  final AppNotification bildirim;
  final bool faded;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onDelete;

  const AppNotificationTile({
    super.key,
    required this.bildirim,
    required this.faded,
    required this.onTap,
    required this.onDismiss,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final (IconData icon, String rozet) = switch (bildirim.type) {
      AppNotification.partnerInvite => (
          Icons.people_alt_rounded,
          l10n.notifTypePartner
        ),
      AppNotification.dailyBrief => (
          Icons.wb_sunny_rounded,
          l10n.notifTypeDailyBrief
        ),
      AppNotification.weeklySummary => (
          Icons.calendar_view_week_rounded,
          l10n.notifTypeWeekly
        ),
      AppNotification.monthlySummary => (
          Icons.calendar_month_rounded,
          l10n.notifTypeMonthly
        ),
      AppNotification.watchlistMove => (
          Icons.visibility_rounded,
          l10n.notifTypeWatchlist
        ),
      AppNotification.inflationDay => (
          Icons.trending_up_rounded,
          l10n.notifTypeInflation
        ),
      _ => (Icons.event_note_rounded, l10n.notifTypeReminder),
    };
    // Bilgi bildirimi: yön/kazanç anlamı yok, marka vurgusu (amber).
    final Color color = context.c.amberText;

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
                          bildirim.title,
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
                        child: Text(rozet,
                            style: context.t.bodySmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: color.withValues(alpha: alphaFactor),
                                decoration: TextDecoration.none)),
                      ),
                    ],
                  ),
                  const SizedBox(height: SandikSpace.xs),
                  Text(
                    faded ? _tarih(context, bildirim.sentAt) : bildirim.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
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

  String _tarih(BuildContext context, DateTime d) {
    final now = DateTime.now();
    final saat = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return context.l10n.notifToday(saat);
    }
    return '${d.day}.${d.month}.${d.year}';
  }
}
