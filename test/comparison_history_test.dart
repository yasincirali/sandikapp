import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/price_service.dart';

/// Karşılaştırma altyapısı — normalize getiri ve altın çevrimi.
///
/// Bu katmanın ürün değeri şu soruda: *"portföyümde OLMAYAN bir varlık son
/// 3 ayda ne yapmış, elimdekilere göre nasıl?"* Kullanıcının o varlık için
/// alım fiyatı olmadığından tek anlamlı ölçü dönem başına göre yüzde
/// değişimdir — testler bu değişmezi kilitliyor.

void main() {
  group('normalizeSeries — dönem başı %0', () {
    test('ilk nokta her zaman sıfır', () {
      final r = normalizeSeries({1: 100.0, 2: 150.0, 3: 200.0})!;
      expect(r.points[1], 0.0);
    });

    test('yüzde değişim doğru hesaplanır', () {
      final r = normalizeSeries({1: 100.0, 2: 150.0, 3: 200.0})!;
      expect(r.points[2], closeTo(50.0, 1e-9));
      expect(r.points[3], closeTo(100.0, 1e-9));
      expect(r.totalReturnPct, closeTo(100.0, 1e-9));
    });

    test('düşüş negatif yüzde verir', () {
      final r = normalizeSeries({1: 200.0, 2: 150.0})!;
      expect(r.points[2], closeTo(-25.0, 1e-9));
      expect(r.totalReturnPct, closeTo(-25.0, 1e-9));
    });

    test('ham ilk/son fiyat korunur (₺X → ₺Y gösterimi için)', () {
      final r = normalizeSeries({10: 42.5, 20: 51.0})!;
      expect(r.firstPrice, 42.5);
      expect(r.lastPrice, 51.0);
    });

    test('anahtar sırası karışık gelse de ZAMANA göre sıralanır', () {
      // Map literal sırası kronolojik değil — normalize sıralamalı.
      final r = normalizeSeries({30: 200.0, 10: 100.0, 20: 150.0})!;
      expect(r.firstPrice, 100.0, reason: 'en küçük ts ilk fiyat olmalı');
      expect(r.lastPrice, 200.0);
      expect(r.points[10], 0.0);
    });

    test('farklı ölçekli iki varlık aynı düzlemde kıyaslanabilir', () {
      // Asıl amaç bu: ₺12 hisse ile ₺4.800 altın aynı grafikte.
      final ucuz = normalizeSeries({1: 12.0, 2: 13.2})!;
      final pahali = normalizeSeries({1: 4800.0, 2: 5280.0})!;
      expect(ucuz.totalReturnPct, closeTo(pahali.totalReturnPct, 1e-9));
      expect(ucuz.totalReturnPct, closeTo(10.0, 1e-9));
    });
  });

  group('normalizeSeries — bozuk veri', () {
    test('tek nokta null döner (çizgi oluşmaz)', () {
      expect(normalizeSeries({1: 100.0}), isNull);
    });

    test('boş seri null döner', () {
      expect(normalizeSeries({}), isNull);
    });

    test('ilk fiyat sıfırsa null — sıfıra bölme engellenir', () {
      expect(normalizeSeries({1: 0.0, 2: 50.0}), isNull);
    });

    test('ilk fiyat negatifse null', () {
      expect(normalizeSeries({1: -5.0, 2: 50.0}), isNull);
    });
  });

  group('altın çevrimi — tek kaynak', () {
    test('ons TRY fiyatı 22 ayar grama iner', () {
      // 1 ons = 31.1035 g, 22/24 saflık.
      final gram = PriceService.gram22kFromXauTry(31103.5);
      expect(gram, closeTo(1000.0 * (22 / 24), 1e-6));
    });

    test('ağırlık çarpanları tabloya uyar', () {
      expect(PriceService.goldWeightFactor('ALTIN_GRAM'), 1.0);
      expect(PriceService.goldWeightFactor('ALTIN_CEYREK'), 1.75);
      expect(PriceService.goldWeightFactor('ALTIN_YARIM'), 3.5);
      expect(PriceService.goldWeightFactor('ALTIN_CUMHURIYET'), 7.216);
      expect(PriceService.goldWeightFactor('ALTIN_ATA'), 7.216);
    });

    test('ALTIN_RESAT gram altın gibi davranMAZ', () {
      // Düzeltilen hata: history_service içindeki YEREL goldFactor
      // switch'inde ALTIN_RESAT yoktu ve default 1.0 dönüyordu — Reşat
      // altını olan kullanıcının grafiği 7.216 kat düşük çiziliyordu.
      // Tek kaynağa (PriceService tablosu) bağlanınca düzeldi.
      expect(PriceService.goldWeightFactor('ALTIN_RESAT'), 7.216);
    });

    test('bilinmeyen sembol 1.0 döner (gram altın gibi)', () {
      expect(PriceService.goldWeightFactor('ALTIN_YOK'), 1.0);
    });
  });
}
