@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/fon_xray_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/fon_dagilimi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/zirve_icerik_karti.dart';
import 'package:portfoy_takip/widgets/zirve_varlik_siralamasi.dart';

/// Zirve portföy ayrıntısı GÖRSEL önizlemesi (2026-10-20): Varlıklar
/// listesi, altında "Fonların içi açılınca" (önce = yalnız liste).
///   flutter test --run-skipped --dart-define=CIKTI=build/gorsel_zi \
///     test/zirve_icerik_gorsel_test.dart
const _cikti = String.fromEnvironment('CIKTI', defaultValue: 'build/gorsel');

FonDagilimi _d(String kod, Map<String, double> d) => FonDagilimi(
    fonKodu: kod, fonTipi: 'YAT', tarih: DateTime(2026, 10, 20), dagilim: d);

final _dagilimlar = {
  'AFT': _d('AFT', const {'yhs': 92.4, 'tpp': 6.1, 'vmtl': 1.5}),
  'IPB': _d('IPB', const {'hs': 88.2, 'tr': 9.3, 'dt': 2.5}),
  'AEA': _d('AEA', const {'dt': 46.0, 'km': 31.5, 'hs': 18.0, 'tpp': 4.5}),
  'AHE': _d('AHE', const {'hs': 71.0, 'kks': 20.0, 'tpp': 9.0}),
};

const _pay = {
  'fon': 38.0,
  'hisse': 27.0,
  'bes': 18.0,
  'kripto': 9.0,
  'altin': 5.0,
  'doviz': 3.0,
};
const _fon = {'AFT': 21.0, 'IPB': 14.0, 'DIGER': 3.0};
const _varlik = {
  'hisse': {'THYAO.IS': 12.0, 'ASELS.IS': 9.0, 'DIGER': 6.0},
  'bes': {'AEA': 11.0, 'AHE': 7.0},
  'kripto': {'BTCUSDT': 6.0, 'ETHUSDT': 3.0},
  'altin': {'ALTIN_GRAM': 5.0},
  'doviz': {'USDTRY=X': 2.0, 'EURTRY=X': 1.0},
};
const _adlar = {
  'AFT': 'Ak Portföy Yeni Teknolojiler Yabancı Hisse Senedi Fonu',
  'IPB': 'İş Portföy BIST Banka Endeksi Hisse Senedi Fonu',
  'AEA': 'Anadolu Hayat Emeklilik Dengeli Fon',
  'AHE': 'Anadolu Hayat Emeklilik Hisse Senedi Fonu',
};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
    final ikon = FontLoader('MaterialIcons')
      ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
    await ikon.load();
  });

  Future<void> ciz(WidgetTester tester, String ad,
      {required bool koyu, required double olcek, required bool sonra}) async {
    final boy = olcek > 1 ? 2600.0 : 1500.0;
    tester.view.physicalSize = Size(390 * 2, boy * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    final p = koyu ? SandikPalette.dark : SandikPalette.light;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        fonXrayGorunurProvider.overrideWithValue(true),
        premiumKilitliProvider.overrideWithValue(false),
        zirveFonDagilimlariProvider
            .overrideWith((ref, kodlar) async => _dagilimlar),
      ],
      child: RepaintBoundary(
        key: k,
        child: MediaQuery(
          data: MediaQueryData(
              size: Size(390, boy), textScaler: TextScaler.linear(olcek)),
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: SandikApp.buildTheme(
                p, koyu ? Brightness.dark : Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('tr'),
            home: Scaffold(
              body: SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SandikSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SandikSectionHeader(title: 'VARLIKLAR'),
                      const SizedBox(height: SandikSpace.sm),
                      ZirveVarlikSiralamasi(
                        pay: _pay,
                        fonDetay: _fon,
                        varlikDetay: _varlik,
                        gruplu: true,
                        adBul: (kod) async => _adlar[kod],
                      ),
                      if (sonra)
                        const ZirveIcerikKarti(
                            pay: _pay, fonDetay: _fon, varlikDetay: _varlik),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 2.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_cikti).createSync(recursive: true);
      File('$_cikti/$ad.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final sonra in [false, true]) {
    for (final koyu in [true, false]) {
      for (final olcek in [1.0, 2.0]) {
        final ad = '${sonra ? 'sonra' : 'once'}_'
            '${koyu ? 'koyu' : 'acik'}_${olcek.toStringAsFixed(1)}x';
        testWidgets(ad,
            (t) => ciz(t, ad, koyu: koyu, olcek: olcek, sonra: sonra));
      }
    }
  }
}
