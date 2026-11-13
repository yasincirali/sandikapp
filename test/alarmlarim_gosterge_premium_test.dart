import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Premium'u biten kullanıcının gösterge/çizgi alarmı (Ar-Ge 14 Kas 02:03
/// #1): satır kalır, "Düzenlemek için Premium" der, düzenleme paywall'a
/// gider; silme serbest. Paywall kapalıyken (kilit yok) bugünkü hâl.
class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => const [];
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => const [];
}

class _G extends GostergeAlarmlariNotifier {
  @override
  Future<List<GostergeAlarmi>> build() async => [
        GostergeAlarmi(
          id: 'g1',
          userId: 'u1',
          symbol: 'THYAO',
          label: 'THY',
          gosterge: GostergeKodu.ema50,
          yon: SeviyeYon.asagi,
          createdAt: DateTime(2026, 11, 1),
        ),
      ];
}

class _C extends CizimAlarmlariNotifier {
  @override
  Future<List<CizimAlarmi>> build() async => [
        CizimAlarmi(
          id: 'c1',
          userId: 'u1',
          symbol: 'THYAO',
          label: 'THY · Destek',
          cizimId: 'cz1',
          t1: DateTime(2026, 10, 1).millisecondsSinceEpoch,
          p1: 300,
          t2: DateTime(2026, 10, 2).millisecondsSinceEpoch,
          p2: 300,
          uzanir: true,
          yon: SeviyeYon.asagi,
          createdAt: DateTime(2026, 10, 30),
        ),
      ];
}

Future<void> _pump(WidgetTester tester, {required bool kilitli}) async {
  tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
      premiumKilitliProvider.overrideWithValue(kilitli),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: const PriceAlertsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('kilitli: satır kalır, "Düzenlemek için Premium", kalem yok',
      (tester) async {
    await _pump(tester, kilitli: true);
    expect(find.byKey(const ValueKey('gosterge_g1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cizim_c1')), findsOneWidget);
    expect(find.text('Düzenlemek için Premium'), findsNWidgets(2));
    // Yeniden adlandırma bir yazmadır (RLS reddeder): kalem çizilmez.
    expect(find.byKey(const ValueKey('cizgiAlarmiAdlandir')), findsNothing);
    expect(find.text('Grafikte aç'), findsNothing);
    // Alt metin nötr, kırmızı değil.
    final c = SandikPalette.dark;
    final metin = tester.widget<Text>(find.text('Düzenlemek için Premium').first);
    expect(metin.style?.color, c.text58);
    // Silme serbest: kaydırma kabuğu duruyor.
    expect(find.byKey(const ValueKey('kaydir_gosterge_g1')), findsOneWidget);
    // Satır dokunulabilir (paywall'a gider); testte paywall RC'si kapalı,
    // `PaywallScreen.show` sessizce döner, ekran yerinde kalır.
    await tester.tap(find.byKey(const ValueKey('gosterge_g1')));
    await tester.pumpAndSettle();
    expect(find.byType(PriceAlertsScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('kilit yok (paywall kapalı ya da Premium): bugünkü hâl',
      (tester) async {
    await _pump(tester, kilitli: false);
    expect(find.text('Düzenlemek için Premium'), findsNothing);
    expect(find.byKey(const ValueKey('cizgiAlarmiAdlandir')), findsOneWidget);
  });

  test('kilitli düzenleme paywall\'u kendi kaynağıyla açar', () {
    final k = ekranKaynagiSync('lib/screens/price_alerts_screen.dart');
    expect(k, contains("source: 'alarm_gosterge_duzenle'"));
  });
}
