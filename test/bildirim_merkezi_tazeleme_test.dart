import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Çan sayfasının sunucu listeleri bayatlamasın (yasin, 2026-10-06:
/// "aylık özeti kapattım, bildirim merkezinde göremedim").
///
/// Aylık/haftalık özet, brifing, TÜFE vb. `app_notifications`'a SUNUCUDA
/// yazılır (0066) ve uygulama arkadayken gelir. Liste yalnızca açılışta
/// okunuyordu; süreç arkada canlı kaldıysa yeni kayıt çanda hiç
/// görünmüyordu. Fiyat alarmı listesi öne dönüşte tazeleniyordu, genel
/// liste unutulmuştu. Bu test ikisinin birlikte tazelendiğini kilitler.
void main() {
  test('öne dönüşte iki sunucu listesi de tazelenir', () {
    final main = ekranKaynagiSync('lib/main.dart');
    expect(main,
        contains('priceAlertNotificationProvider.notifier).refresh()'));
    expect(main, contains('appNotificationProvider.notifier).refresh()'));
  });

  test('çan açılışı ve aşağı çekme listeleri tazeler', () {
    final ana = ekranKaynagiSync('lib/screens/home_screen.dart');
    expect(ana, contains('appNotificationProvider.notifier).refresh()'));
    expect(ana,
        contains('priceAlertNotificationProvider.notifier).refresh()'));
    // Hem çan açılışında hem RefreshIndicator'da çağrılır.
    expect(
      RegExp(r'_sunucuBildirimleriniTazele\(\);').allMatches(ana).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('geçici hata eldeki genel listeyi silmez', () {
    final p = ekranKaynagiSync('lib/providers/app_notification_provider.dart');
    expect(p, contains('if (!state.hasValue) state = AsyncError(e, st);'));
  });
}
