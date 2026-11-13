import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/price_alert.dart';
import 'package:portfoy_takip/models/seviye_alarmi.dart';
import 'package:portfoy_takip/models/yuzde_alarmi.dart';
import 'package:portfoy_takip/providers/price_alert_provider.dart';
import 'package:portfoy_takip/providers/seviye_alarmi_provider.dart';
import 'package:portfoy_takip/providers/yuzde_alarmi_provider.dart';
import 'package:portfoy_takip/screens/price_alerts_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/yazi_olcegi.dart';

/// Alarmlarım: bekleyenler üstte, çalmışlar katlı "Çalanlar (N)" grubunda,
/// "Çalanları temizle" yalnız çalmışları siler (Ar-Ge 29 Eki 16:45 #2).
List<PriceAlert> _fiyat = const [];
List<YuzdeAlarmi> _yuzde = const [];
List<GostergeAlarmi> _gosterge = const [];
final _silinen = <String>[];

class _F extends PriceAlertsNotifier {
  @override
  Future<List<PriceAlert>> build() async => _fiyat;
  @override
  Future<void> delete(String id) async {
    _silinen.add(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <PriceAlert>[])
        if (a.id != id) a
    ]);
  }
}

class _Y extends YuzdeAlarmlariNotifier {
  @override
  Future<List<YuzdeAlarmi>> build() async => _yuzde;
}

class _G extends GostergeAlarmlariNotifier {
  @override
  Future<List<GostergeAlarmi>> build() async => _gosterge;
  @override
  Future<void> delete(String id) async {
    _silinen.add(id);
    state = AsyncData([
      for (final a in state.valueOrNull ?? const <GostergeAlarmi>[])
        if (a.id != id) a
    ]);
  }
}

class _C extends CizimAlarmlariNotifier {
  @override
  Future<List<CizimAlarmi>> build() async => const [];
}

PriceAlert _f(String id, double hedef, {DateTime? tetik}) => PriceAlert(
      id: id,
      userId: 'u1',
      symbol: 'ALTIN_GRAM',
      label: 'Gram altın',
      targetPrice: hedef,
      direction: 'above',
      enabled: true,
      triggeredAt: tetik,
      createdAt: DateTime(2026, 10, 1),
    );

Future<void> _pump(WidgetTester tester, {double genislik = 375}) async {
  tester.view.physicalSize = Size(genislik * 3, 1400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
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
    _yuzde = const [];
    _gosterge = const [];
    _silinen.clear();
  });

  testWidgets('çalmış yoksa başlık yok, liste eskisi gibi', (tester) async {
    _fiyat = [_f('a', 4300)];
    await _pump(tester);
    expect(find.byKey(const ValueKey('calanlarBasligi')), findsNothing);
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
  });

  testWidgets('çalmışlar katlı grupta; dokununca açılır, 44 pt başlık',
      (tester) async {
    _fiyat = [
      _f('a', 4300),
      _f('b', 4100, tetik: DateTime(2026, 10, 20)),
      _f('d', 4000, tetik: DateTime(2026, 10, 25)),
    ];
    _yuzde = [
      YuzdeAlarmi(
        id: 'y',
        userId: 'u1',
        symbol: 'ALTIN_GRAM',
        label: 'Gram altın',
        esikPct: 2,
        yon: YuzdeYon.ikisi,
        sonTetikGunu: yuzdeAlarmGunu(DateTime.now()),
        createdAt: DateTime(2026, 10, 28),
      ),
    ];
    await _pump(tester);
    // "Bekleyenler" etiketi yok (14 Kas): bölüm başlığı varlığın adı.
    expect(find.text('Bekleyenler'), findsNothing);
    expect(find.text('Çalanlar (2)'), findsOneWidget);
    // Bugün çalmış yüzde alarmı yarın yine nöbette: bekleyenlerde.
    expect(find.byKey(const ValueKey('yuzde_y')), findsOneWidget);
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
    expect(find.byKey(const ValueKey('b')), findsNothing);
    final baslik = find.byKey(const ValueKey('calanlarBasligi'));
    expect(tester.getSize(baslik).height, greaterThanOrEqualTo(44));

    await tester.tap(baslik);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('b')), findsOneWidget);
    expect(find.byKey(const ValueKey('d')), findsOneWidget);
    // Çalanlar en son çalan önce.
    expect(tester.getTopLeft(find.byKey(const ValueKey('d'))).dy,
        lessThan(tester.getTopLeft(find.byKey(const ValueKey('b'))).dy));
  });

  testWidgets('"Çalanları temizle" onay sorar, yalnız çalmışları siler',
      (tester) async {
    _fiyat = [
      _f('a', 4300),
      _f('b', 4100, tetik: DateTime(2026, 10, 20)),
    ];
    _gosterge = [
      GostergeAlarmi(
        id: 'g',
        userId: 'u1',
        symbol: 'ALTIN_GRAM',
        label: 'Gram altın',
        gosterge: GostergeKodu.ema50,
        yon: SeviyeYon.yukari,
        triggeredAt: DateTime(2026, 10, 22),
        createdAt: DateTime(2026, 10, 21),
      ),
    ];
    await _pump(tester);
    expect(find.text('Çalanlar (2)'), findsOneWidget);
    // "Temizle" başlığın sağında, grup kapalıyken de; nötr renk, 44 pt.
    final temizle = find.byKey(const ValueKey('calanlariTemizle'));
    expect(temizle, findsOneWidget);
    expect(tester.getSize(temizle).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(temizle).width, greaterThanOrEqualTo(44));
    final stil = tester.widget<TextButton>(temizle).style!;
    expect(stil.foregroundColor!.resolve(const {}), SandikPalette.dark.text58);
    expect(find.byIcon(Icons.delete_sweep_rounded), findsNothing);
    await tester.tap(temizle);
    await tester.pumpAndSettle();
    expect(find.textContaining('Çalmış 2 alarm silinsin mi?'), findsOneWidget);
    await tester.tap(find.text('Sil').last);
    await tester.pumpAndSettle();
    expect(_silinen, unorderedEquals(['b', 'g']));
    expect(find.byKey(const ValueKey('calanlarBasligi')), findsNothing);
    expect(find.byKey(const ValueKey('a')), findsOneWidget);
  });

  // Hiyerarşi (Ar-Ge 14 Kas 02:03 #2): "Bekleyenler" yok, varlık adı tek
  // bölüm başlığı (ekran okuyucuda başlık), çalmış satır tek cümle.
  List<GostergeAlarmi> calmisGosterge() => [
        GostergeAlarmi(
          id: 'g',
          userId: 'u1',
          symbol: 'ALTIN_GRAM',
          label: 'Gram altın',
          gosterge: GostergeKodu.ema50,
          yon: SeviyeYon.yukari,
          triggeredAt: DateTime(2026, 10, 22, 14, 5),
          tetikFiyat: 4210,
          createdAt: DateTime(2026, 10, 21),
        ),
      ];

  testWidgets('varlık başlığı ekran okuyucuda başlık; çalmış gösterge tek cümle',
      (tester) async {
    final h = tester.ensureSemantics();
    _fiyat = [_f('a', 4300)];
    _gosterge = calmisGosterge();
    await _pump(tester);
    expect(find.text('Bekleyenler'), findsNothing);
    final baslik = find.descendant(
        of: find.byKey(const ValueKey('grup_ALTIN_GRAM')),
        matching: find.text('Gram altın'));
    // ignore: deprecated_member_use
    expect(tester.getSemantics(baslik).hasFlag(SemanticsFlag.isHeader), isTrue);
    await tester.tap(find.byKey(const ValueKey('calanlarBasligi')));
    await tester.pumpAndSettle();
    expect(
        find.text('Gram altın EMA50 yukarı kesildi · ₺4.210,00 · '
            '22 Eki 2026 14:05'),
        findsOneWidget);
    expect(find.textContaining('Çalıştı'), findsNothing);
    h.dispose();
  });

  group('taşma', () {
    yaziOlcegiEkseni(() {
      testWidgets('320 pt, başlıklar ve açık Çalanlar', (tester) async {
        yaziOlceginiUygula(tester);
        _fiyat = [
          _f('a', 4300),
          _f('b', 4100, tetik: DateTime(2026, 10, 20, 9, 30)),
        ];
        _gosterge = calmisGosterge();
        await _pump(tester, genislik: 320);
        await tester.tap(find.byKey(const ValueKey('calanlarBasligi')));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final temizle = find.byKey(const ValueKey('calanlariTemizle'));
        expect(tester.getSize(temizle).height, greaterThanOrEqualTo(44));
      });
    });
  });
}
