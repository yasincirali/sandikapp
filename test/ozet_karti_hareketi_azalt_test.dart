import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/portfolio_summary_widget.dart';

/// Hareketi azalt açıkken özet kartının yüksekliği değişince çökmemeli.
///
/// ## Neden
/// Kart yükseklik geçişini `AnimatedSize` ile yapıyordu; süre
/// `SandikMotion.stateOf` ile sıfıra iniyordu. Sıfır süreli `AnimatedSize`
/// boyut değişiminde kendi layout'u içinde yeniden kirlenip assert'le
/// düşer. Integration duman testi (animasyonu kapalı emülatör) #35'ten beri
/// bu yüzden kırmızıydı: "giriş → varlık ekle → portföyde görünür".
Asset _lot(String id, {AssetKind kind = AssetKind.buy, double? sellPrice}) =>
    Asset(
      id: id,
      userId: 'ben',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: kind == AssetKind.sell ? 4 : 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
      kind: kind,
      sellPrice: sellPrice,
    );

Widget _kart(PortfolioState state, {required bool azalt}) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: azalt),
          child: Scaffold(
            body: SingleChildScrollView(
              child: PortfolioSummaryWidget(state: state),
            ),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  final yalnizAlim = PortfolioState(assets: [_lot('b1')]);
  // Satış "gerçekleşen" satırını ekler → kart uzar.
  final satisli = PortfolioState(assets: [
    _lot('b1'),
    _lot('s1', kind: AssetKind.sell, sellPrice: 130),
  ]);

  for (final azalt in [true, false]) {
    testWidgets('kart uzayıp kısalınca hata yok (hareketi azalt: $azalt)',
        (tester) async {
      await tester.pumpWidget(_kart(yalnizAlim, azalt: azalt));
      final ilk = tester.getSize(find.byType(PortfolioSummaryWidget)).height;

      await tester.pumpWidget(_kart(satisli, azalt: azalt));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final uzun = tester.getSize(find.byType(PortfolioSummaryWidget)).height;
      expect(uzun, greaterThan(ilk),
          reason: 'senaryo kartın yüksekliğini değiştirmeli');

      await tester.pumpWidget(_kart(yalnizAlim, azalt: azalt));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
