import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/abd_hisseleri.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:portfoy_takip/utils/piyasa_kapali_etiketi.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ABD hissesi (bayrak `abd_hisse`, 2026-10-08).
///
/// Karar: yeni bir [AssetType] DEĞİL — `type='hisse'`, `sub_category='abd'`,
/// `currency='USD'`, sembol Yahoo'nunki. Bu test hem yeni yolu hem de
/// bayrak KAPALIYKEN her şeyin birebir eski kaldığını kilitler.
class _SahteFiyat implements AddAssetPriceLookup {
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

/// Kaydı yakalar — ABD lot'unun sunucuya hangi alanlarla gideceği.
class _KaydedenPortfoy extends PortfolioNotifier {
  final kayitlar = <Map<String, Object?>>[];

  @override
  Future<PortfolioState> build() async => const PortfolioState();

  @override
  Future<void> addAsset({
    required String name,
    required String ticker,
    required AssetType type,
    required double quantity,
    required double purchasePrice,
    required String currency,
    required String notes,
    required bool isManualPrice,
    String? subCategory,
    String unitType = 'piece',
    DateTime? addedDate,
    double? initialCurrentPrice,
    double commission = 0,
    String? sozlesmeId,
    String? portfoyId,
  }) async {
    kayitlar.add({
      'ticker': ticker,
      'type': type,
      'currency': currency,
      'subCategory': subCategory,
      'name': name,
    });
  }
}

Asset _lot({
  String ticker = 'AAPL',
  String? sub = 'abd',
  String currency = 'USD',
  AssetType type = AssetType.hisse,
}) =>
    Asset(
      id: ticker,
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: type,
      quantity: 10,
      purchasePrice: 100,
      currency: currency,
      notes: '',
      subCategory: sub,
      purchaseFxRate: 40,
      addedDate: DateTime(2026, 1, 2),
    );

void main() {
  tearDown(() {
    RemoteConfigService.testAcik = {};
    SymbolSearchService.clearCacheForTest();
  });

  group('katalog', () {
    test('~150+ kâğıt, sembol biçimi Yahoo (sınıf hissesi tireli)', () {
      expect(abdHisseleri.length, greaterThanOrEqualTo(150));
      final bicim = RegExp(r'^[A-Z]{1,5}(-[A-Z])?$');
      for (final s in abdHisseleri.keys) {
        expect(bicim.hasMatch(s), isTrue, reason: '$s Yahoo biçiminde değil');
      }
      expect(abdHisseleri, contains('BRK-B'));
      expect(abdHisseleri.keys.where((s) => s.contains('.')), isEmpty);
    });

    test('ad boş değil; BIST listesiyle çakışma yok', () {
      for (final e in abdHisseleri.entries) {
        expect(e.value.trim(), isNotEmpty, reason: e.key);
        expect(bist100StocksMap.containsKey(e.key), isFalse, reason: e.key);
      }
    });

    test('popüler ETF ve adlar listede', () {
      for (final s in const [
        'SPY', 'QQQ', 'VOO', 'VTI', 'IVV', 'SCHD', 'VYM', 'DIA', 'IWM', //
        'GLD', 'SLV', 'TLT', 'ARKK', 'SOXX', 'SMH', 'XLK', 'XLF', 'XLE',
        'VEA', 'VWO', 'BND', 'PLTR', 'TSLA', 'NVDA', 'AMD', 'COIN', 'MSTR',
        'HOOD', 'SOFI', 'RIVN', 'NIO', 'BABA', 'TSM', 'ASML',
      ]) {
        expect(abdHisseleri, contains(s));
      }
    });

    test('abdSembolu: büyük harf, nokta → tire, boşluksuz', () {
      expect(abdSembolu(' brk.b '), 'BRK-B');
      expect(abdSembolu('aapl'), 'AAPL');
    });
  });

  group('model', () {
    test('Asset.abdHissesi: hisse + alt kategori abd', () {
      expect(_lot().abdHissesi, isTrue);
      expect(_lot(sub: null).abdHissesi, isFalse,
          reason: 'bayraktan önce elle girilmiş USD hisse ABD sayılmaz');
      expect(_lot(sub: 'BIST Hisseleri', ticker: 'THYAO.IS', currency: 'TRY')
          .abdHissesi, isFalse);
      expect(_lot(type: AssetType.fon).abdHissesi, isFalse);
    });

    test('Position.abdHissesi temsilci lot\'tan', () {
      final p = aggregatePositions([_lot()]).single;
      expect(p.abdHissesi, isTrue);
    });

    test('fiyat yolu mevcut Yahoo + USDTRY yolu (paralel yol yok)', () {
      final a = _lot();
      expect(FiyatKaynagi.usdKote(a), isTrue);
      expect(FiyatKaynagi.seriSembolleri(a), ['AAPL', FiyatKaynagi.usdTry]);
      // Temettü olayı yalnız `.IS` için aranır; USD temettüsünü TL'ye
      // çevirecek ödeme günü kuru yok (bilinçli, değişmedi).
      expect(FiyatKaynagi.temettuSembolu(a), isNull);
    });

    test('takip anahtarı: abd pazar etiketidir, kimlik sembol', () {
      final aapl = WatchlistItem(
        id: '1',
        userId: 'u',
        ticker: 'AAPL',
        name: 'Apple',
        type: AssetType.hisse,
        subCategory: 'abd',
        currency: 'USD',
        addedAt: DateTime(2026),
      );
      expect(aapl.key, 'hisse|AAPL');
      expect(
          varlikAnahtari(
              type: AssetType.hisse, ticker: 'MSFT', subCategory: 'abd'),
          'hisse|MSFT');
      // Öteki alt kategoriler birebir eski kural.
      expect(
          varlikAnahtari(
              type: AssetType.altin,
              ticker: 'ALTIN_CEYREK',
              subCategory: 'Çeyrek Altın'),
          'altin|sub:ÇEYREK ALTIN');
    });

    test('ABD lot\'u varsa "borsa kapalı" denmez (BIST takvimi ABD\'yi bilmez)',
        () {
      expect(
          yalnizcaBorsaVarliklardan(
              [_lot(ticker: 'THYAO.IS', sub: null, currency: 'TRY')]),
          isTrue);
      expect(
          yalnizcaBorsaVarliklardan([
            _lot(ticker: 'THYAO.IS', sub: null, currency: 'TRY'),
            _lot(),
          ]),
          isFalse);
    });
  });

  group('arama', () {
    final svc = SymbolSearchService.instance;

    test('bayrak KAPALI: ABD listelenmez (birebir eski)', () {
      final r = svc.yerelAra('apple');
      expect(r.where((h) => h.source == SymbolSearchService.abdKaynagi),
          isEmpty);
      expect(svc.yerelAra('NVDA'), isEmpty);
    });

    test('bayrak AÇIK: ABD sonucu ABD etiketiyle gelir', () async {
      RemoteConfigService.testAcik = {'abd_hisse'};
      final r = await svc.search('NVDA');
      final hit = r.firstWhere((h) => h.ticker == 'NVDA');
      expect(hit.source, SymbolSearchService.abdKaynagi);
      expect(hit.name, 'NVIDIA');
    });

    test('belirsiz sorguda BIST önce', () {
      RemoteConfigService.testAcik = {'abd_hisse'};
      final r = svc.yerelAra('ar');
      final sonBist = r.lastIndexWhere((h) => h.source == 'BIST');
      final ilkAbd =
          r.indexWhere((h) => h.source == SymbolSearchService.abdKaynagi);
      expect(sonBist, isNonNegative);
      expect(ilkAbd, isNonNegative);
      expect(sonBist, lessThan(ilkAbd));
    });

    test('bayrak sonradan açılırsa önbellek eski sonucu dönmez', () async {
      expect(
          (await svc.search('tesla')).where((h) => h.ticker == 'TSLA'),
          isEmpty);
      RemoteConfigService.testAcik = {'abd_hisse'};
      expect(
          (await svc.search('tesla')).map((h) => h.ticker), contains('TSLA'));
    });

    test('ABD sonucu USD kote hisse kimliği olur (alt kategorisiz)', () {
      final k = VarlikKimligi.fromSymbolHit(const SymbolHit(
          ticker: 'AAPL', name: 'Apple', source: SymbolSearchService.abdKaynagi))!;
      expect(k.type, AssetType.hisse);
      expect(k.currency, 'USD');
      expect(k.subCategory, isNull);
      expect(k.key, 'hisse|AAPL');
    });
  });

  group('ekleme formu', () {
    ProviderContainer kur() {
      final c = ProviderContainer(overrides: [
        addAssetPriceLookupProvider.overrideWithValue(_SahteFiyat()),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('bayrak KAPALI: durum ABD bilmez, serbest sembol eski kural', () {
      final c = kur();
      final args = AddAssetFormArgs(prefillType: AssetType.hisse);
      final n = c.read(addAssetFormProvider(args).notifier);
      expect(c.read(addAssetFormProvider(args)).abdAcik, isFalse);
      // Pazar seçimi bayraksız durumda etkisiz: ABD'ye geçilemez.
      n.selectHisseBorsasi(abd: true);
      n.tickerTyped('AAPL');
      final s = c.read(addAssetFormProvider(args));
      expect(s.isAbd, isFalse);
      expect(s.subCategory, StockSubCategory.other.label);
      expect(s.currency, 'TRY');
    });

    test('ABD seçimi: alt kategori abd, USD, sembol Yahoo biçiminde', () {
      RemoteConfigService.testAcik = {'abd_hisse'};
      final c = kur();
      final args = AddAssetFormArgs(prefillType: AssetType.hisse);
      final n = c.read(addAssetFormProvider(args).notifier);
      final temizle = n.selectHisseBorsasi(abd: true);
      expect(temizle.ticker, '');
      var s = c.read(addAssetFormProvider(args));
      expect(s.isAbd, isTrue);
      expect(s.subCategory, 'abd');
      expect(s.currency, 'USD');

      // Para birimi kilitli.
      n.setCurrency('TRY');
      expect(c.read(addAssetFormProvider(args)).currency, 'USD');

      // Serbest sembol pazarı değiştirmez; nokta tireye döner.
      n.tickerTyped('brk.b');
      s = c.read(addAssetFormProvider(args));
      expect(s.subCategory, 'abd');
      final kimlik = s.resolveIdentity(nameText: '', tickerText: 'brk.b');
      expect(kimlik.ticker, 'BRK-B');
      expect(kimlik.name, 'Berkshire Hathaway (B)');
      expect(kimlik.manual, isFalse);
      expect(s.resolveTicker('brk.b'), 'BRK-B');
      expect(s.kimlikEksigi(tickerText: ''), KimlikEksigi.hisse);
      expect(s.kimlikEksigi(tickerText: 'AAPL'), isNull);
    });

    test('katalogdan seçim adı ve sembolü yazar', () {
      RemoteConfigService.testAcik = {'abd_hisse'};
      final c = kur();
      final args = AddAssetFormArgs(prefillType: AssetType.hisse);
      final n = c.read(addAssetFormProvider(args).notifier);
      n.selectHisseBorsasi(abd: true);
      final y = n.selectAbdHisse('MSFT');
      expect(y.ticker, 'MSFT');
      expect(y.name, 'Microsoft');
    });

    test('BIST\'e dönüş: alt kategori boş, TRY', () {
      RemoteConfigService.testAcik = {'abd_hisse'};
      final c = kur();
      final args = AddAssetFormArgs(prefillType: AssetType.hisse);
      final n = c.read(addAssetFormProvider(args).notifier);
      n.selectHisseBorsasi(abd: true);
      n.selectHisseBorsasi(abd: false);
      final s = c.read(addAssetFormProvider(args));
      expect(s.isAbd, isFalse);
      expect(s.subCategory, isNull);
      expect(s.currency, 'TRY');
    });

    test('aramadan gelen ABD prefill: ABD pazarı + USD', () {
      final s = AddAssetFormState.initial(
        prefillTicker: 'AAPL',
        prefillType: AssetType.hisse,
        abdAcik: true,
      );
      expect(s.isAbd, isTrue);
      expect(s.currency, 'USD');
      // Bayrak kapalıyken aynı prefill birebir eski.
      final eski = AddAssetFormState.initial(
        prefillTicker: 'AAPL',
        prefillType: AssetType.hisse,
      );
      expect(eski.subCategory, isNull);
      expect(eski.currency, AssetType.hisse.defaultCurrency);
    });
  });

  group('ekran', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<_KaydedenPortfoy> ac(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final portfoy = _KaydedenPortfoy();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => portfoy),
          addAssetPriceLookupProvider.overrideWithValue(_SahteFiyat()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: const AddAssetScreen(),
        ),
      ));
      await tester.pump();
      return portfoy;
    }

    testWidgets('bayrak KAPALI: pazar seçimi yok', (tester) async {
      await ac(tester);
      expect(find.byType(SandikSegment), findsNothing);
      expect(find.text('ABD'), findsNothing);
    });

    testWidgets('bayrak AÇIK: ABD seçilir, USD kilitli, kayıt abd + USD',
        (tester) async {
      RemoteConfigService.testAcik = {'abd_hisse'};
      final portfoy = await ac(tester);
      expect(find.byType(SandikSegment), findsOneWidget);

      await tester.tap(find.text('ABD'));
      await tester.pumpAndSettle();
      expect(find.text('ABD hissesi seçmek için dokun...'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Sembol yaz (örn: AAPL, BRK-B)'),
          'brk.b');
      await tester.enterText(find.widgetWithText(TextField, '0').first, '3');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Otomatik').first, '500');
      await tester.pump();
      // Açılır liste yerine sabit "USD".
      expect(find.byType(DropdownButton<String>), findsNothing);
      expect(find.text('USD'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Ekle'));
      await tester.pumpAndSettle();

      expect(portfoy.kayitlar, hasLength(1));
      final k = portfoy.kayitlar.single;
      expect(k['ticker'], 'BRK-B');
      expect(k['type'], AssetType.hisse);
      expect(k['currency'], 'USD');
      expect(k['subCategory'], 'abd');
      expect(k['name'], 'Berkshire Hathaway (B)');
    });
  });
}
