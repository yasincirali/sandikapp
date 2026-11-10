import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/milestone_service.dart';

/// Toplam kâr zirvesi kilometre taşı (`profit_high`).
///
/// Çapa: kutlanan şey piyasanın getirisi, para yatırmak değil. Kâr =
/// seri değeri − net yatırılan; alım ikisini aynı tutarda artırır.
Asset _alim(String id, double tutar, DateTime gun) => Asset(
      id: id,
      userId: 'u1',
      name: 'Test $id',
      ticker: 'TST',
      notes: '',
      type: AssetType.hisse,
      quantity: tutar / 100,
      purchasePrice: 100,
      currency: 'TRY',
      currentPrice: 100,
      kind: AssetKind.buy,
      addedDate: gun,
    );

/// [bas]'tan [son]'a her gün bir nokta; son noktanın değeri [sonDeger].
Map<int, double> _seri(DateTime bas, DateTime son, double deger,
    {double? sonDeger}) {
  final m = <int, double>{};
  for (var g = bas; !g.isAfter(son); g = g.add(const Duration(days: 1))) {
    m[g.millisecondsSinceEpoch] = deger;
  }
  if (sonDeger != null) m[son.millisecondsSinceEpoch] = sonDeger;
  return m;
}

void main() {
  final now = DateTime(2026, 11, 10);
  final bas = DateTime(2026, 9, 1);
  // Önceki zirve 100 ₺, 20 gün önce kaydedildi.
  const kayit = {'profit_high:2026-10-21:100'};

  test('piyasa getirisi önceki zirveyi %5 aşınca taş açılır', () {
    final r = MilestoneService.karZirvesi(
      seri: _seri(bas, now, 1100, sonDeger: 1200),
      lotlar: [_alim('a', 1000, bas)],
      kayitli: kayit,
      now: now,
    );
    expect(r, isNotNull);
    expect(r!.ilk, isFalse);
    expect(r.tas.kind, 'profit_high');
    expect(r.tas.rank, 200);
    expect(r.tas.value, '2026-11-10:200');
  });

  test('para yatırmak kâr üretmez: taş yok', () {
    // Dün 5.000 ₺ alım; değer de tam o kadar arttı.
    final r = MilestoneService.karZirvesi(
      seri: _seri(bas, now, 1100, sonDeger: 6100),
      lotlar: [
        _alim('a', 1000, bas),
        _alim('b', 5000, now.subtract(const Duration(days: 1))),
      ],
      kayitli: kayit,
      now: now,
    );
    expect(r, isNull);
  });

  test('%5 altında artış taş açmaz', () {
    final r = MilestoneService.karZirvesi(
      seri: _seri(bas, now, 1100, sonDeger: 1104),
      lotlar: [_alim('a', 1000, bas)],
      kayitli: kayit,
      now: now,
    );
    expect(r, isNull);
  });

  test('kâr sıfır ya da eksiyse zirve yok', () {
    final r = MilestoneService.karZirvesi(
      seri: _seri(bas, now, 900),
      lotlar: [_alim('a', 1000, bas)],
      kayitli: const {'profit_high:2026-10-01:-500'},
      now: now,
    );
    expect(r, isNull);
  });

  test('haftada en fazla bir kayıt', () {
    const yeni = {'profit_high:2026-11-05:100'};
    expect(MilestoneService.karZirvesiBekleyebilir(yeni, now), isFalse);
    final r = MilestoneService.karZirvesi(
      seri: _seri(bas, now, 1100, sonDeger: 2000),
      lotlar: [_alim('a', 1000, bas)],
      kayitli: yeni,
      now: now,
    );
    expect(r, isNull);
    // Yedi gün dolunca açılır.
    expect(
        MilestoneService.karZirvesiBekleyebilir(
            yeni, now.add(const Duration(days: 2))),
        isTrue);
  });

  test('30 günden kısa geçmiş: taş yok', () {
    final r = MilestoneService.karZirvesi(
      seri: _seri(now.subtract(const Duration(days: 20)), now, 1100,
          sonDeger: 2000),
      lotlar: [_alim('a', 1000, now.subtract(const Duration(days: 20)))],
      kayitli: kayit,
      now: now,
    );
    expect(r, isNull);
  });

  test('seride boşluk, sıfır ya da eksik bileşen varsa taş yok', () {
    final lot = [_alim('a', 1000, bas)];
    final bosluklu = _seri(bas, now, 1100, sonDeger: 2000)
      ..remove(DateTime(2026, 10, 10).millisecondsSinceEpoch)
      ..remove(DateTime(2026, 10, 11).millisecondsSinceEpoch);
    final sifirli = _seri(bas, now, 1100, sonDeger: 2000)
      ..[DateTime(2026, 10, 10).millisecondsSinceEpoch] = 0;
    for (final s in [bosluklu, sifirli]) {
      expect(
          MilestoneService.karZirvesi(
              seri: s, lotlar: lot, kayitli: kayit, now: now),
          isNull);
    }
    expect(
        MilestoneService.karZirvesi(
          seri: _seri(bas, now, 1100, sonDeger: 2000),
          lotlar: lot,
          kayitli: kayit,
          now: now,
          eksikBilesen: true,
        ),
        isNull);
    // Bayat seri (son nokta bir hafta önce) de eksik sayılır.
    expect(
        MilestoneService.karZirvesi(
          seri: _seri(bas, now.subtract(const Duration(days: 7)), 1100,
              sonDeger: 2000),
          lotlar: lot,
          kayitli: kayit,
          now: now,
        ),
        isNull);
  });

  test('hiç kayıt yoksa taban döner, kutlama değil', () {
    final r = MilestoneService.karZirvesi(
      seri: _seri(bas, now, 1500),
      lotlar: [_alim('a', 1000, bas)],
      kayitli: const {'portfolio_value:10000'},
      now: now,
    );
    expect(r, isNotNull);
    expect(r!.ilk, isTrue);
    expect(r.tas.rank, 500);
  });

  test('kâr zirvesi rozete dönmez ve en son seçilir', () {
    expect(
        MilestoneService.anahtardan('profit_high', '2026-11-10:200'), isNull);
    final kar = MilestoneService.karZirvesi(
      seri: _seri(bas, now, 1100, sonDeger: 1200),
      lotlar: [_alim('a', 1000, bas)],
      kayitli: kayit,
      now: now,
    )!
        .tas;
    final deger = MilestoneService.anahtardan('portfolio_value', '10000')!;
    expect(MilestoneService.pickOne([kar, deger]), deger);
    expect(MilestoneService.pickOne([kar]), kar);
  });
}
