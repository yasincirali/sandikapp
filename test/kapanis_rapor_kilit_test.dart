import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/kapanis_ozeti.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/kapanis_ozeti_sheet.dart';

/// Kapanış özetindeki rapor bağlantısı (yasin 2026-11-13): ücretsizde
/// "Bu satışın yıllık raporu Premium'da" der ve dokununca DOĞRUDAN paywall
/// açar (`kapanis_rapor`); Premium'da yıllık rapora gider. Kapı provider'dan.
class _Gozcu extends NavigatorObserver {
  final adlar = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      adlar.add(route.settings.name);
}

Future<_Gozcu> _ac(WidgetTester tester, {required bool kilitli}) async {
  final gozcu = _Gozcu();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      premiumOzellikleriGorunurProvider.overrideWithValue(true),
      premiumKilitliProvider.overrideWithValue(kilitli),
    ],
    child: MaterialApp(
      locale: const Locale('tr', 'TR'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: [gozcu],
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showKapanisOzeti(
              context,
              const KapanisOzeti(ad: 'THYAO', yil: 0, ay: 3, gun: 0),
              degerlendirme: false,
            ),
            child: const Text('ac'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  await tester.pumpAndSettle();
  return gozcu;
}

void main() {
  setUp(() => RemoteConfigService.testAcik = {'paywall_enabled'});
  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('kilitliyken bağlantı kişisel kilit metni, dokununca paywall',
      (tester) async {
    final gozcu = await _ac(tester, kilitli: true);
    expect(find.text("Bu satışın yıllık raporu Premium'da"), findsOneWidget);
    expect(find.text('Yıllık raporda gör'), findsNothing);
    // Paywall yalnız dokunuşla: sayfa açıldığında kendiliğinden açılmadı.
    expect(gozcu.adlar, isNot(contains('paywall')));
    await tester.tap(find.byKey(const ValueKey('kapanis_rapor')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(gozcu.adlar, contains('paywall'));
    expect(gozcu.adlar, isNot(contains('yillik_rapor')));
    expect(kapanisRaporPaywallKaynagi, 'kapanis_rapor');
  });

  testWidgets('Premium: bağlantı değişmedi, yıllık rapora gider',
      (tester) async {
    final gozcu = await _ac(tester, kilitli: false);
    expect(find.text('Yıllık raporda gör'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('kapanis_rapor')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(gozcu.adlar, contains('yillik_rapor'));
    expect(gozcu.adlar, isNot(contains('paywall')));
  });

  testWidgets('özellik görünmüyorsa bağlantı yok', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        premiumOzellikleriGorunurProvider.overrideWithValue(false),
        premiumKilitliProvider.overrideWithValue(false),
      ],
      child: const MaterialApp(
        locale: Locale('tr', 'TR'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
            body: KapanisOzetiSayfasi(
                ozet: KapanisOzeti(ad: 'THYAO', yil: 0, ay: 3, gun: 0))),
      ),
    ));
    expect(find.byKey(const ValueKey('kapanis_rapor')), findsNothing);
  });
}
