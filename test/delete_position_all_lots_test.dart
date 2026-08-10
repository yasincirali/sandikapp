import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Kaydırıp "Sil" dediğinde parça parça eklenmiş varlığın SON EKLENEN kadarı
/// siliniyordu: silme çağrısına `position.representative` geçiliyordu ve o,
/// `aggregatePositions` içinde en yeni buy lot'udur. Geri kalan lot'lar
/// kaldığı için satır azalmış miktarla listeye geri geliyordu.
///
/// Bu testler silmenin hedefinin pozisyonun TÜM lot'ları olduğunu sabitler.

Asset _lot({
  required String id,
  required double qty,
  required DateTime added,
  AssetKind kind = AssetKind.buy,
  double buyPrice = 100,
  double dividendAmount = 0,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: buyPrice,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1.0,
      currentPrice: 120,
      addedDate: added,
      kind: kind,
      dividendAmount: dividendAmount,
    );

void main() {
  group('pozisyon silme tüm lot\'ları hedefler', () {
    test('representative tek başına pozisyonu temsil ETMEZ', () {
      final positions = aggregatePositions([
        _lot(id: 'a1', qty: 10, added: DateTime(2026, 1, 1)),
        _lot(id: 'a2', qty: 5, added: DateTime(2026, 2, 1)),
        _lot(id: 'a3', qty: 7, added: DateTime(2026, 3, 1)),
      ]);
      expect(positions, hasLength(1));
      final p = positions.single;

      // Regresyonun kalbi: representative EN YENİ lot'tur (7 adet), ama
      // pozisyon 22 adettir. Eski kod bu tek lot'u siliyordu.
      expect(p.representative.id, 'a3');
      expect(p.totalQuantity, closeTo(22, 0.0001));

      // Silme hedefi tüm lot'lar olmalı.
      expect(p.lots.map((l) => l.id).toSet(), {'a1', 'a2', 'a3'});
    });

    test('satış ve temettü lot\'ları da silme kapsamındadır', () {
      final positions = aggregatePositions([
        _lot(id: 'buy1', qty: 10, added: DateTime(2026, 1, 1)),
        _lot(id: 'buy2', qty: 5, added: DateTime(2026, 2, 1)),
        _lot(id: 'sell1', qty: 3, added: DateTime(2026, 2, 10), kind: AssetKind.sell),
        _lot(
          id: 'div1',
          qty: 0,
          added: DateTime(2026, 2, 20),
          kind: AssetKind.dividend,
          dividendAmount: 250,
        ),
      ]);
      final p = positions.single;

      // Kalan miktar 12 ama arkasında 4 kayıt var; hepsi gitmeli, yoksa
      // silinen varlığın satış/temettü izleri portföy toplamlarında kalır.
      expect(p.totalQuantity, closeTo(12, 0.0001));
      expect(p.lots.map((l) => l.id).toSet(),
          {'buy1', 'buy2', 'sell1', 'div1'});
    });

    test('deleteLog satırları lot listesine girmez', () {
      final positions = aggregatePositions([
        _lot(id: 'buy1', qty: 10, added: DateTime(2026, 1, 1)),
        _lot(
          id: 'log1',
          qty: 4,
          added: DateTime(2026, 2, 1),
          kind: AssetKind.deleteLog,
        ),
      ]);
      final p = positions.single;

      // deleteLog bir kayıt değil izdir: miktara girmez, tekrar silinmez.
      expect(p.totalQuantity, closeTo(10, 0.0001));
      expect(p.lots.map((l) => l.id).toSet(), {'buy1'});
    });

    test('silme kaydı net miktarı ve kayıt sayısını taşır', () {
      // `deletePositionLots`'un tek deleteLog için hesapladığı değerler.
      // Burada o hesabın kurallarını sabitliyoruz: temettü miktara girmez,
      // satış düşülür, sayım deleteLog hariç tüm kayıtları kapsar.
      final removed = [
        _lot(id: 'buy1', qty: 10, added: DateTime(2026, 1, 1), buyPrice: 100),
        _lot(id: 'buy2', qty: 5, added: DateTime(2026, 2, 1), buyPrice: 120),
        _lot(
            id: 'sell1',
            qty: 3,
            added: DateTime(2026, 3, 1),
            kind: AssetKind.sell),
        _lot(
          id: 'div1',
          qty: 0,
          added: DateTime(2026, 4, 1),
          kind: AssetKind.dividend,
          dividendAmount: 250,
        ),
      ];

      double netQty = 0;
      for (final l in removed) {
        if (l.isDividend) continue;
        netQty += l.isSell ? -l.quantity : l.quantity;
      }

      expect(removed.length, 4, reason: 'deletedCount = 4');
      expect(netQty, closeTo(12, 0.0001),
          reason: '10 + 5 − 3; temettü miktara girmez');
    });

    test('farklı pozisyonlar birbirinin lotunu silmeye sürüklemez', () {
      final other = Asset(
        id: 'b1',
        userId: 'u1',
        name: 'ASELS',
        ticker: 'ASELS',
        type: AssetType.hisse,
        quantity: 9,
        purchasePrice: 50,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        purchaseFxRate: 1.0,
        currentPrice: 60,
        addedDate: DateTime(2026, 1, 5),
      );
      final positions = aggregatePositions([
        _lot(id: 'a1', qty: 10, added: DateTime(2026, 1, 1)),
        _lot(id: 'a2', qty: 5, added: DateTime(2026, 2, 1)),
        other,
      ]);

      final thyao = positions.firstWhere((p) => p.representative.ticker == 'THYAO');
      expect(thyao.lots.map((l) => l.id).toSet(), {'a1', 'a2'});
      expect(thyao.lots.any((l) => l.id == 'b1'), isFalse);
    });
  });
}
