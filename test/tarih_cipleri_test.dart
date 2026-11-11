import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/bugun_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:portfoy_takip/widgets/tarih_cipleri.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// İşlem tarihi hızlı seçim çipleri (2026-11-11): ortak bileşen, Varlık
/// ekle formu ve hızlı al/sat.

typedef _Kayit = ({double fiyat, DateTime? tarih, bool satis});

class _KaydedenPortfoy extends PortfolioNotifier {
  final kayitlar = <_Kayit>[];

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
    String yol = 'form',
    bool maliyetBilinmiyor = false,
  }) async {
    kayitlar.add((fiyat: purchasePrice, tarih: addedDate, satis: false));
  }

  @override
  Future<void> addSellTransaction({
    required Asset asset,
    required double quantity,
    double? sellPrice,
    DateTime? addedDate,
  }) async {
    kayitlar.add((fiyat: sellPrice ?? 0, tarih: addedDate, satis: true));
  }
}

/// Geçmiş kapanış [kapanis] (null → yok), güncel fiyat 100.
class _Kapi implements AddAssetPriceLookup {
  _Kapi({this.kapanis});
  final double? kapanis;
  final sorulanGunler = <DateTime>[];
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async {
    sorulanGunler.add(date);
    return kapanis;
  }

  @override
  Future<double?> spot(String ticker) async => 100;
  @override
  Future<String?> companyName(String ticker) async => 'Şirket';
}

DateTime _dun() {
  final b = dayKey(DateTime.now());
  return DateTime(b.year, b.month, b.day - 1);
}

Finder _cip(String ad) => find.widgetWithText(SandikFiltreCipi, ad);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('hizliTarihler (saf)', () {
    List<(HizliTarihTuru, DateTime)> f(DateTime b) =>
        [for (final s in hizliTarihler(b)) (s.tur, s.gun)];

    test('Salı: dün = Pazartesi = son iş günü → yalnız Bugün · Dün', () {
      expect(f(DateTime(2026, 11, 10, 15)), [
        (HizliTarihTuru.bugun, DateTime(2026, 11, 10)),
        (HizliTarihTuru.dun, DateTime(2026, 11, 9)),
      ]);
    });

    test('Pazartesi: dün Pazar, son iş günü Cuma → üç çip', () {
      expect(f(DateTime(2026, 11, 9)), [
        (HizliTarihTuru.bugun, DateTime(2026, 11, 9)),
        (HizliTarihTuru.dun, DateTime(2026, 11, 8)),
        (HizliTarihTuru.sonIsGunu, DateTime(2026, 11, 6)),
      ]);
    });

    test('Cumartesi: son iş günü bugün değil, dünkü Cuma → tekrar yok', () {
      expect(f(DateTime(2026, 11, 14)).map((e) => e.$1),
          [HizliTarihTuru.bugun, HizliTarihTuru.dun]);
    });

    test('bayram sonrası: Kurban 2027 (16–19 May) → son iş günü 14 May Cuma',
        () {
      expect(f(DateTime(2027, 5, 20)).last,
          (HizliTarihTuru.sonIsGunu, DateTime(2027, 5, 14)));
    });

    test('Ramazan 2026 sonrası: arife (yarım gün) iş günü sayılır', () {
      expect(f(DateTime(2026, 3, 23)).last,
          (HizliTarihTuru.sonIsGunu, DateTime(2026, 3, 19)));
    });

    test('takvim kapsamı dışındaki yıl: son iş günü çipi yok', () {
      expect(BugunService.sonIslemGunu(DateTime(2028, 1, 10)), isNull);
      expect(f(DateTime(2028, 1, 10)).map((e) => e.$1),
          [HizliTarihTuru.bugun, HizliTarihTuru.dun]);
      // Yıl sınırı: kapsanan 2027'nin son Cuma'sı bilinir.
      expect(BugunService.sonIslemGunu(DateTime(2028, 1, 3)),
          DateTime(2027, 12, 31));
    });

    test('sonIsGunu: false → yalnız Bugün · Dün', () {
      expect(
          hizliTarihler(DateTime(2026, 11, 9), sonIsGunu: false), hasLength(2));
    });
  });

  group('TarihCipleri (widget)', () {
    Future<List<DateTime>> ac(WidgetTester tester,
        {required DateTime secili,
        Future<DateTime?> Function()? takvim,
        double yazi = 1}) async {
      final secilen = <DateTime>[];
      await tester.pumpWidget(MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: MediaQuery(
          data: MediaQueryData(
              size: const Size(390, 844), textScaler: TextScaler.linear(yazi)),
          child: Scaffold(
            body: TarihCipleri(
              bugun: DateTime(2026, 11, 9, 10),
              secili: secili,
              onSecildi: secilen.add,
              takvim: takvim,
            ),
          ),
        ),
      ));
      return secilen;
    }

    testWidgets('seçili çipte onay ikonu; son iş günü gün adıyla', (t) async {
      final secilen = await ac(t, secili: DateTime(2026, 11, 9, 10));
      expect(
          find.descendant(
              of: _cip('Bugün'), matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      expect(_cip('Cuma'), findsOneWidget);
      expect(find.bySemanticsLabel('Cuma, son işlem günü'), findsOneWidget);
      expect(find.text('Başka tarih'), findsNothing, reason: 'takvim yok');

      await t.tap(_cip('Cuma'));
      await t.tap(_cip('Dün'));
      expect(secilen, [DateTime(2026, 11, 6), DateTime(2026, 11, 8)]);
    });

    testWidgets('her çip ≥ 44 pt; yazı ×2 taşmaz (yatay kayar)', (t) async {
      await ac(t,
          secili: DateTime(2026, 11, 9), takvim: () async => null, yazi: 2);
      expect(t.takeException(), isNull);
      for (final e in find.byType(SandikFiltreCipi).evaluate()) {
        expect(e.size!.height, greaterThanOrEqualTo(SandikTouch.min));
      }
      expect(find.byType(SingleChildScrollView), findsOneWidget);
    });

    testWidgets('Başka tarih: takvim seçimi döner; seçili tarih çipte yazar',
        (t) async {
      final secilen = await ac(t,
          secili: DateTime(2026, 11, 9),
          takvim: () async => DateTime(2026, 10, 1, 13));
      expect(_cip('Başka tarih'), findsOneWidget);
      await t.tap(_cip('Başka tarih'));
      await t.pump();
      expect(secilen, [DateTime(2026, 10, 1)], reason: 'gün başına çekilir');

      await ac(t, secili: DateTime(2026, 10, 1), takvim: () async => null);
      expect(_cip('1 Eki 2026'), findsOneWidget);
      expect(
          find.descendant(
              of: _cip('1 Eki 2026'),
              matching: find.byIcon(Icons.check_rounded)),
          findsOneWidget);
      expect(find.text('Başka tarih'), findsNothing);
    });
  });

  group('Varlık ekle formu', () {
    Future<(_KaydedenPortfoy, _Kapi)> ac(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final portfoy = _KaydedenPortfoy();
      final kapi = _Kapi(kapanis: 90);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => portfoy),
          addAssetPriceLookupProvider.overrideWithValue(kapi),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const AddAssetScreen(
                            prefillTicker: 'AAPL',
                            prefillType: AssetType.hisse))),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      return (portfoy, kapi);
    }

    Future<void> ekle(WidgetTester tester) async {
      final ekle = find.widgetWithText(FilledButton, 'Ekle');
      await tester.ensureVisible(ekle);
      await tester.tap(ekle);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    }

    testWidgets('varsayılan Bugün: kayıt bugünün tarihiyle', (tester) async {
      final (portfoy, _) = await ac(tester);
      expect(_cip('Bugün'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, '0').first, '2');
      await tester.pump();
      await ekle(tester);
      expect(portfoy.kayitlar, hasLength(1));
      expect(dayKey(portfoy.kayitlar.single.tarih!), dayKey(DateTime.now()));
    });

    testWidgets('Dün: tarih düne yazılır, fiyat o günün kapanışı',
        (tester) async {
      final (portfoy, kapi) = await ac(tester);
      await tester.enterText(find.widgetWithText(TextField, '0').first, '2');
      await tester.ensureVisible(_cip('Dün'));
      await tester.tap(_cip('Dün'));
      await tester.pumpAndSettle(const Duration(milliseconds: 500));
      expect(kapi.sorulanGunler.map(dayKey), contains(_dun()),
          reason: 'geçmiş tarih önizlemesi tetiklendi');
      await ekle(tester);
      expect(portfoy.kayitlar.single.tarih, _dun());
      expect(portfoy.kayitlar.single.fiyat, 90);
    });
  });

  group('Hızlı Al/Sat', () {
    Asset varlik() => Asset(
          id: 'h1',
          userId: 'u',
          name: 'Deneme',
          ticker: 'DENEM.IS',
          type: AssetType.hisse,
          quantity: 500,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 100,
          addedDate: DateTime(2026, 1, 1),
        );

    Future<_KaydedenPortfoy> ac(WidgetTester tester, QuickAdjustMode mod,
        {double? kapanis}) async {
      // 600 pt: test yazı tipinde (Ahem, her harf kare) diyaloğun mevcut
      // "Toplam maliyet" satırı 390 pt'de 11 px taşıyor — bu değişiklikten
      // önce de (doğrulandı); burada ölçülen şey tarih, satır değil.
      tester.view.physicalSize = const Size(1800, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final portfoy = _KaydedenPortfoy();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => portfoy),
          addAssetPriceLookupProvider
              .overrideWithValue(_Kapi(kapanis: kapanis)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => TextButton(
                onPressed: () => showQuickAdjustDialog(context, ref,
                    asset: varlik(), mode: mod),
                child: const Text('ac'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('ac'));
      await tester.pumpAndSettle();
      return portfoy;
    }

    Future<void> onayla(WidgetTester tester, String etiket) async {
      await tester.tap(find.widgetWithText(FilledButton, etiket));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'yalnız Bugün · Dün (takvim yok); varsayılan bugün, tarih '
        'verilmez (eski davranış)', (tester) async {
      final portfoy = await ac(tester, QuickAdjustMode.add, kapanis: 90);
      expect(_cip('Bugün'), findsOneWidget);
      expect(_cip('Dün'), findsOneWidget);
      expect(find.text('Başka tarih'), findsNothing);
      expect(find.byType(SandikFiltreCipi), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).first, '3');
      await onayla(tester, 'Al');
      expect(portfoy.kayitlar.single.tarih, isNull);
      expect(portfoy.kayitlar.single.fiyat, 100);
    });

    testWidgets('Dün: fiyat dünün kapanışıyla dolar, kayıt dünün tarihiyle',
        (tester) async {
      final portfoy = await ac(tester, QuickAdjustMode.add, kapanis: 90);
      await tester.tap(_cip('Dün'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '90'), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, '3');
      await onayla(tester, 'Al');
      expect(portfoy.kayitlar.single.tarih, _dun());
      expect(portfoy.kayitlar.single.fiyat, 90);
    });

    testWidgets('kapanış gelmezse fiyat alanı dokunulmadan kalır',
        (tester) async {
      final portfoy = await ac(tester, QuickAdjustMode.add);
      await tester.tap(_cip('Dün'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '100'), findsOneWidget,
          reason: 'güncel fiyat "dünün kapanışı" diye yazılmaz, alan aynı');
      await tester.enterText(find.byType(TextField).first, '3');
      await onayla(tester, 'Al');
      expect(portfoy.kayitlar.single.tarih, _dun());
      expect(portfoy.kayitlar.single.fiyat, 100);
    });

    testWidgets('elle yazılan fiyat Dün seçilince ezilmez', (tester) async {
      final portfoy = await ac(tester, QuickAdjustMode.add, kapanis: 90);
      await tester.enterText(find.byType(TextField).at(1), '95');
      await tester.tap(_cip('Dün'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '3');
      await onayla(tester, 'Al');
      expect(portfoy.kayitlar.single.fiyat, 95);
      expect(portfoy.kayitlar.single.tarih, _dun());
    });

    testWidgets('Satışta Dün: kayıt dünün tarihi ve kapanışıyla',
        (tester) async {
      final portfoy = await ac(tester, QuickAdjustMode.remove, kapanis: 90);
      await tester.tap(_cip('Dün'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '10');
      await onayla(tester, 'Sat');
      expect(portfoy.kayitlar.single.satis, isTrue);
      expect(portfoy.kayitlar.single.tarih, _dun());
      expect(portfoy.kayitlar.single.fiyat, 90);
    });
  });
}
