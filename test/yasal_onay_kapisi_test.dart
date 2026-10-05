import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/screens/yasal_onay_kapisi_screen.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:portfoy_takip/widgets/zorunlu_okuma.dart' show OkumaIpucu;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/yasal_adim.dart';

/// Yeniden onay kapısı ekranı (2026-10-04).
///
/// Kullanıcı kararı: eski metni onaylayan girişte güncel belgeleri görüp
/// onaylar; Apple/Google ile ilk kez gelen kayıt formundaki taahhüdün
/// aynısını (tek kutu) onaylar. Ekran geri tuşuyla atlanamaz, ağ hatasında
/// kilitlemez ama onayı da yazılmış saymaz.
///
/// 2026-10-05: bayraklar (`yasal_kapi_en_yeni`, `tek_onay_kutusu`,
/// `zorunlu_okuma`) kalktı. Aynı gün okuma sadeleştirme (1.4): YALNIZ Açık
/// Rıza Metni (eksikse) ve yatırım uyarısı sonuna kadar okunur
/// ([okunacaklariOku]; okuma mekaniği `zorunlu_okuma_test`'te); Koşullar,
/// Gizlilik, KVKK salt okunur bağlantıdır ve kutuyla alınır.
///
/// Adım düzeni (2026-10-05, seçenek C): yalnız eksik olanların numaralı
/// adımı (uyarı → Açık Rıza → kutu); kutu son adım, okumalar bitince
/// görünür. Senaryoların tamamı `yasal_adim_plani_test`'te; burada ekran.
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
  });
  tearDown(() {
    YasalOnayService.rpcTesti = null;
    YasalOnayKapisiScreen.uyariKaydiTesti = null;
    YasalOnayService.instance.testSifirla();
  });

  /// Bugünün kullanıcısı: dört belgenin 1.3'ünü ve kutu 1.0'ı onaylamış.
  /// 1.4'te dördü + kutu 1.1 eksik → tek seferde.
  final guncelleme = YasalOnayService.eksikleriHesapla([
    for (final b in YasalBelge.values) (b.tur, '1.3'),
    (YasalTur.kayitTekKutu, '1.0'),
  ]);

  /// Yalnız Açık Rıza Metni'nin güncel sürümü eksik (kutu ve diğer üç
  /// belge güncel) — kutu SORULMAZ, yalnız rıza okunur.
  final yalnizRiza = YasalOnayService.eksikleriHesapla([
    for (final b in YasalBelge.values)
      if (b != YasalBelge.acikRiza) (b.tur, b.surum),
    (YasalTur.acikRiza, '1.3'),
    (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
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
  Finder sigan(String ilkAday) => find
      .byWidgetPredicate((w) => w is SiganMetin && w.adaylar.first == ilkAday);

  Future<void> onayla(WidgetTester tester) async {
    final dugme = find.byType(SandikAsyncButton);
    await tester.ensureVisible(dugme);
    await tester.tap(dugme);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Okuma adımlarını ("Oku ve onayla") sırayla açar ve okuyucuyu
  /// "sonuna kadar okundu, onaylandı" ile kapatır — kapının akışını
  /// sınamak için; kaydırma ayrı testte.
  Future<void> okunacaklariOku(WidgetTester tester, {int adet = 1}) =>
      adimlariOku(tester, l.yasalAdimOkuOnayla, adet: adet);

  SandikAsyncButton dugme(WidgetTester tester) =>
      tester.widget<SandikAsyncButton>(find.byType(SandikAsyncButton));

  /// Kutunun karesine dokunur (cümlede belge bağlantıları var).
  Future<void> kutuyuIsaretle(WidgetTester tester) async {
    final kare = find.descendant(
        of: find.byType(YasalOnayKutusu),
        matching: find.byType(AnimatedContainer));
    await tester.ensureVisible(kare);
    await tester.tap(kare);
    await tester.pump();
  }

  Finder kutuCumlesi() =>
      find.text(YasalMetinKatalogu.tekKutuCumlesi(l), findRichText: true);

  List<String> turler() => [
        for (final o in cagrilar.single['p_ogeler'] as List)
          (o as Map)['tur'] as String,
      ];

  testWidgets(
      'güncellenen belgeler (1.3 → 1.4): "Neler değişti", 2 adım (Açık Rıza '
      '→ kutu); üç belge kutu adımında bağlantı; tek dokunuş yazar',
      (tester) async {
    await ac(tester, guncelleme);
    expect(find.text(l.yasalKapiBaslikGuncel), findsOneWidget);
    expect(find.text(l.yasalKapiNelerDegisti), findsOneWidget);
    // Katlanır, varsayılan kapalı (2026-10-05): not başlığa dokununca açılır.
    expect(find.text(l.yasalKapiDegisiklikNotu), findsNothing);
    await tester.tap(find.text(l.yasalKapiNelerDegisti));
    await tester.pumpAndSettle();
    expect(find.text(l.yasalKapiDegisiklikNotu), findsOneWidget);
    expect(l.yasalKapiDegisiklikNotu,
        startsWith('Sürüm ${YasalBelge.kosullar.surum}'));
    await tester.tap(find.text(l.yasalKapiNelerDegisti));
    await tester.pumpAndSettle();
    expect(find.text(l.yasalKapiDegisiklikNotu), findsNothing);
    expect(find.text(l.yasalAdimKapiBaslik(2)), findsOneWidget);
    expect(sigan(l.yasalKapiOnayla), findsOneWidget);
    // 1. adım Açık Rıza (sıradaki), 2. adım kutu (başlığı görünür, kutu
    // okumadan sonra).
    final kutuBasligi = l.yasalAdimGuncellendi(l.yasalAdimListeVe(
        '${l.yasalBelgeKosullar}, ${l.yasalBelgeGizlilik}', l.yasalBelgeKvkk));
    expect(find.text(l.yasalBelgeAcikRiza), findsOneWidget);
    expect(find.text(kutuBasligi), findsOneWidget);
    expect(find.text(l.yasalAdimOkuOnayla), findsOneWidget);
    expect(kutuCumlesi(), findsNothing);
    expect(find.text(l.yasalAdimSayac(0, 2)), findsOneWidget);
    expect(dugme(tester).onPressed, isNull);
    // Dört belge de adımda: "Diğer belgeler" yok.
    expect(find.textContaining(l.yasalAdimDigerBelgeler(0).split(' (').first),
        findsNothing);

    await okunacaklariOku(tester);
    // Kutu adımında güncellenen üç belge bağlantı, cümlede kalın.
    for (final ad in [
      l.yasalBelgeKosullar,
      l.yasalBelgeGizlilik,
      l.yasalBelgeKvkk,
    ]) {
      expect(sigan(ad), findsOneWidget, reason: ad);
    }
    expect(kutuCumlesi(), findsOneWidget);
    expect(find.text(l.yasalAdimSayac(1, 2)), findsOneWidget);
    await onayla(tester);
    expect(cagrilar, isEmpty, reason: 'kutu işaretsiz: düğme kapalı');
    expect(dugme(tester).onPressed, isNull);
    await kutuyuIsaretle(tester);
    expect(find.text(l.yasalAdimSayac(1, 2)), findsNothing);
    await onayla(tester);
    expect(tamam, 1);
    expect(cagrilar.single['p_kanal'], 'yeniden_onay');
    expect(turler(), [
      YasalTur.kayitTekKutu,
      YasalTur.kosullar,
      YasalTur.gizlilik,
      YasalTur.kvkk,
      YasalTur.acikRiza,
    ]);
    final ogeler = [
      for (final o in cagrilar.single['p_ogeler'] as List) o as Map
    ];
    expect(ogeler.first['surum'], YasalMetinKatalogu.kutuSurumu);
    expect(ogeler[1]['surum'], YasalBelge.kosullar.surum);
    expect(ogeler[1]['degiskenler']['onceki_surum'], '1.3');
    expect(ogeler[1]['degiskenler']['sonuna_kadar_okundu'], isFalse);
    expect(ogeler[2]['degiskenler']['nitelik'], 'bilgilendirme');
    expect(ogeler.last['degiskenler']['sonuna_kadar_okundu'], isTrue);
    expect(uyariKayitlari, isEmpty);
  });

  testWidgets(
      'yalnız Açık Rıza eksik: kutu YOK, rıza okununca yazılan yalnız rıza',
      (tester) async {
    await ac(tester, yalnizRiza);
    expect(find.text(l.yasalKapiBaslikGuncelTek), findsOneWidget);
    expect(find.text(l.yasalAdimKapiBaslik(1)), findsOneWidget);
    expect(find.byType(YasalOnayKutusu), findsNothing);
    expect(find.text(l.yasalAdimKutuBaslik), findsNothing);
    // Diğer üç belge katlanır bölümde.
    expect(find.text(l.yasalAdimDigerBelgeler(3)), findsOneWidget);
    expect(dugme(tester).onPressed, isNull);
    await okunacaklariOku(tester);
    expect(find.byType(YasalOnayKutusu), findsNothing);
    expect(dugme(tester).onPressed, isNotNull);
    await onayla(tester);
    expect(tamam, 1);
    expect(turler(), [YasalTur.acikRiza]);
  });

  testWidgets(
      'ilk kez (sosyal giriş): kayıt formundaki tek kutunun aynısı; '
      'işaretlenmeden onay yazılmaz', (tester) async {
    await ac(tester, ilk);
    expect(find.text(l.yasalKapiBaslikIlk), findsOneWidget);
    expect(find.text(l.yasalKapiNelerDegisti), findsNothing);
    // Kayıttaki adımlar (uyarı burada dahil değil): Açık Rıza → kutu.
    expect(find.text(l.yasalAdimKapiBaslik(2)), findsOneWidget);
    expect(find.text(l.yasalAdimKutuBaslik), findsOneWidget);
    expect(find.text(l.yasalAdimDigerBelgeler(3)), findsOneWidget);
    await okunacaklariOku(tester);
    expect(kutuCumlesi(), findsOneWidget);
    expect(find.text(KayitKutuMetni.rizaCumle), findsNothing);
    await onayla(tester);
    expect(cagrilar, isEmpty, reason: 'kutu işaretsiz');
    expect(tamam, 0);

    await kutuyuIsaretle(tester);
    await onayla(tester);
    expect(tamam, 1);
    expect(turler(), [
      YasalTur.kayitTekKutu,
      YasalTur.kosullar,
      YasalTur.gizlilik,
      YasalTur.kvkk,
      YasalTur.acikRiza,
    ]);
    final kutu = (cagrilar.single['p_ogeler'] as List).first as Map;
    expect(kutu['tur'], YasalTur.kayitTekKutu);
    expect(kutu['hash'], YasalMetinKatalogu.kayitTekKutu('tr').hash);
  });

  testWidgets(
      'kutu adımındaki bağlantı belgeyi SALT OKUNUR açar (onay düğmesi yok); '
      'dönüşte "Açıldı" izi, adım ilerlemez; kayda belge_acildi',
      (tester) async {
    await ac(tester, guncelleme);
    await okunacaklariOku(tester);
    final kosullar = sigan(l.yasalBelgeKosullar);
    await tester.ensureVisible(kosullar);
    await gercekBekle(tester);
    await tester.tap(kosullar);
    await tester.pumpAndSettle();
    final belge = tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
    expect(belge.zorunluOkuma, isFalse);
    expect(belge.title, l.yasalBelgeKosullar);
    expect(find.byType(OkumaIpucu), findsNothing);
    Navigator.of(tester.element(find.byType(LegalDocScreen))).pop();
    await tester.pumpAndSettle();
    expect(find.text(l.yasalBelgeAcildi), findsOneWidget);
    // Açılması onay değildir: sayaç ve düğme değişmez.
    expect(find.text(l.yasalAdimSayac(1, 2)), findsOneWidget);
    expect(dugme(tester).onPressed, isNull);

    await kutuyuIsaretle(tester);
    await onayla(tester);
    final ogeler = {
      for (final o in cagrilar.single['p_ogeler'] as List)
        (o as Map)['tur']: o['degiskenler'] as Map,
    };
    expect(ogeler[YasalTur.kosullar]!['belge_acildi'], isTrue);
    expect(ogeler[YasalTur.gizlilik]!['belge_acildi'], isFalse);
  });

  testWidgets(
      'yalnız Koşullar güncellendi: 1 adım (kutu), başlık "Kullanım '
      'Koşulları güncellendi", belge bağlantı + cümlede kalın; yazım aynı',
      (tester) async {
    final yalnizKosullar = YasalOnayService.eksikleriHesapla([
      for (final b in YasalBelge.values)
        (b.tur, b == YasalBelge.kosullar ? '1.3' : b.surum),
      (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
    ]);
    await ac(tester, yalnizKosullar);
    expect(find.text(l.yasalKapiBaslikGuncelTek), findsOneWidget);
    expect(find.text(l.yasalAdimKapiBaslik(1)), findsOneWidget);
    expect(find.text(l.yasalAdimGuncellendi(l.yasalBelgeKosullar)),
        findsOneWidget);
    expect(find.text(l.yasalAdimKosulGuncelAciklama), findsOneWidget);
    // Okuma adımı yok: kutu hemen sıradaki adım.
    expect(find.text(l.yasalAdimOkuOnayla), findsNothing);
    expect(sigan(l.yasalBelgeKosullar), findsOneWidget);
    expect(kutuCumlesi(), findsOneWidget);
    // Cümlede yalnız güncellenen belge kalın.
    final cumle = tester
        .widgetList<Text>(find.descendant(
            of: find.byType(YasalOnayKutusu), matching: find.byType(Text)))
        .firstWhere((t) => t.textSpan != null)
        .textSpan!;
    FontWeight? kalinlik(String parca) {
      FontWeight? w;
      cumle.visitChildren((span) {
        if (span is TextSpan && span.text == parca) w = span.style?.fontWeight;
        return true;
      });
      return w;
    }

    expect(kalinlik(l.tekOnayKosullarBaglanti), FontWeight.w800);
    expect(kalinlik(l.tekOnayGizlilikBaglanti), isNot(FontWeight.w800));
    expect(dugme(tester).onPressed, isNull);
    await kutuyuIsaretle(tester);
    await onayla(tester);
    expect(tamam, 1);
    expect(turler(), [
      YasalTur.kayitTekKutu,
      YasalTur.kosullar,
      YasalTur.gizlilik,
      YasalTur.kvkk,
    ]);
  });

  testWidgets(
      'diğer belgeler katlanır: dokununca açılır; belge salt okunur açılır',
      (tester) async {
    final semantik = tester.ensureSemantics();
    await ac(tester, yalnizRiza);
    final baslik = find.text(l.yasalAdimDigerBelgeler(3));
    expect(sigan(l.yasalBelgeKvkk), findsNothing);
    expect(tester.getSemantics(baslik),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: false));
    await tester.tap(baslik);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(baslik),
        isSemantics(isButton: true, hasExpandedState: true, isExpanded: true));
    for (final ad in [
      l.yasalBelgeKosullar,
      l.yasalBelgeGizlilik,
      l.yasalBelgeKvkk,
    ]) {
      expect(sigan(ad), findsOneWidget, reason: ad);
      expect(
          tester
              .getSize(find
                  .ancestor(
                      of: sigan(ad), matching: find.byType(ConstrainedBox))
                  .first)
              .height,
          greaterThanOrEqualTo(SandikTouch.min),
          reason: 'dokunma hedefi');
    }
    await gercekBekle(tester);
    await tester.tap(sigan(l.yasalBelgeKvkk));
    await tester.pumpAndSettle();
    final belge = tester.widget<LegalDocScreen>(find.byType(LegalDocScreen));
    expect(belge.zorunluOkuma, isFalse);
    expect(belge.title, l.yasalBelgeKvkk);
    semantik.dispose();
  });

  testWidgets('ağ hatası: hata görünür, kapı KAPANMAZ; yeniden denenir',
      (tester) async {
    YasalOnayService.rpcTesti =
        (_) async => throw const SocketException('bağlantı yok');
    await ac(tester, guncelleme);
    await okunacaklariOku(tester);
    await kutuyuIsaretle(tester);
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
    await okunacaklariOku(tester);
    await kutuyuIsaretle(tester);
    await onayla(tester);
    expect(tamam, 1);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(YasalOnayService.izAnahtari('u1')), isNull);
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
