import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_monogrami.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/para_metni.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

/// Göz alıcılık paketi A (2026-10-09): `varlik_rozeti` + `akan_rakam`.
///
/// Sözleşme: bayrak kapalıyken görünüş birebir eski; açıkken satırda
/// sembolün kendisi, büyük fiyatta yalnız değişen hane döner, ekran okuyucu
/// tek metin okur, "hareketi azalt" açıkken hiç dönmez.
Asset _asset({String ticker = 'ASELS.IS', AssetType type = AssetType.hisse}) =>
    Asset(
      id: 'a-$ticker',
      userId: 'u1',
      name: 'Aselsan',
      ticker: ticker,
      type: type,
      quantity: 10,
      purchasePrice: 100,
      sellPrice: 0,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 120,
      addedDate: DateTime(2026, 7, 24, 14, 29),
    );

Future<void> _satir(WidgetTester tester, Asset a) => tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: TransactionRow(
            asset: a,
            portfolioState: const PortfolioState(),
          ),
        ),
      ),
    );

Widget _metin(String m, {Object? kimlik, bool hareketiAzalt = false}) =>
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: hareketiAzalt),
        child: Scaffold(
          body: Center(
            child: ParaMetni(
              m,
              kimlik: kimlik,
              stil: const TextStyle(color: Color(0xFFF5C842)),
            ),
          ),
        ),
      ),
    );

/// Dönüş sürerken hane kutusunda iki rakam (eski + yeni) üst üste durur.
bool _donuyor(WidgetTester tester) => find
    .descendant(of: find.byType(ParaMetni), matching: find.byType(ClipRect))
    .evaluate()
    .isNotEmpty;

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  tearDown(() => RemoteConfigService.testAcik = {});

  group('varlikMonogrami', () {
    test('hisse, fon, kripto: önek ve .IS atılır, ilk üç karakter', () {
      expect(varlikMonogrami(type: AssetType.hisse, ticker: 'ASELS.IS'),
          'ASE');
      expect(varlikMonogrami(type: AssetType.hisse, ticker: 'THYAO'), 'THY');
      expect(varlikMonogrami(type: AssetType.fon, ticker: 'TEFAS:DLY'), 'DLY');
      expect(
          varlikMonogrami(type: AssetType.kripto, ticker: 'KRIPTO:BTC'), 'BTC');
      expect(varlikMonogrami(type: AssetType.hisse, ticker: 'AAPL'), 'AAP');
    });

    test('sembolü anlamsız türler ikonda kalır (uydurma rozet yok)', () {
      expect(
          varlikMonogrami(type: AssetType.altin, ticker: 'ALTIN_CEYREK'), null);
      expect(
          varlikMonogrami(
              type: AssetType.eurobond, ticker: 'EUROBOND:US900123DG28'),
          null);
      expect(varlikMonogrami(type: AssetType.mevduat, ticker: 'MEVDUAT:x'),
          null);
      expect(varlikMonogrami(type: AssetType.hisse, ticker: 'X'), null);
      expect(varlikMonogrami(type: AssetType.hisse, ticker: ''), null);
    });
  });

  group('varlik_rozeti — hareket satırı', () {
    testWidgets('kapalıyken tür ikonu, sembol yazılmaz', (tester) async {
      await _satir(tester, _asset());
      expect(find.byIcon(AssetType.hisse.icon), findsOneWidget);
      expect(find.text('ASE'), findsNothing);
    });

    testWidgets('açıkken sembol rozeti, ikon yok', (tester) async {
      RemoteConfigService.testAcik = {'varlik_rozeti'};
      await _satir(tester, _asset());
      expect(find.text('ASE'), findsOneWidget);
      expect(find.byIcon(AssetType.hisse.icon), findsNothing);
    });

    testWidgets('açıkken de altın ikonda kalır', (tester) async {
      RemoteConfigService.testAcik = {'varlik_rozeti'};
      await _satir(
          tester, _asset(ticker: 'ALTIN_GRAM', type: AssetType.altin));
      expect(find.byIcon(AssetType.altin.icon), findsOneWidget);
    });
  });

  group('ParaMetni', () {
    testWidgets('ekran okuyucu tek metin okur; ilk çizimde dönmez',
        (tester) async {
      await tester.pumpWidget(_metin('₺206,10'));
      expect(find.bySemanticsLabel('₺206,10'), findsOneWidget);
      expect(_donuyor(tester), isFalse);
    });

    testWidgets('değişen hane döner, sonra yerine oturur', (tester) async {
      await tester.pumpWidget(_metin('₺206,10'));
      await tester.pumpWidget(_metin('₺207,10'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_donuyor(tester), isTrue);
      await tester.pumpAndSettle();
      expect(_donuyor(tester), isFalse);
      expect(find.bySemanticsLabel('₺207,10'), findsOneWidget);
    });

    testWidgets('hareketi azalt açıkken hiç dönmez', (tester) async {
      await tester.pumpWidget(_metin('₺206,10', hareketiAzalt: true));
      await tester.pumpWidget(_metin('₺207,10', hareketiAzalt: true));
      await tester.pump();
      expect(_donuyor(tester), isFalse);
    });

    testWidgets('başka varlığın fiyatı dönmez (kimlik değişti)',
        (tester) async {
      await tester.pumpWidget(_metin('₺206,10', kimlik: 'a'));
      await tester.pumpWidget(_metin('₺207,10', kimlik: 'b'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(_donuyor(tester), isFalse);
    });

    testWidgets('rakamsız metin düz yazılır', (tester) async {
      await tester.pumpWidget(_metin('—'));
      expect(find.text('—'), findsOneWidget);
    });

    testWidgets('simge ve kuruş rakamdan küçük', (tester) async {
      await tester.pumpWidget(_metin('₺748.722,40'));
      final simge = tester.getSize(find.text('₺'));
      final rakam = tester.getSize(find.text('7').first);
      final kurus = tester.getSize(find.text('4').last);
      expect(simge.height, lessThan(rakam.height));
      expect(kurus.height, lessThan(rakam.height));
    });
  });
}
