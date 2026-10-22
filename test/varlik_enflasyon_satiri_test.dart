import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/inflation_service.dart';
import 'package:portfoy_takip/services/real_return_service.dart';

import 'helpers/kaynak.dart';

/// Varlık ekranındaki "Enflasyonun X puan önünde · Eylül TÜFE'sine kadar"
/// satırı (yasin 2026-10-22, artifact seçeneği A).
///
/// Kilitlenenler: (1) satır sayı UYDURMAZ: ilk alıma kadar uzanmayan ya da
/// bir TÜFE ayı bile geçmemiş pencerede hesap hiç başlamaz; (2) hesap
/// portföy kartıyla tek kaynaktan (`hizaliGetiri`); (3) satır yalnız
/// katmanlı karttadır, yeni kart/başlık eklemez, anlamı kelimeyle taşır.
void main() {
  DateTime ay(int y, int m) => DateTime(y, m, 1);

  Asset lot(DateTime tarih) => Asset(
        id: 'ALTIN-1',
        userId: 'u',
        name: 'Gram Altın',
        ticker: 'GRAM',
        type: AssetType.altin,
        quantity: 10,
        purchasePrice: 2725.6,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 4312.18,
        addedDate: tarih,
      );

  setUp(() => InflationService.instance.resetForTest());
  tearDown(() => InflationService.instance.resetForTest());

  group('aldigindanBeri: uydurma yok', () {
    test('lot yoksa null', () async {
      InflationService.instance.seedForTest({ay(2026, 8): 100, ay(2026, 9): 102});
      expect(
          await RealReturnService.aldigindanBeri(const [],
              now: DateTime(2026, 10, 22)),
          isNull);
    });

    test('bu ay alınan varlıkta karşılaştırılacak TÜFE ayı yok → null',
        () async {
      InflationService.instance.seedForTest({ay(2026, 8): 100, ay(2026, 9): 102});
      expect(
          await RealReturnService.aldigindanBeri([lot(DateTime(2026, 10, 5))],
              now: DateTime(2026, 10, 22)),
          isNull);
    });

    test('endeks ilk alıma kadar uzanmıyorsa kısa pencere sunulmaz → null',
        () async {
      // Alış Mart 2025; endeks Ocak 2026'dan başlıyor. Kısaltılmış pencere
      // "aldığından beri" diye yazılırsa yanlış olur.
      InflationService.instance.seedForTest({
        ay(2026, 1): 100,
        ay(2026, 9): 120,
      });
      expect(
          await RealReturnService.aldigindanBeri([lot(DateTime(2025, 3, 14))],
              now: DateTime(2026, 10, 22)),
          isNull);
    });

    test('endeks yoksa null', () async {
      InflationService.instance.seedForTest({});
      expect(
          await RealReturnService.aldigindanBeri([lot(DateTime(2025, 3, 14))],
              now: DateTime(2026, 10, 22)),
          isNull);
    });
  });

  group('pencere ilk alımın bir önceki ay sonundan başlar', () {
    test('Mart 2025 alımı → Şubat 2025 … son açıklanan ay', () async {
      InflationService.instance.seedForTest({
        ay(2024, 12): 90,
        ay(2025, 2): 100,
        ay(2026, 9): 141,
      });
      final w = await InflationService.instance.pencereKapsayan(
          DateTime(2026, 10, 22).difference(DateTime(2025, 3, 14)).inDays + 31,
          now: DateTime(2026, 10, 22),
          enErken: DateTime(2025, 3, 14));
      expect(w, isNotNull);
      expect(w!.ilkAy, ay(2025, 2));
      expect(w.sonAy, ay(2026, 9));
      expect(w.pct, closeTo(41.0, 1e-9));
    });
  });

  group('kaynak', () {
    final servis = ekranKaynagiSync('lib/services/real_return_service.dart');
    final ekran = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');

    test('hesap portföy kartıyla tek yoldan: hizaliGetiri + pencereKapsayan',
        () {
      final govde = servis.substring(servis.indexOf('aldigindanBeri('));
      final son = govde.indexOf('\n  }\n');
      final fn = govde.substring(0, son);
      expect(fn, contains('RealReturnService.hizaliGetiri('));
      expect(fn, contains('pencereKapsayan('));
      expect(fn, contains('w.ilkAy.isAfter(ilkAlimAyi)'));
    });

    test('satır yalnız katmanlı kartta, kendi varlığında, tek iş', () {
      expect(ekran, contains('enflasyon: isOwnAsset ? _enflasyonIsiAl() : null'));
      expect(ekran, contains('RealReturnService.aldigindanBeri(lotlar)'));
      // Hata sessiz kalmaz, satır da çizilmez.
      expect(ekran, contains("reason: 'varlik_enflasyon_satiri'"));
    });

    test('anlam kelimede ve ikonda; yeni kart/başlık yok', () {
      final i = ekran.indexOf('class _EnflasyonSatiri');
      expect(i, greaterThan(0));
      final sinif = ekran.substring(i, ekran.indexOf('\n}\n', i));
      expect(sinif, contains('aheadOfInflationPts'));
      expect(sinif, contains('behindInflationPts'));
      expect(sinif, contains('adInflationThrough'));
      expect(sinif, contains('trending_down_rounded'));
      expect(sinif, contains('Semantics('));
      expect(sinif, isNot(contains('SandikCard')));
      expect(sinif, isNot(contains('SandikSectionHeader')));
    });
  });
}
