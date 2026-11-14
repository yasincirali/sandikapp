import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/comparison_screen.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Karşılaştır Premium turu (Ar-Ge 14 Kas 2026 22:03).
///
/// Seriler `ComparisonScreen.testSeriKaynagi` ile verilir: sayılar testin
/// kendi sabitleridir, ağ yok.

/// Dönem getirisi [pct] olan iki noktalı normalize seri.
NormalizedSeries _seri(double pct) =>
    normalizeSeries({1000: 100, 2000: 100 + pct})!;

Widget _ekran({required int sinir, Widget child = const ComparisonScreen()}) =>
    ProviderScope(
      overrides: [
        karsilastirmaSeriSiniriProvider.overrideWithValue(sinir),
      ],
      child: MaterialApp(home: child),
    );

/// Uzun ekran: çip satırı ListView'in tembel kurulumunda görünür kalsın.
void _uzunEkran(WidgetTester tester) {
  tester.view.physicalSize = const Size(430 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
}

Future<void> _ekle(WidgetTester tester, SymbolHit hit) async {
  final state = tester.state(find.byType(ComparisonScreen));
  // ignore: avoid_dynamic_calls
  await (state as dynamic).addForTest(hit);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

/// `SandikTappable`'ın kendi `Semantics` etiketi (çocuk metinle birleşmeden).
Finder _etiket(String label) => find.byWidgetPredicate(
    (w) => w is Semantics && w.properties.label == label);

const _thy = SymbolHit(ticker: 'THYAO.IS', name: 'THY', source: 'BIST');
const _asel = SymbolHit(ticker: 'ASELS.IS', name: 'Aselsan', source: 'BIST');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  final getiri = <String, double>{};
  setUp(() {
    getiri
      ..clear()
      ..addAll({
        'THYAO.IS': 4,
        'ASELS.IS': -2,
        'XU100.IS': 3,
        'USDTRY=X': 1,
        'ALTIN_GRAM': 12.4,
      });
    ComparisonScreen.testSeriKaynagi = (t, _) async {
      final p = getiri[t];
      return p == null ? null : _seri(p);
    };
  });
  tearDown(() => ComparisonScreen.testSeriKaynagi = null);

  group('kilitli çip (fikir 1)', () {
    testWidgets('ücretsiz sınırda dolu: kilit ikonu, normal ton, Premium etiketi',
        (tester) async {
      _uzunEkran(tester);
      await tester.pumpWidget(_ekran(sinir: 2));
      await tester.pump();
      await _ekle(tester, _thy);
      await _ekle(tester, _asel);

      expect(_etiket('Gram altın kıyasa ekle, Premium'), findsOneWidget);
      expect(_etiket('Gram altın kıyasa ekle'), findsNothing);
      // Çip satırındaki beş çipin hepsi kilitli; ekle düğmesininki ayrı.
      expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(6));

      final metin = tester.widget<Text>(find.text('Gram altın'));
      expect(metin.style?.color, SandikPalette.dark.text90,
          reason: 'kilitli çip soluk (text36) yazmamalı');
    });

    testWidgets('Premium sınırında dolu: devre dışı kalır, kilit yok',
        (tester) async {
      _uzunEkran(tester);
      await tester.pumpWidget(_ekran(sinir: kKarsilastirmaEnFazla));
      await tester.pump();
      for (final h in const [
        _thy,
        _asel,
        SymbolHit(ticker: 'XU100.IS', name: 'BIST 100', source: 'Endeks'),
        SymbolHit(ticker: 'USDTRY=X', name: 'Dolar', source: 'Döviz'),
        SymbolHit(ticker: 'AKBNK.IS', name: 'Akbank', source: 'BIST'),
      ]) {
        await _ekle(tester, h);
      }
      expect(_etiket('Gram altın kıyasa ekle, Premium'), findsNothing);
      final metin = tester.widget<Text>(find.text('Gram altın'));
      expect(metin.style?.color, SandikPalette.dark.text36);
    });
  });
}
