import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/temettu_tahmini_provider.dart';
import 'package:portfoy_takip/screens/temettu_tahmini_screen.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

import 'helpers/kaynak.dart';
import 'helpers/yazi_olcegi.dart';

/// Temettü tahmini: aya dokun → süz, çubuklar ilk açılışta yükselir
/// (2026-11-12).
TahminSatiri _satir(String ad, double brut, List<int> aylar) => TahminSatiri(
      ad: ad,
      sembol: '$ad.IS',
      lot: 10,
      brutPay: brut / 10,
      brutTry: brut,
      netTry: brut * 0.85,
      aylar: aylar,
    );

final _tahmin = TemettuTahmini(
  satirlar: [
    _satir('Tüpraş', 1240, [6]),
    _satir('Ford', 500, [3]),
  ],
  aylik: [0, 0, 500, 0, 0, 1240, 0, 0, 0, 0, 0, 0],
);

Future<void> _ac(WidgetTester tester, {bool hareketiAzalt = false}) async {
  tester.view.physicalSize = const Size(390, 900) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      premiumKilitliProvider.overrideWithValue(false),
      temettuTahminiProvider.overrideWith((ref) async => _tahmin),
    ],
    child: MaterialApp(
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
          brightness: Brightness.dark, extensions: const [SandikPalette.dark]),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: hareketiAzalt),
        child: child!,
      ),
      home: const TemettuTahminiScreen(),
    ),
  ));
  // Sağlayıcı çözülsün, içerik geçişi başlasın — çubuk animasyonu biter
  // bitmez değil, ölçümü testler kendisi yapar.
  await tester.pump();
  await tester.pump();
}

/// Ay sütunu — etiketi "Ay, ₺tutar" (başlıktaki "Ay, tahmini" ile karışmaz).
Finder _ay(String ad) => find.bySemanticsLabel(RegExp('^$ad, ₺'));

double _cubukBoyu(WidgetTester tester, String ad) => tester
    .getSize(
        find.descendant(of: _ay(ad), matching: find.byType(Container)).first)
    .height;

void main() {
  testWidgets('aya dokununca başlık o ayı söyler, liste süzülür; '
      'tekrar dokununca tümü', (tester) async {
    final hapticler = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform, (c) async {
      if (c.method == 'HapticFeedback.vibrate') hapticler.add('${c.arguments}');
      return null;
    });
    await _ac(tester);
    await tester.pumpAndSettle();
    expect(find.text('Tüpraş'), findsOneWidget);
    expect(find.text('Ford'), findsOneWidget);

    await tester.tap(_ay('Haziran'));
    await tester.pumpAndSettle();
    expect(find.text('Haziran, tahmini'), findsOneWidget);
    expect(find.text(fmtTRY(1240)), findsWidgets);
    expect(find.text('Tüpraş'), findsOneWidget);
    expect(find.text('Ford'), findsNothing);
    expect(hapticler, ['HapticFeedbackType.selectionClick']);

    await tester.tap(_ay('Haziran'));
    await tester.pumpAndSettle();
    expect(find.text('Ford'), findsOneWidget);
    expect(find.text('Haziran, tahmini'), findsNothing);
    expect(hapticler, hasLength(2));
  });

  testWidgets('Semantics: ay etiketi, seçili durumu ve dokunma eylemi',
      (tester) async {
    final h = tester.ensureSemantics();
    await _ac(tester);
    await tester.pumpAndSettle();
    final etiket = 'Haziran, ${fmtTRY(1240)}';
    expect(
        tester.getSemantics(find.bySemanticsLabel(etiket)),
        matchesSemantics(
            label: etiket,
            isButton: true,
            hasSelectedState: true,
            isSelected: false,
            hasTapAction: true));
    await tester.tap(find.bySemanticsLabel(etiket));
    await tester.pumpAndSettle();
    expect(
        tester.getSemantics(find.bySemanticsLabel(etiket)),
        matchesSemantics(
            label: etiket,
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true));
    h.dispose();
  });

  testWidgets('her ay sütunu en az 44 pt yüksek dokunma alanı', (tester) async {
    await _ac(tester);
    await tester.pumpAndSettle();
    for (final ay in ['Ocak', 'Haziran', 'Aralık']) {
      final boyut = tester.getSize(_ay(ay));
      expect(boyut.height, greaterThanOrEqualTo(SandikTouch.min),
          reason: '$ay sütunu');
    }
  });

  testWidgets('çubuklar ilk açılışta tabandan yükselir, süzmede yeniden '
      'oynamaz', (tester) async {
    await _ac(tester);
    while (_ay('Haziran').evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final ilk = _cubukBoyu(tester, 'Haziran');
    await tester.pump(SandikMotion.flow ~/ 4);
    final ara = _cubukBoyu(tester, 'Haziran');
    await tester.pumpAndSettle();
    final son = _cubukBoyu(tester, 'Haziran');
    expect(ilk, lessThan(ara), reason: 'tabandan başlar');
    expect(ara, lessThan(son));
    expect(son, closeTo(72, 0.01), reason: 'en büyük ay tam boy');

    // Süzme: bir sonraki karede çubuklar zaten tam boy.
    await tester.tap(_ay('Mart'));
    await tester.pump();
    expect(_cubukBoyu(tester, 'Haziran'), closeTo(72, 0.01));
  });

  testWidgets('hareketi azalt: çubuk ilk karede tam boy (animasyon yok)',
      (tester) async {
    await _ac(tester, hareketiAzalt: true);
    await tester.pump();
    while (_ay('Haziran').evaluate().isEmpty) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(_cubukBoyu(tester, 'Haziran'), closeTo(72, 0.01),
        reason: 'ilk karede tam boy');
  });

  test('süzme yeniden yükseltme oynatmaz; hareket token üzerinden', () {
    final src = ekranKaynagiSync('lib/screens/temettu_tahmini_screen.dart');
    expect(src.contains('SandikMotion.flowOf(context)'), isTrue);
    expect(src.contains('FontWeight.w700'), isFalse);
  });

  yaziOlcegiEkseni(() {
    testWidgets('büyük yazıda taşma yok', (tester) async {
      yaziOlceginiUygula(tester);
      await _ac(tester);
      await tester.pumpAndSettle();
      await tester.tap(_ay('Haziran'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}
