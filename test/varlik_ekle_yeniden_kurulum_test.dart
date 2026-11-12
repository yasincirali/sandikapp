import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset/tur_secici_izgara.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/portfoy_secici.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle: bir tuş vuruşu formun neresini yeniden kurar (Ar-Ge
/// 2026-11-12 #4).
///
/// Ölçüm `debugOnRebuildDirtyWidget` ile: Flutter her `Element.rebuild`'de
/// (kirli ya da üstü yeni yapılandırma verdiği için zorla) bu kancayı
/// çağırır. Tuş vuruşu = miktar alanına tek `enterText` + bir kare.
///
/// Önce (6bb875b, tek `ListenableBuilder` bütün gövdeyi sarıyordu): tür
/// ızgarası 1, kimlik alanı 1, portföy seçici 1 — her harfte üçü de.
/// Sonra: üçü de 0; dinleyici yalnız toplam/ortalama satırında, önizleme
/// kartında, önayar çiplerinde ve not rozetinde. Sayı artarsa biri geniş
/// dinleyiciyi geri getirmiştir.

class _Portfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async =>
      const PortfolioState(ownerId: 'ben');
}

class _Kapi implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => 100;
  @override
  Future<String?> companyName(String ticker) async => null;
}

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() {
    RemoteConfigService.testAcik = {};
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => debugOnRebuildDirtyWidget = null);

  testWidgets('miktar yazmak tür ızgarasını, kimliği, portföy seçiciyi '
      'yeniden kurmaz', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(_Portfoy.new),
        addAssetPriceLookupProvider.overrideWithValue(_Kapi()),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(),
        home: const AddAssetScreen(
          prefillTicker: 'AAPL',
          prefillType: AssetType.hisse,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    final sayac = <String, int>{'izgara': 0, 'kimlik': 0, 'portfoy': 0};
    debugOnRebuildDirtyWidget = (e, _) {
      final w = e.widget;
      if (w is TurSeciciIzgara) sayac['izgara'] = sayac['izgara']! + 1;
      if (w is PortfoyFormSecici) sayac['portfoy'] = sayac['portfoy']! + 1;
      if (w.key == const ValueKey('kimlik-alani')) {
        sayac['kimlik'] = sayac['kimlik']! + 1;
      }
    };

    final miktar = find.widgetWithText(TextField, '0').first;
    await tester.enterText(miktar, '5');
    await tester.pump();
    // ignore: avoid_print
    print('Tuş başına yeniden kurulum: $sayac');

    expect(sayac, {'izgara': 0, 'kimlik': 0, 'portfoy': 0});
  });
}
