import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/services/takip_sirasi.dart';

/// Takip listesi sırası (Ar-Ge 2026-10-24 12:45 #1): saf karar kuralları.
/// Widget tarafı (menü, sürükleme, erişilebilirlik eylemleri)
/// `takip_sirasi_widget_test.dart`'ta.
WatchlistItem _k(String id, double? pct) => WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: id,
      name: id,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: pct == null ? null : 10,
      periodChangePct: pct,
    );

List<String> _id(List<WatchlistItem> l) => [for (final w in l) w.id];

void main() {
  final a = _k('a', 5), b = _k('b', -2), c = _k('c', 1), f = _k('f', null);

  group('değişime göre', () {
    test('yükselen: azalan, fiyatsız dipte (eski davranış birebir)', () {
      expect(_id(degisimeGoreSirala([b, f, a, c])), ['a', 'c', 'b', 'f']);
    });
    test('düşen: artan, fiyatsız yine dipte', () {
      expect(_id(degisimeGoreSirala([b, f, a, c], azalan: false)),
          ['b', 'c', 'a', 'f']);
    });
    test('eşitlikte gelen sıra korunur', () {
      final x = _k('x', 1), y = _k('y', 1);
      expect(_id(degisimeGoreSirala([y, x])), ['y', 'x']);
    });
  });

  group('benim sıram', () {
    test('ilk açılış: bugünkü sıradan (değişime göre) başlar', () {
      final s = takipSirala([b, a, f, c],
          mod: TakipSiralama.benim, kayitliSira: null);
      expect(_id(s.liste), ['a', 'c', 'b', 'f']);
      expect(s.sira, ['a', 'c', 'b', 'f'], reason: 'o an kaydedilecek sıra');
    });

    test('kayıtlı sıra korunur; fiyat değişse de satır yer değiştirmez', () {
      final s = takipSirala([a, b, c],
          mod: TakipSiralama.benim, kayitliSira: ['b', 'c', 'a']);
      expect(_id(s.liste), ['b', 'c', 'a']);
      expect(s.sira, ['b', 'c', 'a']);
    });

    test('yeni eklenen sona, silinen düşer', () {
      final d = _k('d', 9);
      final s = takipSirala([a, b, d],
          mod: TakipSiralama.benim, kayitliSira: ['b', 'x', 'a']);
      expect(_id(s.liste), ['b', 'a', 'd']);
      expect(s.sira, ['b', 'a', 'd']);
    });

    test('boş liste kaydı silmez (ağ hatası da boş döner)', () {
      final s = takipSirala(const [],
          mod: TakipSiralama.benim, kayitliSira: ['b', 'a']);
      expect(s.liste, isEmpty);
      expect(s.sira, ['b', 'a']);
    });

    test('yükselen/düşen seçiliyken de sıra bakılır (yeni eklenen sonda)', () {
      final s = takipSirala([a, b, c],
          mod: TakipSiralama.dusen, kayitliSira: ['c', 'a']);
      expect(_id(s.liste), ['b', 'c', 'a']);
      expect(s.sira, ['c', 'a', 'b']);
    });
  });

  group('taşıma', () {
    const s = ['a', 'b', 'c', 'd'];
    test('aşağı ve yukarı', () {
      expect(siraTasi(s, 0, 1), ['b', 'a', 'c', 'd']);
      expect(siraTasi(s, 3, 2), ['a', 'b', 'd', 'c']);
      expect(siraTasi(s, 0, 3), ['b', 'c', 'd', 'a']);
    });
    test('sınır dışı kırpılır, aynı yer değişiklik yapmaz', () {
      expect(siraTasi(s, 0, -1), same(s));
      expect(siraTasi(s, 3, 9), same(s));
      expect(siraTasi(s, 9, 0), same(s));
    });
  });

  test('tercih değeri: tanınmayan → benim sıram', () {
    expect(takipSiralamaOf(0), TakipSiralama.benim);
    expect(takipSiralamaOf(1), TakipSiralama.yukselen);
    expect(takipSiralamaOf(2), TakipSiralama.dusen);
    expect(takipSiralamaOf(7), TakipSiralama.benim);
  });
}
