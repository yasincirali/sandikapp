import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';

import 'helpers/kaynak.dart';

/// `YasalOnayService` — yasal metin onay kaydı (0102, bayrak
/// `yasal_onay_kaydi`). Supabase testte kalkmaz; RPC `rpcTesti` ile
/// yakalanır.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Map<String, dynamic>> cagrilar;

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'sandık',
      packageName: 'com.sandik.app',
      version: '1.1.7',
      buildNumber: '8',
      buildSignature: '',
    );
    cagrilar = [];
    YasalOnayService.rpcTesti = (p) async => cagrilar.add(p);
    RemoteConfigService.testAcik = {};
  });
  tearDown(() {
    YasalOnayService.rpcTesti = null;
    RemoteConfigService.testAcik = {};
  });

  const ikiKutu = KayitOnayBaglami(
    tekKutu: false,
    dil: 'en',
    kutuUlkesi: 'Almanya (AB)',
    belgeDegiskenleri: {
      'SUPABASE_ULKE': 'Almanya (AB)',
      'SUPABASE_ULKEDE': "Almanya'da (AB)",
    },
    kosulBelgesiAcildi: true,
    rizaBelgesiAcildi: false,
  );

  List<String> turler(Map<String, dynamic> p) =>
      [for (final o in p['p_ogeler'] as List) (o as Map)['tur'] as String];

  test('bayrak KAPALI: hiçbir çağrı yok, akış eski', () async {
    expect(
        await YasalOnayService.instance
            .kayitOnaylariniKaydet(ikiKutu, locale: 'tr_TR'),
        isFalse);
    expect(
        await YasalOnayService.instance.yatirimUyarisiniKaydet(locale: 'tr'),
        isFalse);
    expect(await YasalOnayService.instance.zirveRizasiniKaydet(locale: 'tr'),
        isFalse);
    expect(cagrilar, isEmpty);
  });

  group('bayrak AÇIK', () {
    setUp(() => RemoteConfigService.testAcik = {'yasal_onay_kaydi'});

    test('kayıt, iki kutu: iki kutu + üç belge, Türkçe, gösterilen ülke',
        () async {
      expect(
          await YasalOnayService.instance
              .kayitOnaylariniKaydet(ikiKutu, locale: 'en_US'),
          isTrue);
      final p = cagrilar.single;
      expect(p['p_kanal'], 'kayit');
      expect(p['p_locale'], 'en_US');
      expect(p['p_app_version'], '1.1.7+8');
      expect(turler(p), [
        YasalTur.kayitKutuKosullar,
        YasalTur.kayitKutuRiza,
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
      ]);
      final ogeler = [for (final o in p['p_ogeler'] as List) o as Map];
      // İki kutu her arayüz dilinde Türkçe çizilir.
      expect(ogeler.every((o) => o['dil'] == 'tr'), isTrue);
      expect(ogeler[1]['degiskenler'], {'SUPABASE_ULKE': 'Almanya (AB)'});
      expect(ogeler[2]['degiskenler'], {'belge_acildi': true});
      expect(ogeler[3]['degiskenler']['belge_acildi'], isFalse);
      expect(ogeler[3]['degiskenler']['SUPABASE_ULKEDE'], "Almanya'da (AB)");
      expect(ogeler[4]['degiskenler']['kayit_ekraninda_baglanti'], isFalse);
      expect(ogeler[0]['hash'], YasalMetinKatalogu.kayitKutuKosullar().hash);
    });

    test('kayıt, tek kutu: tek kutu arayüz dilinde, yatırım uyarısı YOK',
        () async {
      const tek = KayitOnayBaglami(
        tekKutu: true,
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

  test('bağlantılar: üç yüzey kaydı çağırır, eski kapı yerinde', () {
    final otp = ekranKaynagiSync('lib/screens/otp_verification_screen.dart');
    expect(otp, contains('YasalOnayService.instance'));
    expect(otp, contains('.kayitOnaylariniKaydet(kayitOnayi'));
    // Bozmama: `disclaimer_acceptances` yazımı ve sırası aynı.
    expect(otp.indexOf('DisclaimerService.instance.kabulKaydet('),
        lessThan(otp.indexOf('kayitOnaylariniKaydet')));

    final uyari =
        ekranKaynagiSync('lib/screens/disclaimer_acceptance_screen.dart');
    expect(uyari, contains('DisclaimerService.instance.kabulKaydet('));
    expect(uyari, contains('YasalOnayService.instance.yatirimUyarisiniKaydet('));

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
}
