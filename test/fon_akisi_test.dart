import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/fon_akisi.dart';

/// Fon para akışı özeti (Balina B1) — saf hesap.
///
/// ## Bu dosyanın kovaladığı şeyler
/// 1. **Uydurma yok.** Akışı olmayan hafta `null` kalır (sıfır değil); akış
///    satırı hiç yoksa ya da veri bayatsa özet kurulmaz.
/// 2. **"Son hafta" verisi olan en yeni haftadır**, takvimdeki hafta değil.
/// 3. **Yatırımcı farkı yalnız ardışık iki bilinen günde** hesaplanır.
/// 4. **Bozuk satır atılır**, tahminle doldurulmaz.
DateTime _g(int ay, int gun) => DateTime.utc(2026, ay, gun);

FonAkisGunu _gun(int ay, int gun, double? akis,
        {double deger = 1e9, int? kisi}) =>
    FonAkisGunu(
        tarih: _g(ay, gun),
        portfoyDegeri: deger,
        netAkis: akis,
        yatirimci: kisi);

void main() {
  // 2026-10-04 Pazar. Son veri 2 Ekim Cuma.
  final simdi = DateTime(2026, 10, 4, 22);

  group('fonAkisOzeti', () {
    test('son hafta = verisi olan en yeni hafta; günleri toplanır', () {
      final ozet = fonAkisOzeti([
        _gun(9, 25, 5e6), // önceki hafta (21–25 Eyl)
        _gun(9, 28, 10e6), // Pazartesi
        _gun(9, 29, -4e6),
        _gun(10, 2, 6e6, deger: 2.4e9), // Cuma
      ], const [], simdi: simdi)!;

      expect(ozet.sonHaftaNet, 12e6);
      expect(ozet.sonHaftaIlkGun, _g(9, 28));
      expect(ozet.veriTarihi, _g(10, 2));
      expect(ozet.buyukluk, 2.4e9);
      expect(ozet.haftalar, hasLength(haftaSayisi));
      expect(ozet.haftalar.last.baslangic, _g(9, 28));
      expect(ozet.haftalar.last.net, 12e6);
      expect(ozet.haftalar[haftaSayisi - 2].baslangic, _g(9, 21));
      expect(ozet.haftalar[haftaSayisi - 2].net, 5e6);
    });

    test('akışı olmayan hafta null kalır — sıfır yazılmaz', () {
      final ozet = fonAkisOzeti([
        _gun(9, 8, 1e6), // 7 Eyl haftası
        _gun(10, 1, 2e6),
      ], const [], simdi: simdi)!;
      // 14 ve 21 Eyl haftalarında satır yok.
      final net = {for (final h in ozet.haftalar) h.baslangic: h.net};
      expect(net[_g(9, 7)], 1e6);
      expect(net[_g(9, 14)], isNull);
      expect(net[_g(9, 21)], isNull);
      expect(net[_g(9, 28)], 2e6);
    });

    test('pencere dışındaki eski hafta grafiğe girmez', () {
      final ozet = fonAkisOzeti([
        _gun(7, 1, 9e9), // 8 haftadan eski
        _gun(10, 1, 2e6),
      ], const [], simdi: simdi)!;
      expect(ozet.haftalar.first.baslangic, _g(8, 10));
      expect(ozet.haftalar.where((h) => h.net == 9e9), isEmpty);
    });

    test('hiç akış satırı yoksa özet kurulmaz', () {
      expect(fonAkisOzeti(const [], const [], simdi: simdi), isNull);
      // İlk gözlem: büyüklük var ama akış henüz hesaplanamadı.
      expect(fonAkisOzeti([_gun(10, 2, null)], const [], simdi: simdi), isNull);
    });

    test('veri bayatsa özet kurulmaz (eski sayı güncel gibi gösterilmez)', () {
      final gunler = [_gun(9, 21, 1e6)];
      // 21 Eyl → 4 Eki = 13 gün > 12 gün sınırı.
      expect(fonAkisOzeti(gunler, const [], simdi: simdi), isNull);
      // 12 gün tam sınırda hâlâ gösterilir (uzun bayram payı).
      expect(
          fonAkisOzeti(gunler, const [], simdi: DateTime(2026, 10, 3, 23)),
          isNotNull);
    });

    test('sıra karışık gelse de sonuç aynı', () {
      final a = fonAkisOzeti(
          [_gun(10, 2, 6e6), _gun(9, 28, 10e6)], const [],
          simdi: simdi)!;
      expect(a.veriTarihi, _g(10, 2));
      expect(a.sonHaftaNet, 16e6);
    });

    test('akışı null olan en yeni gün büyüklüğü ve tarihi yine verir', () {
      // Fon bir gün atlamış: son satırın akışı yok ama veri tarihi odur.
      final ozet = fonAkisOzeti(
          [_gun(9, 30, 3e6), _gun(10, 2, null, deger: 5e9)], const [],
          simdi: simdi)!;
      expect(ozet.veriTarihi, _g(10, 2));
      expect(ozet.buyukluk, 5e9);
      expect(ozet.sonHaftaNet, 3e6);
    });
  });

  group('yatırımcı sayısı', () {
    test('ardışık iki günde sayı varsa fark verilir', () {
      final ozet = fonAkisOzeti([
        _gun(10, 1, 1e6, kisi: 40506),
        _gun(10, 2, 2e6, kisi: 40518),
      ], const [], simdi: simdi)!;
      expect(ozet.yatirimci, 40518);
      expect(ozet.yatirimciDegisimi, 12);
    });

    test('önceki günün sayısı yoksa fark YOK, sayı var', () {
      final ozet = fonAkisOzeti([
        _gun(9, 30, 1e6, kisi: 40000),
        _gun(10, 1, 1e6), // sayı bilinmiyor
        _gun(10, 2, 2e6, kisi: 40518),
      ], const [], simdi: simdi)!;
      expect(ozet.yatirimci, 40518);
      // 30 Eyl → 2 Eki farkı iki günün toplamı olurdu; verilmez.
      expect(ozet.yatirimciDegisimi, isNull);
    });

    test('son günün sayısı yoksa satır hiç yok', () {
      final ozet =
          fonAkisOzeti([_gun(10, 2, 2e6)], const [], simdi: simdi)!;
      expect(ozet.yatirimci, isNull);
      expect(ozet.yatirimciDegisimi, isNull);
    });
  });

  group('olaylar', () {
    FonBalinaOlayi olay(int ay, int gun, double tutar) => FonBalinaOlayi(
        tarih: _g(ay, gun),
        tutar: tutar,
        buyuklukOrani: 0.031,
        sapmaKati: 4.2);

    test('yeniden eskiye, 30 günle ve 4 satırla sınırlı', () {
      final ozet = fonAkisOzeti(
        [_gun(10, 2, 1e6)],
        [
          olay(8, 20, 9e6), // 30 günden eski
          olay(9, 10, 1e6),
          olay(9, 29, -2e6),
          olay(9, 15, 3e6),
          olay(9, 22, 4e6),
          olay(9, 25, 5e6),
        ],
        simdi: simdi,
      )!;
      expect(ozet.olaylar.map((o) => o.tarih),
          [_g(9, 29), _g(9, 25), _g(9, 22), _g(9, 15)]);
      expect(ozet.olaylar.first.giris, isFalse);
    });

    test('olay gününün yatırımcı farkı günlük satırlardan eklenir', () {
      final ozet = fonAkisOzeti(
        [
          _gun(9, 28, 1e6, kisi: 100),
          _gun(9, 29, 50e6, kisi: 112),
          _gun(9, 30, 1e6),
          _gun(10, 1, -40e6, kisi: 90),
        ],
        [olay(9, 29, 50e6), olay(10, 1, -40e6)],
        simdi: simdi,
      )!;
      final fark = {
        for (final o in ozet.olaylar) o.tarih: o.yatirimciDegisimi
      };
      expect(fark[_g(9, 29)], 12);
      // 30 Eyl'ün sayısı yok → 1 Eki farkı bilinmez.
      expect(fark[_g(10, 1)], isNull);
    });
  });

  group('dönem akışı (1 ay / 3 ay)', () {
    // 1 Eylül'den 2 Ekim'e her hafta içi gün; günde +1 mn akış.
    List<FonAkisGunu> seri({double? delik}) {
      final out = <FonAkisGunu>[];
      var d = DateTime.utc(2026, 9, 1);
      while (!d.isAfter(_g(10, 2))) {
        if (d.weekday <= 5) {
          final bosGun = delik != null && d == _g(9, 15);
          out.add(FonAkisGunu(
              tarih: d,
              portfoyDegeri: d == _g(9, 2) ? 100e6 : 120e6,
              netAkis: bosGun ? null : 1e6));
        }
        d = d.add(const Duration(days: 1));
      }
      return out;
    }

    test('oran = akış / dönem BAŞINDAKİ büyüklük; kalan fiyat etkisi', () {
      final ozet = fonAkisOzeti(seri(), const [], simdi: simdi)!;
      final ay1 = ozet.ay1!;
      // Dönem başı 2 Eylül (2 Ekim − 30 gün), büyüklük 100 mn.
      // 3 Eylül–2 Ekim arası 22 işlem günü × 1 mn = 22 mn.
      expect(ay1.para, 22e6);
      expect(ay1.paraOrani, closeTo(0.22, 1e-9));
      // 100 → 120 mn: toplam %20; fiyat etkisi %20 − %22 = −%2.
      expect(ay1.toplamDegisim, closeTo(0.20, 1e-9));
      expect(ay1.fiyatEtkisi, closeTo(-0.02, 1e-9));
    });

    test('dönem içinde akışı bilinmeyen gün varsa oran VERİLMEZ', () {
      final ozet = fonAkisOzeti(seri(delik: 1), const [], simdi: simdi)!;
      expect(ozet.ay1, isNull);
    });

    test('geçmiş dönemi kapsamıyorsa oran verilmez (3 ay için 1 aylık veri)',
        () {
      final ozet = fonAkisOzeti(seri(), const [], simdi: simdi)!;
      expect(ozet.ay3, isNull);
    });

    test('dönem başı satırı hedeften çok eskiyse oran verilmez', () {
      // Tek eski satır 10 Ağustos, sonra 28 Eylül'e kadar boşluk: "1 ay"
      // aslında 7 haftayı kapsardı.
      final ozet = fonAkisOzeti([
        _gun(8, 10, 1e6),
        _gun(9, 28, 1e6),
        _gun(10, 2, 1e6),
      ], const [], simdi: simdi)!;
      expect(ozet.ay1, isNull);
    });
  });

  test('oranAnlamli: akış ya da değişim dönem başı büyüklüğünü aşınca false',
      () {
    expect(
        const DonemAkisi(para: 1, paraOrani: 0.5, toplamDegisim: -0.9)
            .oranAnlamli,
        isTrue);
    expect(
        const DonemAkisi(para: 1, paraOrani: 3.028, toplamDegisim: -0.604)
            .oranAnlamli,
        isFalse);
    expect(
        const DonemAkisi(para: 1, paraOrani: 0.4, toplamDegisim: 1.6)
            .oranAnlamli,
        isFalse);
  });

  group('hafta serisi', () {
    test('son haftadan geriye aynı yönlü haftalar sayılır', () {
      final ozet = fonAkisOzeti([
        _gun(9, 8, 5e6), // giriş — seriyi keser
        _gun(9, 15, -1e6),
        _gun(9, 22, -2e6),
        _gun(9, 29, -3e6),
      ], const [], simdi: simdi)!;
      expect(ozet.seri!.hafta, 3);
      expect(ozet.seri!.giris, isFalse);
    });

    test('tek hafta seri değildir; verisiz hafta seriyi keser', () {
      expect(
          fonAkisOzeti([_gun(9, 22, 2e6), _gun(9, 29, -3e6)], const [],
                  simdi: simdi)!
              .seri,
          isNull);
      // 22 Eylül haftası yok: 15 ve 29 Eylül ardışık sayılmaz.
      expect(
          fonAkisOzeti([_gun(9, 15, -2e6), _gun(9, 29, -3e6)], const [],
                  simdi: simdi)!
              .seri,
          isNull);
    });
  });

  group('ardışık olay günleri birleşir', () {
    FonBalinaOlayi olay(int ay, int gun, double tutar, {double kat = 4}) =>
        FonBalinaOlayi(
            tarih: _g(ay, gun),
            tutar: tutar,
            buyuklukOrani: 0.03,
            sapmaKati: kat);

    final gunler = [
      _gun(9, 18, -1e6), // Cuma
      _gun(9, 21, -50e6), // Pazartesi
      _gun(9, 22, -40e6),
      _gun(9, 23, 1e6),
      _gun(9, 24, 60e6),
      _gun(10, 2, 1e6),
    ];

    test('aynı yönlü ardışık iki gün tek satır: tutar ve oran toplanır', () {
      final ozet = fonAkisOzeti(
        gunler,
        [olay(9, 21, -50e6, kat: 4.9), olay(9, 22, -40e6, kat: 3.7)],
        simdi: simdi,
      )!;
      expect(ozet.olaylar, hasLength(1));
      final o = ozet.olaylar.single;
      expect(o.ilkGun, _g(9, 21));
      expect(o.tarih, _g(9, 22));
      expect(o.gunSayisi, 2);
      expect(o.tutar, -90e6);
      expect(o.buyuklukOrani, closeTo(0.06, 1e-9));
      expect(o.sapmaKati, 4.9);
    });

    test('Cuma ve Pazartesi ardışık işlem günüdür', () {
      final ozet = fonAkisOzeti(
        gunler,
        [olay(9, 18, -30e6), olay(9, 21, -50e6)],
        simdi: simdi,
      )!;
      expect(ozet.olaylar.single.gunSayisi, 2);
      expect(ozet.olaylar.single.ilkGun, _g(9, 18));
    });

    test('yön değişirse ya da arada gün varsa birleşmez', () {
      final ozet = fonAkisOzeti(
        gunler,
        [olay(9, 22, -40e6), olay(9, 24, 60e6), olay(9, 21, -50e6)],
        simdi: simdi,
      )!;
      // 21+22 birleşir; 24 (giriş, arada 23 var) ayrı.
      expect(ozet.olaylar.map((o) => o.gunSayisi), [1, 2]);
      expect(ozet.olaylar.first.giris, isTrue);
      expect(ozet.olaylar.first.ilkGun, isNull);
    });
  });

  group('satır ayrıştırma', () {
    test('sunucu satırı okunur; sayı metin gelse de tarih güne iner', () {
      final g = FonAkisGunu.satirdan({
        'tarih': '2026-10-02',
        'portfoy_degeri': 2385068751.83,
        'net_akis': -10851000,
        'yatirimci': 40518,
      })!;
      expect(g.tarih, _g(10, 2));
      expect(g.portfoyDegeri, 2385068751.83);
      expect(g.netAkis, -10851000);
      expect(g.yatirimci, 40518);
    });

    test('akış ve yatırımcı null kalabilir', () {
      final g = FonAkisGunu.satirdan(
          {'tarih': '2026-10-02', 'portfoy_degeri': 100, 'net_akis': null})!;
      expect(g.netAkis, isNull);
      expect(g.yatirimci, isNull);
    });

    test('bozuk gün satırı atılır', () {
      expect(FonAkisGunu.satirdan({'tarih': 'dün', 'portfoy_degeri': 1}),
          isNull);
      expect(FonAkisGunu.satirdan({'tarih': '2026-10-02'}), isNull);
      expect(
          FonAkisGunu.satirdan({'tarih': '2026-10-02', 'portfoy_degeri': 0}),
          isNull);
    });

    test('olay satırı okunur; bozuk olan atılır', () {
      final o = FonBalinaOlayi.satirdan({
        'tarih': '2026-09-29',
        'tur': 'fon_giris',
        'tutar': 398e6,
        'buyukluk_orani': 0.031,
        'sapma_kati': 4.2,
      })!;
      expect(o.giris, isTrue);
      expect(o.tutar, 398e6);
      expect(
          FonBalinaOlayi.satirdan({
            'tarih': '2026-09-29',
            'tutar': 0,
            'buyukluk_orani': 0.031,
            'sapma_kati': 4.2,
          }),
          isNull);
      expect(FonBalinaOlayi.satirdan({'tarih': '2026-09-29', 'tutar': 5}),
          isNull);
    });
  });
}
