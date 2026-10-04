import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/screens/yasal_onay_kapisi_screen.dart';
import 'package:portfoy_takip/services/disclaimer_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yeniden onay kapısı ekranı (bayrak `yasal_kapi_en_yeni`, 2026-10-04).
///
/// Kullanıcı kararı: eski metni onaylayan girişte güncel belgeleri görüp
/// onaylar; Apple/Google ile ilk kez gelen kayıt formundaki taahhütlerin
/// aynısını onaylar. Ekran geri tuşuyla atlanamaz, ağ hatasında kilitlemez
/// ama onayı da yazılmış saymaz.
void main() {
  final l = AppLocalizationsTr();
  late List<Map<String, dynamic>> cagrilar;
  late List<String> uyariKayitlari;
  late int tamam;

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
    uyariKayitlari = [];
    tamam = 0;
    YasalOnayService.rpcTesti = (p) async => cagrilar.add(p);
    YasalOnayService.instance.testSifirla();
    YasalOnayKapisiScreen.uyariKaydiTesti =
        ({required String userId, required String locale}) async {
      uyariKayitlari.add(userId);
      return true;
    };
    RemoteConfigService.testAcik = {'yasal_onay_kaydi', 'yasal_kapi_en_yeni'};
  });
  tearDown(() {
    YasalOnayService.rpcTesti = null;
    YasalOnayKapisiScreen.uyariKaydiTesti = null;
    YasalOnayService.instance.testSifirla();
    RemoteConfigService.testAcik = {};
  });

  /// Belgelerin eski (1.1) sürümünü onaylamış, kutuları tamam; Açık Rıza
  /// Metni (1.2'de ayrı belge oldu) hiç onaylanmamış.
  final guncelleme = YasalOnayService.eksikleriHesapla([
    (YasalTur.kosullar, '1.1'),
    (YasalTur.gizlilik, '1.1'),
    (YasalTur.kvkk, '1.1'),
    (YasalTur.kayitKutuKosullar, YasalMetinKatalogu.kutuSurumu),
    (YasalTur.kayitKutuRiza, YasalMetinKatalogu.kutuSurumu),
  ]);

  /// Hiç onayı yok (Apple/Google ile ilk giriş, 0102 öncesi hesap).
  final ilk = YasalOnayService.eksikleriHesapla(const []);

  Future<void> ac(
    WidgetTester tester,
    YasalKapiDurumu durum, {
    bool uyari = false,
    // ListView tembel kurar: işlev testleri her şey kurulu olsun diye uzun
    // ekranda; taşma testleri dar ekranda.
    Size boyut = const Size(390, 2400),
    double olcek = 1.0,
    Locale dil = const Locale('tr', 'TR'),
  }) async {
    tester.view.physicalSize = boyut * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      child: MediaQuery(
        data: MediaQueryData(size: boyut, textScaler: TextScaler.linear(olcek)),
        child: MaterialApp(
          locale: dil,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: YasalOnayKapisiScreen(
            userId: 'u1',
            durum: durum,
            yatirimUyarisiDahil: uyari,
            onTamam: () => tamam++,
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  /// `SiganMetin` bir RenderBox: `find.text` onu görmez.
  Finder sigan(String ilkAday) => find.byWidgetPredicate(
      (w) => w is SiganMetin && w.adaylar.first == ilkAday);

  Future<void> onayla(WidgetTester tester) async {
    final dugme = find.byType(SandikAsyncButton);
    await tester.ensureVisible(dugme);
    await tester.tap(dugme);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  List<String> turler() => [
        for (final o in cagrilar.single['p_ogeler'] as List)
          (o as Map)['tur'] as String,
      ];

  testWidgets('güncellenen belgeler: başlık, "Neler değişti", dört belge, kutu '
      'YOK; tek dokunuş yazar ve kapıyı kapatır', (tester) async {
    await ac(tester, guncelleme);
    expect(find.text(l.yasalKapiBaslikGuncel), findsOneWidget);
    expect(find.text(l.yasalKapiNelerDegisti), findsOneWidget);
    expect(find.text(l.yasalKapiDegisiklikNotu), findsOneWidget);
    expect(sigan(l.yasalBelgeKosullar), findsOneWidget);
    expect(sigan(l.yasalBelgeGizlilik), findsOneWidget);
    expect(sigan(l.yasalBelgeKvkk), findsOneWidget);
    expect(sigan(l.yasalBelgeAcikRiza), findsOneWidget);
    expect(sigan(l.yasalKapiOnayla), findsOneWidget);
    expect(find.text(l.yasalBelgeSurum(YasalBelge.kosullar.surum)),
        findsNWidgets(4));
    expect(find.text(l.yasalKapiTaahhutBaslik), findsNothing);
    expect(find.text(KayitKutuMetni.rizaCumle), findsNothing);

    await onayla(tester);
    expect(tamam, 1);
    expect(cagrilar.single['p_kanal'], 'yeniden_onay');
    expect(turler(), [
      YasalTur.kosullar,
      YasalTur.gizlilik,
      YasalTur.kvkk,
      YasalTur.acikRiza,
    ]);
    final ogeler = cagrilar.single['p_ogeler'] as List;
    expect((ogeler.first as Map)['surum'], YasalBelge.kosullar.surum);
    expect((ogeler.first as Map)['degiskenler']['onceki_surum'], '1.1');
    expect((ogeler.last as Map)['degiskenler']['onceki_surum'], isNull);
    expect(uyariKayitlari, isEmpty);
  });

  testWidgets(
      'ilk kez (sosyal giriş): kayıt formundaki iki kutunun aynısı; '
      'işaretlenmeden onay yazılmaz', (tester) async {
    await ac(tester, ilk);
    expect(find.text(l.yasalKapiBaslikIlk), findsOneWidget);
    expect(find.text(l.yasalKapiNelerDegisti), findsNothing);
    expect(find.text(KayitKutuMetni.kosulCumle), findsOneWidget);
    expect(find.text(KayitKutuMetni.rizaCumle), findsOneWidget);
    expect(find.text(KayitKutuMetni.kosulGovde), findsOneWidget);

    await onayla(tester);
    expect(cagrilar, isEmpty);
    expect(tamam, 0);
    expect(find.text(l.yasalKapiKutuGerekli), findsNWidgets(2));

    await tester.ensureVisible(find.text(KayitKutuMetni.kosulCumle));
    await tester.tap(find.text(KayitKutuMetni.kosulCumle));
    await tester.pump();
    await onayla(tester);
    expect(cagrilar, isEmpty, reason: 'yalnız bir kutu işaretli');
    expect(find.text(l.yasalKapiKutuGerekli), findsOneWidget);

    await tester.ensureVisible(find.text(KayitKutuMetni.rizaCumle));
    await tester.tap(find.text(KayitKutuMetni.rizaCumle));
    await tester.pump();
    await onayla(tester);
    expect(tamam, 1);
    expect(turler(), [
      YasalTur.kayitKutuKosullar,
      YasalTur.kayitKutuRiza,
      YasalTur.kosullar,
      YasalTur.gizlilik,
      YasalTur.kvkk,
      YasalTur.acikRiza,
    ]);
    // Kutu metni kataloğun hash'iyle: sunucu aynı metni doğrular.
    expect(((cagrilar.single['p_ogeler'] as List).first as Map)['hash'],
        YasalMetinKatalogu.kayitKutuKosullar().hash);
  });

  testWidgets('tek kutu bayrağı açıkken kapı da tek kutu gösterir',
      (tester) async {
    RemoteConfigService.testAcik = {
      'yasal_onay_kaydi',
      'yasal_kapi_en_yeni',
      'tek_onay_kutusu',
    };
    await ac(tester, ilk);
    final cumle = YasalMetinKatalogu.tekKutuCumlesi(l);
    expect(find.text(cumle), findsOneWidget);
    expect(find.text(KayitKutuMetni.rizaCumle), findsNothing);
    await tester.ensureVisible(find.text(cumle));
    await tester.tap(find.text(cumle));
    await tester.pump();
    await onayla(tester);
    expect(tamam, 1);
    final kutu = (cagrilar.single['p_ogeler'] as List).first as Map;
    expect(kutu['tur'], YasalTur.kayitTekKutu);
    expect(kutu['hash'], YasalMetinKatalogu.kayitTekKutu('tr').hash);
  });

  testWidgets('belge satırı belgeyi açar, "okundu" işaretlenir ve kayda gider',
      (tester) async {
    await ac(tester, guncelleme);
    await tester.tap(find.ancestor(
        of: sigan(l.yasalBelgeKvkk), matching: find.byType(SandikBasma)));
    await tester.pumpAndSettle();
    final belge = tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
    expect(belge.blocks.length, LegalDocs.kvkk.length);
    expect(belge.blocks.first.text, 'KVKK Aydınlatma Metni — sandık');
    expect(belge.confirmMode, isFalse);
    Navigator.of(tester.element(find.byType(LegalDocScreen))).pop();
    await tester.pumpAndSettle();
    expect(
        find.text('${l.yasalBelgeSurum(YasalBelge.kvkk.surum)} · '
            '${l.yasalBelgeAcildi}'),
        findsOneWidget);
    await onayla(tester);
    final kvkk = (cagrilar.single['p_ogeler'] as List)
        .cast<Map<String, dynamic>>()
        .singleWhere((o) => o['tur'] == YasalTur.kvkk);
    expect(kvkk['degiskenler']['belge_acildi'], isTrue);
  });

  testWidgets('ağ hatası: hata görünür, kapı KAPANMAZ; yeniden denenir',
      (tester) async {
    YasalOnayService.rpcTesti =
        (_) async => throw const SocketException('bağlantı yok');
    await ac(tester, guncelleme);
    await onayla(tester);
    expect(tamam, 0);
    expect(find.text(l.yasalKapiKayitHatasi), findsOneWidget);

    YasalOnayService.rpcTesti = (p) async => cagrilar.add(p);
    await onayla(tester);
    expect(tamam, 1);
  });

  testWidgets(
      'sunucu reddederse (metin kayması gibi) kullanıcı kilitlenmez '
      '(fail-open); iz konmaz', (tester) async {
    YasalOnayService.rpcTesti =
        (_) async => throw StateError('yasal metin hash uyusmuyor');
    await ac(tester, guncelleme);
    await onayla(tester);
    expect(tamam, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(YasalOnayService.izAnahtari('u1')), isNull);
  });

  testWidgets(
      'yatırım uyarısı da eksikse aynı ekrana girer: metin görünür, '
      'disclaimer_acceptances aynı çağrıyla yazılır', (tester) async {
    await ac(tester, ilk, uyari: true);
    expect(find.text(disclaimerText), findsOneWidget);
    for (final c in [KayitKutuMetni.kosulCumle, KayitKutuMetni.rizaCumle]) {
      await tester.ensureVisible(find.text(c));
      await tester.tap(find.text(c));
      await tester.pump();
    }
    await onayla(tester);
    expect(uyariKayitlari, ['u1']);
    expect(turler().last, YasalTur.yatirimUyarisi);
    expect(tamam, 1);
  });

  testWidgets('geri tuşuyla atlanamaz', (tester) async {
    await ac(tester, guncelleme);
    final pop = tester.widget<PopScope>(find.byType(PopScope).first);
    expect(pop.canPop, isFalse);
    expect(find.text(l.yasalKapiCikis), findsOneWidget);
  });

  group('dar ekranda taşma yok', () {
    for (final boyut in const [Size(320, 568), Size(360, 640)]) {
      for (final olcek in const [1.0, 1.3, 1.6, 2.0]) {
        for (final dil in const [Locale('tr', 'TR'), Locale('en', 'US')]) {
          testWidgets(
              '${boyut.width.toInt()} dp, yazı x$olcek, ${dil.languageCode}',
              (tester) async {
            await ac(tester, ilk,
                uyari: true, boyut: boyut, olcek: olcek, dil: dil);
            await tester.pump(const Duration(seconds: 1));
            final kaydir = find.byType(Scrollable).first;
            await tester.fling(kaydir, const Offset(0, -6000), 3000);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}
