import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/services/yasal_md.dart';
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
    kvkkBelgesiAcildi: true,
    // Kayıt ekranı rızayı sonuna kadar okutmadan göndermez.
    sonunaKadarOkunanlar: {YasalTur.acikRiza},
  );

  List<String> turler(Map<String, dynamic> p) =>
      [for (final o in p['p_ogeler'] as List) (o as Map)['tur'] as String];

  /// Katalogdaki güncel sürümlerle tam onay takımı: dört belge + tek kutu
  /// 1.1. (2026-10-05'e kadar iki kutulu 1.0 kayıt da tamdı; kutu 1.1'e
  /// çıkınca 1.0 satırları tamam sayılmaz — aşağıdaki testler.)
  List<(String, String)> tamTakim() => [
        for (final m in YasalMetinKatalogu.zorunluBelgeler()) (m.tur, m.surum),
        (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
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
      // 1.4 (okuma sadeleştirme): Koşullar kutuyla kabul — okutulmadı.
      expect(ogeler[1]['degiskenler'], {
        'nitelik': 'kabul',
        'belge_acildi': true,
        'sonuna_kadar_okundu': false,
      });
      // Gizlilik bilgilendirme: sunuldu (bağlantıdan açılmadı).
      expect(ogeler[2]['degiskenler'], {
        'SUPABASE_ULKE': 'Almanya (AB)',
        'SUPABASE_ULKEDE': "Almanya'da (AB)",
        'nitelik': 'bilgilendirme',
        'belge_acildi': false,
        'sonuna_kadar_okundu': false,
      });
      // Yer tutucu değerleri yalnız belgede geçenler: KVKK yalnız ülke adı.
      expect(ogeler[3]['degiskenler'], {
        'SUPABASE_ULKE': 'Almanya (AB)',
        'nitelik': 'bilgilendirme',
        'belge_acildi': true,
        'sonuna_kadar_okundu': false,
      });
      // Açık rıza: sonuna kadar okundu, metnin sonunda verildi.
      expect(ogeler[4]['degiskenler'], {
        'SUPABASE_ULKEDE': "Almanya'da (AB)",
        'nitelik': 'acik_riza',
        'belge_acildi': true,
        'sonuna_kadar_okundu': true,
      });
      expect(ogeler[0]['hash'], YasalMetinKatalogu.kayitTekKutu('en').hash);
      // Belgeler güncel sürümde.
      expect(ogeler[1]['surum'], YasalBelge.kosullar.surum);
      expect(ogeler[4]['surum'], YasalBelge.acikRiza.surum);
    });

    test(
        'kayıt, okumasız bağlam: tek kutu arayüz dilinde; açık rıza ve '
        'yatırım uyarısı YAZILMAZ (rıza kutunun yan etkisi değil)', () async {
      const tek = KayitOnayBaglami(
        dil: 'en',
        kutuUlkesi: 'abroad',
        belgeDegiskenleri: {'SUPABASE_ULKE': 'Yurt dışı'},
        kosulBelgesiAcildi: false,
      );
      await YasalOnayService.instance
          .kayitOnaylariniKaydet(tek, locale: 'en_US');
      final p = cagrilar.single;
      expect(turler(p), [
        YasalTur.kayitTekKutu,
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
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
      expect(d.kutuGerekli, isTrue);
      expect(d.rizaEksik, isTrue);
      expect(d.guncellemeMi, isFalse);
    });

    test(
        'kutu gerekli: kutu YA DA Koşullar/Gizlilik/KVKK eksikse; yalnız '
        'rıza eksikse kutu sorulmaz', () {
      final kutuTamam = (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu);
      List<(String, String)> belgelerHaric(String tur) => [
            for (final m in YasalMetinKatalogu.zorunluBelgeler())
              if (m.tur != tur) (m.tur, m.surum),
            kutuTamam,
          ];
      final yalnizRiza =
          YasalOnayService.eksikleriHesapla(belgelerHaric(YasalTur.acikRiza));
      expect(yalnizRiza.eksik, {YasalTur.acikRiza});
      expect(yalnizRiza.kutuGerekli, isFalse);
      expect(yalnizRiza.rizaEksik, isTrue);
      for (final tur in [YasalTur.kosullar, YasalTur.gizlilik, YasalTur.kvkk]) {
        final d = YasalOnayService.eksikleriHesapla(belgelerHaric(tur));
        expect(d.kutuEksik, isFalse, reason: tur);
        expect(d.kutuGerekli, isTrue, reason: tur);
        expect(d.rizaEksik, isFalse, reason: tur);
      }
    });

    test('güncel takım tam: kapı yok', () {
      expect(YasalOnayService.eksikleriHesapla(tamTakim()).gerekli, isFalse);
    });

    test(
        'belgelerin eski sürümü + iki kutulu 1.0: belgeler ve kutu eksik, '
        '"güncellendi"', () {
      final d = YasalOnayService.eksikleriHesapla([
        (YasalTur.kosullar, '1.1'),
        (YasalTur.gizlilik, '1.1'),
        (YasalTur.kvkk, '1.1'),
        (YasalTur.kayitKutuKosullar, YasalMetinKatalogu.eskiKutuSurumu),
        (YasalTur.kayitKutuRiza, YasalMetinKatalogu.eskiKutuSurumu),
      ]);
      // Üç belge güncellendi, Açık Rıza Metni ilk kez isteniyor; iki kutulu
      // 1.0 kutu 1.1'i tamamlamaz (Koşullar 1.4'ün kabulü kutuyla verilir).
      expect(d.eksik, {
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
        YasalTur.acikRiza,
        YasalOnayService.kutuAnahtari,
      });
      expect(d.kutuEksik, isTrue);
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

    test(
        'kutu yalnız tek kutu 1.1 ile tamam; 1.0 (tek ya da iki kutu) '
        'tamam sayılmaz', () {
      expect(YasalMetinKatalogu.kutuSurumu, '1.1');
      final belgeler = [
        for (final m in YasalMetinKatalogu.zorunluBelgeler()) (m.tur, m.surum),
      ];
      expect(
          YasalOnayService.eksikleriHesapla([
            ...belgeler,
            (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
          ]).gerekli,
          isFalse);
      for (final eski in [
        [(YasalTur.kayitTekKutu, '1.0')],
        [
          (YasalTur.kayitKutuKosullar, '1.0'),
          (YasalTur.kayitKutuRiza, '1.0'),
        ],
      ]) {
        expect(YasalOnayService.eksikleriHesapla([...belgeler, ...eski]).eksik,
            {YasalOnayService.kutuAnahtari});
      }
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
        final yazim = YasalOnayService.instance.kayitOnaylariniKaydet(
            kayitBaglami,
            locale: 'tr_TR',
            userId: 'yeni');
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
          sonunaKadarOkunanlar: {YasalTur.acikRiza},
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
        await YasalOnayService.instance.kayitOnaylariniKaydet(kayitBaglami,
            locale: 'tr_TR', userId: 'yeni');
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
          sonunaKadarOkunanlar: {YasalTur.acikRiza, YasalTur.yatirimUyarisi},
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
        expect(o[1]['degiskenler'], {
          'nitelik': 'kabul',
          'belge_acildi': false,
          'sonuna_kadar_okundu': false,
          'onceki_surum': '1.0',
        });
        expect(o[2]['degiskenler']['onceki_surum'], isNull);
        expect(o[2]['degiskenler']['nitelik'], 'bilgilendirme');
        expect(o[3]['degiskenler']['belge_acildi'], isTrue);
        expect(o[3]['degiskenler']['SUPABASE_ULKE'], 'Almanya (AB)');
        expect(o[3]['degiskenler']['nitelik'], 'bilgilendirme');
        // Açık Rıza Metni yalnız {SUPABASE_ULKEDE} taşır; verilmeyen değer
        // uydurulmaz. Sonuna kadar okundu, sonunda verildi.
        expect(o[4]['degiskenler'], {
          'nitelik': 'acik_riza',
          'belge_acildi': true,
          'sonuna_kadar_okundu': true,
          'onceki_surum': null,
        });
        // Başarı izi koyar: sonraki açılış ağa gitmez.
        sorgu(() => const []);
        expect((await YasalOnayService.instance.kapiDurumu('u1')).gerekli,
            isFalse);
        expect(sorguSayisi, 0);
      });

      test(
          'kapı kaydı: Koşullar/Gizlilik/KVKK yalnız kutuyla, rıza yalnız '
          'okunduysa, uyarı yalnız istenirse', () async {
        // Kutu gösterilmedi (yalnız rıza eksikti), rıza okundu.
        await YasalOnayService.instance.kapiOnaylariniKaydet(
          userId: 'u1',
          durum: YasalOnayService.eksikleriHesapla(const []),
          belgeDegiskenleri: const {},
          acilanBelgeler: const {},
          sonunaKadarOkunanlar: {YasalTur.acikRiza},
          locale: 'tr_TR',
        );
        expect(turler(cagrilar.single), [YasalTur.acikRiza]);
        // Kutu işaretlendi, rıza okunmadı (geçerliydi): rıza yazılmaz.
        cagrilar.clear();
        await YasalOnayService.instance.kapiOnaylariniKaydet(
          userId: 'u2',
          durum: YasalOnayService.eksikleriHesapla(const []),
          belgeDegiskenleri: const {},
          acilanBelgeler: const {},
          kutu: const KapiKutuBaglami(dil: 'tr', kutuUlkesi: 'x'),
          locale: 'tr_TR',
        );
        expect(turler(cagrilar.single), [
          YasalTur.kayitTekKutu,
          YasalTur.kosullar,
          YasalTur.gizlilik,
          YasalTur.kvkk,
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

    test('uygulamaEski: sunucuda kutu 1.1, istemci kutu 1.0 → evet', () {
      expect(
          YasalOnayService.uygulamaEski([(YasalTur.kayitTekKutu, '1.1')],
              uygulamaSurumleri: {YasalTur.kayitTekKutu: '1.0'}),
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

  group(
      '0109: belgeler 1.3 → 1.4 + kutu 1.0 → 1.1, çift onay yok (gerçek '
      'migration sürümleri)', () {
    // Sunucu = migration dosyaları: 0109 dağıtılınca sunucuda 1.1…1.4 ve
    // kutu 1.0 + 1.1 satırları birlikte durur (`yasal_metinler` değişmez).
    final sunucu = [for (final m in migrationMetinleri()) (m.tur, m.surum)];
    final sunucu0109Oncesi = [
      for (final m in migrationMetinleri())
        if (m.dosya.compareTo('0109') < 0) (m.tur, m.surum),
    ];
    final belgeler = [for (final b in YasalBelge.values) b.tur];

    // Yayındaki 1.3 istemcisinin taşıdığı sürümler (0105 sürümü).
    final birNoktaUc = <String, String>{
      for (final t in belgeler) t: '1.3',
      YasalTur.kayitTekKutu: '1.0',
      YasalTur.kayitKutuKosullar: '1.0',
      YasalTur.kayitKutuRiza: '1.0',
    };

    test('0109 1.4 + kutu 1.1 ekler, eskiler kalır', () {
      for (final b in YasalBelge.values) {
        // 0120'den beri Koşullar/Gizlilik/KVKK 1.5; Açık Rıza 1.4'te kaldı.
        expect(YasalOnayService.surumKarsilastir(b.surum, '1.4'),
            greaterThanOrEqualTo(0),
            reason: b.kaynak);
        expect(sunucu, contains((b.tur, '1.4')), reason: '${b.tur}/1.4');
        expect(sunucu, contains((b.tur, '1.3')),
            reason: '${b.tur}/1.3 yerinde kalmalı (eski onaylar)');
        expect(sunucu0109Oncesi, isNot(contains((b.tur, '1.4'))));
      }
      expect(sunucu, contains((YasalTur.kayitTekKutu, '1.1')));
      expect(sunucu, contains((YasalTur.kayitTekKutu, '1.0')));
      expect(sunucu0109Oncesi, isNot(contains((YasalTur.kayitTekKutu, '1.1'))));
    });

    test('0109 öncesi sunucu + 1.3 istemci: eski değil (kapı normal)', () {
      expect(
          YasalOnayService.uygulamaEski(sunucu0109Oncesi,
              uygulamaSurumleri: birNoktaUc),
          isFalse);
    });

    test('0109 dağıtıldı + 1.3 istemci: ESKİ — kapı açılmaz, 1.3 onaylatılmaz',
        () {
      expect(
          YasalOnayService.uygulamaEski(sunucu, uygulamaSurumleri: birNoktaUc),
          isTrue);
    });

    test('0109 dağıtıldı + bu (1.4) istemci: eski değil', () {
      expect(YasalOnayService.uygulamaEski(sunucu), isFalse);
    });

    test(
        '1.3 + kutu 1.0 onaylı kullanıcı, güncel istemci: dört belge + kutu '
        'TEK seferde, tek çağrı', () async {
      YasalOnayService.sunucuSurumTesti = () async => sunucu;
      sorgu(() => [
            for (final t in belgeler) (t, '1.3'),
            (YasalTur.kayitTekKutu, '1.0'),
          ]);
      final d = await YasalOnayService.instance.kapiDurumu('u1');
      expect(d.gerekli, isTrue);
      expect(d.eksik, {...belgeler, YasalOnayService.kutuAnahtari});
      expect(d.kutuGerekli, isTrue);
      expect(d.rizaEksik, isTrue);
      expect(d.guncellemeMi, isTrue, reason: '"Neler değişti" kartı görünür');

      expect(
          await YasalOnayService.instance.kapiOnaylariniKaydet(
            userId: 'u1',
            durum: d,
            belgeDegiskenleri: const {},
            acilanBelgeler: const {},
            sonunaKadarOkunanlar: {YasalTur.acikRiza},
            kutu: const KapiKutuBaglami(dil: 'tr', kutuUlkesi: 'x'),
            locale: 'tr_TR',
          ),
          KapiKayitSonucu.tamam);
      expect(cagrilar, hasLength(1), reason: 'tek çağrı');
      final ogeler = [
        for (final o in cagrilar.single['p_ogeler'] as List) o as Map
      ];
      // Ara sürüm (1.4) sorulmaz: her belge bu derlemenin EN YENİ sürümüyle.
      expect({
        for (final o in ogeler) o['tur']: o['surum']
      }, {
        YasalTur.kayitTekKutu: '1.1',
        for (final b in YasalBelge.values) b.tur: b.surum,
      });
      for (final o in ogeler.skip(1)) {
        expect((o['degiskenler'] as Map)['onceki_surum'], '1.3');
      }
      // Yazılan takım kapıyı tamamlar; onaydan sonra ikinci kez sorulmaz.
      expect(
          YasalOnayService.eksikleriHesapla([
            for (final o in ogeler) (o['tur'] as String, o['surum'] as String),
          ]).gerekli,
          isFalse);
      expect(
          (await YasalOnayService.instance.kapiDurumu('u1')).gerekli, isFalse);
    });

    test('1.2 onaylı (1.3\'ü atlamış) kullanıcı: ara sürüm sorulmaz, 1.4',
        () async {
      YasalOnayService.sunucuSurumTesti = () async => sunucu;
      sorgu(() => [
            for (final t in belgeler) (t, '1.2'),
            (YasalTur.kayitTekKutu, '1.0'),
          ]);
      final d = await YasalOnayService.instance.kapiDurumu('u1');
      expect(d.eksik, {...belgeler, YasalOnayService.kutuAnahtari});
      await YasalOnayService.instance.kapiOnaylariniKaydet(
        userId: 'u1',
        durum: d,
        belgeDegiskenleri: const {},
        acilanBelgeler: const {},
        sonunaKadarOkunanlar: {YasalTur.acikRiza},
        kutu: const KapiKutuBaglami(dil: 'tr', kutuUlkesi: 'x'),
        locale: 'tr_TR',
      );
      final surumler = {
        for (final o in cagrilar.single['p_ogeler'] as List)
          if ((o as Map)['tur'] != YasalTur.kayitTekKutu) o['surum'],
      };
      expect(surumler, {for (final b in YasalBelge.values) b.surum},
          reason: 'ara sürümler hiç onaylatılmaz');
    });
  });

  group('0120: Koşullar/Gizlilik/KVKK 1.4 → 1.5, Açık Rıza değişmez', () {
    final sunucu = [for (final m in migrationMetinleri()) (m.tur, m.surum)];
    final ucBelge = [
      YasalBelge.kosullar.tur,
      YasalBelge.gizlilik.tur,
      YasalBelge.kvkk.tur,
    ];

    test('bu derleme: üç belge 1.5, Açık Rıza 1.4; sunucuda ikisi de var', () {
      for (final t in ucBelge) {
        expect(sunucu, contains((t, '1.5')), reason: '$t/1.5');
        expect(sunucu, contains((t, '1.4')), reason: '$t/1.4 yerinde kalmalı');
      }
      // 0120 Açık Rıza'ya dokunmadı; 1.5'i 0127 (RevenueCat) getirdi.
      expect(sunucu, contains((YasalTur.acikRiza, '1.4')));
      expect(
          YasalOnayService.surumKarsilastir(YasalBelge.acikRiza.surum, '1.4'),
          greaterThanOrEqualTo(0));
    });

    test('0120 dağıtıldı + 1.4 istemci: ESKİ — kapı açılmaz', () {
      expect(
          YasalOnayService.uygulamaEski(sunucu, uygulamaSurumleri: {
            for (final b in YasalBelge.values) b.tur: '1.4',
            YasalTur.kayitTekKutu: '1.1',
          }),
          isTrue);
      expect(YasalOnayService.uygulamaEski(sunucu), isFalse);
    });

    test(
        '1.4 onaylı kullanıcı: üç belge + kutu sorulur, rıza yeniden okutulmaz',
        () async {
      YasalOnayService.sunucuSurumTesti = () async => sunucu;
      sorgu(() => [
            for (final b in YasalBelge.values) (b.tur, '1.4'),
            (YasalTur.kayitTekKutu, '1.1'),
          ]);
      final d = await YasalOnayService.instance.kapiDurumu('u1');
      // Rıza yalnız Açık Rıza'nın KENDİ onay sürümü 1.4'ü geçtiyse sorulur
      // (0127: RevenueCat → 1.5); üç belgenin artışı onu tetiklemez.
      final rizaYeni = YasalOnayService.surumKarsilastir(
              YasalBelge.acikRiza.onaySurumu, '1.4') >
          0;
      expect(d.eksik, {...ucBelge, if (rizaYeni) YasalTur.acikRiza});
      expect(d.kutuGerekli, isTrue, reason: 'Koşullar kutuyla kabul edilir');
      expect(d.rizaEksik, rizaYeni);
      expect(d.guncellemeMi, isTrue);
    });
  });

  group('onay sürümü: esaslı olmayan düzeltme kapıyı açmaz (2026-10-08)', () {
    const md = '# Belge\n\n**Sürüm:** 1.9\n**Onay sürümü:** 1.8\n\nmetin\n';

    test('satır varsa onu, yoksa Sürüm\'ü döner', () {
      expect(yasalMdOnaySurumu(md), '1.8');
      expect(yasalMdOnaySurumu('# B\n\n**Sürüm:** 1.3\n'), '1.3');
    });

    test('her belgede onay sürümü güncel sürümü geçmez', () {
      for (final b in YasalBelge.values) {
        expect(
            YasalOnayService.surumKarsilastir(b.onaySurumu, b.surum),
            lessThanOrEqualTo(0),
            reason: b.kaynak);
      }
    });

    test('Açık Rıza Metni\'nde satır yok: rızanın her değişikliği yeniden '
        'rıza ister', () {
      expect(yasalMdAlan(YasalBelge.acikRiza.md, 'Onay sürümü'), isEmpty);
      expect(YasalBelge.acikRiza.onaySurumu, YasalBelge.acikRiza.surum);
    });

    test('onay sürümünü onaylamış kullanıcıya kapı açılmaz', () {
      final d = YasalOnayService.eksikleriHesapla([
        for (final b in YasalBelge.values) (b.tur, b.onaySurumu),
        (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
      ]);
      expect(d.gerekli, isFalse);
    });
  });
}
