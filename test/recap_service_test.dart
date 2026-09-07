import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/recap_service.dart';

/// "sandık Özeti" hesabı.
///
/// Özetin tek amacı PAYLAŞILABİLİRLİK: insanlar veriyi değil kimliği
/// paylaşır. Bu yüzden testlerin çapası iki şey — karakter etiketinin
/// ayırt edici kalması ve paylaşım metninde TUTAR bulunmaması.
Asset _lot({
  required String id,
  String name = 'Varlık',
  AssetType type = AssetType.hisse,
  double quantity = 1,
  double purchasePrice = 100,
  double currentPrice = 100,
  DateTime? addedDate,
  AssetKind kind = AssetKind.buy,
  DateTime? deletedAt,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: name,
      ticker: 'TST',
      notes: '',
      type: type,
      quantity: quantity,
      purchasePrice: purchasePrice,
      currency: 'TRY',
      currentPrice: currentPrice,
      kind: kind,
      addedDate: addedDate ?? DateTime(2026, 1, 1),
      deletedAt: deletedAt,
    );

({int ts, Map<String, double> values}) _snap(DateTime t, double total) =>
    (ts: t.millisecondsSinceEpoch, values: {'hisse': total});

void main() {
  final now = DateTime(2026, 12, 28);
  double toTRY(double v, String c) => v;

  RecapData run({
    List<Asset> assets = const [],
    List<({int ts, Map<String, double> values})> snapshots = const [],
    double? inflationPct,
  }) =>
      RecapService.compute(
        period: 'yearly',
        assets: assets,
        snapshots: snapshots,
        toTRY: toTRY,
        now: now,
        inflationPct: inflationPct,
      );

  group('karakter etiketi', () {
    test('çoğunluk türü etiketi belirler', () {
      expect(
        RecapService.characterFor({AssetType.altin: 70, AssetType.hisse: 30}),
        PortfolioCharacter.altinci,
      );
      expect(
        RecapService.characterFor({AssetType.hisse: 60, AssetType.doviz: 40}),
        PortfolioCharacter.hisseci,
      );
    });

    test('eşiğin altında kalan dağılım Dengeli', () {
      // %50 eşiği: daha düşüğü dengeli portföyü yanlış etiketler, daha
      // yükseği neredeyse herkesi Dengeli yapar ve etiket ayırt ediciliğini
      // kaybeder — paylaşılabilirliğin tamamı ayırt edicilikte.
      expect(
        RecapService.characterFor({
          AssetType.altin: 40,
          AssetType.hisse: 35,
          AssetType.doviz: 25,
        }),
        PortfolioCharacter.dengeli,
      );
    });

    test('tam eşikte etiket verilir', () {
      expect(
        RecapService.characterFor({AssetType.altin: 50, AssetType.hisse: 50}),
        PortfolioCharacter.altinci,
      );
    });

    test('boş portföy Dengeli', () {
      expect(RecapService.characterFor(const {}), PortfolioCharacter.dengeli);
      expect(
        RecapService.characterFor({AssetType.altin: 0}),
        PortfolioCharacter.dengeli,
      );
    });

    test('her etiketin bir sloganı var', () {
      for (final c in PortfolioCharacter.values) {
        expect(c.label.trim(), isNotEmpty);
        expect(c.tagline.trim(), isNotEmpty);
      }
    });
  });

  group('takip edilen gün', () {
    test('GÜN sayılır, kayıt değil', () {
      // Uygulamayı bir günde on kez açan kullanıcı "10 gün" görmemeli.
      final seri = [
        _snap(DateTime(2026, 3, 1, 9), 100),
        _snap(DateTime(2026, 3, 1, 14), 101),
        _snap(DateTime(2026, 3, 1, 20), 102),
        _snap(DateTime(2026, 3, 2, 9), 103),
      ];
      expect(RecapService.distinctDays(seri), 2);
    });

    test('boş seri sıfır', () {
      expect(RecapService.distinctDays(const []), 0);
    });
  });

  group('dönem değişimi', () {
    test("ilk ve son snapshot'tan hesaplanır", () {
      final d = run(snapshots: [
        _snap(DateTime(2026, 1, 2), 100000),
        _snap(DateTime(2026, 6, 1), 120000),
        _snap(DateTime(2026, 12, 20), 150000),
      ]);
      expect(d.changePct, closeTo(50, 1e-9));
      expect(d.startTotalTRY, 100000);
      expect(d.endTotalTRY, 150000);
    });

    test('sıralama girdi sırasına bağlı değil', () {
      final d = run(snapshots: [
        _snap(DateTime(2026, 12, 20), 150000),
        _snap(DateTime(2026, 1, 2), 100000),
      ]);
      expect(d.changePct, closeTo(50, 1e-9));
    });

    test('snapshot yoksa değişim null — sıfır uydurulmaz', () {
      expect(run().changePct, isNull);
    });
  });

  group('en iyi / en kötü varlık', () {
    test('en kötü YALNIZCA gerçekten kayıptaysa gösterilir', () {
      // Kârdaki bir varlığı "en kötün" diye sunmak kutlamayı azarlamaya
      // çevirir.
      final d = run(assets: [
        _lot(id: 'a', name: 'Az kazandıran', purchasePrice: 100, currentPrice: 105),
        _lot(id: 'b', name: 'Çok kazandıran', purchasePrice: 100, currentPrice: 150),
      ]);
      expect(d.bestAsset?.name, 'Çok kazandıran');
      expect(d.worstAsset, isNull);
    });

    test('kayıptaki varlık en kötü olarak gelir', () {
      final d = run(assets: [
        _lot(id: 'a', name: 'Kayıp', purchasePrice: 100, currentPrice: 60),
        _lot(id: 'b', name: 'Kazanç', purchasePrice: 100, currentPrice: 150),
      ]);
      expect(d.bestAsset?.name, 'Kazanç');
      expect(d.worstAsset?.name, 'Kayıp');
      expect(d.worstAsset!.changePct, lessThan(0));
    });

    test('tek varlıkta en iyi ve en kötü aynı olamaz', () {
      final d = run(assets: [
        _lot(id: 'a', name: 'Tek', purchasePrice: 100, currentPrice: 60),
      ]);
      expect(d.worstAsset, isNull, reason: 'tek varlık hem en iyi hem en kötü olmaz');
    });

    test('maliyeti olmayan varlık ölçüme girmez', () {
      final d = run(assets: [
        _lot(id: 'a', name: 'Bedava', purchasePrice: 0, currentPrice: 100),
      ]);
      expect(d.bestAsset, isNull);
    });

    test('silinmiş varlık sayılmaz', () {
      final d = run(assets: [
        _lot(id: 'a', purchasePrice: 100, currentPrice: 200,
            deletedAt: DateTime(2026, 5, 1)),
      ]);
      expect(d.bestAsset, isNull);
      expect(d.typeCount, 0);
    });
  });

  group('enflasyon farkı', () {
    test('değişim ve enflasyon varsa puan farkı', () {
      final d = run(
        snapshots: [
          _snap(DateTime(2026, 1, 2), 100),
          _snap(DateTime(2026, 12, 20), 146),
        ],
        inflationPct: 40,
      );
      expect(d.inflationSpread, closeTo(6, 1e-9));
    });

    test('enflasyon yoksa null', () {
      final d = run(snapshots: [
        _snap(DateTime(2026, 1, 2), 100),
        _snap(DateTime(2026, 12, 20), 146),
      ]);
      expect(d.inflationSpread, isNull);
    });

    test('değişim yoksa enflasyon tek başına anlam taşımaz', () {
      expect(run(inflationPct: 40).inflationSpread, isNull);
    });
  });

  group('paylaşım metni', () {
    test('TUTAR İÇERMEZ', () {
      // Tutarlı bir kart paylaşılmaz, tutarsız kart paylaşılır.
      // Paylaşılabilirlik bu özelliğin tek amacı.
      final d = run(
        assets: [_lot(id: 'a', type: AssetType.altin, purchasePrice: 100, currentPrice: 150)],
        snapshots: [
          _snap(DateTime(2026, 1, 2), 250000),
          _snap(DateTime(2026, 12, 20), 400000),
        ],
        inflationPct: 40,
      );
      final metin = RecapService.shareText(d, year: 2026);
      expect(metin.contains('₺'), isFalse);
      expect(metin.contains('250'), isFalse);
      expect(metin.contains('400'), isFalse);
      expect(RegExp(r'\d{4,}').hasMatch(metin.replaceAll('2026', '')), isFalse,
          reason: 'dört haneli sayı tutar demektir');
    });

    test('karakter etiketi metinde geçer', () {
      final d = run(assets: [
        _lot(id: 'a', type: AssetType.altin, quantity: 10, currentPrice: 100),
      ]);
      final metin = RecapService.shareText(d, year: 2026);
      expect(metin.contains('Altıncı'), isTrue);
    });

    test('eksik veri satırı hiç yazılmaz', () {
      final metin = RecapService.shareText(run(), year: 2026);
      expect(metin.contains('Portföy değişimi'), isFalse);
      expect(metin.contains('Enflasyonun'), isFalse);
    });
  });

  group('yıllık pencere', () {
    test('26 Aralık - 10 Ocak arası açık', () {
      // 31 Aralık DEĞİL: Wrapped'in erken çıkma sebebi yıl sonu
      // gürültüsünden önce olmak.
      expect(RecapService.isYearlyWindow(DateTime(2026, 12, 26)), isTrue);
      expect(RecapService.isYearlyWindow(DateTime(2026, 12, 31)), isTrue);
      expect(RecapService.isYearlyWindow(DateTime(2027, 1, 1)), isTrue);
      expect(RecapService.isYearlyWindow(DateTime(2027, 1, 10)), isTrue);
    });

    test('pencere dışında kapalı', () {
      expect(RecapService.isYearlyWindow(DateTime(2026, 12, 25)), isFalse);
      expect(RecapService.isYearlyWindow(DateTime(2027, 1, 11)), isFalse);
      expect(RecapService.isYearlyWindow(DateTime(2026, 9, 7)), isFalse);
    });

    test('Ocak\'ta açılan özet BİR ÖNCEKİ yılındır', () {
      // 3 Ocak'ta "2027 Özetin" demek üç günlük bir yılı özetlemek olurdu.
      expect(RecapService.yearFor(DateTime(2027, 1, 3)), 2026);
      expect(RecapService.yearFor(DateTime(2026, 12, 28)), 2026);
    });
  });

  group('isMeaningful', () {
    test('boş özet gösterilmez', () {
      expect(run().isMeaningful, isFalse);
    });

    test('tek bir gerçek sayı yeter', () {
      final d = run(snapshots: [
        _snap(DateTime(2026, 1, 2), 100),
        _snap(DateTime(2026, 12, 20), 150),
      ]);
      expect(d.isMeaningful, isTrue);
    });
  });
}
