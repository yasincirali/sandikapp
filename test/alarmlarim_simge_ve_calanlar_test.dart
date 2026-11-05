import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show priceAlertLimitProvider;
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/alarm_kur_sheet.dart'
    show alarmFiyatMetni;
import 'package:shared_preferences/shared_preferences.dart';

/// Alarmlarım (müşteri raporu 5 Kas 09:15): ABD hissesi hedefi "$" yazar,
/// çalmış alarm ne zaman çaldığını söyler, Çalanlar tek kartta düz liste.
List<PriceAlert> _fiyat = const [];

class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _fiyat;
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

PriceAlert _f(String id, String sembol, String ad, double hedef,
        {DateTime? tetik}) =>
    PriceAlert(
      id: id,
      userId: 'u1',
      symbol: sembol,
      label: ad,
      targetPrice: hedef,
      direction: 'above',
      enabled: true,
      triggeredAt: tetik,
      createdAt: DateTime(2026, 10, 1),
    );

Future<void> _pump(WidgetTester tester, {int? limit}) async {
  tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
      if (limit != null) priceAlertLimitProvider.overrideWithValue(limit),
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
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fiyat = const [];
  });

  test('alarm fiyatı varlığın kendi simgesiyle', () {
    expect(alarmFiyatMetni(240, 'AAPL'), contains(r'$'));
    expect(alarmFiyatMetni(240, 'AAPL'), isNot(contains('₺')));
    expect(alarmFiyatMetni(4300, 'ALTIN_GRAM'), fmtTRYFiyat(4300));
    expect(alarmFiyatMetni(41, 'USDTRY=X'), fmtTRYFiyat(41));
  });

  testWidgets('ABD hissesi alarm satırı "₺" değil "\$" yazar', (tester) async {
    _fiyat = [_f('a', 'AAPL', 'Apple', 240)];
    await _pump(tester);
    expect(find.textContaining(r'$240'), findsOneWidget);
    expect(find.textContaining('₺240'), findsNothing);
  });

  testWidgets('Çalanlar tek kartta, satırda varlık adı ve çalma zamanı',
      (tester) async {
    final an1 = DateTime(2026, 11, 3, 14, 20);
    final an2 = DateTime(2026, 11, 4, 10, 5);
    _fiyat = [
      _f('a', 'ALTIN_GRAM', 'Gram altın', 4300),
      _f('b', 'USDTRY=X', 'Dolar', 41, tetik: an1),
      _f('d', 'ALTIN_GRAM', 'Gram altın', 4000, tetik: an2),
    ];
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey('calanlarBasligi')));
    await tester.pumpAndSettle();

    final kart = find.byKey(const ValueKey('calanlarKarti'));
    expect(kart, findsOneWidget);
    for (final id in ['b', 'd']) {
      expect(find.descendant(of: kart, matching: find.byKey(ValueKey(id))),
          findsOneWidget);
    }
    // Çalanlarda varlık grubu başlığı yok; bekleyen altının grubu kalır.
    expect(find.byKey(const ValueKey('grup_USDTRY=X')), findsNothing);
    expect(find.byKey(const ValueKey('grup_ALTIN_GRAM')), findsOneWidget);
    expect(find.textContaining('Dolar · Çalıştı'), findsOneWidget);
    expect(find.text('Çaldı: ${fmtTarihSaat(an1)}'), findsOneWidget);
    expect(find.text('Çaldı: ${fmtTarihSaat(an2)}'), findsOneWidget);
  });

  List<PriceAlert> nAlarm(int n) => [
        for (var i = 0; i < n; i++)
          _f('a$i', 'ALTIN_GRAM', 'Gram altın', 4000.0 + i)
      ];

  testWidgets('ücretsiz planda 15/20 ve üstünde sayaç, 44 pt', (tester) async {
    _fiyat = nAlarm(16);
    await _pump(tester, limit: 20);
    final sayac = find.byKey(const ValueKey('alarmSayaci'));
    expect(sayac, findsOneWidget);
    expect(find.text('Kurulu alarm: 16/20'), findsOneWidget);
    expect(tester.getSize(sayac).height, greaterThanOrEqualTo(44));
  });

  testWidgets('eşik altında ve sınırsızda sayaç yok', (tester) async {
    _fiyat = nAlarm(14);
    await _pump(tester, limit: 20);
    expect(find.byKey(const ValueKey('alarmSayaci')), findsNothing);
  });

  testWidgets('Premium/paywall kapalı (sınırsız) sayaç yok', (tester) async {
    _fiyat = nAlarm(30);
    await _pump(tester, limit: 1 << 30);
    expect(find.byKey(const ValueKey('alarmSayaci')), findsNothing);
  });

  test('eşik tavanın dörtte üçü', () {
    expect(alarmSayaciEsigi(20), 15);
    expect(alarmSayaciEsigi(10), 8);
  });
}
