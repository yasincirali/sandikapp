import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/calanlar_yakinligi.dart';
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

/// Alarmlarım 3. tur (Ar-Ge 7 Kas 13:40): son 24 saatte çalan alarm varsa
/// Çalanlar açık ve en üstte, yoksa kapalı ve altta; elle seçim oturumda
/// korunur. Yön oku nötr renkte (yeşil/kırmızı kâr/zarar demek).
final _simdi = DateTime(2026, 11, 7, 13, 40);
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
        {DateTime? tetik, String yon = 'above'}) =>
    PriceAlert(
      id: id,
      userId: 'u1',
      symbol: sembol,
      label: ad,
      targetPrice: hedef,
      direction: yon,
      enabled: true,
      triggeredAt: tetik,
      createdAt: DateTime(2026, 10, 1),
    );

List<PriceAlert> _liste(Duration calmaOnce) => [
      _f('a', 'ALTIN_GRAM', 'Gram altın', 4300),
      _f('b', 'THYAO.IS', 'Türk Hava Yolları', 280, yon: 'below'),
      _f('c', 'USDTRY=X', 'Dolar', 41, tetik: _simdi.subtract(calmaOnce)),
    ];

Future<void> _pump(WidgetTester tester,
    {double genislik = 375, double yukseklik = 1400}) async {
  tester.view.physicalSize = Size(genislik * 3, yukseklik * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      priceAlertsProvider.overrideWith(_F.new),
      yuzdeAlarmlariProvider.overrideWith(_Y.new),
      gostergeAlarmlariProvider.overrideWith(_G.new),
      cizimAlarmlariProvider.overrideWith(_C.new),
      alarmSaatProvider.overrideWithValue(() => _simdi),
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

final _baslik = find.byKey(const ValueKey('calanlarBasligi'));
final _kart = find.byKey(const ValueKey('calanlarKarti'));

double _ust(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

Color? _okRengi(WidgetTester tester, String id) {
  final ok = find.descendant(
    of: find.byKey(ValueKey(id)),
    matching: find.byWidgetPredicate((w) =>
        w is Icon &&
        (w.icon == Icons.arrow_upward_rounded ||
            w.icon == Icons.arrow_downward_rounded)),
  );
  return tester.widget<Icon>(ok.first).color;
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _fiyat = const [];
  });

  group('calanlarOneCiksin', () {
    test('23 saat önce çalma: öne çıkar', () {
      expect(
          calanlarOneCiksin(_simdi.subtract(const Duration(hours: 23)), _simdi),
          isTrue);
    });
    test('25 saat önce çalma: kapalı, altta', () {
      expect(
          calanlarOneCiksin(_simdi.subtract(const Duration(hours: 25)), _simdi),
          isFalse);
    });
    test('tam 24 saat: artık eski', () {
      expect(calanlarOneCiksin(_simdi.subtract(calanlarYakinlikSiniri), _simdi),
          isFalse);
    });
    test('hiç çalma yok', () {
      expect(calanlarOneCiksin(null, _simdi), isFalse);
    });
    test('saati ileride görünen çalma yeni sayılır', () {
      expect(calanlarOneCiksin(_simdi.add(const Duration(minutes: 5)), _simdi),
          isTrue);
    });
    test('UTC çalma yerel saatle karşılaştırılır', () {
      final utc = _simdi.toUtc().subtract(const Duration(hours: 1));
      expect(calanlarOneCiksin(utc, _simdi), isTrue);
    });
  });

  testWidgets('yakın çalma: Çalanlar en üstte ve açık, animasyonsuz',
      (tester) async {
    _fiyat = _liste(const Duration(hours: 1));
    tester.view.physicalSize = const Size(375 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        priceAlertsProvider.overrideWith(_F.new),
        yuzdeAlarmlariProvider.overrideWith(_Y.new),
        gostergeAlarmlariProvider.overrideWith(_G.new),
        cizimAlarmlariProvider.overrideWith(_C.new),
        alarmSaatProvider.overrideWithValue(() => _simdi),
      ],
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: const PriceAlertsScreen(),
      ),
    ));
    // Veri gelir gelmez kart tam açık: açılış hareketi oynamaz. Yükleme →
    // içerik geçişi (`SandikIcerikGecisi`) bitene kadar pompala, panel
    // boyu o sırada değişmemeli.
    await tester.pump();
    await tester.pump();
    expect(_kart, findsOneWidget);
    final ilkBoy = tester.getSize(_kart).height;
    await tester.pumpAndSettle();
    expect(tester.getSize(_kart).height, ilkBoy);

    expect(_ust(tester, _baslik),
        lessThan(_ust(tester, find.byKey(const ValueKey('grup_ALTIN_GRAM')))));
    expect(
        find.descendant(of: _kart, matching: find.byKey(const ValueKey('c'))),
        findsOneWidget);
  });

  testWidgets('eski çalma: Çalanlar en altta ve kapalı', (tester) async {
    _fiyat = _liste(const Duration(hours: 25));
    await _pump(tester);
    expect(_kart, findsNothing);
    expect(
        _ust(tester, _baslik),
        greaterThan(
            _ust(tester, find.byKey(const ValueKey('grup_ALTIN_GRAM')))));
  });

  testWidgets('elle kapatma oturumda korunur, grup yerinden oynamaz',
      (tester) async {
    _fiyat = _liste(const Duration(hours: 1));
    await _pump(tester);
    final yer = _ust(tester, _baslik);
    await tester.tap(_baslik);
    await tester.pumpAndSettle();
    expect(_kart, findsNothing);
    expect(_ust(tester, _baslik), yer);

    // Liste yenilenir (sağlayıcı yeniden kurulur): seçim kalır.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(PriceAlertsScreen)));
    container.invalidate(priceAlertsProvider);
    await tester.pumpAndSettle();
    expect(_kart, findsNothing);

    await tester.tap(_baslik);
    await tester.pumpAndSettle();
    expect(_kart, findsOneWidget);
  });

  testWidgets('eski çalmada elle açma çalışır', (tester) async {
    _fiyat = _liste(const Duration(days: 3));
    await _pump(tester);
    await tester.tap(_baslik);
    await tester.pumpAndSettle();
    expect(_kart, findsOneWidget);
  });

  testWidgets('yön oku nötr: bekleyende text58, çalmışta text36',
      (tester) async {
    _fiyat = _liste(const Duration(hours: 1));
    await _pump(tester);
    const p = SandikPalette.dark;
    expect(_okRengi(tester, 'a'), p.text58);
    expect(_okRengi(tester, 'b'), p.text58);
    expect(_okRengi(tester, 'c'), p.text36);
    // Yön okun şeklinde: yukarı/aşağı ayrı simge (yalnız renkle değil).
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('b')),
            matching: find.byIcon(Icons.arrow_downward_rounded)),
        findsOneWidget);
  });

  testWidgets('başlık açık/kapalı durumunu söyler, ≥44 pt', (tester) async {
    final h = tester.ensureSemantics();
    _fiyat = _liste(const Duration(hours: 1));
    await _pump(tester);
    expect(tester.getSize(_baslik).height, greaterThanOrEqualTo(44));
    expect(
        tester.getSemantics(_baslik),
        matchesSemantics(
          label: 'Çalanlar (1)',
          isButton: true,
          hasExpandedState: true,
          isExpanded: true,
          hasTapAction: true,
        ));
    await tester.tap(_baslik);
    await tester.pumpAndSettle();
    expect(
        tester.getSemantics(_baslik),
        matchesSemantics(
          label: 'Çalanlar (1)',
          isButton: true,
          hasExpandedState: true,
          isExpanded: false,
          hasTapAction: true,
        ));
    h.dispose();
  });

  testWidgets('iOS: durum VoiceOver için değer olarak ("açık"/"kapalı")',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final h = tester.ensureSemantics();
    _fiyat = _liste(const Duration(hours: 1));
    await _pump(tester);
    expect(tester.getSemantics(_baslik).value, 'açık');
    await tester.tap(_baslik);
    await tester.pumpAndSettle();
    expect(tester.getSemantics(_baslik).value, 'kapalı');
    h.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  group('taşma', () {
    yaziOlcegiEkseni(() {
      testWidgets('320 pt, açık Çalanlar üstte', (tester) async {
        yaziOlceginiUygula(tester);
        _fiyat = _liste(const Duration(hours: 1));
        await _pump(tester, genislik: 320, yukseklik: 900);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_baslik).height, greaterThanOrEqualTo(44));
      });
    });
  });
}
