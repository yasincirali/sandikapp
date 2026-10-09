import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/providers/hafta_ozeti_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show initPreferencesCache;
import 'package:portfoy_takip/screens/hafta_ozeti_screen.dart';
import 'package:portfoy_takip/services/milestone_service.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/milestone_sheet.dart';
import 'package:portfoy_takip/widgets/sandik_bos_durum.dart';
import 'package:portfoy_takip/widgets/sandik_cizimi.dart';
import 'package:portfoy_takip/widgets/sandik_error_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Göz alıcılık paketi C (2026-10-09), bayrak `goz_alici`: sandık çizimi
/// ortak bileşen, boş durumlarda kapalı sandık, kilometre taşında açılan
/// sandık; hata artık "boş" gibi görünmez (bayraksız hata düzeltmesi).
Widget _kabuk(Widget w) => MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      home: Scaffold(body: Center(child: w)),
    );

/// Sandığın çubukları: yüksekliği 0'dan büyük olanların sayısı.
int _yukselenCubuk(WidgetTester t) => t
    .widgetList<Container>(find.descendant(
        of: find.byType(SandikCizimi), matching: find.byType(Container)))
    .where((c) => c.constraints?.maxWidth == 13 && c.constraints!.maxHeight > 0)
    .length;

void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  group('SandikCizimi', () {
    testWidgets('açık: kapak açılır, dört çubuk yükselir', (t) async {
      await t.pumpWidget(_kabuk(const SandikCizimi()));
      await t.pumpAndSettle();
      expect(_yukselenCubuk(t), 4);
    });

    testWidgets('kapalı: çubuk yok, dokunulmaz', (t) async {
      await t.pumpWidget(_kabuk(const SandikCizimi(
          zemin: SandikZemini.yuzey, acik: false, dokunulabilir: false)));
      await t.pumpAndSettle();
      expect(_yukselenCubuk(t), 0);
      expect(
          find.descendant(
              of: find.byType(SandikCizimi),
              matching: find.byType(GestureDetector)),
          findsNothing);
    });

    testWidgets('ölçek boyutu küçültür, ekran okuyucuya görünmez', (t) async {
      await t.pumpWidget(_kabuk(const SandikCizimi(olcek: 0.5)));
      expect(t.getSize(find.byType(SandikCizimi)), const Size(65, 70));
      expect(
          find.descendant(
              of: find.byType(SandikCizimi),
              matching: find.byType(ExcludeSemantics)),
          findsWidgets);
    });

    testWidgets('hareketi azalt: açık hâl anında çizilir', (t) async {
      await t.pumpWidget(MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: _kabuk(const SandikCizimi())));
      await t.pump();
      expect(_yukselenCubuk(t), 4);
    });
  });

  group('SandikBosIkonu', () {
    testWidgets('kapalıyken eski ikon', (t) async {
      await t.pumpWidget(_kabuk(
          const SandikBosIkonu(ikon: Icons.inbox_rounded, boyut: 64)));
      expect(find.byIcon(Icons.inbox_rounded), findsOneWidget);
      expect(find.byType(SandikCizimi), findsNothing);
    });

    testWidgets('açıkken kapalı sandık', (t) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      await t.pumpWidget(_kabuk(
          const SandikBosIkonu(ikon: Icons.inbox_rounded, boyut: 64)));
      expect(find.byIcon(Icons.inbox_rounded), findsNothing);
      expect(find.byType(SandikCizimi), findsOneWidget);
    });
  });

  testWidgets('SandikBosDurum: sandık, metin, alt satır, eylem', (t) async {
    await t.pumpWidget(_kabuk(SandikBosDurum(
      metin: 'Henüz not yok',
      alt: 'Hafta sonu gelir',
      eylem: TextButton(onPressed: () {}, child: const Text('Ekle')),
    )));
    expect(find.byType(SandikCizimi), findsOneWidget);
    expect(find.text('Henüz not yok'), findsOneWidget);
    expect(find.text('Hafta sonu gelir'), findsOneWidget);
    expect(find.text('Ekle'), findsOneWidget);
  });

  group('kilometre taşı', () {
    const m = Milestone(
        kind: 'portfolio_value',
        value: '100000',
        title: '₺100.000',
        body: 'Sandığın altı haneye ulaştı.',
        rank: 100000);

    testWidgets('kapalıyken eski rozet, sandık yok', (t) async {
      await t.pumpWidget(_kabuk(const MilestoneSheet(milestone: m)));
      // Rozetin gecikmeli titreşimi (sayfa oturduktan sonra) beklenir.
      await t.pump(SandikMotion.surface);
      await t.pumpAndSettle();
      expect(find.byType(SandikCizimi), findsNothing);
      expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    });

    testWidgets('açıkken sandık açılır', (t) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      await t.pumpWidget(_kabuk(const MilestoneSheet(milestone: m)));
      await t.pumpAndSettle();
      expect(find.byType(SandikCizimi), findsOneWidget);
      expect(_yukselenCubuk(t), 4);
      expect(find.text('₺100.000'), findsOneWidget);
    });
  });

  testWidgets('Haftanın özeti: hata boş gibi görünmez, yeniden dene var',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
    await t.pumpWidget(ProviderScope(
      overrides: [
        haftaOzetiProvider.overrideWith((ref) async => throw Exception('x')),
        notOzetleriProvider.overrideWith((ref, a) async => const {}),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: const HaftaOzetiScreen(),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byType(SandikErrorView), findsOneWidget);
  });
}
