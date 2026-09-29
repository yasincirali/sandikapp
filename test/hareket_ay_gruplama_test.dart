import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';

/// Tüm hareketler ekranının ay kapları (seçenek A, 2026-09-28).
///
/// `hareketleriAylaGrupla` yalnızca ardışık kayıtları ay sınırından keser;
/// sıralamaz. Ekran zaten yeni→eski sıralı liste verir. Burada üç şey
/// sabitlenir: ay anahtarı ayın ilk günüdür, kayıt sırası korunur, sayfalama
/// büyüdüğünde (aynı liste + yeni kayıtlar) son kap büyür yeni kap açılmaz.
Asset _a(String id, DateTime t) => Asset(
      id: id,
      userId: 'u1',
      name: id,
      ticker: '',
      type: AssetType.altin,
      quantity: 1,
      purchasePrice: 1,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 1,
      addedDate: t,
    );

void main() {
  test('boş liste → boş', () {
    expect(hareketleriAylaGrupla(const []), isEmpty);
  });

  test('aynı aydaki kayıtlar tek kapta, sıra korunur', () {
    final g = hareketleriAylaGrupla([
      _a('c', DateTime(2026, 9, 25, 14, 29)),
      _a('b', DateTime(2026, 9, 24, 21, 2)),
      _a('a', DateTime(2026, 9, 23, 10, 32)),
    ]);
    expect(g, hasLength(1));
    expect(g.single.ay, DateTime(2026, 9));
    expect(g.single.kayitlar.map((e) => e.id), ['c', 'b', 'a']);
  });

  test('ay değişince yeni kap; yıl sınırı da ayırır', () {
    final g = hareketleriAylaGrupla([
      _a('eylul', DateTime(2026, 9, 1)),
      _a('agustos', DateTime(2026, 8, 31, 23, 59)),
      _a('ocak', DateTime(2026, 1, 5)),
      _a('aralik', DateTime(2025, 12, 31)),
    ]);
    expect(g.map((e) => e.ay), [
      DateTime(2026, 9),
      DateTime(2026, 8),
      DateTime(2026, 1),
      DateTime(2025, 12),
    ]);
    expect(g.map((e) => e.kayitlar.length), [1, 1, 1, 1]);
  });

  test('sayfa büyüyünce son kap büyür, yeni kap açılmaz', () {
    final ilk = [
      _a('1', DateTime(2026, 9, 25)),
      _a('2', DateTime(2026, 9, 20)),
    ];
    final sonra = [...ilk, _a('3', DateTime(2026, 9, 2))];
    expect(hareketleriAylaGrupla(ilk), hasLength(1));
    final g = hareketleriAylaGrupla(sonra);
    expect(g, hasLength(1));
    expect(g.single.kayitlar, hasLength(3));
  });
}
