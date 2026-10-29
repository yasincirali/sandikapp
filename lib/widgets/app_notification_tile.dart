import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/app_notification.dart';
import '../theme/sandik.dart';
import 'bildirim_satiri.dart';

/// Genel bildirim satırı — `PriceAlertTile` / `_SignalTile` ile AYNI görsel
/// dil (yuvarlak ikon + başlık + tür rozeti + alt satır + sağda eylem);
/// ortak iskelet `BildirimSatiri`.
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

  /// Test/vitrin: satır açık başlasın.
  final bool baslangictaAcik;

  /// [onTap]: bildirimin varış yeri — 2026-10-29'dan beri satıra dokunmak
  /// değil, açık satırdaki "Aç" düğmesi çağırır.
  const AppNotificationTile({
    super.key,
    required this.bildirim,
    required this.faded,
    required this.onTap,
    required this.onDismiss,
    required this.onDelete,
    this.baslangictaAcik = false,
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
      // 0086: temettü önerisi — dokununca ön dolu temettü diyaloğu.
      AppNotification.temettu => (
          Icons.savings_outlined,
          l10n.notifTypeDividend
        ),
      // 0169: günlük yüzde alarmı — fiyat alarmıyla aynı zil ikonu.
      // 0170: gösterge ve çizgi alarmı — aynı zil ikonu.
      AppNotification.yuzdeAlarm ||
      AppNotification.gostergeAlarm ||
      AppNotification.cizimAlarm =>
        (
          Icons.notifications_active_rounded,
          l10n.notifTypeAlarm
        ),
      _ => (Icons.event_note_rounded, l10n.notifTypeReminder),
    };
    // Bilgi bildirimi: yön/kazanç anlamı yok, marka vurgusu (amber).
    //
    // İskelet ve açılır davranış `BildirimSatiri`'nde (2026-10-29): dokunuş
    // tam metni açar, gezinme açık satırdaki "Aç"ta. Soluk (geçmiş) satır
    // da gövdeyi gösterir; tarih eskiden gövdenin YERİNE yazılıyordu.
    return BildirimSatiri(
      renk: context.c.amberText,
      ikon: icon,
      // Üç satıra kadar (2026-10-02 müşteri testi): başlığın asıl bilgisi
      // sonda ("… son kapanışta %9,5 düştü") ve tek satırda üç noktanın
      // altında kalıyordu. Açık satırda sınır yok.
      baslik: bildirim.title,
      kapaliBaslikSatiri: 3,
      rozet: rozet,
      govde: bildirim.body,
      zaman: _tarih(context, bildirim.sentAt),
      faded: faded,
      onAc: onTap,
      onDismiss: onDismiss,
      onDelete: onDelete,
      baslangictaAcik: baslangictaAcik,
    );
  }

  String _tarih(BuildContext context, DateTime ham) {
    // `sent_at` sunucudan UTC gelir (`DateTime.parse` "+00:00" → UTC);
    // yerel saate çevrilmeden TR'de saat 3 geri, gece yarısı civarında
    // gün de yanlış yazıyordu.
    final d = ham.toLocal();
    final now = DateTime.now();
    final saat = '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return context.l10n.notifToday(saat);
    }
    return '${d.day}.${d.month}.${d.year} $saat';
  }
}
