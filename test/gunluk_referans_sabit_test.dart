import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/price_service.dart';

import 'helpers/kaynak.dart';

/// Gün başı referansı gün içinde SABİT (kullanıcı kararı 2026-10-02:
/// "Bugün kartı, Performans › GÜNLÜK, Live Activity ve widget hepsi
/// senkron olmalı").
///
/// Referans `fiyat ÷ (1 + yüzde)`; kaynak yüzdeyi iki basamağa yuvarlıyor.
/// Fiyat %0,01 oynayıp yüzde aynı kalınca referans de oynuyor ve her fiyat
/// turunda çekilen gün içi seri farklı bir "açılış" taşıyordu: dört yüzey
/// aynı formülle farklı rakam gösteriyordu (ölçüldü +₺140 / −₺260). Dünkü
/// kapanış gün içinde değişmez — ilk ölçüm kalır; gün değişince ya da
/// taban gerçekten değişince (eşik üstü) yenilenir.
void main() {
  final p = PriceService.instance;
  setUp(() {
    p.sonBilinenFiyatlariTemizle();
    PriceService.saat = () => DateTime(2026, 10, 2, 11, 0);
  });
  tearDown(() {
    p.sonBilinenFiyatlariTemizle();
    PriceService.saat = DateTime.now;
  });

  test('aynı gün, yuvarlama titremesi: ilk referans kalır', () {
    p.testIcinKotasyonYaz('USDTRY=X', 41.25, gunlukPct: -0.40);
    final ilk = p.gunlukReferansFiyat('USDTRY=X')!;
    expect(ilk, closeTo(41.25 / 0.996, 1e-9));
    // Fiyat %0,02 oynadı, yüzde yuvarlanıp aynı kaldı.
    p.testIcinKotasyonYaz('USDTRY=X', 41.26, gunlukPct: -0.40);
    expect(p.gunlukReferansFiyat('USDTRY=X'), ilk,
        reason: 'dünkü kapanış gün içinde oynamaz');
    // Yüzde de güncel kalır (bant onu okur).
    p.testIcinKotasyonYaz('USDTRY=X', 41.30, gunlukPct: -0.28);
    expect(p.gunlukDegisimPct('USDTRY=X'), -0.28);
    expect(p.gunlukReferansFiyat('USDTRY=X'), ilk);
  });

  test('taban gerçekten değişti (eşik üstü): referans yenilenir', () {
    p.testIcinKotasyonYaz('THYAO.IS', 300, gunlukPct: 1.0);
    final ilk = p.gunlukReferansFiyat('THYAO.IS')!;
    // Yeni seans: önceki kapanış %2 farklı.
    p.testIcinKotasyonYaz('THYAO.IS', 300, gunlukPct: -1.0);
    expect(p.gunlukReferansFiyat('THYAO.IS'), isNot(closeTo(ilk, 1e-9)));
    expect(p.gunlukReferansFiyat('THYAO.IS'), closeTo(300 / 0.99, 1e-9));
  });

  test('gün değişince koşulsuz yenilenir', () {
    p.testIcinKotasyonYaz('GC=F', 2500, gunlukPct: 0.10);
    final ilk = p.gunlukReferansFiyat('GC=F')!;
    PriceService.saat = () => DateTime(2026, 10, 3, 9, 0);
    p.testIcinKotasyonYaz('GC=F', 2500.5, gunlukPct: 0.10);
    expect(p.gunlukReferansFiyat('GC=F'), isNot(equals(ilk)));
  });

  test('eşik bir nabızlık titremeden büyük, bir seans tabanından küçük', () {
    expect(PriceService.gunlukReferansToleransi, greaterThan(0.0005));
    expect(PriceService.gunlukReferansToleransi, lessThan(0.01));
  });

  group('kaynak: görünür olunca hemen tazeleme (nabız beklenmez)', () {
    test('Bugün kartı ve Performans sekme görünürlüğünü dinler', () {
      final kart = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
      expect(kart.contains('_gorunurluk = yeni..addListener(_gorunurlukDegisti)'),
          isTrue);
      expect(kart.contains('_gorunurluk?.removeListener(_gorunurlukDegisti)'),
          isTrue, reason: 'dinleyici dispose\'da kaldırılmalı');
      final perf =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      expect(perf.contains('_gorunurluk = yeni..addListener(_gorunurlukDegisti)'),
          isTrue);
      expect(perf.contains('_gorunurluk?.removeListener(_gorunurlukDegisti)'),
          isTrue);
    });
  });
}
