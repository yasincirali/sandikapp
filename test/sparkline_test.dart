import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/sparkline_service.dart';

Asset _asset({
  required AssetType type,
  String ticker = 'THYAO.IS',
  bool isManualPrice = false,
}) =>
    Asset(
      id: 'a1',
      userId: 'u1',
      name: 'Test',
      ticker: ticker,
      type: type,
      quantity: 1,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: isManualPrice,
    );

void main() {
  group('SparklineService.normalize', () {
    test('yükselen seriyi 0..1 aralığına oturtur', () {
      final out = SparklineService.normalize([
        (1, 10.0),
        (2, 20.0),
        (3, 30.0),
      ]);

      expect(out, [0.0, 0.5, 1.0]);
    });

    test('düz seri ortada yatay çizgi olur (sıfıra bölme yok)', () {
      final out = SparklineService.normalize([
        (1, 42.0),
        (2, 42.0),
        (3, 42.0),
      ]);

      // Tüm noktalar eşitken span=0; NaN yerine 0.5 beklenir.
      expect(out, [0.5, 0.5, 0.5]);
      expect(out.every((v) => v.isFinite), isTrue);
    });

    test('tek nokta çizilmez — trend sayılmaz', () {
      expect(SparklineService.normalize([(1, 10.0)]), isEmpty);
      expect(SparklineService.normalize([]), isEmpty);
    });

    test('sırasız gelen noktalar zamana göre sıralanır', () {
      // Yahoo sıralı döner ama TEFAS/karışık kaynaklarda garanti değil.
      final out = SparklineService.normalize([
        (3, 30.0),
        (1, 10.0),
        (2, 20.0),
      ]);

      expect(out, [0.0, 0.5, 1.0]);
    });

    test('sıfır/negatif fiyatlar elenir', () {
      final out = SparklineService.normalize([
        (1, 10.0),
        (2, 0.0),
        (3, 20.0),
      ]);

      // 0.0 atılır; kalan iki geçerli nokta uçlara oturur.
      expect(out, [0.0, 1.0]);
    });

    test('eleme sonrası iki noktanın altına düşerse boş döner', () {
      final out = SparklineService.normalize([
        (1, 10.0),
        (2, 0.0),
        (3, -5.0),
      ]);

      expect(out, isEmpty);
    });

    test('düşen seri de 0..1 aralığında kalır', () {
      final out = SparklineService.normalize([
        (1, 30.0),
        (2, 20.0),
        (3, 10.0),
      ]);

      expect(out, [1.0, 0.5, 0.0]);
      expect(out.every((v) => v >= 0.0 && v <= 1.0), isTrue);
    });
  });

  group('SparklineService.supports', () {
    test('manuel fiyatlı varlıkta grafik yok', () {
      // "Ev", "Araba" gibi elle girilen varlıkların fiyat geçmişi yoktur.
      expect(
        SparklineService.supports(
          _asset(type: AssetType.hisse, isManualPrice: true),
        ),
        isFalse,
      );
    });

    test('altın ticker olmadan da desteklenir (GC=F eğrisi)', () {
      expect(
        SparklineService.supports(
          _asset(type: AssetType.altin, ticker: 'ALTIN_GRAM'),
        ),
        isTrue,
      );
    });

    test('ticker boşsa desteklenmez', () {
      expect(
        SparklineService.supports(_asset(type: AssetType.hisse, ticker: '')),
        isFalse,
      );
    });

    test('hisse, fon, döviz ve emtia desteklenir', () {
      for (final t in [
        AssetType.hisse,
        AssetType.fon,
        AssetType.doviz,
        AssetType.emtia,
      ]) {
        expect(SparklineService.supports(_asset(type: t)), isTrue,
            reason: '$t desteklenmeli');
      }
    });
  });
}
