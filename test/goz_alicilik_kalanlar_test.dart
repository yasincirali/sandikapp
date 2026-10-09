import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/screens/recap_screen.dart';
import 'package:portfoy_takip/services/recap_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/hikaye_akisi.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// Göz alıcılığın kalanları (2026-10-09):
/// - Portföy varlık detayında büyük fiyat imleci izler; başlığa giden etiket
///   grafiğin etiketinden ayrı kurulabilir (varlığın hane sayısı).
/// - Yıllık özet ortak hikâye kabuğunda; davranış eskisiyle aynı.
void main() {
  testWidgets('imlecEtiketiBuilder verilince başlığa o yazılır', (t) async {
    final imlec = ValueNotifier<(String, String)?>(null);
    addTearDown(imlec.dispose);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ZoomableChart(
          fullMinX: 0,
          fullMaxX: 10,
          height: 200,
          imlecEtiketi: imlec,
          crosshairLabelBuilder: (x) => ('₺${x.round()},00', 'grafik'),
          imlecEtiketiBuilder: (x) => ('₺${x.round()},000000', 'başlık'),
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
    final g = await t.startGesture(t.getCenter(find.byType(ZoomableChart)));
    await t.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(imlec.value?.$2, 'başlık');
    expect(imlec.value?.$1, endsWith(',000000'));
    await g.up();
    await t.pump();
    expect(imlec.value, isNull);
  });

  testWidgets('yıllık özet ortak kabukta: çubuklar, Devam, son sayfada Paylaş',
      (t) async {
    const veri = RecapData(
      period: 'yearly',
      character: PortfolioCharacter.hisseci,
      trackedDays: 3,
      typeCount: 1,
      changePct: 12.4,
    );
    await t.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      locale: const Locale('tr'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RecapScreen(data: veri, year: 2026),
    ));
    await t.pumpAndSettle();
    final l10n = AppLocalizations.of(t.element(find.byType(RecapScreen)))!;
    expect(find.byType(HikayeAkisi), findsOneWidget);
    expect(find.byTooltip('Kapat'), findsOneWidget);
    // Açılış + karakter + değişim: üç sayfa.
    await t.tap(find.text(l10n.hkyDevam));
    await t.pumpAndSettle();
    expect(find.text('Hisseci'), findsOneWidget);
    await t.tap(find.text(l10n.hkyDevam));
    await t.pumpAndSettle();
    expect(find.text('+%12,4'), findsOneWidget);
    expect(find.text(l10n.shareWord), findsOneWidget);
  });
}
