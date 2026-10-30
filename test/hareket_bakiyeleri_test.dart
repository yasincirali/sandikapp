import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

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
}) =>
    Asset(
      id: id,
      userId: user,
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      sellPrice: 120,
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

void main() {
  test('alım ve satım: önceki/sonraki miktar', () {
    final b = hareketBakiyeleri([
      _lot('s1', 4, _g(3), kind: AssetKind.sell),
      _lot('a1', 10, _g(1)),
      _lot('a2', 6, _g(2)),
    ]);
    expect(b['a1'], (once: 0.0, sonra: 10.0));
    expect(b['a2'], (once: 10.0, sonra: 16.0));
    expect(b['s1'], (once: 16.0, sonra: 12.0));
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
    expect(b['s1'], (once: 5.0, sonra: 0.0));
    expect(b['a2'], (once: 0.0, sonra: 3.0));
  });

  test('aynı anda alım satımdan önce sayılır', () {
    final b = hareketBakiyeleri([
      _lot('s1', 5, _g(1), kind: AssetKind.sell),
      _lot('a1', 5, _g(1)),
    ]);
    expect(b['a1'], (once: 0.0, sonra: 5.0));
    expect(b['s1'], (once: 5.0, sonra: 0.0));
  });

  test('ortakların aynı hissesi netleşmez', () {
    final b = hareketBakiyeleri([
      _lot('a1', 10, _g(1), user: 'ben'),
      _lot('o1', 7, _g(2), user: 'ortak'),
      _lot('s1', 3, _g(3), kind: AssetKind.sell, user: 'ben'),
    ]);
    expect(b['o1'], (once: 0.0, sonra: 7.0));
    expect(b['s1'], (once: 10.0, sonra: 7.0));
  });

  test('farklı varlıklar ayrı yürür', () {
    final b = hareketBakiyeleri([
      _lot('a1', 10, _g(1)),
      _lot('x1', 2, _g(2), ticker: 'ASELS.IS'),
    ]);
    expect(b['x1'], (once: 0.0, sonra: 2.0));
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
    expect(b['x1'], (once: 0.0, sonra: 2.0));
  });

  test('temettü miktara girmez ve bakiye almaz', () {
    final b = hareketBakiyeleri([
      _lot('a1', 10, _g(1)),
      _lot('t1', 0, _g(2), kind: AssetKind.dividend, dividend: 50),
      _lot('a2', 5, _g(3)),
    ]);
    expect(b.containsKey('t1'), isFalse);
    expect(b['a2'], (once: 10.0, sonra: 15.0));
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
    expect(b['a3'], (once: 10.0, sonra: 15.0));
  });

  test('mevduat ve BES için bakiye yok', () {
    final b = hareketBakiyeleri([
      _lot('m1', 100000, _g(1), type: AssetType.mevduat, ticker: 'MEVDUAT:1'),
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
    expect(yeni['a3'], (once: 15.0, sonra: 16.0));
  });

  // UX raporu 30 Eki §4: ilk alımda "0 → 550 lot" sağdaki "Alım · 550
  // lot"u tekrar ediyordu; önceki bakiye 0 iken satır yok.
  test('ilk alımda bakiye satırı yok, sonraki alımda var', () {
    final l = AppLocalizationsTr();
    final lot = _lot('a1', 550, _g(1));
    expect(hareketBakiyeMetni(l, lot, (once: 0.0, sonra: 550.0)), isNull);
    final m = hareketBakiyeMetni(l, lot, (once: 550.0, sonra: 1100.0));
    expect(m, isNotNull);
    expect(m!.gorunen, contains('550'));
  });
}
