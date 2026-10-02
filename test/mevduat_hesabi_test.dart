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

  test('vadeli dönem vade içinde DÜZ, faiz vade sonunda eklenir (2026-10-02)',
      () {
    final d = [donem(bas, 32)];
    final vade = bas.add(const Duration(days: 32));
    expect(MevduatHesabi.birimDeger(d, bas.add(const Duration(days: 16))),
        1.0);
    expect(
        MevduatHesabi.birimDeger(d, vade.subtract(const Duration(seconds: 1))),
        1.0,
        reason: 'vade gününden bir saniye önce bile faiz eklenmemiş');
    expect(MevduatHesabi.birimDeger(d, vade), closeTo(1 + net32, 1e-12));
  });

  test('vade içinde beklenen net faiz: vade sonunda eklenecek tutar', () {
    final d = [donem(bas, 32)];
    expect(MevduatHesabi.vadeSonuNetFaizi(d, 250000),
        closeTo(250000 * net32, 1e-6));
    expect(MevduatHesabi.vadeSonuNetFaizi([donem(bas, null)], 250000),
        isNull,
        reason: 'günlük faizlide vade yok');
  });

  test('vade içinde oran değişti: kazanç SON orana göre (dönem yerinde)', () {
    // Kullanıcı kararı 2026-10-02: oran vade içinde %42 → %38 olursa vade
    // sonunda tüm dönem %38 üzerinden eklenir; vade öncesi değer düz kaldığı
    // için geri alınan bir kazanç yok.
    final once = [donem(bas, 32, faiz: 42)];
    final sonra = [donem(bas, 32, faiz: 38)];
    final g16 = bas.add(const Duration(days: 16));
    expect(MevduatHesabi.birimDeger(once, g16),
        MevduatHesabi.birimDeger(sonra, g16));
    expect(MevduatHesabi.vadeSonuNetFaizi(sonra, 100000),
        closeTo(100000 * 0.38 * 0.825 * 32 / 365, 1e-6));
  });

  test('eski kayıt: vadeden önce açılmış sonraki dönem o güne kadarki faizi '
      'geçişte ekler (geçmiş değer değişmez)', () {
    final g10 = bas.add(const Duration(days: 10));
    final d = [donem(bas, 32, id: 'a'), donem(g10, 32, faiz: 40, id: 'b')];
    expect(MevduatHesabi.birimDeger(d, g10),
        closeTo(1 + 0.42 * 0.825 * 10 / 365, 1e-12));
    expect(MevduatHesabi.birimDeger(d, g10.add(const Duration(days: 5))),
        MevduatHesabi.birimDeger(d, g10));
  });

  test('portföy şeridi özeti: vadeli ve günlük faizli', () {
    final g8 = bas.add(const Duration(days: 8));
    final o = MevduatHesabi.ozet([donem(bas, 32)], 100000, g8)!;
    expect(o.vade, bas.add(const Duration(days: 32)));
    expect(o.ilerleme, closeTo(0.25, 1e-9));
    expect(o.kalanGun, 24);
    expect(o.doldu, isFalse);
    expect(o.vadeSonuNet, closeTo(100000 * net32, 1e-6));
    expect(o.gunlukNet, isNull);

    final v = MevduatHesabi.ozet(
        [donem(bas, null, faiz: 36.5, stopaj: 0)], 100000, bas)!;
    expect(v.vade, isNull);
    expect(v.gunlukNet, closeTo(100, 1e-9));
    expect(v.vadeSonuNet, isNull);
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

  test('önerilen stopaj açılış gününe göre: 9487 dönemi (2025-02-01..07-08)',
      () {
    // 2025 Mart'ında açılan mevduata 10041'in oranı önerilmez.
    final t = DateTime(2025, 3, 15);
    expect(onerilenStopaj(t, 32), 15);
    expect(onerilenStopaj(t, 365), 12);
    expect(onerilenStopaj(t, 730), 10);
    expect(onerilenStopaj(t, null), 15);
    // Sınır günleri: karar günü yeni oranla açılır.
    expect(onerilenStopaj(DateTime(2025, 7, 8), 32), 15);
    expect(onerilenStopaj(DateTime(2025, 7, 9), 32), 17.5);
    expect(onerilenStopaj(DateTime(2025, 2, 1), 365), 12);
  });

  group('bu dönem net (donemKazanci)', () {
    // Vadeli dönemde değer vade içinde düz; hareket gününden faiz alma
    // kuralı günlük faizli hesapta anlamlı — iç testler onunla.
    final d = [donem(bas, null, faiz: 45)];
    final vade = bas.add(const Duration(days: 32));
    double b(int g) =>
        MevduatHesabi.birimDeger(d, bas.add(Duration(days: g)))!;

    test('tek alım: dönemin net faizi', () {
      expect(MevduatHesabi.donemKazanci(d, [(bas, 100000)], vade),
          closeTo(100000 * (b(32) - 1), 1e-6));
    });

    test('vadeli: vade gelince dönemin tamamı, öncesinde 0', () {
      final dv = [donem(bas, 32, faiz: 45)];
      const n = 0.45 * 0.825;
      expect(
          MevduatHesabi.donemKazanci(
              dv, [(bas, 100000)], bas.add(const Duration(days: 16))),
          0);
      expect(MevduatHesabi.donemKazanci(dv, [(bas, 100000)], vade),
          closeTo(100000 * n * 32 / 365, 1e-6));
    });

    test('dönem içinde eklenen para kendi gününden faiz alır', () {
      final g16 = bas.add(const Duration(days: 16));
      final pay2 = 100000 / b(16);
      final k = MevduatHesabi.donemKazanci(
          d, [(bas, 100000), (g16, pay2)], vade);
      // Eski hesap (toplam pay × dönem büyümesi) yeni parayı dönem başından
      // saydı.
      expect(k, closeTo(100000 * (b(32) - 1) + pay2 * (b(32) - b(16)), 1e-6));
      expect(k, lessThan((100000 + pay2) * (b(32) - 1)));
    });

    test('dönem içi çekim: çekilen pay çekim gününe kadar sayılır', () {
      final g16 = bas.add(const Duration(days: 16));
      final k = MevduatHesabi.donemKazanci(
          d, [(bas, 100000), (g16, -40000)], vade);
      expect(k, closeTo(60000 * (b(32) - 1) + 40000 * (b(16) - 1), 1e-6));
    });

    test('yenilenmiş dönemde önceki dönemin alımı dönem başından sayılır', () {
      final d2 = [
        donem(bas, 32, faiz: 45, id: 'a'),
        donem(vade, 32, faiz: 40, id: 'b'),
      ];
      final son = vade.add(const Duration(days: 32));
      final basBirim = MevduatHesabi.birimDeger(d2, vade)!;
      final sonBirim = MevduatHesabi.birimDeger(d2, son)!;
      expect(MevduatHesabi.donemKazanci(d2, [(bas, 100000)], son),
          closeTo(100000 * (sonBirim - basBirim), 1e-6));
    });
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
