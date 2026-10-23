@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/grafik_cizimi.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/screens/tam_ekran_grafik_screen.dart';
import 'package:portfoy_takip/services/cizim_deposu.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yatay tam ekran grafik (2026-10-23) — GÖRSEL önizleme, `build/gorsel/`
/// altına PNG. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/tam_ekran_grafik_gorsel_test.dart
///
/// Sayılar DEMO'dur: deterministik yapay fiyat yolu, canlı veri değil.
const _gun = 86400000;

List<OhlcBar> _barlar(int bas) {
  var k = 280.0;
  final r = math.Random(7);
  return [
    for (var i = 0; i < 260; i++)
      () {
        final a = k;
        k = a * (1 + 0.012 * math.sin(i / 11) + (r.nextDouble() - 0.5) * 0.03);
        final y = math.max(a, k) * (1 + r.nextDouble() * 0.012);
        final d = math.min(a, k) * (1 - r.nextDouble() * 0.012);
        return OhlcBar(
            t: bas + i * _gun,
            acilis: a,
            enYuksek: y,
            enDusuk: d,
            kapanis: k,
            hacim: 2e6 + r.nextDouble() * 3e6);
      }(),
  ];
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
  });
  tearDown(() {
    MumVerisi.testCekici = null;
    MumVerisi.instance.onbellegiTemizle();
  });

  for (final koyu in [true, false]) {
    testWidgets('tam ekran ${koyu ? 'koyu' : 'açık'}', (tester) async {
      final simdi = DateTime.now();
      final bas = DateTime(simdi.year, simdi.month, simdi.day)
          .subtract(const Duration(days: 259))
          .millisecondsSinceEpoch;
      final m = _barlar(bas);
      var dip = 190;
      for (var i = 190; i < 215; i++) {
        if (m[i].enDusuk < m[dip].enDusuk) dip = i;
      }
      SharedPreferences.setMockInitialValues({});
      MumVerisi.testCekici = (a, ar, b, s) async => m;
      await CizimDeposu.instance.yaz('THYAO.IS', [
        // Destek trendi: dip ile sonraki yükselişin bir dibi arası.
        GrafikCizimi(
            tur: CizimTuru.trend,
            a: CizimNoktasi(m[dip].t, m[dip].enDusuk),
            b: CizimNoktasi(m[dip + 30].t, m[dip + 30].enDusuk)),
        GrafikCizimi(
            tur: CizimTuru.yatayIsin,
            a: CizimNoktasi(m[190].t, m[190].enYuksek)),
        GrafikCizimi(
            tur: CizimTuru.kutu,
            a: CizimNoktasi(m[205].t, m[205].enYuksek * 1.02),
            b: CizimNoktasi(m[222].t, m[222].enDusuk * 0.98)),
      ]);
      final son = m.last.kapanis;

      tester.view.devicePixelRatio = 2;
      tester.view.physicalSize = const Size(844 * 2, 390 * 2);
      addTearDown(tester.view.reset);
      const k = ValueKey('cerceve');
      final palet = koyu ? SandikPalette.dark : SandikPalette.light;
      await tester.pumpWidget(ProviderScope(
        child: RepaintBoundary(
          key: k,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: SandikApp.buildTheme(
                palet, koyu ? Brightness.dark : Brightness.light),
            locale: const Locale('tr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: TamEkranGrafikEkrani(
              varlik: Asset(
                id: 't',
                userId: 'u',
                name: 'Türk Hava Yolları',
                ticker: 'THYAO.IS',
                type: AssetType.hisse,
                quantity: 1,
                purchasePrice: 1,
                currency: 'TRY',
                notes: '',
                isManualPrice: false,
                currentPrice: son,
                addedDate: DateTime(2025),
              ),
              ad: 'THYAO',
              canliBirim: son,
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // Trend çizgisini seç: yüzen sil düğmesi görünsün.
      await tester.tap(find.byTooltip('Trend çizgisi'));
      await tester.pump();
      await tester.tap(find.byTooltip('İmleç'));
      await tester.pump(const Duration(seconds: 5));

      await tester.runAsync(() async {
        final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
        final img = await b.toImage(pixelRatio: 2);
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        Directory('build/gorsel').createSync(recursive: true);
        File('build/gorsel/tam_ekran_${koyu ? 'koyu' : 'acik'}.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 6));
    });
  }
}
