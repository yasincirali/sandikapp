import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/gosterge_degeri.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Gösterge alarmı satırında göstergenin şu anki değeri ve uzaklık (Ar-Ge
/// 14 Kas 02:03 #5). Hesap sunucunun tanımıyla aynı
/// (`_shared/gosterge_alarmi.ts`); seri yoksa satır eskisi gibi.
List<(int, double)> _gunluk(int gun, double Function(int i) deger,
    {DateTime? simdi}) {
  final s = simdi ?? DateTime.now();
  return [
    for (var i = gun; i >= 1; i--)
      (s.subtract(Duration(days: i)).millisecondsSinceEpoch, deger(i)),
  ];
}

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
          symbol: 'THYAO.IS',
          label: 'THY',
          gosterge: GostergeKodu.ema20,
          yon: SeviyeYon.asagi,
          createdAt: DateTime(2026, 11, 1),
        ),
      ];
}

class _C extends CizimAlarmlariNotifier {
  @override
  Future<List<CizimAlarmi>> build() async => const [];
}

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: [
        Asset(
          id: 'a1',
          userId: 'u1',
          name: 'THY',
          ticker: 'THYAO.IS',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 80,
          currentPrice: 100,
          currency: 'TRY',
          notes: '',
          addedDate: DateTime(2026, 9, 1),
        ),
      ],
      ownerId: 'u1',
      usdTry: 42.0,
      eurTry: 46.0,
      gbpTry: 54.0);
}

Future<void> _pump(WidgetTester tester, List<(int, double)> seri) async {
  tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  final istenen = <String>[];
  await tester.pumpWidget(ProviderScope(
    overrides: [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
      portfolioProvider.overrideWith(_Portfoy.new),
      gostergeSerisiProvider.overrideWith((ref, sembol) async {
        istenen.add(sembol);
        return seri;
      }),
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
  expect(istenen, ['THYAO.IS']);
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('gostergeKapanislari', () {
    final simdi = DateTime(2026, 11, 13, 15);

    test('bugünün yarım çubuğu atılır, canlı fiyat sona eklenir', () {
      final seri = [
        ..._gunluk(3, (i) => 10.0 + i, simdi: simdi),
        (simdi.subtract(const Duration(hours: 1)).millisecondsSinceEpoch, 99.0),
      ];
      expect(gostergeKapanislari(seri, 20, simdi), [13, 12, 11, 20]);
    });

    test('canlı fiyat yoksa, seri boşsa ya da bayatsa null', () {
      final seri = _gunluk(3, (_) => 10, simdi: simdi);
      expect(gostergeKapanislari(seri, 0, simdi), isNull);
      expect(gostergeKapanislari(const [], 10, simdi), isNull);
      final bayat = [
        (simdi.subtract(const Duration(days: 9)).millisecondsSinceEpoch, 10.0)
      ];
      expect(gostergeKapanislari(bayat, 10, simdi), isNull);
    });

    test('730 günden eski nokta hesaba girmez (sunucu penceresi)', () {
      final seri = _gunluk(800, (_) => 10, simdi: simdi);
      expect(gostergeKapanislari(seri, 10, simdi)!.length, lessThan(732));
    });
  });

  group('gostergeSeviyesi', () {
    final k = [for (var i = 0; i < 250; i++) 100.0 + (i % 7)];

    test('EMA grafikteki fonksiyonun son değeri', () {
      expect(gostergeSeviyesi(GostergeKodu.ema50, k),
          TechnicalAnalysisService.emaSeries(k, 50).last);
      expect(gostergeSeviyesi(GostergeKodu.ema200, k),
          TechnicalAnalysisService.emaSeries(k, 200).last);
    });

    test('MA20 ve Bollinger (20, 2σ, nüfus sapması)', () {
      final d = [for (var i = 0; i < 20; i++) i.isEven ? 9.0 : 11.0];
      expect(gostergeSeviyesi(GostergeKodu.sma20, d), 10);
      expect(gostergeSeviyesi(GostergeKodu.bbUst, d), closeTo(12, 1e-9));
      expect(gostergeSeviyesi(GostergeKodu.bbAlt, d), closeTo(8, 1e-9));
    });

    test('veri yetmezse null (uydurma yok)', () {
      expect(gostergeSeviyesi(GostergeKodu.ema200, k.sublist(0, 199)), isNull);
      expect(gostergeSeviyesi(GostergeKodu.bbUst, k.sublist(0, 19)), isNull);
    });
  });

  test('seri sembolü kapsamdan: altın ve TL dövizde yok', () {
    expect(FiyatKaynagi.gostergeAlarmSerisi('THYAO.IS'), 'THYAO.IS');
    expect(FiyatKaynagi.gostergeAlarmSerisi('ALTIN_GRAM'), isNull);
    expect(FiyatKaynagi.gostergeAlarmSerisi('USDTRY=X'), isNull);
    expect(FiyatKaynagi.gostergeAlarmSerisiAraligi('TEFAS:AFT'), '3y');
    expect(FiyatKaynagi.gostergeAlarmSerisiAraligi('THYAO.IS'), '2y');
  });

  testWidgets('seri varken satır göstergenin değerini ve uzaklığı yazar',
      (tester) async {
    await _pump(tester, _gunluk(60, (_) => 90));
    final satir = find.byKey(const ValueKey('gosterge_g1'));
    // EMA20 ≈ 90,95 (59 gün 90 + canlı 100); fiyat 100, aşağı keserse.
    expect(
        find.descendant(of: satir, matching: find.text('EMA20 ₺90,95')),
        findsOneWidget);
    expect(
        find.descendant(
            of: satir, matching: find.byKey(const ValueKey('alarmMesafe'))),
        findsOneWidget);
  });

  testWidgets('seri yoksa ya da kısaysa satır eskisi gibi', (tester) async {
    await _pump(tester, _gunluk(10, (_) => 90));
    final satir = find.byKey(const ValueKey('gosterge_g1'));
    expect(find.descendant(of: satir, matching: find.textContaining('EMA20 ₺')),
        findsNothing);
    expect(
        find.descendant(
            of: satir, matching: find.byKey(const ValueKey('alarmMesafe'))),
        findsNothing);
  });
}
