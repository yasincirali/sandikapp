import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/raporlar_provider.dart';
import 'package:portfoy_takip/widgets/raporlar_kapisi.dart';

import 'helpers/kaynak.dart';

/// Performans › 1A'daki aylık rapor satırı (Ar-Ge 2 Kas 12:45 #2, müşteri
/// raporu 13:15 YAP). Kilitlenen: rapor yoksa satır yok; kilitliyken kilit
/// simgesi; yalnız 1A'da; dokunma alanı ≥44 pt; yazı 3,1× taşmaz.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Future<void> pump(WidgetTester tester,
      {DateTime? donem, bool kilitli = false, double olcek = 1}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        aylikRaporDonemiProvider.overrideWithValue(donem),
        premiumKilitliProvider.overrideWithValue(kilitli),
      ],
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
          child: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(16),
              child: AylikRaporSatiri(),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('rapor yoksa satır çizilmez', (tester) async {
    await pump(tester);
    expect(find.byIcon(Icons.summarize_rounded), findsNothing);
  });

  testWidgets('rapor varsa ay adıyla satır, açıkken ok', (tester) async {
    await pump(tester, donem: DateTime(2026, 10));
    expect(find.byIcon(Icons.summarize_rounded), findsOneWidget);
    expect(find.textContaining('Ekim 2026'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right_rounded), findsOneWidget);
    final kutu = tester.getSize(find
        .ancestor(
            of: find.byIcon(Icons.summarize_rounded),
            matching: find.byType(GestureDetector))
        .first);
    expect(kutu.height, greaterThanOrEqualTo(44));
  });

  testWidgets('kilitliyken kilit simgesi', (tester) async {
    await pump(tester, donem: DateTime(2026, 10), kilitli: true);
    expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
  });

  testWidgets('Dynamic Type 3,1×: taşma yok', (tester) async {
    await pump(tester, donem: DateTime(2026, 10), olcek: 3.1);
    expect(tester.takeException(), isNull);
  });

  test('Performans\'ta yalnız 1A seçiliyken, iki akışta da', () {
    final k = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
    expect('const AylikRaporSatiri()'.allMatches(k).length, 2);
    final i = k.indexOf('const AylikRaporSatiri()');
    expect(k.substring(i - 200, i), contains('SummaryPeriod.birAy'));
  });
}
