import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/providers/signal_provider.dart';
import 'package:portfoy_takip/screens/performance_screen.dart';

/// Yeniden biçimlendirilen sinyal şeridi dar ekranda taşmamalı.
///
/// Şerit 2026-09-10'da nötr kart diline çevrildi: sol renkli çizgi + daire
/// içinde ikon + üç satır metin + sağda zaman etiketi. Yatay eksende artık
/// daha çok öğe var.
///
/// **Neden gerekli:** aynı sınıf bir test bu ekranda daha önce GERÇEK
/// taşmalar buldu (141px ve 266px). Emülatör Flutter'ı render edemediği
/// için (bkz. CLAUDE.md) taşmayı gözle görmenin yolu yok.
class _SahteSinyaller extends SignalNotifier {
  _SahteSinyaller(this._veri);
  final List<SignalAlert> _veri;

  @override
  Future<List<SignalAlert>> build() async => _veri;
}

Asset _asset() => Asset(
      id: 'lot-1',
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
    );

SignalAlert _alert() => SignalAlert(
      assetId: 'sunucu-lot',
      assetName: 'Türk Hava Yolları',
      assetTicker: 'THYAO.IS',
      assetType: AssetType.hisse,
      signal: SignalType.sell,
      // En geniş hâl: iki haneli sayaçlar + üç haneli güven.
      buyCount: 12,
      sellCount: 34,
      confidence: 100,
      detectedAt: DateTime.now().subtract(const Duration(hours: 5)),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  // Genişliği `SizedBox` ile DAYAT: `tester.view.physicalSize` dıştaki
  // MaterialApp'in MediaQuery'si tarafından eziliyor ve test dar ekranı
  // hiç sınamıyordu (2026-09-10'da ölçülerek bulundu — ekran genişliği
  // 0.0 çıkmıştı).
  for (final (genislik, olcek) in const [
    (320.0, 1.0),
    (320.0, 1.6),
    (390.0, 2.0),
  ]) {
    testWidgets('şerit taşmaz — ${genislik.toInt()}pt × $olcek',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            signalProvider.overrideWith(() => _SahteSinyaller([_alert()])),
          ],
          child: MaterialApp(
            theme: ThemeData.dark(),
            home: MediaQuery(
              data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
              child: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: genislik,
                    child: SingleChildScrollView(
                      child: AssetSignalCard(asset: _asset(), onTap: () {}),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
