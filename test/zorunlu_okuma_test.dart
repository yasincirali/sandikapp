import 'package:flutter/material.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/screens/disclaimer_acceptance_screen.dart';
import 'package:portfoy_takip/screens/legal_doc_screen.dart';
import 'package:portfoy_takip/screens/otp_verification_screen.dart';
import 'package:portfoy_takip/screens/register_screen.dart';
import 'package:portfoy_takip/screens/yasal_onay_kapisi_screen.dart';
import 'package:portfoy_takip/screens/zirve_portfoyler_screen.dart';
import 'package:portfoy_takip/services/disclaimer_service.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';
import 'package:portfoy_takip/services/yasal_onay_service.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';
import 'package:portfoy_takip/widgets/sigan_metin.dart';
import 'package:portfoy_takip/widgets/zirve_riza_karti.dart';
import 'package:portfoy_takip/widgets/zorunlu_okuma.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';
import 'helpers/yasal_adim.dart' show adimlariOku;

/// Zorunlu okuma (bayrak `zorunlu_okuma`, kullanıcı kararı 2026-10-04):
/// *"Özeti değil hepsini okutmalıyız. Zorunlu okutup en sonda onaylatarak
/// ilerleyelim."* Onay istenen her metin TAM gösterilir; sonuna kadar
/// kaydırılmadan onay düğmesi açılmaz, onay metnin EN SONUNDADIR; bütün
/// metinler onaylanmadan akış ilerlemez.
///
/// Bayrak `zorunlu_okuma` (ve `tek_onay_kutusu`) 2026-10-05'te kalktı:
/// davranış kalıcı, testler iki kutulu ve "bayrak kapalı" dalları sınamaz.
///
/// Okuma sadeleştirme (kullanıcı kararı 2026-10-05: *"Tüm hepsini içinden
/// onaylatmak çok uzun bir process gibi oldu."*): kayıtta ve kapıda YALNIZ
/// Açık Rıza Metni ve yatırım uyarısı sonuna kadar okunur. Koşullar,
/// Gizlilik ve KVKK salt okunur bağlantıdır; Koşullar kutuyla kabul
/// edilir, ikisi için kutu "bilgilendirildim" der. Kutu cümlesi AÇIK RIZA
/// İÇERMEZ ve kutu metinlere kilitli değildir. Okuyucunun mekaniği (sona
/// ulaşma, erişilebilirlik) aynen sınanır.
///
/// Adım düzeni (2026-10-05, seçenek C): okunacaklar numaralı adımlardır
/// (uyarı → Açık Rıza → kutu); eylem yalnız sıradaki adımda, kutu son
/// adım. Bilgi amaçlı belgeler katlanır "Diğer belgeler"de.
void main() {
  final l = AppLocalizationsTr();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'sandık',
      packageName: 'com.sandik.app',
      version: '1.1.7',
      buildNumber: '8',
      buildSignature: '',
    );
  });
  tearDown(() {
    RegisterScreen.kayitIstegiTesti = null;
    YasalOnayService.rpcTesti = null;
    YasalOnayKapisiScreen.uyariKaydiTesti = null;
    YasalOnayService.instance.testSifirla();
  });

  Future<void> kur(
    WidgetTester tester,
    Widget ekran, {
    Size boyut = const Size(390, 844),
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
    await tester.pump();
  }

  /// Okuyucuyu açan ev sahibi: dönüşü [sonuclar]'a yazar.
  Widget evSahibi(ZorunluMetin Function(AppLocalizations) metin,
          List<ZorunluOkumaSonucu?> sonuclar) =>
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async => sonuclar
                  .add(await zorunluOkumaAc(context, metin(context.l10nOrTr))),
              child: const Text('aç'),
            ),
          ),
        ),
      );

  Finder okuyucuListesi() => find.descendant(
      of: find.byType(LegalDocScreen), matching: find.byType(Scrollable));

  // Liste tembel ve sona ulaşma yapışkan: düğme kurulu ama görünüm dışında
  // olabilir → `skipOffstage: false`, basmadan önce `ensureVisible`.
  Finder etkinOnay() => find.descendant(
      of: find.byType(LegalDocScreen),
      matching: find.byIcon(Icons.check_circle_rounded, skipOffstage: false),
      skipOffstage: false);

  Finder kilitliOnay() => find.descendant(
      of: find.byType(LegalDocScreen),
      matching: find.byIcon(Icons.lock_outline_rounded, skipOffstage: false),
      skipOffstage: false);

  /// `pushGuarded`'ın çift dokunma penceresi GERÇEK saatle ölçülür (500 ms);
  /// önceki itme (ya da önceki test) pencerede kalmasın.
  Future<void> gercekBekle(WidgetTester tester) => tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 550)));

  bool sonaUlasildi() => find.byType(OkumaIpucu).evaluate().isEmpty;

  /// Parmakla sona kadar kaydırır (sınırlı deneme — kilitlenirse test
  /// burada düşer, sonsuz döngüye girmez).
  Future<void> sonunaKadarKaydir(WidgetTester tester, Finder liste) async {
    for (var i = 0; i < 300 && !sonaUlasildi(); i++) {
      await tester.drag(liste.first, const Offset(0, -1500));
      await tester.pump();
      await tester.pump();
    }
    expect(sonaUlasildi(), isTrue, reason: 'parmakla sona ulaşılamadı');
  }

  /// Okuyucuda: sona kaydır, en alttaki onaya bas, dön.
  Future<void> okuVeOnayla(WidgetTester tester) async {
    await tester.pumpAndSettle();
    await sonunaKadarKaydir(tester, okuyucuListesi());
    await tester.pumpAndSettle();
    await tester.ensureVisible(etkinOnay());
    await tester.tap(etkinOnay());
    await tester.pumpAndSettle();
  }

  // ── Ölçüm (saf) ─────────────────────────────────────────────────────────
  group('OkumaOlcumu', () {
    ScrollMetrics m(double pixels, double max, {double viewport = 600}) =>
        FixedScrollMetrics(
          minScrollExtent: 0,
          maxScrollExtent: max,
          pixels: pixels,
          viewportDimension: viewport,
          axisDirection: AxisDirection.down,
          devicePixelRatio: 3,
        );

    test('sığan metin baştan "sona ulaştı", ilerleme 1', () {
      expect(OkumaOlcumu.sonaUlasti(m(0, 0)), isTrue);
      expect(OkumaOlcumu.ilerleme(m(0, 0)), 1);
    });

    test('baştan ortaya: ulaşılmadı; tolerans içinde: ulaşıldı', () {
      expect(OkumaOlcumu.sonaUlasti(m(0, 5000)), isFalse);
      expect(OkumaOlcumu.sonaUlasti(m(2500, 5000)), isFalse);
      expect(OkumaOlcumu.ilerleme(m(2500, 5000)), closeTo(0.5, 0.001));
      expect(
          OkumaOlcumu.sonaUlasti(m(5000 - OkumaOlcumu.tolerans, 5000)), isTrue);
      expect(OkumaOlcumu.sonaUlasti(m(5000 - OkumaOlcumu.tolerans - 1, 5000)),
          isFalse);
    });

    test('düğmeden sonraki boşluk (sonPay) sayılmaz', () {
      // showOnScreen düğmenin altını hizalar; alttaki 60 pt boşluk görünmez
      // kalabilir. Payı saymamak düğmeyi kilitli bırakırdı.
      final x = m(5000 - OkumaOlcumu.tolerans - 60, 5000);
      expect(OkumaOlcumu.sonaUlasti(x), isFalse);
      expect(OkumaOlcumu.sonaUlasti(x, sonPay: 60), isTrue);
    });
  });

  // ── Okuyucu ─────────────────────────────────────────────────────────────
  group('okuyucu (LegalDocScreen zorunlu kip)', () {
    testWidgets(
        'uzun metin: onay EN SONDA, kilitli; ipucu görünür; '
        'kilitliyken basmak dönmez; sona kaydırınca açılır ve sonucu döner',
        (tester) async {
      final sonuclar = <ZorunluOkumaSonucu?>[];
      await kur(
          tester,
          evSahibi(
              (l) => ZorunluMetin.belge(l, YasalBelge.kosullar), sonuclar));
      await gercekBekle(tester);
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();

      expect(find.byType(OkumaIpucu), findsOneWidget);
      expect(
          find
              .byType(SiganMetin)
              .evaluate()
              .map((e) => (e.widget as SiganMetin).adaylar.first),
          contains(l.zorunluOkumaIpucu));
      // Onay düğmesi metnin sonunda ve kilitli.
      expect(etkinOnay(), findsNothing);
      expect(kilitliOnay(), findsOneWidget);
      final konum = tester.state<ScrollableState>(okuyucuListesi().first);
      expect(tester.getTopLeft(kilitliOnay()).dy,
          greaterThan(konum.position.viewportDimension),
          reason: 'düğme metnin sonunda, ilk ekranda değil');

      await sonunaKadarKaydir(tester, okuyucuListesi());
      await tester.pumpAndSettle();
      expect(etkinOnay(), findsOneWidget);
      await tester.ensureVisible(etkinOnay());
      await tester.pump();
      await tester.tap(etkinOnay());
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocScreen), findsNothing);
      expect(sonuclar.single?.onaylandi, isTrue);
      expect(sonuclar.single?.sonunaKadarOkundu, isTrue);
    });

    testWidgets('sona yakın ama ulaşmadan: düğme kilitli, basmak dönmez',
        (tester) async {
      // Sona 150 pt kala (düğme yarı görünür, son satırlar okunmadı).
      final sonuclar = <ZorunluOkumaSonucu?>[];
      await kur(
        tester,
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async => sonuclar.add(await zorunluOkumaAc(
                  context,
                  ZorunluMetin(
                    tur: 'deneme',
                    adaylar: const ['Deneme'],
                    ikon: Icons.gavel_rounded,
                    surum: '1',
                    bloklar: () => [
                      for (var i = 0; i < 120; i++) LegalBlock.p('Satır $i'),
                    ],
                    onayAdaylari: const ['Onayla'],
                  ))),
              child: const Text('aç'),
            ),
          ),
        ),
      );
      await gercekBekle(tester);
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(sonaUlasildi(), isFalse);
      final durum = tester.state<ScrollableState>(okuyucuListesi().first);
      durum.position.jumpTo(durum.position.maxScrollExtent - 150);
      await tester.pump();
      await tester.pump();
      expect(durum.position.extentAfter, closeTo(150, 1));
      expect(sonaUlasildi(), isFalse);
      expect(kilitliOnay(), findsOneWidget);
      await tester.tap(kilitliOnay(), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(LegalDocScreen), findsOneWidget);
      expect(sonuclar, isEmpty);
      // Son birkaç satır: açılır.
      await tester.drag(okuyucuListesi().first, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(sonaUlasildi(), isTrue);
      expect(etkinOnay(), findsOneWidget);
    });

    testWidgets('ekrana sığan metin: düğme baştan açık, ipucu yok',
        (tester) async {
      final sonuclar = <ZorunluOkumaSonucu?>[];
      await kur(
          tester, evSahibi((l) => ZorunluMetin.yatirimUyarisi(l), sonuclar),
          boyut: const Size(390, 1400));
      await gercekBekle(tester);
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(sonaUlasildi(), isTrue);
      expect(etkinOnay(), findsOneWidget);
      // Tam metin tek kaynaktan: `disclaimerText`'in kendisi.
      expect(find.text(disclaimerText), findsOneWidget);
      await tester.tap(etkinOnay());
      await tester.pumpAndSettle();
      expect(sonuclar.single?.onaylandi, isTrue);
    });

    testWidgets('geri dönmek onay değildir (null)', (tester) async {
      final sonuclar = <ZorunluOkumaSonucu?>[];
      await kur(tester,
          evSahibi((l) => ZorunluMetin.belge(l, YasalBelge.kvkk), sonuclar));
      await gercekBekle(tester);
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      // Sistem geri tuşu.
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(sonuclar.single, isNull);
    });

    testWidgets('açık rıza metninin sonunda "açık rıza veriyorum" yazar',
        (tester) async {
      await kur(tester,
          evSahibi((l) => ZorunluMetin.belge(l, YasalBelge.acikRiza), []));
      await gercekBekle(tester);
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      await sonunaKadarKaydir(tester, okuyucuListesi());
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((w) =>
              w is SiganMetin && w.adaylar.first == l.zorunluOkumaRizaVer),
          findsOneWidget);
    });
  });

  // ── Erişilebilirlik: kilitlenme yok ─────────────────────────────────────
  group('ekran okuyucuyla sona ulaşılır (kilitlenme yok)', () {
    for (final (boyut, olcek) in const [
      (Size(320, 568), 2.0),
      (Size(360, 640), 1.6),
      (Size(390, 844), 1.0),
    ]) {
      testWidgets(
          'kaydırma eylemi (TalkBack/VoiceOver) — '
          '${boyut.width.toInt()} dp, yazı x$olcek', (tester) async {
        final sem = tester.ensureSemantics();
        final sonuclar = <ZorunluOkumaSonucu?>[];
        await kur(
            tester,
            evSahibi(
                (l) => ZorunluMetin.belge(l, YasalBelge.kosullar), sonuclar),
            boyut: boyut,
            olcek: olcek);
        await gercekBekle(tester);
        await tester.tap(find.text('aç'));
        await tester.pumpAndSettle();
        expect(sonaUlasildi(), isFalse);
        // Yalnız semantik eylem: parmak yok. Her eylem görünümün ~%80'i.
        var eylem = 0;
        while (!sonaUlasildi()) {
          expect(eylem++, lessThan(2000), reason: 'ekran okuyucu kilitlendi');
          tester.semantics.scrollUp(scrollable: find.semantics.scrollable());
          await tester.pump();
          await tester.pump();
        }
        await tester.pumpAndSettle();
        // Onay da ekran okuyucunun "dokun" eylemiyle verilir.
        final dugme = find.semantics.byPredicate((n) =>
            n.getSemanticsData().flagsCollection.isButton &&
            n.getSemanticsData().flagsCollection.isEnabled == Tristate.isTrue &&
            n.label.contains(l.zorunluOkumaOnaylaKisa));
        tester.semantics.tap(dugme);
        await tester.pumpAndSettle();
        expect(sonuclar.single?.onaylandi, isTrue);
        expect(tester.takeException(), isNull);
        sem.dispose();
      });
    }

    testWidgets(
        'odak düğmeye gelince (showOnScreen) — düğmeden sonraki boşluk '
        'kilitlemez', (tester) async {
      final sem = tester.ensureSemantics();
      await kur(tester,
          evSahibi((l) => ZorunluMetin.belge(l, YasalBelge.acikRiza), []),
          boyut: const Size(320, 568), olcek: 2.0);
      await gercekBekle(tester);
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      final dugme = find.semantics.byPredicate((n) =>
          n.getSemanticsData().flagsCollection.isButton &&
          n.label.contains(l.zorunluOkumaRizaVerKisa));
      // Düğme ağaca girene kadar (önbellek bölgesi) parmakla yaklaş.
      final liste = okuyucuListesi().first;
      for (var i = 0; i < 500 && dugme.evaluate().isEmpty; i++) {
        await tester.drag(liste, const Offset(0, -200));
        await tester.pump();
        await tester.pump();
      }
      expect(dugme, findsOneWidget);
      if (!sonaUlasildi()) {
        tester.semantics.performAction(dugme, SemanticsAction.showOnScreen,
            checkForAction: false);
        await tester.pump();
        await tester.pump();
      }
      expect(sonaUlasildi(), isTrue);
      sem.dispose();
    });
  });

  // ── Kayıt ekranı ────────────────────────────────────────────────────────
  group('kayıt ekranı', () {
    Finder alan(String etiket) =>
        find.ancestor(of: find.text(etiket), matching: find.byType(TextField));

    Future<void> formuDoldur(WidgetTester tester) async {
      for (final (etiket, metin) in [
        (l.kullaniciAdiEtiket, 'deneme_kisi'),
        (l.email, 'deneme@ornek.com'),
        (l.password, 'abcd1234'),
        (l.passwordRepeat, 'abcd1234'),
      ]) {
        await tester.enterText(alan(etiket), metin);
        await tester.pump();
      }
      await tester.pump(const Duration(seconds: 1));
    }

    Finder kayitDugmesi() => find.descendant(
        of: find.byType(ListView), matching: find.text(l.register));

    Future<void> kayitaBas(WidgetTester tester) async {
      await tester.ensureVisible(kayitDugmesi());
      await tester.tap(kayitDugmesi());
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    List<String> istekleriYakala() {
      final istekler = <String>[];
      RegisterScreen.kayitIstegiTesti = ({
        required String email,
        required String displayName,
        required String password,
      }) async =>
          istekler.add(email);
      return istekler;
    }

    /// Sıradaki [n] okuma adımını gerçekten sona kaydırıp onaylar.
    Future<void> oku(WidgetTester tester, int n) async {
      for (var i = 0; i < n; i++) {
        final dugme = find.text(l.yasalAdimOkuOnayla);
        await tester.ensureVisible(dugme);
        await tester.pumpAndSettle();
        await gercekBekle(tester);
        await tester.tap(dugme);
        await okuVeOnayla(tester);
      }
    }

    Finder kare() => find.descendant(
        of: find.byType(YasalOnayKutusu),
        matching: find.byType(AnimatedContainer));

    Future<void> kapat(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 5));
    }

    testWidgets(
        'adımlar: 1 Yatırım Uyarısı, 2 Açık Rıza (oku/onayla), 3 kutu; '
        'Koşullar/Gizlilik/KVKK katlanır bölümde; okunmadan "Kayıt ol" '
        'çalışmaz ve eksik adımı adıyla söyler', (tester) async {
      final istekler = istekleriYakala();
      await kur(tester, const RegisterScreen(), boyut: const Size(390, 2400));
      await formuDoldur(tester);

      // Kullanıcı adı alanı aynen yerinde (kullanıcı kuralı).
      expect(alan(l.kullaniciAdiEtiket), findsOneWidget);
      expect(find.text(l.yasalAdimKayitBaslik(3)), findsOneWidget);
      final y = [
        for (final ad in [
          l.yasalBelgeYatirimUyarisi,
          l.yasalBelgeAcikRiza,
          l.yasalAdimKutuBaslik,
        ])
          tester.getTopLeft(find.text(ad)).dy,
      ];
      expect(y, [...y]..sort(), reason: 'uyarı → Açık Rıza → kutu');
      // Eylem yalnız sıradaki adımda; kutu son adım.
      expect(find.text(l.yasalAdimOkuOnayla), findsOneWidget);
      expect(find.text(l.yasalAdimUyariAciklama), findsOneWidget);
      expect(find.byType(YasalOnayKutusu), findsNothing);
      expect(find.text(l.yasalAdimDigerBelgeler(3)), findsOneWidget);

      await kayitaBas(tester);
      expect(istekler, isEmpty);
      expect(
          find.text(l.zorunluOkumaEksik(
              [l.yasalBelgeYatirimUyarisi, l.yasalBelgeAcikRiza].join(', '))),
          findsWidgets);

      // Uyarı okundu, Açık Rıza okunmadı: kayıt yine gitmez, eksik adıyla.
      // (Önce hata diyaloğu kapansın — adımın üstünü örtüyor.)
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await oku(tester, 1);
      expect(find.text(l.yasalAdimOkunduOnaylandi), findsOneWidget);
      expect(find.text(l.yasalAdimRizaAciklama), findsOneWidget);
      await gercekBekle(tester);
      await kayitaBas(tester);
      expect(istekler, isEmpty, reason: 'açık rıza okunmadan kayıt yok');
      expect(find.text(l.zorunluOkumaEksik(l.yasalBelgeAcikRiza)),
          findsWidgets);
      await kapat(tester);
    });

    testWidgets(
        'Açık Rıza + uyarı sonuna kadar okunup kutu işaretlenince kayıt '
        'gider; kayıt: rıza okundu, Koşullar/Gizlilik/KVKK okutulmadı',
        (tester) async {
      final istekler = istekleriYakala();
      await kur(tester, const RegisterScreen(), boyut: const Size(390, 2400));
      await formuDoldur(tester);
      await oku(tester, 2);
      // Okunan iki adımda "Okundu ve onaylandı" + yeşil onay dairesi.
      expect(find.text(l.yasalAdimOkunduOnaylandi), findsNWidgets(2));
      expect(find.text(l.yasalAdimOkuOnayla), findsNothing);
      // Rızayı vermek kutuyu işaretlemez (paketleme yok).
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      await tester.ensureVisible(kare());
      await tester.tap(kare());
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await gercekBekle(tester); // OTP ekranı da pushGuarded ile açılır
      await kayitaBas(tester);
      await tester.pumpAndSettle();
      expect(istekler, ['deneme@ornek.com']);

      final baglam = tester
          .widget<OtpVerificationScreen>(find.byType(OtpVerificationScreen))
          .kayitOnayi!;
      expect(baglam.yatirimUyarisiOnaylandi, isTrue);
      final ogeler = {
        for (final o in baglam.ogeler()) o['tur'] as String: o,
      };
      expect(ogeler.keys, {
        YasalTur.kayitTekKutu,
        YasalTur.kosullar,
        YasalTur.gizlilik,
        YasalTur.kvkk,
        YasalTur.acikRiza,
        YasalTur.yatirimUyarisi,
      });
      expect(ogeler[YasalTur.kayitTekKutu]!['surum'],
          YasalMetinKatalogu.kutuSurumu);
      final uyari = ogeler[YasalTur.yatirimUyarisi]!;
      expect(uyari['hash'], disclaimerHash,
          reason: 'gösterilen TAM metnin hash\'i');
      expect(uyari['degiskenler'],
          {'belge_acildi': true, 'sonuna_kadar_okundu': true});
      Map<String, dynamic> d(String tur) =>
          ogeler[tur]!['degiskenler'] as Map<String, dynamic>;
      expect(d(YasalTur.acikRiza)['sonuna_kadar_okundu'], isTrue);
      expect(d(YasalTur.acikRiza)['nitelik'], 'acik_riza');
      expect(d(YasalTur.kosullar)['nitelik'], 'kabul');
      for (final b in YasalBelge.kutuylaAlinanlar) {
        expect(d(b.tur)['sonuna_kadar_okundu'], isFalse, reason: b.tur);
        // Bağlantıya dokunulmadı → açılmadı.
        expect(d(b.tur)['belge_acildi'], isFalse, reason: b.tur);
      }
      expect(d(YasalTur.gizlilik)['nitelik'], 'bilgilendirme');
      expect(d(YasalTur.kvkk)['nitelik'], 'bilgilendirme');
      await kapat(tester);
    });

    testWidgets(
        'diğer belgeler bağlantıdır: belge SALT OKUNUR açılır, dönüşte '
        '"Açıldı" izi (onay değil, adım ilerlemez); kayda belge_acildi',
        (tester) async {
      await kur(tester, const RegisterScreen(), boyut: const Size(390, 2400));
      await tester.tap(find.text(l.yasalAdimDigerBelgeler(3)));
      await tester.pumpAndSettle();
      final kvkk = find.byWidgetPredicate(
          (w) => w is SiganMetin && w.adaylar.first == l.yasalBelgeKvkk);
      await tester.ensureVisible(kvkk);
      await gercekBekle(tester);
      await tester.tap(kvkk);
      await tester.pumpAndSettle();
      expect(
          tester.widget<LegalDocScreen>(find.byType(LegalDocScreen)).zorunluOkuma,
          isFalse);
      expect(find.byType(OkumaIpucu), findsNothing);
      expect(etkinOnay(), findsNothing, reason: 'salt okunur: onay yok');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text(l.yasalBelgeAcildi), findsOneWidget);
      // Açmak onay değildir: sıradaki adım hâlâ uyarı.
      expect(find.text(l.yasalAdimOkunduOnaylandi), findsNothing);
      expect(find.text(l.yasalAdimUyariAciklama), findsOneWidget);
      await kapat(tester);
    });

    test('kutu cümlesinde (ve açıklamasında) "açık rıza" geçmez — TR ve EN',
        () {
      for (final ll in <AppLocalizations>[
        AppLocalizationsTr(),
        AppLocalizationsEn()
      ]) {
        for (final metin in [
          YasalMetinKatalogu.tekKutuCumlesi(ll),
          ll.tekOnayAciklama('x'),
          ll.tekOnayGerekli,
        ]) {
          final k = metin.toLowerCase();
          expect(k, isNot(contains('açık rıza')), reason: metin);
          expect(k, isNot(contains('açık rızan')), reason: metin);
          expect(k, isNot(contains('explicit consent')), reason: metin);
        }
      }
    });

    testWidgets('ekrandaki kutu cümlesi katalogla aynı ve rıza içermez',
        (tester) async {
      await kur(tester, const RegisterScreen(), boyut: const Size(390, 2400));
      await adimlariOku(tester, l.yasalAdimOkuOnayla, adet: 2);
      final cumle =
          find.text(YasalMetinKatalogu.tekKutuCumlesi(l), findRichText: true);
      expect(cumle, findsOneWidget);
      final rich = find
          .descendant(of: find.byType(YasalOnayKutusu), matching: cumle)
          .evaluate()
          .single
          .widget;
      final duz = rich is RichText
          ? rich.text.toPlainText()
          : (rich as Text).textSpan!.toPlainText();
      expect(duz.toLowerCase(), isNot(contains('açık rıza')));
      await kapat(tester);
    });

    // Kayıt ekranı her zaman okutur; bağlam başka yoldan (okumasız)
    // kurulursa uyarı ve AÇIK RIZA GİRMEZ — rıza kutunun yan etkisi değil.
    test('okunmamış bağlam: uyarı yok, rıza yok, okundu işareti yok', () {
      const b = KayitOnayBaglami(
        dil: 'tr',
        kutuUlkesi: 'Almanya (AB)',
        belgeDegiskenleri: {},
        kosulBelgesiAcildi: true,
      );
      final ogeler = b.ogeler();
      expect(ogeler.map((o) => o['tur']),
          isNot(contains(YasalTur.yatirimUyarisi)));
      expect(ogeler.map((o) => o['tur']), isNot(contains(YasalTur.acikRiza)));
      for (final o in ogeler) {
        expect((o['degiskenler'] as Map)['sonuna_kadar_okundu'] == true,
            isFalse);
      }
    });
  });

  // ── OTP: gösterilmemiş metne onay yazılmaz (bayraktan bağımsız) ─────────
  test('OTP sonrası disclaimer_acceptances yalnız tam metin onaylandıysa', () {
    // Kaynak bekçisi: koşul kabulKaydet'ten ÖNCE değerlendirilir.
    final src = ekranKaynagiSync('lib/screens/otp_verification_screen.dart');
    final kosul = src.indexOf('kayitOnayi.yatirimUyarisiOnaylandi &&');
    final kayit = src.indexOf('DisclaimerService.instance.kabulKaydet(');
    expect(kosul, isNonNegative);
    expect(kayit, greaterThan(kosul));
    expect(src.substring(kosul, kayit), isNot(contains(';')),
        reason: 'aynı ifadede kısa devre: koşul tutmazsa kayıt çağrılmaz');
  });

  // ── Yeniden onay kapısı ─────────────────────────────────────────────────
  group('yeniden onay kapısı', () {
    late List<Map<String, dynamic>> cagrilar;
    late List<String> uyariKayitlari;

    setUp(() {
      cagrilar = [];
      uyariKayitlari = [];
      YasalOnayService.rpcTesti = (p) async => cagrilar.add(p);
      YasalOnayKapisiScreen.uyariKaydiTesti =
          ({required String userId, required String locale}) async {
        uyariKayitlari.add(userId);
        return true;
      };
    });

    testWidgets(
        'ilk kez + uyarı: 3 adım (uyarı → Açık Rıza → kutu); okunanlar '
        'gerçekten sona kaydırılır; düğme son adımı bekler; yazım okuma '
        'işaretini taşır', (tester) async {
      var tamam = 0;
      await kur(
        tester,
        YasalOnayKapisiScreen(
          userId: 'u1',
          durum: YasalOnayService.eksikleriHesapla(const []),
          yatirimUyarisiDahil: true,
          onTamam: () => tamam++,
        ),
        boyut: const Size(390, 2400),
      );
      SandikAsyncButton dugme() =>
          tester.widget<SandikAsyncButton>(find.byType(SandikAsyncButton));
      expect(dugme().onPressed, isNull);
      expect(find.text(l.yasalAdimKapiBaslik(3)), findsOneWidget);
      expect(find.text(l.yasalAdimOkuOnayla), findsOneWidget);
      expect(find.text(l.yasalAdimSayac(0, 3)), findsOneWidget);
      // Uyarı bir adım; adımda tam metin yok (okuyucuda).
      expect(find.text(disclaimerText), findsNothing);
      expect(find.byType(YasalOnayKutusu), findsNothing);

      for (var i = 0; i < 2; i++) {
        final d = find.text(l.yasalAdimOkuOnayla);
        await tester.ensureVisible(d);
        await gercekBekle(tester);
        await tester.tap(d);
        await okuVeOnayla(tester);
      }
      // Okumalar bitti, kutu sıradaki: düğme hâlâ kapalı.
      expect(dugme().onPressed, isNull);
      expect(find.text(l.yasalAdimSayac(2, 3)), findsOneWidget);
      final kare = find.descendant(
          of: find.byType(YasalOnayKutusu),
          matching: find.byType(AnimatedContainer));
      await tester.ensureVisible(kare);
      await tester.tap(kare);
      await tester.pump();
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(dugme().onPressed, isNotNull);
      await tester.ensureVisible(find.byType(SandikAsyncButton));
      await tester.tap(find.byType(SandikAsyncButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(tamam, 1);
      expect(uyariKayitlari, ['u1']);
      final ogeler = [
        for (final o in cagrilar.single['p_ogeler'] as List)
          o as Map<String, dynamic>,
      ];
      final okunan = {
        for (final o in ogeler)
          if ((o['degiskenler'] as Map)['sonuna_kadar_okundu'] == true)
            o['tur'],
      };
      expect(okunan, {YasalTur.acikRiza, YasalTur.yatirimUyarisi});
      expect({for (final o in ogeler) o['tur']}, {
        YasalTur.kayitTekKutu,
        for (final b in YasalBelge.values) b.tur,
        YasalTur.yatirimUyarisi,
      });
    });
  });

  // ── Yatırım uyarısı ekranı ──────────────────────────────────────────────
  testWidgets('yatırım uyarısı ekranı: metnin sonuna gelmeden kutu kilitli',
      (tester) async {
    await kur(
      tester,
      DisclaimerAcceptanceScreen(userId: 'u1', onAccepted: () {}),
      boyut: const Size(320, 568),
      olcek: 2.0,
    );
    expect(find.byType(OkumaIpucu), findsOneWidget);
    final kutu = find.text(l.disclaimerAcceptRow);
    await tester.tap(kutu, warnIfMissed: false);
    await tester.pump();
    // Kilitliyken dokunuş işaretlemez; (kutu ekranda değilse de değişmez).
    expect(find.byIcon(Icons.check_rounded), findsNothing);
    await sonunaKadarKaydir(
        tester,
        find.descendant(
            of: find.byType(DisclaimerAcceptanceScreen),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(kutu);
    await tester.tap(kutu);
    await tester.pump();
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ── Zirve rızası ────────────────────────────────────────────────────────
  testWidgets(
      'Zirve rızası: kart TAM metin; sona gelmeden "Katılıyorum" '
      'kapalı, gelince açık', (tester) async {
    var katildi = 0;
    await kur(
      tester,
      Scaffold(
        body: ZirveRizaOkumaGovdesi(
          hp: 12,
          onKatil: () async => katildi++,
          onSimdiDegil: () {},
        ),
      ),
      boyut: const Size(320, 568),
    );
    SandikAsyncButton dugme() => tester.widget<SandikAsyncButton>(
        find.byType(SandikAsyncButton, skipOffstage: false));
    expect(dugme().onPressed, isNull);
    expect(find.byType(OkumaIpucu), findsOneWidget);
    await sonunaKadarKaydir(
        tester,
        find.descendant(
            of: find.byType(ZirveRizaOkumaGovdesi),
            matching: find.byType(Scrollable)));
    await tester.pumpAndSettle();
    expect(dugme().onPressed, isNotNull);
    // Kart metni değişmedi: katalog gövdesi kartın sabitlerinden.
    expect(YasalMetinKatalogu.zirveRiza().govde,
        contains(ZirveRizaKarti.maddeler.first.$2));
    await tester.tap(find.text(ZirveRizaKarti.katilEtiketi));
    await tester.pump();
    expect(katildi, 1);
  });

  // ── Taşma: 320/360 dp × yazı 1,0/1,6/2,0 × TR/EN ───────────────────────
  group('taşma yok', () {
    for (final dil in const [Locale('tr', 'TR'), Locale('en')]) {
      for (final boyut in const [Size(320, 568), Size(360, 640)]) {
        for (final olcek in const [1.0, 1.6, 2.0]) {
          final ad =
              '${dil.languageCode} ${boyut.width.toInt()} dp, yazı x$olcek';

          testWidgets('kayıt ekranı — $ad', (tester) async {
            await kur(tester, const RegisterScreen(),
                boyut: boyut, olcek: olcek, dil: dil);
            await tester.pump(const Duration(seconds: 1));
            final ll = dil.languageCode == 'en'
                ? AppLocalizationsEn()
                : AppLocalizationsTr();
            // Kutu son adım: okumalar bitince görünür.
            await adimlariOku(tester, ll.yasalAdimOkuOnayla, adet: 2);
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
                find.text(YasalMetinKatalogu.tekKutuCumlesi(ll),
                    findRichText: true),
                200,
                scrollable: find.byType(Scrollable).first);
            await tester.pump();
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await tester.pump(const Duration(seconds: 5));
          });

          testWidgets('okuyucu (açık rıza, en uzun düğme) — $ad',
              (tester) async {
            await kur(tester,
                evSahibi((l) => ZorunluMetin.belge(l, YasalBelge.acikRiza), []),
                boyut: boyut, olcek: olcek, dil: dil);
            await gercekBekle(tester);
            await tester.tap(find.text('aç'));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
            await sonunaKadarKaydir(tester, okuyucuListesi());
            await tester.pumpAndSettle();
            expect(etkinOnay(), findsOneWidget);
            expect(tester.takeException(), isNull);
          });

          testWidgets('kapı (uyarı + kutu) — $ad', (tester) async {
            await kur(
              tester,
              YasalOnayKapisiScreen(
                userId: 'u1',
                durum: YasalOnayService.eksikleriHesapla(const []),
                yatirimUyarisiDahil: true,
                onTamam: () {},
              ),
              boyut: boyut,
              olcek: olcek,
              dil: dil,
            );
            final ll = dil.languageCode == 'en'
                ? AppLocalizationsEn()
                : AppLocalizationsTr();
            await adimlariOku(tester, ll.yasalAdimOkuOnayla, adet: 2);
            expect(tester.takeException(), isNull);
            await tester.scrollUntilVisible(
                find.text(YasalMetinKatalogu.tekKutuCumlesi(ll),
                    findRichText: true),
                200,
                scrollable: find.byType(Scrollable).first);
            await tester.pump();
            expect(tester.takeException(), isNull);
          });

          testWidgets('yatırım uyarısı ekranı — $ad', (tester) async {
            await kur(
              tester,
              DisclaimerAcceptanceScreen(userId: 'u1', onAccepted: () {}),
              boyut: boyut,
              olcek: olcek,
              dil: dil,
            );
            await sonunaKadarKaydir(
                tester,
                find.descendant(
                    of: find.byType(DisclaimerAcceptanceScreen),
                    matching: find.byType(Scrollable)));
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          });
        }
      }
    }
  });
}

extension on BuildContext {
  /// Testte delegate her zaman var; yine de `context.l10n` ile aynı geri
  /// dönüş.
  AppLocalizations get l10nOrTr =>
      Localizations.of<AppLocalizations>(this, AppLocalizations) ??
      AppLocalizationsTr();
}
