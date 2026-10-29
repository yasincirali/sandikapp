import 'package:flutter/material.dart';

import '../l10n/l10n.dart';
import '../models/asset_type.dart';
import '../models/price_alert_notification.dart';
import '../theme/sandik.dart';
import '../utils/tr_format.dart';
import 'bildirim_satiri.dart';

/// Fiyat alarmı satırı — `_SignalTile` ile AYNI görsel dil.
///
/// Ayrı bir widget olması, `_SignalTile`'ı iki modele birden hizmet eder
/// hâle getirmemek için: o sınıf `SignalAlert`'in al/sat/nötr ve güven
/// alanlarına dayanıyor, alarmda ikisi de yok. Ortak olan kart iskeleti
/// (yuvarlak ikon + ad + rozet + alt satır + sağdaki eylem) burada
/// tekrarlanıyor; tekrar bilinçli, çünkü alternatifi iki farklı anlamı tek
/// parametreleştirilmiş widget'a sıkıştırmaktı. 2026-10-29: iskelet
/// (açılır davranış dahil) `BildirimSatiri`'ne çıktı; MODEL ayrılığı sürüyor,
/// bu sınıf alarm alanlarını metne çevirir.
class PriceAlertTile extends StatelessWidget {
  final PriceAlertNotification bildirim;
  final bool faded;
  final VoidCallback onTap;
  final VoidCallback? onDismiss;
  final VoidCallback? onDelete;

  /// Test/vitrin: satır açık başlasın.
  final bool baslangictaAcik;

  /// [onTap]: alarmın varlığı — 2026-10-29'dan beri açık satırdaki "Aç".
  const PriceAlertTile({
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
    // Yön rengi sinyaldekiyle AYNI sözleşme: yukarı = gain, aşağı = loss.
    // Alarm "iyi haber" demek değil (kullanıcı düşüşe de alarm kurar) ama
    // ok yönü ile renk tutarlı olmalı, aksi halde ikisi çelişir.
    final yukari = bildirim.yukari;
    final simge = alarmFiyatSimgesi(bildirim.symbol);
    // Kullanıcının görmek istediği sayı TETİKLENME fiyatıdır, hedef değil:
    // hedefi zaten kendisi koydu. Simge sembolün kendi biriminde
    // (2026-10-29): ABD hissesi alarmı "₺255,10" yazıyordu, sayı dolardı.
    // `fmtFiyat` 1'in altını 4 anlamlı haneyle yazar (SHIB ₺0,0004).
    String fiyat(double v) => fmtFiyat(v, symbol: simge ?? '');
    return BildirimSatiri(
      renk: yukari ? context.c.gain : context.c.loss,
      ikon: yukari
          ? Icons.notifications_active_rounded
          : Icons.notifications_active_outlined,
      baslik: bildirim.label,
      kapaliBaslikSatiri: 1,
      rozet: context.l10n.notifTypeAlarm,
      govde: context.l10n.alarmTileBody(
          fiyat(bildirim.triggeredPrice), fiyat(bildirim.targetPrice)),
      // Push gövdesindeki "tek seferlik, kapatıldı" bilgisi çanda da var;
      // kapalı satırı kalabalıklaştırmasın diye yalnız açıkken.
      ekAciklama: context.l10n.alarmTileOneShot,
      zaman: _tarih(context, bildirim.sentAt),
      faded: faded,
      onAc: onTap,
      onDismiss: onDismiss,
      onDelete: onDelete,
      baslangictaAcik: baslangictaAcik,
    );
  }

  /// `sent_at` UTC gelir; yerel saate çevrilir (genel bildirim satırıyla
  /// aynı kural — çevrilmeden TR'de saat 3 geri yazılıyordu).
  String _tarih(BuildContext context, DateTime ham) {
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
