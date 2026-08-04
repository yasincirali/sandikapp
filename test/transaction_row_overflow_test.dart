import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

/// Portföy hareketleri satırının taşma regresyonu.
///
/// **Bug (2026-08-03):** kullanıcı ekranında "BOTTOM OVERFLOWED BY 3.9 PIXELS"
/// görünüyordu. İki ayrı taşma vardı:
///   1. Dikey — sol kolon varsayılan `MainAxisSize.max` ile satır yüksekliğine
///      zorlanıyordu; iki satırlık TEFAS fon başlığı + rozet satırı sığmıyordu.
///   2. Yatay (161px, 320pt ekranda) — rozet satırı (tür + tarih + miktar)
///      dar ekranda tek satıra sığmıyordu. Bunu ilk düzeltme ortaya çıkardı
///      ve YALNIZCA bu test yakaladı; geniş ekranda görünmüyor.
///
/// Test artık GERÇEK `TransactionRow` widget'ını pump ediyor. Önceki sürüm
/// ağacın yapısal kopyasını test ediyordu — kopya bayatlarsa test yeşil
/// kalırken uygulama taşabilirdi.
///
/// Flutter taşmayı exception olarak raporlar; `takeException()` null değilse
/// satır taşmış demektir.

Asset _asset({
  required String name,
  required AssetType type,
  String ticker = '',
  double qty = 486.948,
  AssetKind kind = AssetKind.buy,
  double dividend = 0,
}) =>
    Asset(
      id: 'tx-$name-${kind.name}',
      userId: 'u1',
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 814.5,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 814.5,
      addedDate: DateTime(2026, 7, 24),
      kind: kind,
      dividendAmount: dividend,
    );

Future<void> _pump(
  WidgetTester tester,
  Asset asset, {
  double width = 375,
  bool hideBalance = false,
}) async {
  tester.view.physicalSize = Size(width * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: TransactionRow(
            asset: asset,
            portfolioState: const PortfolioState(),
            hideBalance: hideBalance,
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() async {
    // Satır `DateFormat('d MMM yyyy', 'tr_TR')` kullanıyor; locale verisi
    // yüklenmezse format çağrısı LocaleDataException atar.
    await initializeDateFormatting('tr_TR');
  });

  group('portföy hareketleri satırı — taşma', () {
    testWidgets('uzun fon adı (kullanıcının gördüğü senaryo)', (tester) async {
      await _pump(
        tester,
        _asset(
          name: 'Yapı Kredi Portföy Teknoloji Değişken Fon',
          type: AssetType.fon,
          ticker: 'TEFAS:YKT',
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('kısa hisse kodu', (tester) async {
      await _pump(
        tester,
        _asset(name: 'Türk Hava Yolları', type: AssetType.hisse,
            ticker: 'THYAO.IS', qty: 100),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('temettü satırı — miktar rozeti gizli', (tester) async {
      await _pump(
        tester,
        _asset(
          name: 'Türk Hava Yolları',
          type: AssetType.hisse,
          ticker: 'THYAO.IS',
          qty: 0,
          kind: AssetKind.dividend,
          dividend: 1250,
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('satış satırı', (tester) async {
      await _pump(
        tester,
        _asset(name: 'Aselsan', type: AssetType.hisse,
            ticker: 'ASELS.IS', kind: AssetKind.sell),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('bakiye gizliyken', (tester) async {
      await _pump(
        tester,
        _asset(name: 'Aselsan', type: AssetType.hisse, ticker: 'ASELS.IS'),
        hideBalance: true,
      );
      expect(tester.takeException(), isNull);
    });

    // Asıl koruma: tek bir genişlikte değil, cihaz yelpazesinde taşma yok.
    for (final w in <double>[320, 360, 375, 390, 430]) {
      testWidgets('${w.toInt()}pt ekranda uzun fon adı', (tester) async {
        await _pump(
          tester,
          _asset(
            name: 'İş Portföy Çoklu Varlık Değişken Fon',
            type: AssetType.fon,
            ticker: 'TEFAS:IJC',
          ),
          width: w,
        );
        expect(tester.takeException(), isNull,
            reason: '${w.toInt()}pt ekranda satır taşıyor');
      });
    }

    testWidgets('altın — birim öneki olan varlık', (tester) async {
      await _pump(
        tester,
        _asset(name: 'Gram Altın', type: AssetType.altin, qty: 12.5),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
