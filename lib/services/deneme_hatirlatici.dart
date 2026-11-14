import 'package:intl/intl.dart';

import '../l10n/generated/app_localizations.dart';
import 'notification_service.dart';
import 'satin_alma_service.dart';

/// Ücretsiz deneme bitmeden önce TEK dürüst hatırlatma (Ar-Ge 14 Kas #3).
///
/// Neden: paywall çizelgesi "Bugün · 7. gün ilk ödeme" diyordu; arada
/// hatırlatma yoktu ve Apple denemeler için hatırlatma göndermez. Sürpriz
/// ödeme = iade isteği + bir yıldız. Hatırlatma vaadi deneme başlatmanın
/// önündeki korkuyu da kaldırır (paywall'daki "Hatırlatırız" düğümü).
///
/// Kurallar:
/// - Yalnız denemede ve yenileneceği BİLİNİYORKEN (iptal edilmemiş);
///   iptal edilmiş denemede var olan hatırlatma kaldırılır.
/// - Bitişten [denemeHatirlatmaOnce] önce; o an geçmişse (bitişe 2 günden
///   az) kurulmaz: geç gelen "2 gün kaldı" yanlış bilgidir.
/// - Bildirim izni yoksa sessiz: izin sorulmaz, uyarı gösterilmez.
/// - Sabit kimlik ([bildirimId]): hak her tazelendiğinde yeniden kurmak
///   öncekinin yerine geçer, çift bildirim olmaz.
/// - Tutar yalnız mağazanın priceString'i (uydurma sayı yasak); bilinmiyorsa
///   tutarsız metin.
/// - Dönem bilinmiyorsa (mağaza yanıt vermedi, `null`) hiçbir şey
///   değiştirilmez: okuma hatası kurulu hatırlatmayı silmesin.
const denemeHatirlatmaOnce = Duration(days: 2);

/// Saf karar: hatırlatma ne zaman; kurulmayacaksa null.
DateTime? denemeHatirlatmaZamani(AbonelikDonemi d, DateTime simdi) {
  final bitis = d.bitis;
  if (!d.deneme || !d.yenilenecek || bitis == null) return null;
  final zaman = bitis.subtract(denemeHatirlatmaOnce);
  return zaman.isAfter(simdi) ? zaman : null;
}

/// Platform çağrıları; testte sahtesi verilir.
abstract class YerelBildirimPlatformu {
  Future<bool> izinVar();
  Future<void> planla({
    required int id,
    required DateTime zaman,
    required String baslik,
    required String govde,
    required String payload,
  });
  Future<void> iptal(int id);
}

/// Uygulamadaki platform: [NotificationService].
class BildirimServisiPlatformu implements YerelBildirimPlatformu {
  const BildirimServisiPlatformu();

  @override
  Future<bool> izinVar() => NotificationService.instance.bildirimIzniVar();

  @override
  Future<void> planla({
    required int id,
    required DateTime zaman,
    required String baslik,
    required String govde,
    required String payload,
  }) =>
      NotificationService.instance.planliBildirimKur(
          id: id, zaman: zaman, baslik: baslik, govde: govde, payload: payload);

  @override
  Future<void> iptal(int id) =>
      NotificationService.instance.planliBildirimIptal(id);
}

class DenemeHatirlatici {
  const DenemeHatirlatici(this.platform);

  final YerelBildirimPlatformu platform;

  /// Sabit kimlik; başka yerel bildirimlerin `Object.hash` kimlikleriyle
  /// çakışma olasılığı ihmal edilebilir.
  static const bildirimId = 141120261;

  /// [d] her yeni okunduğunda çağrılır (`abonelikDonemiProvider`).
  Future<void> guncelle(AbonelikDonemi? d,
      {required AppLocalizations l10n, DateTime? simdi}) async {
    if (d == null) return;
    final zaman = denemeHatirlatmaZamani(d, simdi ?? DateTime.now());
    if (zaman == null || !await platform.izinVar()) {
      await platform.iptal(bildirimId);
      return;
    }
    final dil = l10n.localeName == 'en' ? 'en_US' : 'tr_TR';
    final tarih = DateFormat('d MMMM', dil).format(d.bitis!.toLocal());
    final tutar = d.ilkOdemeTutari;
    await platform.planla(
      id: bildirimId,
      zaman: zaman,
      baslik: l10n.denemeHatirlatmaBaslik,
      govde: tutar == null
          ? l10n.denemeHatirlatmaGovdeTutarsiz(tarih)
          : l10n.denemeHatirlatmaGovde(tarih, tutar),
      payload: NotificationService.denemeHatirlatmaPayload,
    );
  }
}
