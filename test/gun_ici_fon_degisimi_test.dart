import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/tefas_nav_gozlem.dart';
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

  // ── Çapa: sunucu gözlemi varsa basamak ORAYA, yoksa sabit saate ──────────
  //
  // TEFAS yayın damgası vermez; `observe-tefas-nav` (0063) NAV tarihinin
  // sunucuda ilk görüldüğü anı yazar. `fonBasamakAni` bu gözlemi yalnızca
  // çizilen güne aitse kullanır; her başka durumda eski davranış
  // (`tefasNavYayinSaati`) — gözlem olmadan hiçbir şey değişmemeli.
  group('fonBasamakAni — gözlem çapası', () {
    int normalize(int ms) {
      final d = DateTime.fromMillisecondsSinceEpoch(ms);
      final m = (d.minute ~/ 5) * 5;
      return DateTime(d.year, d.month, d.day, d.hour, m).millisecondsSinceEpoch;
    }

    TefasNavGozlem gozlem({
      required DateTime navTarihi,
      required DateTime ilkGorulme,
    }) =>
        TefasNavGozlem(
            fonKodu: 'AFT', navTarihi: navTarihi, ilkGorulme: ilkGorulme);

    test('gözlem yoksa varsayılan aynen döner (null dahil)', () {
      expect(
        fonBasamakAni(
            dayStart: gun,
            nowTs: ts(12),
            varsayilanTs: basamak,
            gozlem: null,
            normalizeSlot: normalize),
        basamak,
      );
      expect(
        fonBasamakAni(
            dayStart: gun,
            nowTs: ts(9),
            varsayilanTs: null,
            gozlem: null,
            normalizeSlot: normalize),
        isNull,
      );
    });

    test('bugünkü NAV bugün görüldüyse basamak ilk görülme slotuna gider', () {
      final g = gozlem(
          navTarihi: gun, ilkGorulme: DateTime(2026, 9, 10, 8, 33));
      expect(
        fonBasamakAni(
            dayStart: gun,
            nowTs: ts(12),
            varsayilanTs: basamak,
            gozlem: g,
            normalizeSlot: normalize),
        ts(8, 30),
        reason: '08:33 → 5 dk ızgarada 08:30; sabit 10:00 değil',
      );
    });

    test('gözlem 10:00\'dan önceyse basamak varsayılandan ERKEN çizilir', () {
      // Gün henüz 10:00\'a gelmedi → varsayılan null (basamak yok). Gözlem
      // 08:30\'da → 09:00\'da basamak ARTIK var.
      final g = gozlem(
          navTarihi: gun, ilkGorulme: DateTime(2026, 9, 10, 8, 30));
      expect(
        fonBasamakAni(
            dayStart: gun,
            nowTs: ts(9),
            varsayilanTs: null,
            gozlem: g,
            normalizeSlot: normalize),
        ts(8, 30),
      );
    });

    test('NAV tarihi çizilen gün değilse gözlem YOK sayılır', () {
      // Dünkü NAV\'ın gözlemi bugünün basamağını taşıyamaz.
      final g = gozlem(
          navTarihi: DateTime(2026, 9, 9),
          ilkGorulme: DateTime(2026, 9, 9, 8, 30));
      expect(
        fonBasamakAni(
            dayStart: gun,
            nowTs: ts(12),
            varsayilanTs: basamak,
            gozlem: g,
            normalizeSlot: normalize),
        basamak,
      );
    });

    test('bugünkü NAV DÜN görüldüyse (TEFAS erken yayımladı) varsayılana döner', () {
      // İlk görülme çizilen güne düşmüyor: basamak dünün içinde kalırdı ve
      // grafiğin sol ucunda uçurum açılırdı. Sabit saat daha dürüst.
      final g = gozlem(
          navTarihi: gun, ilkGorulme: DateTime(2026, 9, 9, 23, 40));
      expect(
        fonBasamakAni(
            dayStart: gun,
            nowTs: ts(12),
            varsayilanTs: basamak,
            gozlem: g,
            normalizeSlot: normalize),
        basamak,
      );
    });

    test('gözlem ŞİMDİDEN ilerideyse basamak henüz yok (null)', () {
      // Cihaz saati geri kalmış: hizalama fon için no-op kalmalı, imlece
      // yapışık uçurum oluşmamalı (2026-09-10 dersi).
      final g = gozlem(
          navTarihi: gun, ilkGorulme: DateTime(2026, 9, 10, 11, 0));
      expect(
        fonBasamakAni(
            dayStart: gun,
            nowTs: ts(10, 30),
            varsayilanTs: basamak,
            gozlem: g,
            normalizeSlot: normalize),
        isNull,
      );
    });

    test('gözlemli basamak "Tümü" ve "Fon" görünümünde aynı yerdedir', () {
      // Çapa yalnızca gözleme ve güne bağlı; portföydeki başka varlıklara
      // değil (ilk sürümün hatası buydu).
      final g = gozlem(
          navTarihi: gun, ilkGorulme: DateTime(2026, 9, 10, 9, 2));
      int? hesapla() => fonBasamakAni(
          dayStart: gun,
          nowTs: ts(15),
          varsayilanTs: basamak,
          gozlem: g,
          normalizeSlot: normalize);
      expect(hesapla(), hesapla());
      expect(hesapla(), ts(9, 0));
    });
  });

  group('TefasNavGozlem.fromMap', () {
    test('date kolonu yerel güne, damgalar yerel saate çevrilir', () {
      final g = TefasNavGozlem.fromMap({
        'fon_kodu': 'AFT',
        'nav_tarihi': '2026-09-10',
        'ilk_gorulme': '2026-09-10T05:31:07+00:00',
        'onceki_kontrol': null,
      });
      expect(g, isNotNull);
      expect(g!.navTarihi, DateTime(2026, 9, 10));
      expect(g.ilkGorulme.isUtc, isFalse);
      expect(g.ilkGorulme.toUtc(), DateTime.utc(2026, 9, 10, 5, 31, 7));
      expect(g.oncekiKontrol, isNull);
    });

    test('eksik/bozuk alan → null (satır atlanır)', () {
      expect(TefasNavGozlem.fromMap({'fon_kodu': 'AFT'}), isNull);
      expect(
        TefasNavGozlem.fromMap({
          'fon_kodu': '',
          'nav_tarihi': '2026-09-10',
          'ilk_gorulme': '2026-09-10T05:31:07Z',
        }),
        isNull,
      );
    });
  });

  group('tefasKodu', () {
    test('önek soyulur, büyük harfe çevrilir', () {
      expect(tefasKodu('TEFAS:aft'), 'AFT');
      expect(tefasKodu('AFT'), 'AFT');
    });
  });
}
