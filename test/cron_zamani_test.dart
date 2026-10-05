import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/cron_zamani.dart';

/// Push Teşhisi "hiç çalışmamış" uyarısı aylık işleri ayırır (2026-09-21):
/// ayın 1'i / 3'ü koşan işler ilk slotlarından önce kurulduysa arıza değil.
void main() {
  test('gün-ay alanı sayıysa aylık', () {
    expect(cronAyGunu('30 6 1 * *'), 1); // monthly-summary (0067)
    expect(cronAyGunu('30 7 3,4 * *'), 3); // monthly-summary (0093)
    expect(cronAyGunu('5 7 3 * *'), 3); // fetch-inflation
    expect(cronAyGunu('15 7 4 * *'), 4); // calendar-nudge retry
  });

  test('gün aralığı aylık, ilk gün döner (0110)', () {
    expect(cronAyGunu('5 7 3-12 * *'), 3); // fetch-inflation
    expect(cronAyGunu('30 7 3-12 * *'), 3); // monthly-summary
    expect(cronAyGunu('0 0 1,5-9 * *'), 1);
    expect(cronAyGunu('0 0 9-3 * *'), isNull, reason: 'ters aralık');
    expect(cronAyGunu('0 0 3-40 * *'), isNull);
  });

  test('yıldız, hafta günü ve aralıklar aylık değil', () {
    expect(cronAyGunu('0 7-15 * * *'), isNull); // analyze-signals
    expect(cronAyGunu('45 6 * * 2-5'), isNull); // daily-brief
    expect(cronAyGunu('*/30 5-18 * * *'), isNull); // check-price-alerts
    expect(cronAyGunu('50 22 * * 0'), isNull); // haftalık temizlik
  });

  test('bozuk ifade null', () {
    expect(cronAyGunu(''), isNull);
    expect(cronAyGunu('0 7'), isNull);
    expect(cronAyGunu('0 7 40 * *'), isNull);
  });
}
