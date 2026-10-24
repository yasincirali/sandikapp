import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/seni_ilgilendiren_gunler.dart';
import 'package:portfoy_takip/services/temettu_gecmisi.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';

/// "Seni ilgilendiren günler" saf kararları (2026-10-21).
void main() {
  final bugun = DateTime.utc(2026, 10, 21); // Çarşamba
  GunOlayi tcmb(int a, int g) =>
      GunOlayi(gun: DateTime.utc(2026, a, g), tur: GunOlayiTuru.tcmb);
  GunOlayi fomc(int a, int g) =>
      GunOlayi(gun: DateTime.utc(2026, a, g), tur: GunOlayiTuru.fomc);
  GunOlayi temettu(String kod, int a, int g) => GunOlayi(
      gun: DateTime.utc(2026, a, g), tur: GunOlayiTuru.temettu, kod: kod);

  group('satır: iki günlük pencere', () {
    test('bugün, yarın, öbür gün satıra çıkar; üçüncü gün çıkmaz', () {
      for (final (g, cikar) in [
        (21, true),
        (22, true),
        (23, true),
        (24, false)
      ]) {
        expect(satirOlayi([tcmb(10, g)], bugun: bugun, kapatilanlar: const {}),
            cikar ? isNotNull : isNull,
            reason: '$g Ekim');
      }
    });

    test('geçmiş olay çıkmaz', () {
      expect(satirOlayi([tcmb(10, 20)], bugun: bugun, kapatilanlar: const {}),
          isNull);
    });

    test('olay yoksa null', () {
      expect(
          satirOlayi(const [], bugun: bugun, kapatilanlar: const {}), isNull);
    });

    test('en yakın olay seçilir; aynı günde makro temettüden önce', () {
      final o = satirOlayi(
          [temettu('THYAO', 10, 22), fomc(10, 23), tcmb(10, 22)],
          bugun: bugun,
          kapatilanlar: const {});
      expect(o, tcmb(10, 22));
    });

    test('kapatılan olay düşer, sıradaki iki gün içindeyse o gelir', () {
      final olaylar = [tcmb(10, 22), temettu('THYAO', 10, 23)];
      expect(
          satirOlayi(olaylar,
              bugun: bugun, kapatilanlar: {tcmb(10, 22).kimlik}),
          temettu('THYAO', 10, 23));
      expect(
          satirOlayi(olaylar, bugun: bugun, kapatilanlar: {
            tcmb(10, 22).kimlik,
            temettu('THYAO', 10, 23).kimlik,
          }),
          isNull);
    });

    test('kimlik tarihli ve kod içerir (kalıcı kayıt biçimi)', () {
      expect(tcmb(10, 22).kimlik, 'tcmb_2026-10-22');
      expect(temettu('THYAO', 1, 5).kimlik, 'temettu_THYAO_2026-01-05');
    });
  });

  group('sayfa listesi', () {
    test('14 gün (4 Kasım dahil, 5 Kasım hariç), tarihe göre sıralı', () {
      final l = yaklasanOlaylar(
          [fomc(10, 28), tcmb(11, 5), tcmb(10, 22), tcmb(11, 4)],
          bugun: bugun,
          kapatilanlar: const {});
      expect(l, [tcmb(10, 22), fomc(10, 28), tcmb(11, 4)]);
    });
  });

  group('yuva sırası: bilgi eksik > takvim > radar > güncelleme > öneri', () {
    final o = tcmb(10, 22);
    test('bilgi eksik her şeyi geçer', () {
      expect(
          anaSayfaDurtusu(
              bilgiEksikGorunur: true, takvimOlayi: o, oneriVar: true),
          AnaSayfaDurtusu.bilgiEksik);
    });
    test('takvim olayı öneriyi geçer', () {
      expect(
          anaSayfaDurtusu(
              bilgiEksikGorunur: false, takvimOlayi: o, oneriVar: true),
          AnaSayfaDurtusu.takvim);
    });
    test('olay yoksa öneri', () {
      expect(
          anaSayfaDurtusu(
              bilgiEksikGorunur: false, takvimOlayi: null, oneriVar: true),
          AnaSayfaDurtusu.oneri);
    });
    // Bugün altı tek yuva (2026-10-24): veri kalitesi > takvim > radar >
    // güncelleme > öneri. Her ikili sıra ayrı ayrı kilitli.
    test('radar: takvimin altında, güncelleme ve önerinin üstünde', () {
      AnaSayfaDurtusu? y({
        bool eksik = false,
        GunOlayi? takvim,
        bool radar = false,
        bool guncelleme = false,
        bool oneri = false,
      }) =>
          anaSayfaDurtusu(
              bilgiEksikGorunur: eksik,
              takvimOlayi: takvim,
              oneriVar: oneri,
              guncellemeVar: guncelleme,
              radarVar: radar);
      expect(
          y(eksik: true, takvim: o, radar: true, guncelleme: true, oneri: true),
          AnaSayfaDurtusu.bilgiEksik);
      expect(y(eksik: true, radar: true), AnaSayfaDurtusu.bilgiEksik);
      expect(y(takvim: o, radar: true, guncelleme: true, oneri: true),
          AnaSayfaDurtusu.takvim);
      expect(
          y(radar: true, guncelleme: true, oneri: true), AnaSayfaDurtusu.radar);
      expect(y(radar: true, oneri: true), AnaSayfaDurtusu.radar);
      expect(y(guncelleme: true, oneri: true), AnaSayfaDurtusu.guncelleme);
      expect(y(radar: true), AnaSayfaDurtusu.radar);
    });
    test('radar verilmezse eski sıra birebir', () {
      expect(
          anaSayfaDurtusu(
              bilgiEksikGorunur: false,
              takvimOlayi: null,
              oneriVar: true,
              guncellemeVar: true),
          AnaSayfaDurtusu.guncelleme);
    });
    test('hiçbiri yoksa null', () {
      expect(
          anaSayfaDurtusu(
              bilgiEksikGorunur: false, takvimOlayi: null, oneriVar: false),
          isNull);
    });
  });

  group('temettü günleri', () {
    test('geçen yılın hak günü bu yıla taşınır, .IS eki düşer', () {
      final l = temettuGunleri({
        'THYAO.IS': [DateTime.utc(2025, 10, 23), DateTime.utc(2025, 6, 2)],
      }, bugun: bugun);
      expect(l, [temettu('THYAO', 10, 23)]);
    });

    test('29 Şubat 28 Şubat olur (1 Mart\'a taşmaz)', () {
      final l = temettuGunleri({
        'X.IS': [DateTime.utc(2028, 2, 29)],
      }, bugun: bugun);
      expect(l.single.gun, DateTime.utc(2029, 2, 28));
    });

    test('tahmin satırı hak günlerini taşır (tek temettü yolu)', () {
      final t = temettuTahmini([
        TahminGirdisi(ad: 'THY', sembol: 'THYAO.IS', lot: 10, olaylar: [
          TemettuOlayi(hakTarihi: DateTime.utc(2025, 10, 23), tutarPay: 3),
        ]),
      ], stopaj: null, simdi: DateTime.utc(2026, 10, 21));
      expect(t.satirlar.single.hakGunleri, [DateTime.utc(2025, 10, 23)]);
    });
  });

  group('makro takvim', () {
    test('TCMB PPK Perşembe, Fed karar günü Çarşamba (yazım hatası kilidi)',
        () {
      for (final o in makroTakvim) {
        expect(o.gun.weekday,
            o.tur == GunOlayiTuru.tcmb ? DateTime.thursday : DateTime.wednesday,
            reason: o.kimlik);
      }
    });

    test('kimlikler tekil, liste yalnız makro', () {
      expect(
          makroTakvim.map((o) => o.kimlik).toSet().length, makroTakvim.length);
      expect(makroTakvim.every((o) => o.kod == null), isTrue);
    });

    test('yarın (22 Eki 2026) TCMB kararı satıra çıkar', () {
      expect(satirOlayi(makroTakvim, bugun: bugun, kapatilanlar: const {}),
          tcmb(10, 22));
    });
  });
}
