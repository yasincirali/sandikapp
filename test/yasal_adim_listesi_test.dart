import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/screens/yasal_onay_kapisi_screen.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/yasal_adim.dart';

/// Ortak adım listesi (`YasalAdimListesi`, kullanıcı kararı 2026-10-05,
/// seçenek "C · Adım adım") — ekran okuyucu sırası, dokunma hedefleri ve
/// dar ekran/büyük yazı taşması. Adım KURALI `yasal_adim_plani_test`'te,
/// ekran akışları `kayit_tek_onay_test`, `yasal_onay_kapisi_test`,
/// `zorunlu_okuma_test`'te.
void main() {
  final tr = AppLocalizationsTr();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'sandık',
      packageName: 'com.sandik.app',
      version: '1.1.7',
      buildNumber: '8',
      buildSignature: '',
    );
    YasalOnayService.instance.testSifirla();
  });

  Future<void> kur(
    WidgetTester tester,
    Widget ekran, {
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
          home: ekran,
        ),
      ),
    ));
    await tester.pump();
  }

  /// Kullanıcının etkin onayları: [eski]deki belgeler eski sürümde,
  /// diğerleri ve kutu güncel.
  YasalKapiDurumu durum(Set<YasalBelge> eski) =>
      YasalOnayService.eksikleriHesapla([
        for (final b in YasalBelge.values)
          (b.tur, eski.contains(b) ? '1.0' : b.surum),
        (YasalTur.kayitTekKutu, YasalMetinKatalogu.kutuSurumu),
      ]);

  Widget kapi(YasalKapiDurumu d, {bool uyari = false}) => YasalOnayKapisiScreen(
        userId: 'u1',
        durum: d,
        yatirimUyarisiDahil: uyari,
        onTamam: () {},
      );

  group('ekran okuyucu: adımlar sırayla, "Adım n/N, ad, durum"', () {
    testWidgets('kayıt — durumlar okudukça ilerler', (tester) async {
      final semantik = tester.ensureSemantics();
      await kur(tester, const RegisterScreen());
      final etiketler = [
        'Adım 1/3, ${tr.yasalBelgeYatirimUyarisi}, bekliyor',
        'Adım 2/3, ${tr.yasalBelgeAcikRiza}, sırası gelecek',
        'Adım 3/3, ${tr.yasalAdimKutuBaslik}, sırası gelecek',
      ];
      expect(etiketler[1], tr.yasalAdimSemantik(2, 3, tr.yasalBelgeAcikRiza,
          tr.yasalAdimDurumSonra));
      final y = <double>[];
      for (final e in etiketler) {
        final f = find.bySemanticsLabel(e);
        expect(f, findsOneWidget, reason: e);
        y.add(tester.getRect(f).top);
      }
      expect(y, [...y]..sort(), reason: 'yukarıdan aşağı aynı sıra');

      await adimlariOku(tester, tr.yasalAdimOkuOnayla, adet: 1);
      expect(
          find.bySemanticsLabel(
              'Adım 1/3, ${tr.yasalBelgeYatirimUyarisi}, tamamlandı'),
          findsOneWidget);
      expect(find.bySemanticsLabel('Adım 2/3, ${tr.yasalBelgeAcikRiza}, '
          'bekliyor'), findsOneWidget);
      // Eylem başlıktan SONRA gelir ve düğme olarak okunur.
      final dugme = find.text(tr.yasalAdimOkuOnayla);
      expect(tester.getSemantics(dugme), isSemantics(isButton: true));
      expect(tester.getRect(dugme).top,
          greaterThan(tester.getRect(find.bySemanticsLabel(
              'Adım 2/3, ${tr.yasalBelgeAcikRiza}, bekliyor')).top));
      semantik.dispose();
    });

    testWidgets('kapı, İngilizce — tek adım', (tester) async {
      final semantik = tester.ensureSemantics();
      final en = AppLocalizationsEn();
      await kur(tester, kapi(durum({YasalBelge.acikRiza})),
          dil: const Locale('en'));
      expect(find.text(en.yasalAdimKapiBaslik(1)), findsOneWidget);
      expect(find.text(en.yasalKapiBaslikGuncelTek), findsOneWidget);
      expect(
          find.bySemanticsLabel(
              'Step 1 of 1, ${en.yasalBelgeAcikRiza}, waiting'),
          findsOneWidget);
      semantik.dispose();
    });
  });

  group('dokunma hedefleri ≥ SandikTouch.min', () {
    for (final olcek in const [1.0, 2.0]) {
      testWidgets('yazı x$olcek', (tester) async {
        await kur(tester, kapi(durum({YasalBelge.acikRiza}), uyari: true),
            boyut: const Size(320, 2400), olcek: olcek);
        Size boyutu(Finder f) => tester.getSize(f);
        await tester.scrollUntilVisible(
            find.text(tr.yasalAdimOkuOnayla), 200,
            scrollable: find.byType(Scrollable).first);
        final dugme = find.ancestor(
            of: find.text(tr.yasalAdimOkuOnayla),
            matching: find.byType(SandikBasma));
        expect(boyutu(dugme).height, greaterThanOrEqualTo(SandikTouch.min));
        expect(boyutu(dugme).width, greaterThanOrEqualTo(SandikTouch.min));
        await tester.scrollUntilVisible(
            find.text(tr.yasalAdimDigerBelgeler(3)), 200,
            scrollable: find.byType(Scrollable).first);
        final digerBaslik = find.ancestor(
            of: find.text(tr.yasalAdimDigerBelgeler(3)),
            matching: find.byType(SandikBasma));
        expect(boyutu(digerBaslik).height,
            greaterThanOrEqualTo(SandikTouch.min));
        expect(tester.takeException(), isNull);
      });
    }
  });

  // ── Taşma: 320/360 dp × yazı 1,0/1,6/2,0 × TR/EN; kayıt + kapı, 1 ve 3
  // adımlı. Her adım tamamlanır (kutu görünür), diğer belgeler açılır,
  // ekran sonuna kadar kaydırılır.
  group('taşma yok', () {
    final ekranlar = <(String, Widget Function(), int)>[
      ('kayıt (3 adım)', () => const RegisterScreen(), 2),
      (
        'kapı ilk + uyarı (3 adım)',
        () => kapi(YasalOnayService.eksikleriHesapla(const []), uyari: true),
        2
      ),
      ('kapı yalnız Koşullar (1 adım)', () => kapi(durum({YasalBelge.kosullar})),
          0),
      (
        'kapı yalnız Gizlilik + KVKK (1 adım)',
        () => kapi(durum({YasalBelge.gizlilik, YasalBelge.kvkk})),
        0
      ),
      ('kapı yalnız Açık Rıza (1 adım)', () => kapi(durum({YasalBelge.acikRiza})),
          1),
    ];
    for (final dil in const [Locale('tr', 'TR'), Locale('en')]) {
      for (final boyut in const [Size(320, 568), Size(360, 640)]) {
        for (final olcek in const [1.0, 1.6, 2.0]) {
          for (final (ad, ekran, okuma) in ekranlar) {
            testWidgets(
                '$ad — ${dil.languageCode} ${boyut.width.toInt()} dp, '
                'yazı x$olcek', (tester) async {
              final ll = dil.languageCode == 'en'
                  ? AppLocalizationsEn()
                  : AppLocalizationsTr();
              await kur(tester, ekran(),
                  boyut: boyut, olcek: olcek, dil: dil);
              await tester.pump(const Duration(seconds: 1));
              expect(tester.takeException(), isNull);
              await adimlariOku(tester, ll.yasalAdimOkuOnayla, adet: okuma);
              expect(tester.takeException(), isNull);
              final liste = find.byType(Scrollable).first;
              final diger = find.textContaining(
                  ll.yasalAdimDigerBelgeler(0).split(' (').first);
              await tester.scrollUntilVisible(diger, 200, scrollable: liste);
              // Kısmen görünürse (alt kenarda) dokunuş alttaki "Çıkış yap"a
              // düşer: tamamen görünür alana al.
              await tester.ensureVisible(diger);
              await tester.pumpAndSettle();
              await tester.tap(diger);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.fling(liste, const Offset(0, -6000), 3000);
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox());
              await tester.pump(const Duration(seconds: 5));
            });
          }
        }
      }
    }
  });

  group('odak sıradaki adıma geçer (2026-10-05)', () {
    testWidgets(
        'kısa ekranda okuma bitince liste sıradaki adıma kendiliğinden '
        'kayar; kutu adımı görünür alanda', (tester) async {
      await kur(tester, kapi(durum(YasalBelge.values.toSet()), uyari: true),
          boyut: const Size(390, 700));
      final liste = find.byType(Scrollable).first;
      double ofset() =>
          tester.state<ScrollableState>(liste).position.pixels;
      expect(ofset(), 0);
      // Uyarı → Açık Rıza: iki okuma, ardından kutu adımı sıradaki.
      await adimlariOku(tester, tr.yasalAdimOkuOnayla, adet: 2);
      expect(ofset(), greaterThan(0),
          reason: 'kullanıcı kaydırmadan sıradaki adıma gelinmeli');
      final kare = find.descendant(
          of: find.byType(YasalOnayKutusu),
          matching: find.byType(AnimatedContainer));
      final alan = tester.getRect(liste);
      final kutu = tester.getRect(kare);
      expect(kutu.top, greaterThanOrEqualTo(alan.top));
      expect(kutu.bottom, lessThanOrEqualTo(alan.bottom),
          reason: 'kutu kaydırmadan görünür olmalı');
    });
  });
}
