import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/widgets/tour_anchor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle tür çiplerinin sırası (kullanıcı kararı 2026-09-25):
/// Hisse, Döviz, Altın, Fon, Kripto, Emtia, Diğer.
///
/// Sıra enum'dan (`AssetType.values`) ayrı bir listede; enum sırası uygulamanın
/// geri kalanını (filtre çipleri, tür dökümü) sıralamaya devam eder. Ayrı liste
/// tutmanın riski: yeni tür enum'a eklenip buraya eklenmezse seçicide hiç
/// görünmez. İlk test bunu yakalar.
class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

void main() {
  test('ekleme sırası her türü tam bir kez içerir', () {
    expect(AssetType.eklemeSirasi.toSet(), AssetType.values.toSet(),
        reason: 'Enum\'a eklenen tür `eklemeSirasi`na yazılmazsa Varlık '
            'Ekle seçicisinde görünmez.');
    expect(AssetType.eklemeSirasi.length, AssetType.values.length);
  });

  test('ekleme sırası kullanıcının istediği sıra', () {
    expect(AssetType.eklemeSirasi, [
      AssetType.hisse,
      AssetType.doviz,
      AssetType.altin,
      AssetType.fon,
      AssetType.kripto,
      AssetType.emtia,
      AssetType.diger,
    ]);
  });

  testWidgets('Varlık Ekle çipleri bu sırayla çizilir', (tester) async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(375 * 3, 812 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _BosPortfoy()),
        addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
      ],
      child: MaterialApp(theme: ThemeData.dark(), home: const AddAssetScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final secici = find.byWidgetPredicate(
        (w) => w is TourAnchor && w.target == TourTarget.turSecici);
    // Yatay kaydırmalı satır: ekran dışındaki çip de yerleşir, x'i büyür.
    final xler = [
      for (final t in AssetType.eklemeSirasi)
        tester
            .getTopLeft(find.descendant(of: secici, matching: find.text(t.label)))
            .dx,
    ];
    for (var i = 1; i < xler.length; i++) {
      expect(xler[i], greaterThan(xler[i - 1]),
          reason: '${AssetType.eklemeSirasi[i].label} '
              '${AssetType.eklemeSirasi[i - 1].label}\'dan sonra gelmeli');
    }
  });
}
