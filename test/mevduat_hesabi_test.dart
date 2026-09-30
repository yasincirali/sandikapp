import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/services/mevduat_hesabi.dart';

/// Mevduat birim değeri — sözleşmeden, uydurmasız (2026-09-30).
///
/// Kilitlenen kurallar (`mevduat_hesabi.dart` başlığı):
///   · vadeli dönem basit faiz, vade sonunda anaparaya eklenir (zincir);
///   · vadesiz dönem günlük bileşik;
///   · net = brüt × (1 − stopaj);
///   · son vade dolup yeni dönem girilmediyse değer DÜZ kalır.
void main() {
  MevduatDonemi donem(DateTime bas, int? gun,
          {double faiz = 42, double stopaj = 17.5, String id = 'd'}) =>
      MevduatDonemi(
        id: id,
        sozlesmeId: 's',
        baslangic: bas,
        vadeSonu: gun == null ? null : bas.add(Duration(days: gun)),
        yillikFaiz: faiz,
        stopaj: stopaj,
      );

  final bas = DateTime(2026, 9, 1);
  const net32 = 0.42 * 0.825 * 32 / 365;

  test('çalışma örneği: ₺250.000, %42, 32 gün, %17,5 stopaj → +₺7.595', () {
    final net = MevduatHesabi.donemNetFaizi(
        anapara: 250000, yillikFaiz: 42, stopaj: 17.5, gun: 32);
    expect(net, closeTo(7594.52, 0.01));
    // Aynı sayı birim değerden de çıkar — form ile portföy aynı motor.
    final b = MevduatHesabi.birimDeger(
        [donem(bas, 32)], bas.add(const Duration(days: 32)))!;
    expect(250000 * (b - 1), closeTo(net, 0.01));
  });

  test('başlamadan önce değer yok (sıfır değil)', () {
    expect(MevduatHesabi.birimDeger([donem(bas, 32)], DateTime(2026, 8, 31)),
        isNull);
  });

  test('vadeli dönem doğrusal tahakkuk eder', () {
    final yari = MevduatHesabi.birimDeger(
        [donem(bas, 32)], bas.add(const Duration(days: 16)))!;
    expect(yari, closeTo(1 + net32 / 2, 1e-12));
  });

  test('vade doldu, yenilenmedi: değer DÜZ kalır (yenileme faizi uydurulmaz)',
      () {
    final d = [donem(bas, 32)];
    final vade = MevduatHesabi.birimDeger(d, bas.add(const Duration(days: 32)))!;
    final sonra =
        MevduatHesabi.birimDeger(d, bas.add(const Duration(days: 60)))!;
    expect(sonra, vade);
    expect(MevduatHesabi.vadesiDoldu(d, bas.add(const Duration(days: 40))),
        isTrue);
  });

  test('yenileme zinciri: yeni dönem vade sonundaki tutardan bileşir', () {
    final d1 = donem(bas, 32, id: 'a');
    final d2 = donem(bas.add(const Duration(days: 32)), 32, faiz: 40, id: 'b');
    final son = MevduatHesabi.birimDeger(
        [d2, d1], bas.add(const Duration(days: 64)))!; // sırasız verildi
    const net2 = 0.40 * 0.825 * 32 / 365;
    expect(son, closeTo((1 + net32) * (1 + net2), 1e-12));
    expect(MevduatHesabi.donemSayisi([d1, d2]), 2);
  });

  test('vade ile yenileme arasındaki boşlukta faiz işlemez', () {
    final d1 = donem(bas, 32, id: 'a');
    final d2 = donem(bas.add(const Duration(days: 40)), 32, id: 'b');
    final arada = MevduatHesabi.birimDeger(
        [d1, d2], bas.add(const Duration(days: 36)))!;
    expect(arada, closeTo(1 + net32, 1e-12));
  });

  test('vadesiz: günlük bileşik', () {
    final d = [donem(bas, null, faiz: 36.5, stopaj: 0)];
    final v = MevduatHesabi.birimDeger(d, bas.add(const Duration(days: 2)))!;
    expect(v, closeTo(1.001 * 1.001, 1e-12));
    expect(MevduatHesabi.vadesiDoldu(d, DateTime(2030)), isFalse);
    expect(MevduatHesabi.vadeyeKalanGun(d, DateTime(2030)), isNull);
  });

  test('vadesiz hesapta oran değişimi yeni dönemdir, eski birikim korunur',
      () {
    final d1 = donem(bas, null, faiz: 36.5, stopaj: 0, id: 'a');
    final d2 = donem(bas.add(const Duration(days: 1)), null,
        faiz: 73, stopaj: 0, id: 'b');
    final v = MevduatHesabi.birimDeger(
        [d1, d2], bas.add(const Duration(days: 2)))!;
    expect(v, closeTo(1.001 * 1.002, 1e-12));
  });

  test('önerilen stopaj vadeye göre (10041 sayılı karar)', () {
    final t = DateTime(2026, 9, 30);
    expect(onerilenStopaj(t, 32), 17.5);
    expect(onerilenStopaj(t, 181), 17.5);
    expect(onerilenStopaj(t, 365), 15);
    expect(onerilenStopaj(t, 400), 10);
    expect(onerilenStopaj(t, null), 17.5, reason: 'vadesiz = 6 aya kadar');
  });

  test('seri: başlangıç öncesi nokta yok, son nokta "şimdi", nokta sayısı sınırlı',
      () {
    final son = bas.add(const Duration(days: 10));
    final s = MevduatHesabi.seri([donem(bas, 32)],
        bas: bas.subtract(const Duration(days: 5)),
        son: son,
        adim: const Duration(days: 1));
    expect(s.first.$1, greaterThanOrEqualTo(bas.millisecondsSinceEpoch));
    expect(s.last.$1, son.millisecondsSinceEpoch);
    final sik = MevduatHesabi.seri([donem(bas, 32)],
        bas: bas, son: bas.add(const Duration(days: 30)),
        adim: const Duration(minutes: 5));
    expect(sik.length, lessThanOrEqualTo(2001));
  });

  test('vadeye kalan gün ve ilerleme', () {
    final d = [donem(bas, 32)];
    final an = DateTime(2026, 9, 21, 15);
    expect(MevduatHesabi.vadeyeKalanGun(d, an), 12);
    expect(MevduatHesabi.donemIlerlemesi(d, an), closeTo(0.645, 0.01));
  });

  test('aralık eşlemeleri', () {
    expect(aralikSuresi('1mo'), const Duration(days: 31));
    expect(aralikAdimi('5m'), const Duration(minutes: 5));
    expect(aralikAdimi('1wk'), const Duration(days: 7));
    expect(aralikAdimi('??'), const Duration(days: 1));
  });
}
