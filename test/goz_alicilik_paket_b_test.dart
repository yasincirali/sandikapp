import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart'
    show kucukHalkaDilimi;
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/fiyat_grafigi.dart' show donemUclariX;
import 'package:portfoy_takip/widgets/varlik_ozeti.dart';
import 'package:portfoy_takip/widgets/varlik_rozeti.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// Göz alıcılık paketi B + rozet yayılımı (2026-10-09), bayrak `goz_alici`.
///
/// Sözleşme: bayrak kapalıyken her yüzey birebir eski (tür noktası, düz
/// fiyat, hare yok, halka büyük sayfayı açar); açıkken rozet listelerde,
/// büyük fiyat imleci izler, hare dönem yönünü taşır, halkada dilim seçilir.
Widget _kabuk(Widget w) => MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      home: Scaffold(body: Center(child: w)),
    );

void main() {
  tearDown(() => RemoteConfigService.testAcik = {});

  group('VarlikRozeti', () {
    testWidgets('kapalıyken 8pt tür noktası, sembol yazılmaz', (t) async {
      await t.pumpWidget(_kabuk(
          const VarlikRozeti(type: AssetType.hisse, ticker: 'ASELS.IS')));
      expect(find.text('ASE'), findsNothing);
      expect(t.getSize(find.byType(VarlikRozeti)), const Size(8, 8));
    });

    testWidgets('açıkken hissede sembol rozeti', (t) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      await t.pumpWidget(_kabuk(
          const VarlikRozeti(type: AssetType.hisse, ticker: 'ASELS.IS')));
      expect(find.text('ASE'), findsOneWidget);
      expect(t.getSize(find.byType(VarlikRozeti)),
          const Size(VarlikRozeti.cap, VarlikRozeti.cap));
    });

    testWidgets('açıkken de altın noktada kalır', (t) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      await t.pumpWidget(_kabuk(
          const VarlikRozeti(type: AssetType.altin, ticker: 'ALTIN_GRAM')));
      expect(t.getSize(find.byType(VarlikRozeti)), const Size(8, 8));
    });
  });

  group('kucukHalkaDilimi', () {
    const boyut = Size.square(120);
    // Tepeden saat yönünde: hisse %50 (sağ yarı), fon %25 (sol alt
    // çeyrek), altın %25 (sol üst çeyrek).
    const dilimler = [
      (tur: AssetType.hisse, pay: 0.5),
      (tur: AssetType.fon, pay: 0.25),
      (tur: AssetType.altin, pay: 0.25),
    ];

    test('halka bandında açıya göre dilim', () {
      expect(kucukHalkaDilimi(dilimler, const Offset(110, 60), boyut),
          AssetType.hisse);
      expect(kucukHalkaDilimi(dilimler, const Offset(30, 100), boyut),
          AssetType.fon);
      expect(kucukHalkaDilimi(dilimler, const Offset(30, 20), boyut),
          AssetType.altin);
    });

    test('ortaya ya da kutu dışına düşen dokunuş dilim seçmez', () {
      expect(kucukHalkaDilimi(dilimler, const Offset(60, 60), boyut), null);
      expect(kucukHalkaDilimi(dilimler, const Offset(0, 0), boyut), null);
      expect(kucukHalkaDilimi(dilimler, null, boyut), null);
      expect(kucukHalkaDilimi(const [], const Offset(110, 60), boyut), null);
    });
  });

  test('donemUclariX: zirve ve dip', () {
    expect(
        donemUclariX(const [
          FlSpot(0, 5),
          FlSpot(1, 9),
          FlSpot(2, 2),
          FlSpot(3, 6),
        ]),
        {1.0, 2.0});
    expect(donemUclariX(const []), isEmpty);
  });

  group('VarlikFiyatBlogu', () {
    Widget blok({ValueNotifier<(String, String)?>? imlec}) => Builder(
          builder: (context) => VarlikFiyatBlogu(
            etiket: 'GÜNCEL FİYAT',
            fiyat: '₺206,10',
            fiyatRengi: context.c.text90,
            degisim: (metin: '+%2,66 · 1 yıl', renk: context.c.gain),
            imlec: imlec,
          ),
        );

    bool hareVar(WidgetTester t) => find
        .byWidgetPredicate((w) =>
            w is DecoratedBox &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).gradient is RadialGradient)
        .evaluate()
        .isNotEmpty;

    testWidgets('kapalıyken hare yok, düz fiyat', (t) async {
      await t.pumpWidget(_kabuk(blok()));
      expect(hareVar(t), isFalse);
      expect(find.text('₺206,10'), findsOneWidget);
    });

    testWidgets('açıkken yön haresi var', (t) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      await t.pumpWidget(_kabuk(blok()));
      await t.pumpAndSettle();
      expect(hareVar(t), isTrue);
    });

    testWidgets('imleç gezerken fiyat ve tarih imleçten, sonra geri döner',
        (t) async {
      RemoteConfigService.testAcik = {'goz_alici'};
      final imlec = ValueNotifier<(String, String)?>(null);
      addTearDown(imlec.dispose);
      await t.pumpWidget(_kabuk(blok(imlec: imlec)));
      expect(find.bySemanticsLabel('₺206,10'), findsOneWidget);

      imlec.value = ('₺198,40', '3 Mar 2026');
      await t.pump();
      expect(find.bySemanticsLabel('₺198,40'), findsOneWidget);
      expect(find.text('3 Mar 2026'), findsOneWidget);
      expect(find.text('+%2,66 · 1 yıl'), findsNothing);

      imlec.value = null;
      await t.pumpAndSettle();
      expect(find.bySemanticsLabel('₺206,10'), findsOneWidget);
      expect(find.text('+%2,66 · 1 yıl'), findsOneWidget);
    });
  });

  testWidgets('ZoomableChart imleç etiketini dinleyene yazar, bırakınca siler',
      (t) async {
    final imlec = ValueNotifier<(String, String)?>(null);
    addTearDown(imlec.dispose);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ZoomableChart(
          fullMinX: 0,
          fullMaxX: 10,
          height: 200,
          imlecEtiketi: imlec,
          crosshairLabelBuilder: (x) => ('₺${x.round()}', 'gün ${x.round()}'),
          builder: (_, __) => LineChartData(
            minX: 0,
            maxX: 10,
            minY: 0,
            maxY: 10,
            lineBarsData: [
              LineChartBarData(spots: [
                for (var i = 0; i <= 10; i++) FlSpot(i.toDouble(), i / 2),
              ]),
            ],
          ),
        ),
      ),
    ));
    await t.pumpAndSettle();
    final g =
        await t.startGesture(t.getCenter(find.byType(ZoomableChart)));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(imlec.value, isNotNull);
    await g.up();
    await t.pump();
    expect(imlec.value, isNull);
  });
}
