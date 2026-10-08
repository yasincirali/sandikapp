import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/screens/aylik_rapor_screen.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// Aylık rapor (S18-B): özet cümlesi notu çıkan varlıkları sayar; tutulup
/// notu çıkmayanlar sonda adlarıyla anılır (titiz okur "5 varlığım var,
/// rapor 3 diyor" diye takılmasın).
void main() {
  final ay = DateTime.utc(2026, 9, 1);

  AnalizOzeti not(String t, String rozet) => AnalizOzeti(
      ticker: t, donem: ay, baslik: '$t başlığı', rozet: rozet, maddeSayisi: 2);

  testWidgets('notu çıkmayan tutulan varlıklar adlarıyla yazılır',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        tutulanNotAnahtarlariProvider.overrideWithValue(
            ['TEFAS:TTE', 'TEFAS:AFT', 'THYAO.IS', 'KRIPTO:BTC', 'TEFAS:AH5']),
        notOzetleriProvider.overrideWith((ref, a) async => {
              'TEFAS:TTE': not('TEFAS:TTE', 'buyuk_giris'),
              'THYAO.IS': not('THYAO.IS', 'sakin'),
              'KRIPTO:BTC': not('KRIPTO:BTC', 'sakin'),
            }),
      ],
      child: MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AylikRaporScreen(donem: ay),
      ),
    ));
    await tester.pumpAndSettle();
    final l10n =
        AppLocalizations.of(tester.element(find.byType(AylikRaporScreen)))!;
    expect(find.text(l10n.anzAylikOzetVar('3', '1')), findsOneWidget);
    expect(find.text(l10n.anzAylikEksik('AFT, AH5')), findsOneWidget);
  });
}
