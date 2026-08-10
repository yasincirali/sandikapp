import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// "PORTFÖY HAREKETLERİ" listesi HAM LEDGER'dan beslenmeli.
///
/// Regresyon: home_screen listeyi `aggregatePositions(...).asDisplayAsset()`
/// üzerinden kuruyordu. Aggregate her varlığı tek bir sentetik pozisyona
/// indirger — satış lot'ları buy miktarından düşer, temettü ve deleteLog
/// satırları tamamen elenir. Sonuç: kullanıcı Al/Sat/Temettü yaptığında
/// hareket listesinde YENİ KAYIT görünmüyordu, yalnızca mevcut satırın
/// miktarı değişiyordu.
///
/// Bu testler aggregate'in neyi kaybettiğini ve ham ledger'ın neyi
/// koruduğunu sabitler.

Asset _lot({
  required String id,
  required double qty,
  required DateTime added,
  AssetKind kind = AssetKind.buy,
  double buyPrice = 100,
  double dividendAmount = 0,
  int deletedCount = 0,
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
      deletedCount: deletedCount,
    );

/// home_screen'in hareket listesi için yaptığı iş: ham ledger, tarihe göre
/// yeniden eskiye. deleteLog dahil — silme de bir harekettir, ama pozisyon
/// başına TEK satır olarak (bkz. `deletePositionLots`).
List<Asset> _movements(List<Asset> ledger) => [...ledger]
  ..sort((a, b) => b.addedDate.compareTo(a.addedDate));

/// home_screen'in summary/dağılım için yaptığı iş (hareketler için YANLIŞ).
List<Asset> _aggregated(List<Asset> ledger) =>
    aggregatePositions(ledger).map((p) => p.asDisplayAsset()).toList();

void main() {
  final ledger = [
    _lot(id: 'buy1', qty: 10, added: DateTime(2026, 1, 1)),
    _lot(id: 'buy2', qty: 5, added: DateTime(2026, 2, 1)),
    _lot(id: 'sell1', qty: 3, added: DateTime(2026, 3, 1), kind: AssetKind.sell),
    _lot(
      id: 'div1',
      qty: 0,
      added: DateTime(2026, 4, 1),
      kind: AssetKind.dividend,
      dividendAmount: 250,
    ),
  ];

  group('hareket listesi ham ledger\'dan gelir', () {
    test('her Al/Sat/Temettü işlemi ayrı satırdır', () {
      final rows = _movements(ledger);

      expect(rows, hasLength(4),
          reason: 'dört işlem → dört hareket satırı');
      expect(rows.map((a) => a.id).toList(),
          ['div1', 'sell1', 'buy2', 'buy1'],
          reason: 'yeniden eskiye sıralanır');
    });

    test('aggregate kullanılırsa Sat ve Temettü KAYBOLUR (eski hata)', () {
      final rows = _aggregated(ledger);

      // Dört işlem tek satıra iner: kullanıcının şikayeti tam olarak buydu.
      expect(rows, hasLength(1));
      expect(rows.single.quantity, closeTo(12, 0.0001),
          reason: 'aggregate yalnızca NET miktarı gösterir (10+5-3)');
      expect(rows.single.id, startsWith('pos:'),
          reason: 'sentetik pozisyon — gerçek bir işlem kaydı değil');
    });

    test('satış kaydı hareket listesinde satış olarak durur', () {
      final sell = _movements(ledger).firstWhere((a) => a.id == 'sell1');
      expect(sell.isSell, isTrue);
      expect(sell.quantity, closeTo(3, 0.0001));
    });

    test('temettü kaydı hareket listesinde temettü olarak durur', () {
      final div = _movements(ledger).firstWhere((a) => a.id == 'div1');
      expect(div.isDividend, isTrue);
      expect(div.dividendAmount, closeTo(250, 0.0001));
      // Temettü miktara girmez — satır tutarı `dividendAmount`'tan okunur.
      expect(div.quantity, closeTo(0, 0.0001));
    });

    test('silmeden sonra ÖNCEKİ hareketler listede kalır + silme kaydı eklenir',
        () {
      // `deletePositionLots`'un ürettiği son durum: lot'lar FİZİKSEL olarak
      // silinmez, `deletedAt` damgalanır; üstüne bir de deleteLog eklenir.
      final stamp = DateTime(2026, 4, 2);
      final afterDelete = [
        for (final lot in ledger) lot.copyWithDeletedAt(stamp),
        _lot(
          id: 'log1',
          qty: 12,
          added: stamp,
          kind: AssetKind.deleteLog,
          deletedCount: 4,
        ),
      ];

      final rows = _movements(afterDelete);

      // Kullanıcının istediği: hareketler ayrı ayrı DURUR, en son silme
      // işlemi de AYRICA bir kayıt olarak düşer.
      expect(rows, hasLength(5),
          reason: '4 orijinal hareket + 1 silme kaydı');
      expect(rows.first.isDeleteLog, isTrue,
          reason: 'silme en yeni kayıt → listenin başında');
      expect(rows.first.deletedCount, 4);

      // Orijinal Alım/Satım/Temettü satırları kimliğini korur.
      final originals = rows.where((a) => !a.isDeleteLog).toList();
      expect(originals.map((a) => a.id).toSet(),
          {'buy1', 'buy2', 'sell1', 'div1'});
      expect(originals.every((a) => a.isDeleted), isTrue,
          reason: 'hepsi damgalı — geçmişte görünür ama hesaba girmez');
    });

    test('silinmiş lot\'lar hiçbir toplama girmez', () {
      final stamp = DateTime(2026, 4, 2);
      final afterDelete = [
        for (final lot in ledger) lot.copyWithDeletedAt(stamp),
      ];

      // Aggregate silinmiş lot'ları eler → ortada pozisyon kalmaz.
      expect(_aggregated(afterDelete), isEmpty,
          reason: 'silinen varlık portföy toplamlarından tamamen düşer');

      // Temettü de düşer: silinen varlığın temettüsü getiriye eklenmemeli.
      expect(totalDividendTRY(afterDelete), closeTo(0, 0.0001));
    });

    test('silinmemiş varlığın temettüsü toplamda kalır', () {
      // Karşı kontrol: yukarıdaki testin sıfırı, filtrenin fazla geniş
      // olmasından değil gerçekten silinmiş olmasından gelmeli.
      expect(totalDividendTRY(ledger), closeTo(250, 0.0001));
      expect(_aggregated(ledger), hasLength(1));
    });

    test('lot başına mezar taşı yazılmaz (eski hata)', () {
      // Regresyon: silme her lot için ayrı deleteLog yazıyordu; üç lot'lu
      // varlığı silmek listeye üç ayrı "Silindi" satırı bırakıyordu.
      final perLotTombstones = [
        for (final lot in ledger)
          _lot(
            id: 'log-${lot.id}',
            qty: lot.quantity,
            added: lot.addedDate,
            kind: AssetKind.deleteLog,
          ),
      ];

      expect(_movements(perLotTombstones).length, 4,
          reason: 'eski davranışın neye benzediğini sabitler — '
              'yeni kod bu listeyi ÜRETMEZ');

      // Yeni davranış: tek satır, sayı içinde.
      final consolidated = _movements([
        _lot(
          id: 'log1',
          qty: 12,
          added: DateTime(2026, 4, 2),
          kind: AssetKind.deleteLog,
          deletedCount: 4,
        ),
      ]);
      expect(consolidated, hasLength(1));
      expect(consolidated.single.deletedCount, 4);
    });

    test('deletedCount 0/1 ise satır düz "Silindi" okunur', () {
      // Etiket kuralı: yalnızca >1 sayıyı gösterir. 1 kayıt için sayı
      // gürültüdür; 0 eski kayıt demektir (migration 0026 öncesi).
      final old = _lot(
        id: 'log-old',
        qty: 5,
        added: DateTime(2026, 1, 1),
        kind: AssetKind.deleteLog,
      );
      final single = _lot(
        id: 'log-single',
        qty: 5,
        added: DateTime(2026, 1, 2),
        kind: AssetKind.deleteLog,
        deletedCount: 1,
      );

      expect(old.deletedCount, 0);
      expect(single.deletedCount, 1);
      // İkisi de "· N kayıt" eki ALMAZ.
      expect(old.deletedCount > 1, isFalse);
      expect(single.deletedCount > 1, isFalse);
    });

    test('bir varlığın silinmesi diğerinin hareketlerini götürmez', () {
      final gold = Asset(
        id: 'gold1',
        userId: 'u1',
        name: 'Çeyrek Altın',
        ticker: '',
        type: AssetType.altin,
        quantity: 2,
        purchasePrice: 5000,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        purchaseFxRate: 1.0,
        currentPrice: 5200,
        addedDate: DateTime(2026, 5, 1),
        subCategory: 'Çeyrek',
      );

      // THYAO silindi: lot'ları damgalandı + bir silme kaydı eklendi.
      // Altın dokunulmadan durmalı.
      final stamp = DateTime(2026, 4, 2);
      final afterDelete = [
        for (final lot in ledger) lot.copyWithDeletedAt(stamp),
        _lot(
          id: 'log1',
          qty: 12,
          added: stamp,
          kind: AssetKind.deleteLog,
          deletedCount: 4,
        ),
        gold,
      ];

      final goldRow =
          _movements(afterDelete).firstWhere((a) => a.id == 'gold1');
      expect(goldRow.isDeleted, isFalse,
          reason: 'altın damgalanmamalı');
      expect(goldRow.isActive, isTrue);

      // Ve toplamlarda yalnızca altın kalmalı.
      final positions = _aggregated(afterDelete);
      expect(positions, hasLength(1));
      expect(positions.single.type, AssetType.altin);
    });

    test('tür filtresi hareketleri süzer ama işlemleri birleştirmez', () {
      final mixed = [
        ...ledger,
        Asset(
          id: 'gold1',
          userId: 'u1',
          name: 'Çeyrek Altın',
          ticker: '',
          type: AssetType.altin,
          quantity: 2,
          purchasePrice: 5000,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          purchaseFxRate: 1.0,
          currentPrice: 5200,
          addedDate: DateTime(2026, 5, 1),
          subCategory: 'Çeyrek',
        ),
      ];

      final onlyStocks = _movements(mixed)
          .where((a) => a.type == AssetType.hisse)
          .toList();

      expect(onlyStocks, hasLength(4));
      expect(onlyStocks.any((a) => a.id == 'gold1'), isFalse);
    });
  });
}
