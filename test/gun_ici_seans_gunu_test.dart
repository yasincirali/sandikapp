import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';

/// **"GÜNLÜK" sekmesi DÜMDÜZ bir çizgi çiziyordu.**
///
/// Kullanıcı bildirimi (2026-09-07, Pazar): "günlük grafik için data
/// alınamıyor olabilir mi, normalde yüksek precision ile göstermesi
/// gerekirdi. Dümdüz çizgi sebebi nedir."
///
/// İki bağımsız sebep vardı ve ikisi de burada kilitleniyor:
///
/// 1. **Izgara her zaman BUGÜNE kuruluyordu.** Piyasa kapalıyken (hafta
///    sonu, tatil) Yahoo'nun `range=1d` yanıtı son seansa aittir; o
///    noktalar bugünün 288 slotuna yayılınca seri tek bir değere
///    dönüşüyordu. Karar artık `HistoryService.seansGunu` içinde ve saf
///    olduğu için hafta içi koşan bir testte de doğrulanabiliyor.
///
/// 2. **Y ekseninin asgari bandı %8'di.** Portföyün gün içi hareketi
///    tipik olarak ±%0,5–2 olduğundan gerçek dalgalanma grafik
///    yüksekliğinin onda birine sıkışıyordu.
void main() {
  int ts(DateTime d) => d.millisecondsSinceEpoch;

  group('seans günü — hangi gün çizilir', () {
    test('veri bugüne aitse bugün çizilir', () {
      final now = DateTime(2026, 9, 4, 15, 30); // Cuma
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 4, 15, 25)),
      );
      expect(gun, DateTime(2026, 9, 4));
    });

    test('PAZAR günü CUMA seansı çizilir — düz çizginin sebebi', () {
      // Asıl hata: ızgara Pazar 00:00'a kuruluyor, Cuma kapanışı 288
      // slotun hepsine yayılıyor ve grafik düzleşiyordu.
      final now = DateTime(2026, 9, 6, 11, 0); // Pazar
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 4, 18, 5)), // Cuma kapanışı
      );
      expect(gun, DateTime(2026, 9, 4), reason: 'son seans günü çizilmeli');
      expect(gun.isBefore(DateTime(2026, 9, 6)), isTrue);
    });

    test('resmî tatilde de son seans çizilir (hafta içi olabilir)', () {
      // Kural takvimden değil VERİDEN türetilir; tatil listesi tutmaya
      // gerek yok. Salı tatilse en son veri Pazartesi'ye aittir.
      final now = DateTime(2026, 4, 23, 12, 0);
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 4, 22, 18, 5)),
      );
      expect(gun, DateTime(2026, 4, 22));
    });

    test('hiç veri yoksa bugüne düşülür — boş ızgara üretilmez', () {
      final now = DateTime(2026, 9, 6, 11, 0);
      expect(
        HistoryService.seansGunu(now: now, enSonVeriTs: null),
        DateTime(2026, 9, 6),
      );
    });

    test('gelecek tarihli veri ileri bir güne ızgara kurmaz', () {
      // Saat dilimi kayması Yahoo damgasını bir gün ileri atabilir.
      // Yarına ızgara kurmak "gelecek slotları çizme" kuralıyla
      // birleşince BOŞ grafik demek olurdu.
      final now = DateTime(2026, 9, 4, 15, 0);
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 5, 2, 0)),
      );
      expect(gun, DateTime(2026, 9, 4));
    });
  });

  group('Y ekseni — gün içi hareket ezilmez', () {
    // 250.000 TL'lik portföy, gün içinde %1 hareket (2.500 TL).
    const double ortalama = 250000;
    const double alt = 248750;
    const double ust = 251250;

    ({double minY, double maxY, double interval}) bant(double oran) =>
        gorunurYBandi(
          dataMinY: alt,
          dataMaxY: ust,
          avgY: ortalama,
          asgariBantOrani: oran,
        );

    test('%1 hareket bandın anlamlı bir kısmını doldurur', () {
      final b = bant(gunIciAsgariBantOrani);
      final bantYuksekligi = b.maxY - b.minY;
      final hareket = ust - alt;
      // Hareket, bandın en az beşte birini kaplamalı. Eski %8'lik taban
      // bunu ~%10'a düşürüyordu ve çizgi düz görünüyordu.
      expect(hareket / bantYuksekligi, greaterThan(0.2),
          reason: 'gün içi hareket grafikte okunabilir olmalı');
    });

    test('eski %8 tabanı aynı veriyi ezerdi — regresyon kilidi', () {
      final yeni = bant(gunIciAsgariBantOrani);
      final eski = bant(0.08);
      expect(yeni.maxY - yeni.minY, lessThan(eski.maxY - eski.minY),
          reason: 'gün içi bandı daralmalı');
    });

    test('veri HER ZAMAN bandın içinde kalır', () {
      for (final oran in [gunIciAsgariBantOrani, 0.08]) {
        final b = bant(oran);
        expect(b.minY, lessThanOrEqualTo(alt));
        expect(b.maxY, greaterThanOrEqualTo(ust));
      }
    });

    test('gerçekten düz seride bant kapanmaz (sıfıra bölme yok)', () {
      // Tek fiyat: dataRange 0. Taban olmasaydı band sıfır genişlikte
      // olur ve gürültü tuvale yayılırdı.
      final b = gorunurYBandi(
        dataMinY: ortalama,
        dataMaxY: ortalama,
        avgY: ortalama,
        asgariBantOrani: gunIciAsgariBantOrani,
      );
      expect(b.maxY, greaterThan(b.minY));
      expect(b.interval, greaterThan(0));
    });

    test('sıfır ortalamada band çökmez', () {
      final b = gorunurYBandi(
        dataMinY: 0,
        dataMaxY: 0,
        avgY: 0,
        asgariBantOrani: gunIciAsgariBantOrani,
      );
      expect(b.maxY, greaterThan(b.minY));
      expect(b.minY, greaterThanOrEqualTo(0));
    });
  });
}
