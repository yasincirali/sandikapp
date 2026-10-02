import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Widget ve Live Activity yazımı fiyat turu bitmeden yapılmaz (2026-10-02
/// müşteri testi).
///
/// Portföy dinleyicisi soğuk açılışta ilk yayını (veritabanındaki fiyatla)
/// alıp `HomeWidgetService.updateWithChart` / `LiveActivityService.sync`
/// çağırıyordu. İkisi gün içi seriyi ORTAK önbellekten ister ve boşsa çeker:
/// seri altının gün başı referansı yokken kuruluyor, "taze" damgasıyla
/// önbelleğe giriyor ve Bugün kartı 30 sn boyunca onu kullanıyordu
/// (−₺8.713 → +₺6.551, işaret ters). Davranış `_AuthGate`'in build'inde,
/// widget testiyle kurmak bütün uygulamayı ayağa kaldırmak demek; kural
/// kaynakta kilitlenir.
void main() {
  final kaynak = ekranKaynagiSync('lib/main.dart');

  test('dinleyici, tur sürerken yazımı tur sonuna bırakır', () {
    final dinleyici = kaynak.indexOf('final snapshot = yerlesik;');
    expect(dinleyici, greaterThan(0));
    final kapi = kaynak.indexOf('notifier.fiyatTuruSuruyor', dinleyici);
    final ertele =
        kaynak.indexOf('_yuzeyYaziminiTurSonunaBirak(notifier)', dinleyici);
    final yaz = kaynak.indexOf('_gunIciYuzeyleriniYaz(snapshot)', dinleyici);
    expect(kapi, greaterThan(dinleyici));
    expect(ertele, greaterThan(kapi));
    expect(yaz, greaterThan(ertele),
        reason: 'doğrudan yazım tur kapısından SONRA gelmeli');
  });

  test('ertelenen yazım turu ve bir kareyi bekler, en güncel defteri yazar',
      () {
    final i = kaynak.indexOf('void _yuzeyYaziminiTurSonunaBirak(');
    expect(i, greaterThan(0));
    final govde = kaynak.substring(i, kaynak.indexOf('\n  }\n', i));
    expect(govde, contains('fiyatTurunuVeKareyiBekle('));
    expect(govde, contains('ref.read(portfolioProvider)'));
    expect(govde, contains('_gunIciYuzeyleriniYaz(son)'));
  });

  test('widget ve Live Activity çağrıları yalnızca ortak yazım metodunda', () {
    expect('updateWithChart('.allMatches(kaynak).length, 2,
        reason: 'biri _gunIciYuzeyleriniYaz, biri _gunIciSeriGeldi');
    final i = kaynak.indexOf('void _gunIciYuzeyleriniYaz(');
    final govde = kaynak.substring(i, kaynak.indexOf('\n  }\n', i));
    expect(govde, contains('HomeWidgetService.instance.updateWithChart('));
    expect(govde, contains('LiveActivityService.instance.sync('));
  });
}
