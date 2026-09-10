import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Gün içi ("GÜNLÜK") seride FONUN günlük değişimi.
///
/// ## Neden basamak var
/// TEFAS gün içi NAV yayınlamıyor; fon gün boyu `currentPrice` ile SABİT
/// çiziliyordu. Tür dökümünde `first` ve `last` aynı sayı oluyor, değişim
/// tanım gereği %0 çıkıyordu — oysa iki NAV arasında gerçek bir fark var
/// (kullanıcı bildirimi 2026-09-10: "günlükte fon seçilince de değişim yok
/// gözüküyor ancak aslında var").
///
/// ## Neden çapa SABİT bir saat
/// İlk düzeltmede basamak, seansın ilk gerçek fiyat verisine çapalıydı. O
/// veri yalnızca hisse/altın/emtia/döviz dallarında üretiliyor; portföyde
/// (ya da "Fon" tür filtresinde) fondan başka varlık yoksa çapa HİÇ
/// oluşmuyordu. Sonuç: fon gün boyu önceki NAV'da kalıyor, son slotu canlı
/// toplamla ezen hizalama tek noktalık dik bir uçurum bırakıyor ve o uçurum
/// "ŞİMDİ" imlecine yapışık olarak dakikalar geçtikçe sağa kayıyordu
/// (kullanıcı ekran görüntüsü, 2026-09-10).
void main() {
  // Çizilen gün: 10 Eylül 2026. Basamak saati `tefasNavYayinSaati`.
  final gun = DateTime(2026, 9, 10);
  int ts(int saat, [int dakika = 0]) =>
      DateTime(2026, 9, 10, saat, dakika).millisecondsSinceEpoch;
  final basamak = gun
      .add(const Duration(hours: tefasNavYayinSaati))
      .millisecondsSinceEpoch;

  group('gunIciFonBirimFiyati — basamak', () {
    test('yayın saatinden ÖNCE önceki NAV kullanılır', () {
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5,
            oncekiNav: 10.0,
            slotTs: ts(9, 55),
            basamakTs: basamak),
        10.0,
      );
    });

    test('yayın saatinde ve SONRASINDA güncel NAV kullanılır', () {
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5,
            oncekiNav: 10.0,
            slotTs: basamak,
            basamakTs: basamak),
        10.5,
        reason: 'sınır DAHİL — basamak tam o slotta düşer',
      );
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5,
            oncekiNav: 10.0,
            slotTs: ts(17),
            basamakTs: basamak),
        10.5,
      );
    });

    test('gün içi seri iki uçta FARKLI değer taşır — değişim görünür', () {
      const guncel = 10.5;
      const onceki = 10.0;
      final ilk = gunIciFonBirimFiyati(
          guncelNav: guncel,
          oncekiNav: onceki,
          slotTs: ts(0),
          basamakTs: basamak);
      final son = gunIciFonBirimFiyati(
          guncelNav: guncel,
          oncekiNav: onceki,
          slotTs: ts(23, 55),
          basamakTs: basamak);
      expect(son - ilk, closeTo(0.5, 1e-9),
          reason: 'değişim NAV farkının kendisi olmalı');
      expect((son - ilk) / ilk * 100, closeTo(5.0, 1e-9));
    });
  });

  group('gunIciFonBirimFiyati — imlece yapışan uçurum REGRESYONU', () {
    test('basamak SON slotta değil, sabit saatte durur', () {
      // Asıl hata buydu: fon gün boyu önceki NAV'da kalıp yalnızca son
      // noktada güncel NAV'a sıçrıyordu. Burada 14:19'da bakıldığında
      // basamağın çoktan geçmiş (10:00) olduğunu, son slotun ise ondan
      // FARKSIZ olduğunu doğruluyoruz — yani uçurum yok.
      const guncel = 10.5;
      const onceki = 10.0;
      double birim(int t) => gunIciFonBirimFiyati(
          guncelNav: guncel, oncekiNav: onceki, slotTs: t, basamakTs: basamak);

      expect(birim(ts(14, 15)), guncel);
      expect(birim(ts(14, 19)), guncel);
      expect(birim(ts(14, 19)), birim(ts(14, 15)),
          reason: 'son slot komşusuyla aynı olmalı — dik uçurum olmamalı');
    });

    test('basamak saat ilerledikçe KAYMAZ', () {
      // Aynı gün, iki farklı "şimdi". Basamağın yeri her ikisinde de aynı.
      const guncel = 10.5;
      const onceki = 10.0;
      double birim(int t) => gunIciFonBirimFiyati(
          guncelNav: guncel, oncekiNav: onceki, slotTs: t, basamakTs: basamak);

      // 09:55 önceki NAV, 10:00 güncel NAV — saat kaç olursa olsun.
      expect(birim(ts(9, 55)), onceki);
      expect(birim(ts(10)), guncel);
    });

    test('yayın saatine ULAŞILMADIYSA basamak hiç yoktur', () {
      // Sabah 08:00'de bakıldığında `basamakTs` null gelir. O gün fon
      // baştan sona güncel NAV ile çizilir; son slotu canlı toplamla ezen
      // hizalama böylece fon için no-op kalır ve uçurum oluşamaz.
      double birim(int t) => gunIciFonBirimFiyati(
          guncelNav: 10.5, oncekiNav: 10.0, slotTs: t, basamakTs: null);

      expect(birim(ts(0)), 10.5);
      expect(birim(ts(7, 55)), 10.5);
      expect(birim(ts(8)), 10.5);
      expect(birim(ts(0)), birim(ts(8)), reason: 'gün boyu sabit — basamak yok');
    });
  });

  group('gunIciFonBirimFiyati — geri düşüşler', () {
    test('önceki NAV bilinmiyorsa davranış SABİT kalır', () {
      // Tek noktalı seri / elle fiyatlanan fon / TEFAS erişilemedi.
      for (final t in [ts(0), ts(9, 55), ts(10), ts(17)]) {
        expect(
          gunIciFonBirimFiyati(
              guncelNav: 10.5,
              oncekiNav: null,
              slotTs: t,
              basamakTs: basamak),
          10.5,
        );
      }
    });

    test('geçersiz (<=0) önceki NAV yok sayılır', () {
      // Bozuk bir NAV baz alınırsa fonun günlük değişimi %-100 gibi
      // saçma bir sayıya çıkardı.
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: 0, slotTs: ts(0), basamakTs: basamak),
        10.5,
      );
      expect(
        gunIciFonBirimFiyati(
            guncelNav: 10.5, oncekiNav: -3, slotTs: ts(0), basamakTs: basamak),
        10.5,
      );
    });

    test('NAV düştüğünde basamak da aşağı iner', () {
      final ilk = gunIciFonBirimFiyati(
          guncelNav: 9.4, oncekiNav: 10.0, slotTs: ts(0), basamakTs: basamak);
      final son = gunIciFonBirimFiyati(
          guncelNav: 9.4, oncekiNav: 10.0, slotTs: ts(17), basamakTs: basamak);
      expect(son, lessThan(ilk));
    });

    test('ara değer UYDURULMAZ — yalnızca iki seviye vardır', () {
      // Doğrusal rampa çizmek, fonun olmayan bir gün içi hareketini icat
      // etmek olurdu. Gün boyunca yalnızca iki değer görülebilir.
      const guncel = 12.0;
      const onceki = 11.0;
      final seviyeler = <double>{
        for (var saat = 0; saat < 24; saat++)
          gunIciFonBirimFiyati(
              guncelNav: guncel,
              oncekiNav: onceki,
              slotTs: ts(saat),
              basamakTs: basamak),
      };
      expect(seviyeler, {onceki, guncel});
    });
  });
}
