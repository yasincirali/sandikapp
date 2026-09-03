import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/comparison_screen.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Karşılaştırma ekranı — işlem butonlarının doğru duruma göre çıkması.
///
/// Kural: sahip OLUNMAYAN varlıkta "Portföyüme ekle", sahip olunanda
/// "Al"/"Sat", portföy serilerinde HİÇBİRİ (kendi portföyünü satın almak
/// anlamsız).

Asset _asset({
  required String ticker,
  required String name,
  AssetType type = AssetType.hisse,
  double qty = 10,
}) =>
    Asset(
      id: 'a-$ticker',
      userId: 'u1',
      name: name,
      ticker: ticker,
      type: type,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 120,
      addedDate: DateTime(2026, 1, 1),
      kind: AssetKind.buy,
    );

class _FakePortfolio extends PortfolioNotifier {
  _FakePortfolio(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async => PortfolioState(
        assets: _assets,
        usdTry: 42.0,
        eurTry: 46.0,
        gbpTry: 54.0,
      );
}

/// Hiç tamamlanmayan portföy — kalıcı `AsyncLoading` durumu.
class _NeverLoadsPortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() => Completer<PortfolioState>().future;
}

Widget _wrap(List<Asset> portfolio) => ProviderScope(
      overrides: [
        portfolioProvider.overrideWith(() => _FakePortfolio(portfolio)),
      ],
      child: const MaterialApp(home: ComparisonScreen()),
    );

/// Portföy sağlayıcısının çözülmesini bekler.
///
/// `PortfolioNotifier.build()` async: ekran ilk çizildiğinde provider hâlâ
/// `AsyncLoading` durumundadır ve `_positionFor` içindeki `valueOrNull`
/// null döner — yani "sahip olunan varlık" bile sahipsiz görünür. Testin
/// provider'ı ÖNCE okuyup çözülmesini beklemesi gerekiyor.
Future<void> _settlePortfolio(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ComparisonScreen)),
  );
  await container.read(portfolioProvider.future);
  await tester.pump();
}

/// Ekranı kurup verilen sembolü listeye ekler.
///
/// Ağ yok — seri çekilemeyecek ve satır "veri yok" gösterecek. Testin
/// ilgilendiği şey seri değil, BUTONLAR; onlar seriden bağımsız çizilir.
Future<void> _addSymbol(WidgetTester tester, SymbolHit hit) async {
  final state = tester.state(find.byType(ComparisonScreen));
  // ignore: avoid_dynamic_calls
  await (state as dynamic).addForTest(hit);
  // `pumpAndSettle` KULLANILAMAZ: seri çekilemediğinde satırda sonsuz
  // dönen bir spinner kalabiliyor ve settle zaman aşımına düşüyor.
  // İki `pump` yeterli — biri setState'i, biri yeniden çizimi işler.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  // Grafiğin zaman ekseni Türkçe tarih basıyor; locale verisi
  // uygulamada `main.dart` içinde yükleniyor, widget testinde
  // burada. (Kod tabanındaki yerleşik desen.)
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  const thyao =
      SymbolHit(ticker: 'THYAO.IS', name: 'Türk Hava Yolları', source: 'BIST');
  const garan =
      SymbolHit(ticker: 'GARAN.IS', name: 'Garanti BBVA', source: 'BIST');

  testWidgets('sahip OLUNMAYAN varlıkta "Portföyüme ekle" çıkar',
      (tester) async {
    await tester.pumpWidget(_wrap([]));
    await tester.pumpAndSettle();
    await _settlePortfolio(tester);

    await _addSymbol(tester, thyao);

    expect(find.text('Portföyüme ekle'), findsOneWidget);
    expect(find.text('Al'), findsNothing);
    expect(find.text('Sat'), findsNothing);
  });

  testWidgets('sahip OLUNAN varlıkta "Al" ve "Sat" çıkar', (tester) async {
    await tester.pumpWidget(_wrap([
      _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları'),
    ]));
    await tester.pumpAndSettle();
    await _settlePortfolio(tester);

    await _addSymbol(tester, thyao);

    expect(find.text('Al'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
    expect(find.text('Portföyüme ekle'), findsNothing);
  });

  testWidgets('tamamı satılmış pozisyon SAHİP sayılmaz', (tester) async {
    // Net miktar sıfır → "Sat" gösterilmemeli, "ekle" çıkmalı.
    await tester.pumpWidget(_wrap([
      _asset(ticker: 'THYAO.IS', name: 'Türk Hava Yolları', qty: 10),
      Asset(
        id: 'a-sell',
        userId: 'u1',
        name: 'Türk Hava Yolları',
        ticker: 'THYAO.IS',
        type: AssetType.hisse,
        quantity: 10,
        purchasePrice: 130,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 130,
        addedDate: DateTime(2026, 2, 1),
        kind: AssetKind.sell,
      ),
    ]));
    await tester.pumpAndSettle();
    await _settlePortfolio(tester);

    await _addSymbol(tester, thyao);

    expect(find.text('Portföyüme ekle'), findsOneWidget);
    expect(find.text('Sat'), findsNothing);
  });

  testWidgets('başka bir varlığa sahip olmak butonu değiştirmez',
      (tester) async {
    // GARAN'a sahip ama THYAO'ya değil → THYAO satırında "ekle" olmalı.
    await tester.pumpWidget(_wrap([
      _asset(ticker: 'GARAN.IS', name: 'Garanti BBVA'),
    ]));
    await tester.pumpAndSettle();
    await _settlePortfolio(tester);

    await _addSymbol(tester, thyao);

    expect(find.text('Portföyüme ekle'), findsOneWidget);
    expect(find.text('Al'), findsNothing);
  });

  testWidgets('portföy serisinde işlem butonu ÇIKMAZ', (tester) async {
    await tester.pumpWidget(_wrap([
      _asset(ticker: 'GARAN.IS', name: 'Garanti BBVA'),
    ]));
    await tester.pumpAndSettle();
    await _settlePortfolio(tester);

    await _addSymbol(
      tester,
      const SymbolHit(
        ticker: PortfolioSeries.mine,
        name: 'Tüm varlıklarımın toplam getirisi',
        source: 'Portföy',
      ),
    );

    expect(find.text('Portföyüme ekle'), findsNothing);
    expect(find.text('Al'), findsNothing);
    expect(find.text('Sat'), findsNothing);
  });

  testWidgets('portföy YÜKLENİRKEN hiçbir buton gösterilmez', (tester) async {
    // Düzeltilen hata: yükleme sırasında `valueOrNull` null döndüğü için
    // sahip OLUNAN varlıkta bile "Portföyüme ekle" çıkıyordu; kullanıcı
    // ona basıp aynı varlık için ikinci kayıt açardı.
    //
    // Hiç tamamlanmayan bir provider: gerçek AsyncLoading durumu. Normal
    // fake ile bu yakalanamıyor çünkü pump'lar arasında çözülüyor.
    await tester.pumpWidget(ProviderScope(
      overrides: [portfolioProvider.overrideWith(_NeverLoadsPortfolio.new)],
      child: const MaterialApp(home: ComparisonScreen()),
    ));
    await tester.pump();

    await _addSymbol(tester, thyao);

    expect(find.text('Portföyüme ekle'), findsNothing,
        reason: 'yükleme bitmeden yanlış buton gösterilmemeli');
    expect(find.text('Al'), findsNothing);
    expect(find.text('Sat'), findsNothing);
  });

  testWidgets('iki varlık: biri sahip, biri değil — butonlar ayrışır',
      (tester) async {
    await tester.pumpWidget(_wrap([
      _asset(ticker: 'GARAN.IS', name: 'Garanti BBVA'),
    ]));
    await tester.pumpAndSettle();
    await _settlePortfolio(tester);

    await _addSymbol(tester, garan); // sahip
    await _addSymbol(tester, thyao); // değil

    expect(find.text('Al'), findsOneWidget);
    expect(find.text('Sat'), findsOneWidget);
    expect(find.text('Portföyüme ekle'), findsOneWidget);
  });
}
