import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumErisimProvider;
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/sinyal_varligi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Alarmlarım'ın sonunda "Sinyal bildirimleri · N varlık" (Ar-Ge 14 Kas
/// 02:03 #3): yalnız Premium'da ve sinyal bildirimi giden varlık varken.
class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => [
        PriceAlert(
          id: 'a',
          userId: 'u1',
          symbol: 'ALTIN_GRAM',
          label: 'Gram altın',
          targetPrice: 4300,
          direction: 'above',
          enabled: true,
          createdAt: DateTime(2026, 10, 1),
        ),
      ];
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => const [];
}

class _G extends GostergeAlarmlariNotifier {
  @override
  Future<List<GostergeAlarmi>> build() async => const [];
}

class _C extends CizimAlarmlariNotifier {
  @override
  Future<List<CizimAlarmi>> build() async => const [];
}

class _Gozcu extends NavigatorObserver {
  final adlar = <String?>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      adlar.add(route.settings.name);
}

Future<_Gozcu> _pump(WidgetTester tester, {required int sayi}) async {
  tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final gozcu = _Gozcu();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
      sinyalBildirimliVarlikSayisiProvider.overrideWithValue(sayi),
    ],
    child: MaterialApp(
      navigatorObservers: [gozcu],
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: const PriceAlertsScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return gozcu;
}

Asset _a(String id, String ticker, AssetType tur,
        {AssetKind kind = AssetKind.buy, String? ref, bool? manuel}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: tur,
      quantity: 1,
      purchasePrice: 10,
      currency: 'TRY',
      notes: '',
      kind: kind,
      refAssetId: ref,
      isManualPrice: manuel,
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('sinyalBildirimliVarlikSayisi', () {
    Set<String> hepsi(AssetType _) => {'rsi'};

    test('aynı varlığın lot\'ları bir sayılır, manuel ve mevduat sayılmaz', () {
      final lotlar = [
        _a('1', 'THYAO', AssetType.hisse),
        _a('2', 'THYAO', AssetType.hisse),
        _a('3', 'AFT', AssetType.fon),
        _a('4', 'Ev', AssetType.diger, manuel: true),
      ];
      expect(sinyalBildirimliVarlikSayisi(lotlar, hepsi), 2);
    });

    test('göstergesi boş tür sayılmaz', () {
      final lotlar = [
        _a('1', 'THYAO', AssetType.hisse),
        _a('2', 'AFT', AssetType.fon),
      ];
      expect(
          sinyalBildirimliVarlikSayisi(
              lotlar, (t) => t == AssetType.fon ? <String>{} : {'rsi'}),
          1);
    });

    test('tamamen satılmış pozisyon sayılmaz', () {
      final lotlar = [
        _a('1', 'THYAO', AssetType.hisse),
        _a('2', 'THYAO', AssetType.hisse, kind: AssetKind.sell, ref: '1'),
      ];
      expect(sinyalBildirimliVarlikSayisi(lotlar, hepsi), 0);
    });

    test('Premium erişimi yoksa provider 0', () {
      final c = ProviderContainer(
          overrides: [premiumErisimProvider.overrideWithValue(false)]);
      addTearDown(c.dispose);
      expect(c.read(sinyalBildirimliVarlikSayisiProvider), 0);
    });
  });

  testWidgets('Premium + sinyal açık: satır, 44 pt, düğme, ayarlara gider',
      (tester) async {
    final h = tester.ensureSemantics();
    final gozcu = await _pump(tester, sayi: 3);
    final satir = find.byKey(const ValueKey('sinyalSatiri'));
    expect(satir, findsOneWidget);
    expect(find.text('Sinyal bildirimleri · 3 varlık'), findsOneWidget);
    expect(tester.getSize(satir).height, greaterThanOrEqualTo(44));
    expect(
        tester.getSemantics(find.text('Sinyal bildirimleri · 3 varlık')),
        matchesSemantics(
            isButton: true,
            hasTapAction: true,
            label: 'Sinyal bildirimleri · 3 varlık'));
    // Listenin sonunda: alarm grubunun altında.
    expect(tester.getTopLeft(satir).dy,
        greaterThan(tester.getTopLeft(find.byKey(const ValueKey('a'))).dy));
    await tester.tap(satir);
    await tester.pump();
    expect(gozcu.adlar, contains('signal_settings'));
    h.dispose();
  });

  testWidgets('sinyal bildirimi yok ya da Premium değil: satır yok',
      (tester) async {
    await _pump(tester, sayi: 0);
    expect(find.byKey(const ValueKey('sinyalSatiri')), findsNothing);
  });
}
