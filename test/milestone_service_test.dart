import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/milestone_service.dart';

/// Kilometre taşı hesabı.
///
/// **Bu testlerin ilkesel çapası:** kutlanan şey BİRİKİMDİR, işlem değil.
/// Robinhood her işlem sonrası konfeti atıyordu ve Massachusetts uzlaşması
/// (7,5M$, Ocak 2024) tam olarak bunu hedef aldı. Buradaki eşiklerin
/// hiçbiri bir işleme bağlı olmamalı — testler bunu da kontrol ediyor.
Asset _lot({
  required String id,
  AssetType type = AssetType.hisse,
  String? subCategory,
  double quantity = 1,
  DateTime? addedDate,
  AssetKind kind = AssetKind.buy,
  DateTime? deletedAt,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Test $id',
      ticker: 'TST',
      notes: '',
      type: type,
      subCategory: subCategory,
      quantity: quantity,
      purchasePrice: 100,
      currency: 'TRY',
      currentPrice: 100,
      kind: kind,
      addedDate: addedDate ?? DateTime(2026, 1, 1),
      deletedAt: deletedAt,
    );

void main() {
  final now = DateTime(2026, 9, 6);

  group('portföy değeri', () {
    test('geçilen tüm eşikler döner, geçilmeyenler dönmez', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a')],
        totalTRY: 120000,
        now: now,
      ).where((e) => e.kind == 'portfolio_value').toList();

      expect(m.map((e) => e.value),
          containsAll(['10000', '25000', '50000', '100000']));
      expect(m.map((e) => e.value), isNot(contains('250000')));
    });

    test('boş portföyde hiçbir eşik yok', () {
      expect(
        MilestoneService.evaluate(assets: const [], totalTRY: 999999, now: now),
        isEmpty,
      );
    });

    test('silinmiş lot eşiği tetiklemez', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a', deletedAt: DateTime(2026, 5, 1))],
        totalTRY: 500000,
        now: now,
      );
      expect(m, isEmpty, reason: 'silinen varlık portföyde sayılmaz');
    });
  });

  group('altın adedi', () {
    test('adet üzerinden sayılır, gram karşılığı üzerinden değil', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(
              id: 'g1',
              type: AssetType.altin,
              subCategory: 'ALTIN_CEYREK',
              quantity: 12),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'gold_count').toList();

      expect(m.map((e) => e.value), containsAll(['ALTIN_CEYREK:1',
          'ALTIN_CEYREK:5', 'ALTIN_CEYREK:10']));
      expect(m.map((e) => e.value), isNot(contains('ALTIN_CEYREK:25')));
    });

    test('aynı türün lotları toplanır', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(id: 'g1', type: AssetType.altin, subCategory: 'ALTIN_GRAM', quantity: 3),
          _lot(id: 'g2', type: AssetType.altin, subCategory: 'ALTIN_GRAM', quantity: 2),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'gold_count').toList();
      expect(m.map((e) => e.value), contains('ALTIN_GRAM:5'));
    });

    test('küsurat aşağı yuvarlanır — 4,9 çeyrek 5 sayılmaz', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(id: 'g', type: AssetType.altin, subCategory: 'ALTIN_CEYREK', quantity: 4.9),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'gold_count').toList();
      expect(m.map((e) => e.value), contains('ALTIN_CEYREK:1'));
      expect(m.map((e) => e.value), isNot(contains('ALTIN_CEYREK:5')));
    });
  });

  group('portföy yaşı', () {
    test('en ESKİ alım portföyün yaşını belirler', () {
      final m = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', addedDate: DateTime(2024, 1, 1)),
          _lot(id: 'b', addedDate: DateTime(2026, 8, 1)),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'portfolio_age').toList();
      expect(m.map((e) => e.value), containsAll(['1y', '2y']));
      expect(m.map((e) => e.value), isNot(contains('3y')));
    });

    test('bir yıldan yeni portföyde yaş eşiği yok', () {
      final m = MilestoneService.evaluate(
        assets: [_lot(id: 'a', addedDate: DateTime(2026, 6, 1))],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'portfolio_age');
      expect(m, isEmpty);
    });
  });

  group('çeşitlendirme', () {
    test('farklı TÜR sayılır, farklı varlık değil', () {
      final ucTur = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', type: AssetType.hisse),
          _lot(id: 'b', type: AssetType.altin, subCategory: 'ALTIN_GRAM'),
          _lot(id: 'c', type: AssetType.doviz),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'diversification').toList();
      expect(ucTur.map((e) => e.value), contains('3types'));

      final ayniTur = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', type: AssetType.hisse),
          _lot(id: 'b', type: AssetType.hisse),
          _lot(id: 'c', type: AssetType.hisse),
        ],
        totalTRY: 1000,
        now: now,
      ).where((e) => e.kind == 'diversification');
      expect(ayniTur, isEmpty, reason: 'üç hisse çeşitlendirme değildir');
    });
  });

  group('pickOne', () {
    test('metin değil SAYISAL büyüklüğe göre seçer', () {
      // Bu testin sebebi gerçek bir hata: `value` metindir ve '25000'
      // metin olarak '100000'den büyüktür. Metinle sıralayan bir seçim,
      // 100 bin eşiği yerine 25 bini kutlardı.
      final secilen = MilestoneService.pickOne(const [
        Milestone(
            kind: 'portfolio_value',
            value: '25000',
            title: '',
            body: '',
            rank: 25000),
        Milestone(
            kind: 'portfolio_value',
            value: '100000',
            title: '',
            body: '',
            rank: 100000),
      ]);
      expect(secilen?.value, '100000');
    });

    test('öncelik: yaş > değer > altın > çeşitlendirme', () {
      final secilen = MilestoneService.pickOne(const [
        Milestone(kind: 'diversification', value: '3types', title: '', body: '', rank: 3),
        Milestone(kind: 'gold_count', value: 'ALTIN_GRAM:5', title: '', body: '', rank: 5),
        Milestone(kind: 'portfolio_value', value: '100000', title: '', body: '', rank: 100000),
        Milestone(kind: 'portfolio_age', value: '1y', title: '', body: '', rank: 1),
      ]);
      expect(secilen?.kind, 'portfolio_age',
          reason: 'yaş en nadir ve en duygusal eşik');
    });

    test('boş listede null', () {
      expect(MilestoneService.pickOne(const []), isNull);
    });
  });

  group('ilke kontrolü', () {
    test('hiçbir eşik İŞLEME bağlı değil', () {
      // Eşik türleri sabit bir küme: işlem sayısı, alım-satım sıklığı ya da
      // "bugün işlem yaptın" gibi bir kalem EKLENMEMELİ. Yeni bir tür
      // eklenirse bu test kırılır ve karar bilinçli verilir.
      const izinli = {
        'portfolio_value',
        'gold_count',
        'portfolio_age',
        'diversification',
      };
      final uretilen = MilestoneService.evaluate(
        assets: [
          _lot(id: 'a', type: AssetType.hisse, addedDate: DateTime(2023, 1, 1)),
          _lot(id: 'b', type: AssetType.altin, subCategory: 'ALTIN_CEYREK', quantity: 10),
          _lot(id: 'c', type: AssetType.doviz),
        ],
        totalTRY: 2000000,
        now: now,
      ).map((e) => e.kind).toSet();
      expect(uretilen.difference(izinli), isEmpty);
    });
  });
}
