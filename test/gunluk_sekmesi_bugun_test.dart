import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// GÜNLÜK sekmesi HER ZAMAN bugünü çizer.
///
/// ## Kullanıcı kararı (2026-09-13)
/// "Grafik 12 Eylül 20:55'e kadar gidiyor, sonrasında direkt şimdiki ana
/// atlıyor. Burada sadece günlük grafik bulunmalı; ayın 13'ünde günlük
/// tabında 12 Eylül verisini görmemeliyim."
///
/// ## Neden eski davranış vardı ve neden DEĞİŞTİ
/// `seansGunu` 2026-09-07'de eklendi: piyasa kapalıyken Yahoo'nun
/// `range=1d` yanıtı SON SEANSA ait olduğu için ızgarayı bugüne kurmak
/// dümdüz bir çizgi üretiyordu ("data alınamıyor olabilir mi?").
/// Çözüm, veriyi ait olduğu güne çizmekti.
///
/// O çözüm İKİ yeni sorun doğurdu:
///
///   1. **Sekme adı yalan söylüyordu.** 13 Eylül'de "GÜNLÜK" sekmesi
///      12 Eylül'ü gösteriyordu.
///   2. **Seri ile ucu ayrışıyordu.** Servis seriyi son seansın son
///      damgasında (Cuma 20:55) bitiriyor, ekran ise ucuna CANLI toplamı
///      ekliyordu. Aradaki saatlerde hiçbir nokta yok — grafik düz gidip
///      sonra "şimdi"ye ATLIYORDU. Kullanıcının gördüğü tam olarak budur.
///
/// Düz çizgi artık kabul edilebilir, çünkü ekranda onu AÇIKLAYAN bir rozet
/// var ("BORSA KAPALI" / "SON VERİ" — `piyasa_kapali_etiketi.dart`).
/// 2026-09-07'de o rozet yoktu; düz çizgi sessizdi ve bu yüzden korkutucuydu.
/// Dürüst ve açıklanmış bir düz çizgi, yanlış güne çizilmiş bir seriden iyidir.
void main() {
  group('seansGunu — HER ZAMAN bugün', () {
    test('Pazar günü BUGÜNÜ döner (Cuma verisi olsa bile)', () {
      // Eski davranış Cuma 11 Eylül'ü döndürüyordu.
      final pazar = DateTime(2026, 9, 13, 20, 15);
      final cumaVeri = DateTime(2026, 9, 11, 18).millisecondsSinceEpoch;

      expect(
        HistoryService.seansGunu(now: pazar, enSonVeriTs: cumaVeri),
        DateTime(2026, 9, 13),
        reason: '13 Eylül\'de GÜNLÜK sekmesi 12 Eylül verisi göstermemeli',
      );
    });

    test('hafta içi de bugün', () {
      final cuma = DateTime(2026, 9, 11, 14);
      expect(
        HistoryService.seansGunu(
          now: cuma,
          enSonVeriTs: DateTime(2026, 9, 11, 13).millisecondsSinceEpoch,
        ),
        DateTime(2026, 9, 11),
      );
    });

    test('veri yoksa bugün', () {
      final g = DateTime(2026, 9, 13, 9);
      expect(HistoryService.seansGunu(now: g, enSonVeriTs: null),
          DateTime(2026, 9, 13));
    });

    test('ileri tarihli damga bugüne çekilir', () {
      // Saat dilimi kayması: ileri bir güne ızgara kurmak boş grafik demek.
      final g = DateTime(2026, 9, 13, 9);
      expect(
        HistoryService.seansGunu(
          now: g,
          enSonVeriTs: DateTime(2026, 9, 14, 3).millisecondsSinceEpoch,
        ),
        DateTime(2026, 9, 13),
      );
    });

    test('gece yarısından hemen sonra da bugün', () {
      // Sınır: 00:05'te dünün verisi hâlâ en yeni damgadır.
      final geceYarisi = DateTime(2026, 9, 13, 0, 5);
      expect(
        HistoryService.seansGunu(
          now: geceYarisi,
          enSonVeriTs: DateTime(2026, 9, 12, 23, 55).millisecondsSinceEpoch,
        ),
        DateTime(2026, 9, 13),
        reason: 'GÜNLÜK her zaman içinde bulunulan takvim günü',
      );
    });
  });

  group('gunIciSagUc — seri ŞİMDİ\'de biter, kuyruk yok', () {
    int norm(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      return DateTime(d.year, d.month, d.day, d.hour, (d.minute ~/ 5) * 5)
          .millisecondsSinceEpoch;
    }

    test('seansSonuTs null iken sağ uç ŞİMDİ ve kapalı bölge YOK', () {
      // `seansGunu` artık hep bugünü döndürdüğü için `gecmisSeans` hiçbir
      // zaman true olmuyor; dolayısıyla `seansSonuTs` daima null.
      // Seri ŞİMDİ'de bitince ekranın eklediği canlı uç noktası serinin
      // devamına düşüyor — ATLAMA ortadan kalkıyor.
      final now = DateTime(2026, 9, 13, 20, 15);
      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: null,
        normalizeSlot: norm,
      );

      expect(r.sagUc, norm(now.millisecondsSinceEpoch));
      expect(r.piyasaKapali, isNull,
          reason: 'kapalı kuyruk kaldırıldı — gri/kesikli bölge yok');
    });
  });
}
