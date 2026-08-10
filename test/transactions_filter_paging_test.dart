import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';

/// Hareket ekranının filtre + sayfalama kuralları.
///
/// Ekranın kendisi Riverpod + Supabase + auth gerektirdiği için pump
/// edilemiyor; buradaki testler filtre/sayfalama mantığını ekrandakiyle
/// AYNI kurallarla yeniden kurup davranışı sabitler. Kural değişirse iki
/// taraf birlikte güncellenmeli.

Asset _lot({
  required String id,
  required String name,
  required DateTime added,
  AssetType type = AssetType.hisse,
  String ticker = '',
  String? subCategory,
  AssetKind kind = AssetKind.buy,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: name,
      ticker: ticker,
      type: type,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1.0,
      currentPrice: 120,
      addedDate: added,
      subCategory: subCategory,
      kind: kind,
    );

/// `_AllTransactionsScreenState._filtered` ile aynı kurallar.
List<Asset> filterLedger(
  List<Asset> ledger, {
  AssetType? type,
  DateTime? from,
  DateTime? to,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  final out = <Asset>[];
  for (final a in ledger) {
    if (type != null && a.type != type) continue;
    if (from != null && a.addedDate.isBefore(from)) continue;
    if (to != null && a.addedDate.isAfter(to)) continue;
    if (q.isNotEmpty) {
      final name = a.name.toLowerCase();
      final ticker = a.ticker.toLowerCase();
      final sub = (a.subCategory ?? '').toLowerCase();
      if (!name.contains(q) && !ticker.contains(q) && !sub.contains(q)) {
        continue;
      }
    }
    out.add(a);
  }
  out.sort((a, b) => b.addedDate.compareTo(a.addedDate));
  return out;
}

void main() {
  final ledger = [
    _lot(
        id: 'a1',
        name: 'Türk Hava Yolları',
        ticker: 'THYAO',
        added: DateTime(2026, 1, 10)),
    _lot(
        id: 'a2',
        name: 'Türk Hava Yolları',
        ticker: 'THYAO',
        added: DateTime(2026, 6, 1),
        kind: AssetKind.sell),
    _lot(
        id: 'a3',
        name: 'Aselsan',
        ticker: 'ASELS',
        added: DateTime(2026, 7, 15)),
    _lot(
      id: 'g1',
      name: 'Çeyrek Altın',
      type: AssetType.altin,
      subCategory: 'Çeyrek',
      added: DateTime(2026, 8, 1),
    ),
  ];

  group('filtreler', () {
    test('varsayılan: hepsi, yeniden eskiye', () {
      final rows = filterLedger(ledger);
      expect(rows.map((a) => a.id).toList(), ['g1', 'a3', 'a2', 'a1']);
    });

    test('tür filtresi yalnızca o türü bırakır', () {
      final rows = filterLedger(ledger, type: AssetType.altin);
      expect(rows.map((a) => a.id).toList(), ['g1']);
    });

    test('metin araması ticker üzerinden çalışır', () {
      final rows = filterLedger(ledger, query: 'thyao');
      expect(rows.map((a) => a.id).toList(), ['a2', 'a1']);
    });

    test('metin araması ada göre çalışır ve büyük/küçük harf duyarsızdır', () {
      final rows = filterLedger(ledger, query: 'ASELSAN');
      expect(rows.map((a) => a.id).toList(), ['a3']);
    });

    test('metin araması subCategory üzerinden çalışır (ticker\'sız varlık)', () {
      // Altında ticker yok — arama yalnızca ada baksaydı "çeyrek" bulunmazdı.
      final rows = filterLedger(ledger, query: 'çeyrek');
      expect(rows.map((a) => a.id).toList(), ['g1']);
    });

    test('tarih aralığı başlangıcı dahil eder', () {
      final rows = filterLedger(ledger, from: DateTime(2026, 6, 1));
      expect(rows.map((a) => a.id).toList(), ['g1', 'a3', 'a2'],
          reason: '1 Haziran işlemi aralığın İÇİNDE');
    });

    test('tarih aralığı bitişi gün sonuna kadar dahil eder', () {
      // Kullanıcı 15 Temmuz seçtiyse o günün işlemi listeye girmeli.
      final rows = filterLedger(
        ledger,
        to: DateTime(2026, 7, 15, 23, 59, 59),
      );
      expect(rows.map((a) => a.id).toList(), ['a3', 'a2', 'a1']);
    });

    test('filtreler birlikte uygulanır', () {
      final rows = filterLedger(
        ledger,
        type: AssetType.hisse,
        from: DateTime(2026, 5, 1),
        query: 'thyao',
      );
      expect(rows.map((a) => a.id).toList(), ['a2']);
    });

    test('eşleşme yoksa boş liste döner', () {
      expect(filterLedger(ledger, query: 'yokböylevarlık'), isEmpty);
    });
  });

  group('sayfalama', () {
    const pageSize = 25;

    List<Asset> manyRows(int n) => [
          for (var i = 0; i < n; i++)
            _lot(
              id: 'x$i',
              name: 'Varlık $i',
              ticker: 'TCK$i',
              added: DateTime(2026, 1, 1).add(Duration(days: i)),
            ),
        ];

    test('ilk sayfa yalnızca pageSize kadar satır gösterir', () {
      final rows = filterLedger(manyRows(80));
      final shown = pageSize.clamp(0, rows.length);
      expect(rows.length, 80);
      expect(shown, 25);
    });

    test('büyütme pageSize kadar ekler ve toplamı AŞMAZ', () {
      final rows = filterLedger(manyRows(60));
      var visible = pageSize;
      visible = (visible + pageSize).clamp(0, rows.length); // 50
      expect(visible, 50);
      visible = (visible + pageSize).clamp(0, rows.length); // 60, 75 değil
      expect(visible, 60,
          reason: 'clamp olmadan itemCount listeyi aşar ve RangeError olur');
    });

    test('toplam pageSize altındaysa hepsi görünür', () {
      final rows = filterLedger(manyRows(7));
      expect(pageSize.clamp(0, rows.length), 7);
    });

    test('boş listede görünür satır 0', () {
      expect(pageSize.clamp(0, 0), 0);
    });
  });
}
