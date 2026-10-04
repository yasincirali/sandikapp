import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/karsilama_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/seviye_anketi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sadeleştirme (2026-10-04): girişten önce tanıtım ve seviye anketi.
///
/// Kurallar: tanıtımdan "Giriş yap"/"Atla" bir daha gösterilmemesini yazar
/// (cihaz tercihi); anket üç cevaptan sonra seviyeyi AYNI tercihe yazar.
final _tr = AppLocalizationsTr();

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  Widget host(Widget child, ProviderContainer c) => UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: Scaffold(body: child),
        ),
      );

  group('KarsilamaScreen', () {
    testWidgets('dört sayfa gezilir, son sayfada "Hesap oluştur" çıkar',
        (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(const KarsilamaScreen(), c));
      expect(find.text(_tr.welcomeP1Title), findsOneWidget);
      expect(find.text(_tr.welcomeNext), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text(_tr.welcomeNext));
        await tester.pumpAndSettle();
      }
      expect(find.text(_tr.welcomeP4Title), findsOneWidget);
      expect(find.text(_tr.welcomeCreateAccount), findsOneWidget);
    });

    testWidgets('"Hesabım var" tanıtımı görüldü sayar', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(const KarsilamaScreen(), c));
      expect(c.read(karsilamaGorulduProvider), isFalse);
      await tester.tap(find.text(_tr.welcomeHaveAccount));
      await tester.pump();
      expect(c.read(karsilamaGorulduProvider), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('karsilama_goruldu'), isTrue);
    });

    testWidgets('dar ekranda taşma yok', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(const KarsilamaScreen(), c));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('SeviyeAnketi', () {
    testWidgets('üç cevap seviyeyi yazar ve sonucu gösterir', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(const SeviyeAnketi(), c));
      expect(find.text(_tr.levelSurveyQ1), findsOneWidget);
      await tester.tap(find.text(_tr.levelSurveyQ1A0));
      await tester.pump();
      expect(find.text(_tr.levelSurveyQ2), findsOneWidget);
      await tester.tap(find.text(_tr.levelSurveyQ2A0));
      await tester.pump();
      await tester.tap(find.text(_tr.levelSurveyQ3A0));
      await tester.pump();
      expect(c.read(yatirimciSeviyesiProvider), YatirimciSeviyesi.baslangic);
      expect(
          find.text(_tr.levelSurveyResult(_tr.levelBeginner)), findsOneWidget);
    });

    testWidgets('"Geri" önceki soruya döner, seviye yazılmaz', (tester) async {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await tester.pumpWidget(host(const SeviyeAnketi(), c));
      await tester.tap(find.text(_tr.levelSurveyQ1A2));
      await tester.pump();
      await tester.tap(find.text(_tr.levelSurveyBack));
      await tester.pump();
      expect(find.text(_tr.levelSurveyQ1), findsOneWidget);
      expect(c.read(yatirimciSeviyesiProvider), YatirimciSeviyesi.varsayilan);
    });
  });
}
