import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';
import 'helpers/yasal_migration.dart';

/// `YasalOnayService` — yasal metin onay kaydı (0102, bayrak
/// `yasal_onay_kaydi`) ve girişteki yeniden onay kapısı (bayrak
/// `yasal_kapi_en_yeni`). Supabase testte kalkmaz; RPC `rpcTesti`, kapı
/// sorgusu `sorguTesti` ile yakalanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> cagrilar;
  late int sorguSayisi;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'sandık',
      packageName: 'com.sandik.app',
      version: '1.1.7',
      buildNumber: '8',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
    cagrilar = [];
    sorguSayisi = 0;
    YasalOnayService.rpcTesti = (p) async => cagrilar.add(p);
    YasalOnayService.sorguTesti = null;
    // Sunucu, uygulamanın taşıdığı sürümleri taşır (uygulama güncel).
    YasalOnayService.sunucuSurumTesti = () async => [
          for (final m in YasalMetinKatalogu.zorunluBelgeler())
            (m.tur, m.surum),
          (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
        ];
    YasalOnayService.instance.testSifirla();
  });
  tearDown(() {
    YasalOnayService.sunucuSurumTesti = null;
    YasalOnayService.rpcTesti = null;
    YasalOnayService.sorguTesti = null;
    YasalOnayService.instance.testSifirla();
  });

  // Kayıt yalnız tek kutulu (bayrak `tek_onay_kutusu` 2026-10-05'te kalktı).
  const kayitBaglami = KayitOnayBaglami(
    dil: 'en',
    kutuUlkesi: 'Almanya (AB)',
    belgeDegiskenleri: {
      'SUPABASE_ULKE': 'Almanya (AB)',
      'SUPABASE_ULKEDE': "Almanya'da (AB)",
    },
    kosulBelgesiAcildi: true,
    rizaBelgesiAcildi: false,
    kvkkBelgesiAcildi: true,
  );

  List<String> turler(Map<String, dynamic> p) =>
      [for (final o in p['p_ogeler'] as List) (o as Map)['tur'] as String];

  /// Katalogdaki güncel sürümlerle tam onay takımı — İKİ kutulu eski kayıt
  /// (2026-10-04 öncesi kullanıcıların sunucudaki satırları; kapı onları da
  /// tam saymalı).
  List<(String, String)> tamTakim() => [
        for (final m in YasalMetinKatalogu.zorunluBelgeler()) (m.tur, m.surum),
        (YasalTur.kayitKutuKosullar, YasalMetinKatalogu.kutuSurumu),
        (YasalTur.kayitKutuRiza, YasalMetinKatalogu.kutuSurumu),
      ];

  void sorgu(List<(String, String)> Function() cevap) {
    YasalOnayService.sorguTesti = (_) async {
      sorguSayisi++;
      return cevap();
    };
  }

  group('kayıt', () {
    test('kayıt: tek kutu + dört belge, belgeler Türkçe, gösterilen ülke',
        () async {
      expect(
          await YasalOnayService.instance
              .kayitOnaylariniKaydet(kayitBaglami, locale: 'en_US'),
          isTrue);
      final p = cagrilar.single;
      expect(p['p_kanal'], 'kayit');
      expect(p['p_locale'], 'en_US');
      expect(p['p_app_version'], '1.1.7+8');
      expect(turler(p), [
        YasalTur.kayitTekKutu,
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
        YasalTur.acikRiza,
      ]);
      final ogeler = [for (final o in p['p_ogeler'] as List) o as Map];
      // Kutu arayüz dilinde; belgeler her dilde Türkçe.
      expect(ogeler[0]['dil'], 'en');
      expect(ogeler.skip(1).every((o) => o['dil'] == 'tr'), isTrue);
      expect(ogeler[0]['degiskenler'], {'SUPABASE_ULKE': 'Almanya (AB)'});
      expect(ogeler[1]['degiskenler'], {'belge_acildi': true});
      // Gizlilik 1.2'den beri kendi bağlantısıyla açılır (açılmadı).
      expect(ogeler[2]['degiskenler'], {
        'SUPABASE_ULKE': 'Almanya (AB)',
        'SUPABASE_ULKEDE': "Almanya'da (AB)",
        'belge_acildi': false,
      });
      // KVKK Aydınlatma 2026-10-04'ten beri kayıt ekranından açılabiliyor;
      // eski "kayit_ekraninda_baglanti: false" notu kalktı.
      expect(ogeler[3]['degiskenler']['belge_acildi'], isTrue);
      expect(ogeler[3]['degiskenler'],
          isNot(contains('kayit_ekraninda_baglanti')));
      // Yer tutucu değerleri yalnız belgede geçenler: KVKK yalnız ülke adı.
      expect(ogeler[3]['degiskenler'],
          {'SUPABASE_ULKE': 'Almanya (AB)', 'belge_acildi': true});
      // "açık rıza" bağlantısı 1.2'den beri Açık Rıza Metni'ni açar.
      expect(ogeler[4]['degiskenler'],
          {'SUPABASE_ULKEDE': "Almanya'da (AB)", 'belge_acildi': false});
      expect(ogeler[0]['hash'], YasalMetinKatalogu.kayitTekKutu('en').hash);
      // Belgeler güncel sürümde.
      expect(ogeler[1]['surum'], YasalBelge.kosullar.surum);
      expect(ogeler[4]['surum'], YasalBelge.acikRiza.surum);
    });

    test('kayıt, tek kutu: tek kutu arayüz dilinde, yatırım uyarısı YOK',
        () async {
      const tek = KayitOnayBaglami(
        dil: 'en',
        kutuUlkesi: 'abroad',
        belgeDegiskenleri: {'SUPABASE_ULKE': 'Yurt dışı'},
        kosulBelgesiAcildi: false,
        rizaBelgesiAcildi: false,
      );
      await YasalOnayService.instance
          .kayitOnaylariniKaydet(tek, locale: 'en_US');
      final p = cagrilar.single;
      expect(turler(p), [
        YasalTur.kayitTekKutu,
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
        YasalTur.acikRiza,
      ]);
      final kutu = (p['p_ogeler'] as List).first as Map;
      expect(kutu['dil'], 'en');
      expect(kutu['hash'], YasalMetinKatalogu.kayitTekKutu('en').hash);
      expect(kutu['degiskenler'], {'SUPABASE_ULKE': 'abroad'});
      expect(turler(p), isNot(contains(YasalTur.yatirimUyarisi)));
    });

    test('yatırım uyarısı ve zirve kendi kanallarında', () async {
      await YasalOnayService.instance.yatirimUyarisiniKaydet(locale: 'tr_TR');
      await YasalOnayService.instance.zirveRizasiniKaydet(locale: 'tr_TR');
      expect(cagrilar.map((p) => p['p_kanal']),
          ['yatirim_uyarisi_ekrani', 'zirve']);
      expect(turler(cagrilar[0]), [YasalTur.yatirimUyarisi]);
      expect(turler(cagrilar[1]), [YasalTur.zirveRiza]);
      expect(((cagrilar[1]['p_ogeler'] as List).single as Map)['surum'],
          '2026-10-01');
    });

    test('RPC hatası fırlamaz, false döner (akış durmaz)', () async {
      YasalOnayService.rpcTesti =
          (_) async => throw StateError('yasal metin hash uyusmuyor');
      expect(
          await YasalOnayService.instance.yatirimUyarisiniKaydet(locale: 'tr'),
          isFalse);
    });
  });

  group('sürüm karşılaştırma ve eksik hesabı (saf)', () {
    test('sayısal parçalar sayı olarak', () {
      expect(YasalOnayService.surumKarsilastir('1.10', '1.9'), greaterThan(0));
      expect(YasalOnayService.surumKarsilastir('1.1', '1.1'), 0);
      expect(YasalOnayService.surumKarsilastir('1.0', '1.1'), lessThan(0));
      expect(YasalOnayService.surumKarsilastir('1.1', '1.1.0'), 0);
      expect(YasalOnayService.surumKarsilastir('2026-10-01', '2026-09-30'),
          greaterThan(0));
    });

    test('hiç onay yok: dört belge + kutu eksik, "ilk kez"', () {
      final d = YasalOnayService.eksikleriHesapla(const []);
      expect(d.eksik, {
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
        YasalTur.acikRiza,
        YasalOnayService.kutuAnahtari,
      });
      expect(d.kutuEksik, isTrue);
      expect(d.guncellemeMi, isFalse);
    });

    test('güncel takım tam: kapı yok', () {
      expect(YasalOnayService.eksikleriHesapla(tamTakim()).gerekli, isFalse);
    });

    test('belgelerin eski sürümü: yalnız belgeler eksik, "güncellendi"', () {
      final d = YasalOnayService.eksikleriHesapla([
        (YasalTur.kosullar, '1.1'),
        (YasalTur.gizlilik, '1.1'),
        (YasalTur.kvkk, '1.1'),
        (YasalTur.kayitKutuKosullar, YasalMetinKatalogu.kutuSurumu),
        (YasalTur.kayitKutuRiza, YasalMetinKatalogu.kutuSurumu),
      ]);
      // 1.1 → 1.2: üç belge güncellendi, Açık Rıza Metni ilk kez isteniyor.
      expect(d.eksik, {
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
        YasalTur.acikRiza,
      });
      expect(d.kutuEksik, isFalse);
      expect(d.guncellemeMi, isTrue);
      expect(d.oncekiSurum[YasalTur.kosullar], '1.1');
      expect(d.oncekiSurum[YasalTur.acikRiza], isNull);
    });

    test('daha YENİ sürüm onaylı: eski istemci geri onaylatmaz', () {
      final d = YasalOnayService.eksikleriHesapla([
        for (final (t, _) in tamTakim()) (t, '9.9'),
      ]);
      expect(d.gerekli, isFalse);
    });

    test('tek kutu da kutu taahhüdünü tamamlar; yarım iki kutu tamamlamaz', () {
      final belgeler = [
        for (final m in YasalMetinKatalogu.zorunluBelgeler()) (m.tur, m.surum),
      ];
      expect(
          YasalOnayService.eksikleriHesapla([
            ...belgeler,
            (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
          ]).gerekli,
          isFalse);
      expect(
          YasalOnayService.eksikleriHesapla([
            ...belgeler,
            (YasalTur.kayitKutuKosullar, YasalMetinKatalogu.kutuSurumu),
          ]).eksik,
          {YasalOnayService.kutuAnahtari});
    });

    test('yatırım uyarısı ve Zirve kapının işi değil', () {
      final d = YasalOnayService.eksikleriHesapla(tamTakim());
      expect(d.eksik, isNot(contains(YasalTur.yatirimUyarisi)));
      expect(d.eksik, isNot(contains(YasalTur.zirveRiza)));
    });

    test('cihaz izinin anahtarı sürümleri taşır (sürüm artınca geçersiz)', () {
      final a = YasalOnayService.izAnahtari('u1');
      expect(a, contains('${YasalTur.kosullar}@${YasalBelge.kosullar.surum}'));
      expect(a, contains('${YasalTur.acikRiza}@${YasalBelge.acikRiza.surum}'));
      expect(
          a,
          contains('${YasalOnayService.kutuAnahtari}@'
              '${YasalMetinKatalogu.kutuSurumu}'));
      expect(a, endsWith('_u1'));
    });
  });

  group('yeniden onay kapısı', () {
    // Kapı koşulsuz (bayraklar `yasal_onay_kaydi` + `yasal_kapi_en_yeni`
    // 2026-10-05'te kalktı; "bayrak kapalı: ağ yok" testleri onlarla gitti).
    group('kapı', () {
      test('eski kullanıcı / sosyal girişle ilk kez (hiç onay yok): kapı',
          () async {
        sorgu(() => const []);
        final d = await YasalOnayService.instance.kapiDurumu('u1');
        expect(d.gerekli, isTrue);
        expect(d.kutuEksik, isTrue);
      });

      test('onayı tam: bir kez sorulur, sonra cihaz izinden (ağ yok)',
          () async {
        sorgu(tamTakim);
        expect((await YasalOnayService.instance.kapiDurumu('u1')).gerekli,
            isFalse);
        expect(sorguSayisi, 1);
        // Yeni süreç (bellek boş) — iz diskte.
        YasalOnayService.instance.testSifirla();
        expect((await YasalOnayService.instance.kapiDurumu('u1')).gerekli,
            isFalse);
        expect(sorguSayisi, 1);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getBool(YasalOnayService.izAnahtari('u1')), isTrue);
      });

      test('eksikken iz KONMAZ: sonraki açılış yine sorar', () async {
        sorgu(() => const []);
        await YasalOnayService.instance.kapiDurumu('u1');
        await YasalOnayService.instance.kapiDurumu('u1');
        expect(sorguSayisi, 2);
      });

      test('ağ hatası: fail-open, iz yok, sonraki açılışta yeniden denenir',
          () async {
        YasalOnayService.sorguTesti = (_) async {
          sorguSayisi++;
          throw const SocketException('bağlantı yok');
        };
        expect((await YasalOnayService.instance.kapiDurumu('u1')).gerekli,
            isFalse);
        sorgu(() => const []);
        expect(
            (await YasalOnayService.instance.kapiDurumu('u1')).gerekli, isTrue);
        expect(sorguSayisi, 2);
      });

      test(
          'e-postayla yeni kayıt: OTP sonrası "kayit" yazımı sürerken kapı '
          'onu bekler ve kapıyı GÖSTERMEZ (aynı sürümler)', () async {
        final rpcBitti = Completer<void>();
        YasalOnayService.rpcTesti = (p) async {
          cagrilar.add(p);
          await rpcBitti.future;
        };
        // Sunucuda henüz satır yok (yazım bitmedi) — sorgu yapılırsa kapı
        // açılırdı.
        sorgu(() => const []);
        final yazim = YasalOnayService.instance
            .kayitOnaylariniKaydet(kayitBaglami, locale: 'tr_TR', userId: 'yeni');
        final kapi = YasalOnayService.instance.kapiDurumu('yeni');
        await Future<void>.delayed(Duration.zero);
        rpcBitti.complete();
        expect(await yazim, isTrue);
        final d = await kapi;
        expect(d.gerekli, isFalse);
        expect(sorguSayisi, 0);
        expect(cagrilar.single['p_kanal'], 'kayit');
        // Kayıt tam takımı yazdı → kapının aradığı her şey içinde.
        final yazilan = [
          for (final o in cagrilar.single['p_ogeler'] as List)
            ((o as Map)['tur'] as String, o['surum'] as String),
        ];
        expect(YasalOnayService.eksikleriHesapla(yazilan).gerekli, isFalse);
      });

      test('tek kutulu kayıt da kapıyı tamamlar', () async {
        const tek = KayitOnayBaglami(
          dil: 'tr',
          kutuUlkesi: 'Almanya (AB)',
          belgeDegiskenleri: {},
          kosulBelgesiAcildi: false,
          rizaBelgesiAcildi: false,
        );
        await YasalOnayService.instance
            .kayitOnaylariniKaydet(tek, locale: 'tr_TR', userId: 'yeni');
        sorgu(() => const []);
        expect((await YasalOnayService.instance.kapiDurumu('yeni')).gerekli,
            isFalse);
        expect(sorguSayisi, 0);
      });

      test('kayıt yazımı düşerse kapı sunucuya sorar', () async {
        YasalOnayService.rpcTesti =
            (_) async => throw const SocketException('yok');
        await YasalOnayService.instance
            .kayitOnaylariniKaydet(kayitBaglami, locale: 'tr_TR', userId: 'yeni');
        sorgu(() => const []);
        expect((await YasalOnayService.instance.kapiDurumu('yeni')).gerekli,
            isTrue);
        expect(sorguSayisi, 1);
      });

      test('kapı kaydı: yeniden_onay kanalı, dört belge + kutu + uyarı',
          () async {
        final durum = YasalOnayService.eksikleriHesapla([
          (YasalTur.kosullar, '1.0'),
        ]);
        final sonuc = await YasalOnayService.instance.kapiOnaylariniKaydet(
          userId: 'u1',
          durum: durum,
          belgeDegiskenleri: const {'SUPABASE_ULKE': 'Almanya (AB)'},
          acilanBelgeler: {YasalTur.kvkk},
          kutu: const KapiKutuBaglami(dil: 'tr', kutuUlkesi: 'Almanya (AB)'),
          yatirimUyarisiDahil: true,
          locale: 'tr_TR',
        );
        expect(sonuc, KapiKayitSonucu.tamam);
        final p = cagrilar.single;
        expect(p['p_kanal'], 'yeniden_onay');
        expect(turler(p), [
          YasalTur.kayitTekKutu,
          YasalTur.kosullar,
          YasalTur.gizlilik,
          YasalTur.kvkk,
          YasalTur.acikRiza,
          YasalTur.yatirimUyarisi,
        ]);
        final o = [for (final x in p['p_ogeler'] as List) x as Map];
        expect(o[1]['degiskenler'],
            {'belge_acildi': false, 'onceki_surum': '1.0'});
        expect(o[2]['degiskenler']['onceki_surum'], isNull);
        expect(o[3]['degiskenler']['belge_acildi'], isTrue);
        expect(o[3]['degiskenler']['SUPABASE_ULKE'], 'Almanya (AB)');
        // Açık Rıza Metni yalnız {SUPABASE_ULKEDE} taşır; verilmeyen değer
        // uydurulmaz.
        expect(
            o[4]['degiskenler'], {'belge_acildi': false, 'onceki_surum': null});
        // Başarı izi koyar: sonraki açılış ağa gitmez.
        sorgu(() => const []);
        expect((await YasalOnayService.instance.kapiDurumu('u1')).gerekli,
            isFalse);
        expect(sorguSayisi, 0);
      });

      test('kapı kaydı: kutu yalnız gösterildiyse, uyarı yalnız istenirse',
          () async {
        await YasalOnayService.instance.kapiOnaylariniKaydet(
          userId: 'u1',
          durum: YasalOnayService.eksikleriHesapla(const []),
          belgeDegiskenleri: const {},
          acilanBelgeler: const {},
          locale: 'tr_TR',
        );
        expect(turler(cagrilar.single), [
          YasalTur.kosullar,
          YasalTur.gizlilik,
          YasalTur.kvkk,
          YasalTur.acikRiza
        ]);
      });

      test('kapı kaydı hataları: ağ → agHatasi, sunucu → sunucuHatasi; iz yok',
          () async {
        YasalOnayService.rpcTesti =
            (_) async => throw const SocketException('yok');
        Future<KapiKayitSonucu> kaydet() =>
            YasalOnayService.instance.kapiOnaylariniKaydet(
              userId: 'u1',
              durum: YasalOnayService.eksikleriHesapla(const []),
              belgeDegiskenleri: const {},
              acilanBelgeler: const {},
              locale: 'tr_TR',
            );
        expect(await kaydet(), KapiKayitSonucu.agHatasi);
        YasalOnayService.rpcTesti =
            (_) async => throw StateError('yasal metin hash uyusmuyor');
        expect(await kaydet(), KapiKayitSonucu.sunucuHatasi);
        sorgu(() => const []);
        expect(
            (await YasalOnayService.instance.kapiDurumu('u1')).gerekli, isTrue);
      });
    });
  });

  test('bağlantılar: üç yüzey kaydı çağırır, eski kapı yerinde', () {
    final otp = ekranKaynagiSync('lib/screens/otp_verification_screen.dart');
    expect(otp, contains('YasalOnayService.instance'));
    expect(otp, contains('.kayitOnaylariniKaydet(kayitOnayi'));
    // Kapı yazımı bekleyebilsin diye kullanıcı kimliği verilir.
    expect(otp, contains('userId: user.id'));
    // Bozmama: `disclaimer_acceptances` yazımı ve sırası aynı.
    expect(otp.indexOf('DisclaimerService.instance.kabulKaydet('),
        lessThan(otp.indexOf('kayitOnaylariniKaydet')));

    final uyari =
        ekranKaynagiSync('lib/screens/disclaimer_acceptance_screen.dart');
    expect(uyari, contains('DisclaimerService.instance.kabulKaydet('));
    expect(
        uyari, contains('YasalOnayService.instance.yatirimUyarisiniKaydet('));

    final zirve = ekranKaynagiSync('lib/screens/zirve_portfoyler_screen.dart');
    expect(zirve, contains('YasalOnayService.instance.zirveRizasiniKaydet('));
    // Rıza önce asıl kapıya (0091) yazılır; ispat kaydı ondan sonra.
    expect(zirve.indexOf('setZirveRizasi(true)'),
        lessThan(zirve.indexOf('zirveRizasiniKaydet(')));

    final kayit = ekranKaynagiSync('lib/screens/register_screen.dart');
    expect(kayit, contains('kayitOnayi: kayitOnayi'));
    // Kutu metinleri katalogdan; ekranda literal kopya yok.
    expect(kayit, isNot(contains('18 yaşından büyük olduğunu beyan')));
    expect(kayit, isNot(contains('Verilerimin yurt dışına aktarılmasına')));
  });

  test('giriş kapısı sırası: yasal kapı → yatırım uyarısı → kullanıcı adı', () {
    // `_resolveScreen`: Apple/Google ile ilk kez gelen kullanıcı önce
    // belgeleri onaylar, zorunlu kullanıcı adı ekranı ondan SONRA aynen
    // gelir (kullanıcı kuralı: kullanıcı adı kaldırılmaz/ertelenmez).
    final main = ekranKaynagiSync('lib/main.dart');
    final cozum = main.substring(main.indexOf('Widget _resolveScreen('));
    final kapi = cozum.indexOf('YasalOnayKapisiScreen(');
    final uyari = cozum.indexOf('DisclaimerAcceptanceScreen(');
    final ad = cozum.indexOf('KullaniciAdiScreen(');
    expect(kapi, greaterThan(0));
    expect(kapi, lessThan(uyari));
    expect(uyari, lessThan(ad));
    // Splash kapının kararını da bekler (yoksa ana ekran bir kare görünür).
    expect(cozum, contains('_yasalKapi == null'));
    // Eski kapı aynen: yatırım uyarısı ekranı hâlâ kendi kaydını yazar.
    expect(main, contains('DisclaimerService.instance.hasAccepted(user.id)'));
  });

  group('sunucuda daha yeni metin: eski metin onaylatılmaz (çift onay yok)',
      () {
    // Kullanıcı kuralı 2026-10-04: "en yeni sürüm onaylatılmalı; çift onay
    // olmamalı 2 güncelleme geldiyse."
    String ileri(String surum) => '${surum}9';
    final kosullar = YasalMetinKatalogu.zorunluBelgeler().first;

    test('uygulamaEski: aynı sürümler → hayır', () {
      expect(
          YasalOnayService.uygulamaEski([
            for (final m in YasalMetinKatalogu.zorunluBelgeler())
              (m.tur, m.surum),
          ]),
          isFalse);
    });

    test('uygulamaEski: bir belgenin daha yeni sürümü → evet', () {
      expect(
          YasalOnayService.uygulamaEski(
              [(kosullar.tur, ileri(kosullar.surum))]),
          isTrue);
    });

    test('uygulamaEski: kutu metninin daha yeni sürümü → evet', () {
      expect(
          YasalOnayService.uygulamaEski([
            (YasalTur.kayitTekKutu, ileri(YasalMetinKatalogu.kutuSurumu)),
          ]),
          isTrue);
    });

    test('uygulamaEski: kapının sormadığı tür (zirve) yeni → hayır', () {
      expect(
          YasalOnayService.uygulamaEski([(YasalTur.zirveRiza, '2099-01-01')]),
          isFalse);
    });

    test('uygulamaEski: sunucuda daha ESKİ sürüm de var → hayır', () {
      expect(YasalOnayService.uygulamaEski([(kosullar.tur, '0.1')]), isFalse);
    });

    test('eksik onay + uygulama eski: kapı AÇILMAZ, iz konmaz', () async {
      YasalOnayService.sunucuSurumTesti =
          () async => [(kosullar.tur, ileri(kosullar.surum))];
      sorgu(() => const []);
      expect(
          (await YasalOnayService.instance.kapiDurumu('u1')).gerekli, isFalse);
      // İz yok: güncel uygulama geldiğinde yeniden sorulur.
      await YasalOnayService.instance.kapiDurumu('u1');
      expect(sorguSayisi, 2);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(YasalOnayService.izAnahtari('u1')), isNull);
    });

    test('eksik onay + uygulama güncel: kapı açılır (tek seferde en yeni)',
        () async {
      sorgu(() => [(kosullar.tur, '1.0')]);
      final d = await YasalOnayService.instance.kapiDurumu('u1');
      expect(d.gerekli, isTrue);
      expect(d.eksik, contains(kosullar.tur));
    });
  });

  group('0105: belgeler 1.2 → 1.3, çift onay yok (gerçek migration sürümleri)',
      () {
    // Sunucu = migration dosyaları: 0105 dağıtılınca sunucuda 1.1, 1.2 VE
    // 1.3 satırları birlikte durur (`yasal_metinler` değişmez).
    final sunucu = [for (final m in migrationMetinleri()) (m.tur, m.surum)];
    final sunucu0105Oncesi = [
      for (final m in migrationMetinleri())
        if (m.dosya.compareTo('0105') < 0) (m.tur, m.surum),
    ];
    final belgeler = [for (final b in YasalBelge.values) b.tur];

    // Yayındaki 1.2 istemcisinin taşıdığı sürümler (0103/0104 sürümü).
    final ikiNoktaIki = <String, String>{
      for (final t in belgeler) t: '1.2',
      YasalTur.kayitTekKutu: YasalMetinKatalogu.kutuSurumu,
      YasalTur.kayitKutuKosullar: YasalMetinKatalogu.kutuSurumu,
      YasalTur.kayitKutuRiza: YasalMetinKatalogu.kutuSurumu,
    };

    // Kapı 2026-10-05'ten beri koşulsuz (bayraklar kaldırıldı); çağrı
    // yerleri okunur kalsın diye boş.
    void kapiAcik() {}

    test('bu derleme dört belgede 1.3 taşır; 0105 1.3\'ü ekler, 1.2 kalır', () {
      for (final b in YasalBelge.values) {
        expect(b.surum, '1.3', reason: b.kaynak);
        expect(sunucu, contains((b.tur, '1.3')), reason: '${b.tur}/1.3');
        expect(sunucu, contains((b.tur, '1.2')),
            reason: '${b.tur}/1.2 yerinde kalmalı (eski onaylar)');
        expect(sunucu0105Oncesi, isNot(contains((b.tur, '1.3'))));
      }
    });

    test('0105 öncesi sunucu + 1.2 istemci: eski değil (kapı normal)', () {
      expect(
          YasalOnayService.uygulamaEski(sunucu0105Oncesi,
              uygulamaSurumleri: ikiNoktaIki),
          isFalse);
    });

    test('0105 dağıtıldı + 1.2 istemci: ESKİ — kapı açılmaz, 1.2 onaylatılmaz',
        () {
      expect(
          YasalOnayService.uygulamaEski(sunucu,
              uygulamaSurumleri: ikiNoktaIki),
          isTrue);
    });

    test('0105 dağıtıldı + bu (1.3) istemci: eski değil', () {
      expect(YasalOnayService.uygulamaEski(sunucu), isFalse);
    });

    test('1.2 onaylı kullanıcı, güncel istemci: dört belge TEK seferde 1.3',
        () async {
      kapiAcik();
      YasalOnayService.sunucuSurumTesti = () async => sunucu;
      sorgu(() => [
            for (final t in belgeler) (t, '1.2'),
            (YasalTur.kayitKutuKosullar, YasalMetinKatalogu.kutuSurumu),
            (YasalTur.kayitKutuRiza, YasalMetinKatalogu.kutuSurumu),
          ]);
      final d = await YasalOnayService.instance.kapiDurumu('u1');
      expect(d.gerekli, isTrue);
      expect(d.eksik, belgeler.toSet(), reason: 'kutular tamam, belgeler eksik');
      expect(d.guncellemeMi, isTrue, reason: '"Neler değişti" kartı görünür');

      expect(
          await YasalOnayService.instance.kapiOnaylariniKaydet(
            userId: 'u1',
            durum: d,
            belgeDegiskenleri: const {},
            acilanBelgeler: belgeler.toSet(),
            sonunaKadarOkunanlar: belgeler.toSet(),
            locale: 'tr_TR',
          ),
          KapiKayitSonucu.tamam);
      expect(cagrilar, hasLength(1), reason: 'tek çağrı');
      final ogeler = [
        for (final o in cagrilar.single['p_ogeler'] as List) o as Map
      ];
      expect({for (final o in ogeler) o['tur']: o['surum']},
          {for (final t in belgeler) t: '1.3'});
      for (final o in ogeler) {
        expect((o['degiskenler'] as Map)['onceki_surum'], '1.2');
      }
      // Onaydan sonra kapı kapalı: ikinci kez sorulmaz.
      expect(
          (await YasalOnayService.instance.kapiDurumu('u1')).gerekli, isFalse);
    });

    test('1.1 onaylı (1.2\'yi atlamış) kullanıcı: ara sürüm sorulmaz, 1.3',
        () async {
      kapiAcik();
      YasalOnayService.sunucuSurumTesti = () async => sunucu;
      sorgu(() => [
            (YasalTur.kosullar, '1.1'),
            (YasalTur.gizlilik, '1.1'),
            (YasalTur.kvkk, '1.1'),
            (YasalTur.kayitKutuKosullar, YasalMetinKatalogu.kutuSurumu),
            (YasalTur.kayitKutuRiza, YasalMetinKatalogu.kutuSurumu),
          ]);
      final d = await YasalOnayService.instance.kapiDurumu('u1');
      expect(d.eksik, belgeler.toSet());
      await YasalOnayService.instance.kapiOnaylariniKaydet(
        userId: 'u1',
        durum: d,
        belgeDegiskenleri: const {},
        acilanBelgeler: const {},
        locale: 'tr_TR',
      );
      final surumler = {
        for (final o in cagrilar.single['p_ogeler'] as List)
          (o as Map)['surum'],
      };
      expect(surumler, {'1.3'}, reason: '1.2 hiç onaylatılmaz');
    });
  });
}
