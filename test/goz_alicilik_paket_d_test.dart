import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/analiz_provider.dart';
import 'package:portfoy_takip/screens/aylik_rapor_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/varlik_analizi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hikaye_akisi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Göz alıcılık paketi D (2026-10-09), bayrak `goz_alici`: aylık hikâye.
///
/// Sözleşme: bayrak kapalıyken rapor birebir eski liste; açıkken ayın ilk
/// açılışında hikâye (açılış → sayı → en çok üç öne çıkan), bitince ya da
/// atlanınca liste ve ay "görüldü"; ikinci açılışta doğrudan liste, en
/// üstte "Hikâye olarak izle".
void main() {
  final ay = DateTime.utc(2026, 9, 1);

  AnalizOzeti not(String t, String rozet) => AnalizOzeti(
      ticker: t, donem: ay, baslik: '$t başlığı', rozet: rozet, maddeSayisi: 2);

  Widget ekran({double yaziOlcegi = 1}) => ProviderScope(
        overrides: [
          tutulanNotAnahtarlariProvider.overrideWithValue(
              ['TEFAS:TTE', 'THYAO.IS', 'KRIPTO:BTC', 'ASELS.IS']),
          notOzetleriProvider.overrideWith((ref, a) async => {
                'TEFAS:TTE': not('TEFAS:TTE', 'buyuk_giris'),
                'ASELS.IS': not('ASELS.IS', 'buyuk_cikis'),
                'THYAO.IS': not('THYAO.IS', 'sakin'),
                'KRIPTO:BTC': not('KRIPTO:BTC', 'sakin'),
              }),
        ],
        child: MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(yaziOlcegi)),
            child: child!,
          ),
          home: AylikRaporScreen(donem: ay),
        ),
      );

  AppLocalizations l(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(AylikRaporScreen)))!;

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => RemoteConfigService.testAcik = {});

  testWidgets('kapalıyken hikâye yok, birebir liste', (t) async {
    await t.pumpWidget(ekran());
    await t.pumpAndSettle();
    expect(find.byType(HikayeAkisi), findsNothing);
    expect(find.text(l(t).hkyAylikTekrar), findsNothing);
    expect(find.text(l(t).anzAylikOzetVar('4', '2')), findsOneWidget);
  });

  testWidgets('açıkken ilk açılışta hikâye; sonunda liste ve ay görüldü',
      (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(ekran());
    await t.pumpAndSettle();
    final l10n = l(t);
    expect(find.byType(HikayeAkisi), findsOneWidget);
    expect(find.text(l10n.hkyAylikAcilis), findsOneWidget);

    await t.tap(find.text(l10n.hkyDevam));
    await t.pumpAndSettle();
    expect(find.text('4'), findsOneWidget);
    expect(find.text(l10n.hkyAylikHareketli('2')), findsOneWidget);

    // Öne çıkanlar listeyle aynı önem sırasında: giriş, sonra çıkış.
    await t.tap(find.text(l10n.hkyDevam));
    await t.pumpAndSettle();
    expect(find.text('TTE'), findsOneWidget);
    await t.tap(find.text(l10n.hkyDevam));
    await t.pumpAndSettle();
    expect(find.text('ASELS'), findsOneWidget);

    // Son sayfa: sakin notlar hikâyeye girmez, düğme raporu açar.
    await t.tap(find.text(l10n.hkyAylikRaporuAc));
    await t.pumpAndSettle();
    expect(find.byType(HikayeAkisi), findsNothing);
    expect(find.text(l10n.anzAylikOzetVar('4', '2')), findsOneWidget);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(AylikHikayeKapisi.goruldu), '2026-09');
  });

  testWidgets('görülen ayda doğrudan liste; "Hikâye olarak izle" geri açar',
      (t) async {
    SharedPreferences.setMockInitialValues(
        {AylikHikayeKapisi.goruldu: '2026-09'});
    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(ekran());
    await t.pumpAndSettle();
    final l10n = l(t);
    expect(find.byType(HikayeAkisi), findsNothing);
    await t.tap(find.text(l10n.hkyAylikTekrar));
    await t.pumpAndSettle();
    expect(find.byType(HikayeAkisi), findsOneWidget);
  });

  testWidgets('yeni ay hikâyeyi yeniden açar', (t) async {
    SharedPreferences.setMockInitialValues(
        {AylikHikayeKapisi.goruldu: '2026-08'});
    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(ekran());
    await t.pumpAndSettle();
    expect(find.byType(HikayeAkisi), findsOneWidget);
  });

  testWidgets('Atla listeye geçer ve ayı görüldü sayar', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    await t.pumpWidget(ekran());
    await t.pumpAndSettle();
    await t.tap(find.text(l(t).hkyAtla));
    await t.pumpAndSettle();
    expect(find.byType(HikayeAkisi), findsNothing);
    final p = await SharedPreferences.getInstance();
    expect(p.getString(AylikHikayeKapisi.goruldu), '2026-09');
  });

  testWidgets('320pt ve yazı ×2 taşmaz', (t) async {
    RemoteConfigService.testAcik = {'goz_alici'};
    t.view.physicalSize = const Size(320, 568);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(ekran(yaziOlcegi: 2));
    await t.pumpAndSettle();
    for (var i = 0; i < 3; i++) {
      await t.tap(find.text(l(t).hkyDevam));
      await t.pumpAndSettle();
    }
    expect(t.takeException(), isNull);
  });
}
