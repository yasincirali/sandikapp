import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';

/// Hareket satırının "önceki → sonraki" bakiyesi (kullanıcı isteği
/// 2026-10-29). Sözleşme `hareketBakiyeleri` belge yorumunda: miktar, ham
/// defter, sahip başına, yalnız süren alım/satım, mevduat/BES yok,
/// tutarsız defterde uydurma yok.
Asset _lot(
  String id,
  double qty,
  DateTime tarih, {
  AssetKind kind = AssetKind.buy,
  String user = 'u1',
  String ticker = 'THYAO.IS',
  AssetType type = AssetType.hisse,
  DateTime? deletedAt,
  double dividend = 0,
  double alis = 100,
  double? satis = 120,
}) =>
    Asset(
      id: id,
      userId: user,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: alis,
      sellPrice: satis,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 110,
      addedDate: tarih,
      kind: kind,
      deletedAt: deletedAt,
      dividendAmount: dividend,
    );

DateTime _g(int gun, [int saat = 12]) => DateTime(2026, 3, gun, saat);

/// Yalnız miktar — miktar testleri değeri ayrı testte sınar.
({double once, double sonra})? _m(HareketBakiyesi? b) =>
    b == null ? null : (once: b.once, sonra: b.sonra);

void main() {
  test('alım ve satım: önceki/sonraki miktar', () {
    final b = hareketBakiyeleri([
      _lot('s1', 4, _g(3), kind: AssetKind.sell),
      _lot('a1', 10, _g(1)),
      _lot('a2', 6, _g(2)),
    ]);
    expect(_m(b['a1']), (once: 0.0, sonra: 10.0));
    expect(_m(b['a2']), (once: 10.0, sonra: 16.0));
    expect(_m(b['s1']), (once: 16.0, sonra: 12.0));
  });

  test('tamamen satış sıfıra iner; kayan nokta gürültüsü 0 olur', () {
    final b = hareketBakiyeleri([
      _lot('a1', 0.1, _g(1)),
      _lot('a2', 0.2, _g(2)),
      _lot('s1', 0.3, _g(3), kind: AssetKind.sell),
    ]);
    expect(b['s1']!.sonra, 0);
  });

  test('kapanıştan sonra yeniden alım sıfırdan başlar (ham defter)', () {
    final b = hareketBakiyeleri([
      _lot('a1', 5, _g(1)),
      _lot('s1', 5, _g(2), kind: AssetKind.sell),
      _lot('a2', 3, _g(3)),
    ]);
    expect(_m(b['s1']), (once: 5.0, sonra: 0.0));
    expect(_m(b['a2']), (once: 0.0, sonra: 3.0));
  });

  test('aynı anda alım satımdan önce sayılır', () {
    final b = hareketBakiyeleri([
      _lot('s1', 5, _g(1), kind: AssetKind.sell),
      _lot('a1', 5, _g(1)),
    ]);
    expect(_m(b['a1']), (once: 0.0, sonra: 5.0));
    expect(_m(b['s1']), (once: 5.0, sonra: 0.0));
  });

  test('ortakların aynı hissesi netleşmez', () {
    final b = hareketBakiyeleri([
      _lot('a1', 10, _g(1), user: 'ben'),
      _lot('o1', 7, _g(2), user: 'ortak'),
      _lot('s1', 3, _g(3), kind: AssetKind.sell, user: 'ben'),
    ]);
    expect(_m(b['o1']), (once: 0.0, sonra: 7.0));
    expect(_m(b['s1']), (once: 10.0, sonra: 7.0));
  });

  test('farklı varlıklar ayrı yürür', () {
    final b = hareketBakiyeleri([
      _lot('a1', 10, _g(1)),
      _lot('x1', 2, _g(2), ticker: 'ASELS.IS'),
    ]);
    expect(_m(b['x1']), (once: 0.0, sonra: 2.0));
  });

  test('elde olandan fazla satış: o pozisyona hiç bakiye yok', () {
    final b = hareketBakiyeleri([
      _lot('a1', 3, _g(1)),
      _lot('s1', 5, _g(2), kind: AssetKind.sell),
      _lot('a2', 10, _g(3)),
      // Başka pozisyon etkilenmez.
      _lot('x1', 2, _g(1), ticker: 'ASELS.IS'),
    ]);
    expect(b.containsKey('a1'), isFalse);
    expect(b.containsKey('s1'), isFalse);
    expect(b.containsKey('a2'), isFalse);
    expect(_m(b['x1']), (once: 0.0, sonra: 2.0));
  });

  test('temettü miktara girmez ve bakiye almaz', () {
    final b = hareketBakiyeleri([
      _lot('a1', 10, _g(1)),
      _lot('t1', 0, _g(2), kind: AssetKind.dividend, dividend: 50),
      _lot('a2', 5, _g(3)),
    ]);
    expect(b.containsKey('t1'), isFalse);
    expect(_m(b['a2']), (once: 10.0, sonra: 15.0));
  });

  test('silinmiş lot ve mezar taşı sayılmaz', () {
    final b = hareketBakiyeleri([
      _lot('a1', 10, _g(1)),
      _lot('a2', 99, _g(2), deletedAt: _g(5)),
      _lot('m1', 0, _g(5), kind: AssetKind.deleteLog),
      _lot('a3', 5, _g(3)),
    ]);
    expect(b.containsKey('a2'), isFalse);
    expect(b.containsKey('m1'), isFalse);
    expect(_m(b['a3']), (once: 10.0, sonra: 15.0));
  });

  test('mevduat ve BES için bakiye yok', () {
    final b = hareketBakiyeleri([
      _lot('m1', 100000, _g(1),
          type: AssetType.mevduat, ticker: 'MEVDUAT:1'),
      _lot('b1', 500, _g(1), type: AssetType.bes, ticker: 'AEA'),
    ]);
    expect(b, isEmpty);
  });

  test('önbellek: aynı nesnelerden yeni liste aynı sonucu döner', () {
    final lots = [_lot('a1', 10, _g(1)), _lot('a2', 5, _g(2))];
    final o = HareketBakiyeOnbellegi();
    final ilk = o.hesapla(List.of(lots));
    expect(identical(o.hesapla(List.of(lots)), ilk), isTrue);
    final yeni = o.hesapla([...lots, _lot('a3', 1, _g(3))]);
    expect(identical(yeni, ilk), isFalse);
    expect(_m(yeni['a3']), (once: 15.0, sonra: 16.0));
  });

  // Değer (kullanıcı isteği 2026-10-29, ikinci tur): miktar × O İŞLEMİN
  // birim fiyatı; bugünkü fiyat (`currentPrice` 110) hiç girmez.
  group('değer — işlem fiyatıyla', () {
    test('alım: alış fiyatı, satım: satış fiyatı', () {
      final b = hareketBakiyeleri([
        _lot('a1', 400, _g(1), alis: 31),
        _lot('s1', 100, _g(2), kind: AssetKind.sell, satis: 31),
      ]);
      expect(b['a1']!.onceDeger, 0);
      expect(b['a1']!.sonraDeger, 12400);
      expect(b['s1']!.onceDeger, 12400);
      expect(b['s1']!.sonraDeger, 9300);
    });

    test('fark satırdaki işlem tutarına eşit', () {
      final b = hareketBakiyeleri([
        _lot('a1', 10, _g(1), alis: 50),
        _lot('a2', 6, _g(2), alis: 80),
      ]);
      final a2 = b['a2']!;
      expect(a2.sonraDeger! - a2.onceDeger!, 6 * 80);
      // Önceki değer de BU işlemin fiyatıyla: 10 × 80, alıştaki 50 değil.
      expect(a2.onceDeger, 800);
    });

    test('satış fiyatı bilinmiyorsa değer yok, miktar kalır', () {
      final b = hareketBakiyeleri([
        _lot('a1', 10, _g(1)),
        _lot('s1', 4, _g(2), kind: AssetKind.sell, satis: null),
      ]);
      expect(_m(b['s1']), (once: 10.0, sonra: 6.0));
      expect(b['s1']!.onceDeger, isNull);
      expect(b['s1']!.sonraDeger, isNull);
    });

    test('sıfır fiyat: değer yok', () {
      final b = hareketBakiyeleri([_lot('a1', 10, _g(1), alis: 0)]);
      expect(b['a1']!.sonra, 10);
      expect(b['a1']!.sonraDeger, isNull);
    });
  });
}
