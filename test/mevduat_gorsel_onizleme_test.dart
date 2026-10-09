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
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/mevduat_bankasi.dart';
import 'package:portfoy_takip/providers/mevduat_banka_provider.dart';
import 'package:portfoy_takip/screens/add_asset/mevduat_formu.dart';
import 'package:portfoy_takip/services/db_logger.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Mevduat banka seçicinin (bayrak `mevduat_banka_secici`) önce/sonra
/// görselleri — `build/gorsel/`. Assert etmez (`gorsel` etiketi CI'da
/// atlanır). Elle: flutter test --tags gorsel test/mevduat_gorsel_onizleme_test.dart
///
/// Faiz ortalaması ÖRNEK veridir (TCMB değeri değil): görsel, formun
/// davranışını gösterir.
const _bankalar = [
  MevduatBankasi(kod: 'ziraat', ad: 'Ziraat Bankası', katilim: false),
  MevduatBankasi(kod: 'isbank', ad: 'İş Bankası', katilim: false),
  MevduatBankasi(kod: 'garanti', ad: 'Garanti BBVA', katilim: false),
  MevduatBankasi(kod: 'akbank', ad: 'Akbank', katilim: false),
  MevduatBankasi(kod: 'yapikredi', ad: 'Yapı Kredi', katilim: false),
  MevduatBankasi(kod: 'vakifbank', ad: 'VakıfBank', katilim: false),
  MevduatBankasi(kod: 'halkbank', ad: 'Halkbank', katilim: false),
  MevduatBankasi(kod: 'qnb', ad: 'QNB', katilim: false),
  MevduatBankasi(kod: 'enpara', ad: 'Enpara', katilim: false),
  MevduatBankasi(kod: 'denizbank', ad: 'DenizBank', katilim: false),
  MevduatBankasi(kod: 'teb', ad: 'TEB', katilim: false),
  MevduatBankasi(kod: 'kuveytturk', ad: 'Kuveyt Türk', katilim: true),
  MevduatBankasi(kod: 'turkiyefinans', ad: 'Türkiye Finans', katilim: true),
];

final _ortalamalar = {
  for (final (d, f) in [('ay1', 41.2), ('ay3', 40.1), ('ay6', 37.5), ('yil1', 33.0)])
    d: MevduatFaizOrtalamasi(
        dilim: d, yillikBilesik: f, veriTarihi: DateTime(2026, 10, 2)),
};

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
    DbLogger.silentInTests = true;
  });
  tearDownAll(() {
    DbLogger.silentInTests = false;
    RemoteConfigService.testAcik = {};
  });
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<void> ciz(WidgetTester tester, String ad,
      {required bool bayrak,
      bool acik = false,
      double yukseklik = 1180,
      Future<void> Function()? sonra}) async {
    RemoteConfigService.testAcik = bayrak ? {'mevduat_banka_secici'} : {};
    tester.view.physicalSize = Size(390 * 2, yukseklik * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    const k = ValueKey('kok');
    final p = acik ? SandikPalette.light : SandikPalette.dark;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        mevduatKaynaklariProvider.overrideWith(
            (ref) async => (bankalar: _bankalar, ortalamalar: _ortalamalar)),
      ],
      child: RepaintBoundary(
        key: k,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: SandikApp.buildTheme(
              p, acik ? Brightness.light : Brightness.dark),
          home: const Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(SandikSpace.lgs),
                child: MevduatFormu(),
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    if (sonra != null) await sonra();
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/mevduat_$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> bekle(WidgetTester tester) async {
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> doldur(WidgetTester tester, String banka) async {
    await tester.tap(find.byType(TextField).first);
    await bekle(tester);
    await tester.tap(find.text(banka).last);
    await bekle(tester);
    await tester.enterText(find.byType(TextField).at(1), '250.000');
    await tester.enterText(
        find.byType(TextField).last, 'Maaş müşterisi kampanyası, 3. ay');
    FocusManager.instance.primaryFocus?.unfocus();
    await bekle(tester);
  }

  testWidgets('önce: bugünkü form', (tester) async {
    await ciz(tester, '1_once', bayrak: false, sonra: () async {
      await tester.enterText(find.byType(TextField).first, 'Akbank');
      await tester.enterText(find.byType(TextField).at(1), '250.000');
      FocusManager.instance.primaryFocus?.unfocus();
    });
  });

  testWidgets('sonra: banka seçici', (tester) async {
    await ciz(tester, '2_secici', bayrak: true, yukseklik: 844,
        sonra: () async {
      await tester.tap(find.byType(TextField).first);
      await bekle(tester);
    });
  });

  testWidgets('sonra: banka seçildi, faiz önerildi, not', (tester) async {
    await ciz(tester, '3_doldu', bayrak: true,
        sonra: () => doldur(tester, 'Akbank'));
  });

  testWidgets('sonra: kendi oranı', (tester) async {
    await ciz(tester, '4_elle', bayrak: true, sonra: () async {
      await doldur(tester, 'Akbank');
      await tester.enterText(find.byType(TextField).at(2), '45');
      FocusManager.instance.primaryFocus?.unfocus();
    });
  });

  testWidgets('sonra: katılım bankası', (tester) async {
    await ciz(tester, '5_katilim', bayrak: true,
        sonra: () => doldur(tester, 'Kuveyt Türk'));
  });

  testWidgets('sonra: açık tema', (tester) async {
    await ciz(tester, '6_acik', bayrak: true, acik: true,
        sonra: () => doldur(tester, 'Garanti BBVA'));
  });
}
