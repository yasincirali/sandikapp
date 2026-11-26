// Ar-Ge 26 Kas 1203 (UI/UX turu 21): ekstre içe aktarmanın Premium kapıları.
// Kilit satırı ve paywall kartı widget testiyle; ekstre ekranı ağ, rıza ve
// Premium durumu istediği için akış kodda kaynak taramasıyla kilitlenir.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/screens/paywall_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';

import 'helpers/kaynak.dart';

Widget _uygulama(Widget home) => ProviderScope(
      overrides: [denemeHakkiGunuProvider.overrideWith((ref) async => null)],
      child: MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.dark]),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: home),
      ),
    );

void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  group('#1 kilit satırı satın alma dönüşü', () {
    Future<int> dokunVeKapat(WidgetTester t, bool? sonuc) async {
      RemoteConfigService.testAcik = {'paywall_enabled'};
      var cagri = 0;
      await t.pumpWidget(_uygulama(KilitSatiri(
        metin: "Yapay zekâyla eşleme Premium'da",
        kaynak: 'ekstre_ai',
        ozellik: 'ekstre_ai',
        onAcildi: () => cagri++,
      )));
      await t.pumpAndSettle();
      await t.tap(find.byType(KilitSatiri));
      await t.pumpAndSettle();
      expect(find.byType(PaywallScreen), findsOneWidget);
      t.state<NavigatorState>(find.byType(Navigator).first).pop(sonuc);
      await t.pumpAndSettle();
      return cagri;
    }

    testWidgets('satın alınca (true) onAcildi bir kez çağrılır', (t) async {
      expect(await dokunVeKapat(t, true), 1);
    });

    testWidgets('vazgeçince (null/false) çağrılmaz', (t) async {
      expect(await dokunVeKapat(t, null), 0);
      expect(await dokunVeKapat(t, false), 0);
    });
  });

  group('#3 ekran görüntüsünden açılan paywall kendi cümlesini söyler', () {
    Future<void> ac(WidgetTester t, String kaynak) async {
      t.view.physicalSize = const Size(1170, 2532);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        child: MaterialApp(
          theme: ThemeData(extensions: const [SandikPalette.dark]),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PaywallScreen(source: kaynak),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('ekran_goruntusu: görüntü cümlesi, yapay zekâ cümlesi yok',
        (t) async {
      await ac(t, 'ekran_goruntusu');
      expect(
          find.text(
              'Portföy ekranının görüntüsünden maliyetleri topluca doldur.'),
          findsOneWidget);
      expect(find.text('Premium: ekran görüntüsünden toplu maliyet'),
          findsOneWidget);
      expect(find.text('Ekstreni yükle, satırları yapay zekâ eşlesin.'),
          findsNothing);
    });

    testWidgets('ekstre_ai: eski yapay zekâ cümlesi kalır', (t) async {
      await ac(t, 'ekstre_ai');
      expect(find.text('Ekstreni yükle, satırları yapay zekâ eşlesin.'),
          findsOneWidget);
      expect(find.text('Premium: yapay zekâyla eşleme'), findsOneWidget);
    });

    test('kart eşlemesi değişmedi: iki kaynak da ekstre kartı', () {
      expect(kaynaktanKart('ekran_goruntusu'), PaywallKarti.ekstre);
      expect(kaynaktanKart('ekstre_ai'), PaywallKarti.ekstre);
    });
  });

  group('ekstre ekranı (kaynak taraması)', () {
    final ekstre = ekranKaynagiSync('lib/screens/csv_import_screen.dart');

    test('#1 #6 kilit satırı ozellik ve onAi geçirir', () {
      final i = ekstre.indexOf('KilitSatiri(');
      final satir = ekstre.substring(i, ekstre.indexOf(')', i) + 1);
      expect(satir, contains("kaynak: 'ekstre_ai'"));
      expect(satir, contains("ozellik: 'ekstre_ai'"));
      expect(satir, contains('onAcildi: onAi'));
      // Satın alma dönüşü ekran kapandıktan sonra gelebilir.
      expect(ekstre, contains('if (e == null || !mounted) return;'));
    });

    test('#2 rıza hatası rıza sayfasını bir kez açar, sonsuz döngü yok', () {
      final i = ekstre.indexOf('} else if (h.riza) {');
      final dal = ekstre.substring(i, ekstre.indexOf('} else {', i + 30) + 200);
      expect(dal, contains('_aiRizasi = false'));
      expect(dal, contains('if (!yenidenDeneme)'));
      expect(dal, contains('_aiIleEsle(yenidenDeneme: true)'));
      expect(dal, contains('l.importAiRizaGerekli'));
    });

    test('#4 yapay zekâ da bulamadı: mevcut yollar cümlede', () {
      final i = ekstre.indexOf('l.importAiNoMatch,');
      expect(i, greaterThan(0));
      final blok = ekstre.substring(i, i + 300);
      expect(blok, contains('if (e.ana != null) l.importAiNoMatchDuzelt'));
      expect(blok, contains('ekranGoruntusuMaliyet'));
      expect(blok, contains('l.importAiNoMatchGorsel'));
    });

    test('#5 rıza sayfası: başlık w600, iki düğme 44 pt, metin tam', () {
      final i = ekstre.indexOf('class _AiRizaSayfasi');
      final sayfa = ekstre.substring(i);
      expect(sayfa, isNot(contains('FontWeight.w700')));
      expect(sayfa, contains('FontWeight.w600'));
      expect(RegExp(r'minimumSize: SandikTouch\.minSize').allMatches(sayfa).length,
          2);
      // Rıza metni kısaltılmadan, tek parça ekranda.
      expect(sayfa, contains('Text(l.importAiRizaMetin,'));
      expect(sayfa, isNot(contains('maxLines')));
    });
  });
}
