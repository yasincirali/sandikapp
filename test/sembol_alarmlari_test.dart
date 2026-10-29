import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/sembol_alarmlari_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/alarm_seridi.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Dört alarm türü tek yerden (Ar-Ge 29 Eki 16:45 #1): yüzde alarmı varlık
/// şeridinde ve Portföy rozetinde de görünür; sayım dört türü toplar.
List<PriceAlert> _fiyat = const [];
List<YuzdeAlarmi> _yuzde = const [];
List<GostergeAlarmi> _gosterge = const [];

class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _fiyat;
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => _yuzde;
}

class _G extends GostergeAlarmlariNotifier {
  @override
  Future<List<GostergeAlarmi>> build() async => _gosterge;
}

class _C extends CizimAlarmlariNotifier {
  @override
  Future<List<CizimAlarmi>> build() async => const [];
}

final _overrides = [
  priceAlertsProvider.overrideWith(_F.new),
  yuzdeAlarmlariProvider.overrideWith(_Y.new),
  gostergeAlarmlariProvider.overrideWith(_G.new),
  cizimAlarmlariProvider.overrideWith(_C.new),
];

PriceAlert _f(String id, String s, {DateTime? tetik}) => PriceAlert(
      id: id,
      userId: 'u1',
      symbol: s,
      label: s,
      targetPrice: 4300,
      direction: 'above',
      enabled: true,
      triggeredAt: tetik,
      createdAt: DateTime(2026, 10, 1),
    );

YuzdeAlarmi _y(String id, String s, {String? gun}) => YuzdeAlarmi(
      id: id,
      userId: 'u1',
      symbol: s,
      label: s,
      esikPct: 2,
      yon: YuzdeYon.ikisi,
      sonTetikGunu: gun,
      createdAt: DateTime(2026, 10, 28),
    );

GostergeAlarmi _g(String id, String s) => GostergeAlarmi(
      id: id,
      userId: 'u1',
      symbol: s,
      label: s,
      gosterge: GostergeKodu.ema50,
      yon: SeviyeYon.yukari,
      createdAt: DateTime(2026, 10, 28),
    );

Future<void> _pump(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(375 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: _overrides,
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(body: body),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fiyat = const [];
    _yuzde = const [];
    _gosterge = const [];
  });

  test('sayım dört türü toplar; başka sembol ve sönmüş fiyat alarmı girmez',
      () async {
    _fiyat = [
      _f('a', 'ALTIN_GRAM'),
      _f('b', 'ALTIN_GRAM', tetik: DateTime(2026, 10, 2)),
      _f('c', 'USDTRY=X'),
    ];
    _yuzde = [
      _y('y', 'ALTIN_GRAM', gun: yuzdeAlarmGunu(DateTime.now())),
      _y('z', 'USDTRY=X'),
    ];
    _gosterge = [_g('g', 'ALTIN_GRAM')];
    final c = ProviderContainer(overrides: _overrides);
    addTearDown(c.dispose);
    await c.read(priceAlertsProvider.future);
    await c.read(yuzdeAlarmlariProvider.future);
    await c.read(gostergeAlarmlariProvider.future);
    await c.read(cizimAlarmlariProvider.future);
    final o = c.read(sembolAlarmlariProvider('ALTIN_GRAM'));
    expect(o.fiyat, hasLength(2));
    expect(o.yuzde, hasLength(1));
    // Bugün çalmış yüzde alarmı yarın yine nöbette: sayılır.
    expect(o.aktif, 3);
    expect(c.read(sembolAlarmlariProvider('EURTRY=X')).bos, isTrue);
  });

  testWidgets('yalnız yüzde alarmı → şerit çizilir, çip ve cümle',
      (tester) async {
    _yuzde = [_y('y', 'ALTIN_GRAM')];
    final semantics = tester.ensureSemantics();
    await _pump(
        tester,
        const AlarmSeridi(
            sembol: 'ALTIN_GRAM', ad: 'Gram altın', guncelFiyat: 4200));
    expect(find.text('Günlük %2 hareket'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('^Günlük %2 hareket alarmı kurulu')),
        findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('bugün çalmış yüzde alarmı → "bugün çaldı" ve onay ikonu',
      (tester) async {
    _yuzde = [_y('y', 'ALTIN_GRAM', gun: yuzdeAlarmGunu(DateTime.now()))];
    await _pump(
        tester,
        const AlarmSeridi(
            sembol: 'ALTIN_GRAM', ad: 'Gram altın', guncelFiyat: 4200));
    expect(find.text('Günlük %2 hareket · bugün çaldı'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('yüzde çipine dokununca silme sorulur', (tester) async {
    _yuzde = [_y('y', 'ALTIN_GRAM')];
    await _pump(
        tester,
        const AlarmSeridi(
            sembol: 'ALTIN_GRAM', ad: 'Gram altın', guncelFiyat: 4200));
    await tester.tap(find.text('Günlük %2 hareket'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Her gün yeniden kurulmayı bırakır'),
        findsOneWidget);
  });
}
