import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/bulk_cart_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/bulk_add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// UI/UX inceleme turu 20 (2026-11-26 07:03): ücretsiz varlık sınırı anı.
///
/// #1 "kalanı sepette bırak" sığmayanları silmesin; #2 satın alma sonrası
/// seçilen hedef açıkken form KENDİ rotasını kapatsın; #3 Premium seçilip
/// paywall kapatılınca kota sheet'i bir kez daha sorsun; #5 hiç kalem
/// sığmadığında ayrı gövde; #6 son üç hak satırı paywall'a gitsin.

class _SahtePortfoy extends PortfolioNotifier {
  final List<String> eklenen = [];

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
    eklenen.add(name);
  }
}

BulkCartItem _kalem(int i) => BulkCartItem(
      id: 'id-$i',
      type: AssetType.hisse,
      name: 'Varlik $i',
      ticker: 'HIS$i.IS',
      quantity: 1,
      price: 100,
      currency: 'TRY',
      addedDate: DateTime.now(),
      isManualPrice: true,
    );

Future<(ProviderContainer, _SahtePortfoy)> _kur(
    WidgetTester tester, int kalemSayisi,
    {int kullanilan = 0}) async {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  final portfoy = _SahtePortfoy();
  final container = ProviderContainer(overrides: [
    portfolioProvider.overrideWith(() => portfoy),
    varlikKotasiProvider
        .overrideWithValue((kullanilan: kullanilan, sinir: 10)),
    kotaAnahtarlariProvider.overrideWithValue(
        {for (var i = 0; i < kullanilan; i++) 'dolu-$i'}),
  ]);
  addTearDown(container.dispose);
  final sepet = container.read(bulkCartProvider.notifier);
  for (var i = 0; i < kalemSayisi; i++) {
    sepet.add(_kalem(i));
  }

  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThemeData.dark(),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<bool>(
                builder: (_) => const BulkAddAssetScreen())),
            child: const Text('aç'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('aç'));
  await tester.pumpAndSettle();
  return (container, portfoy);
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // Paywall açılmaz, `show` null döner: "satın almadan kapattı".
    RemoteConfigService.testKapali = {'paywall_enabled'};
  });
  tearDown(() => RemoteConfigService.testKapali = {});

  testWidgets('#1 12 kalem, 10 sığar: sığanları kaydet → sepette 2 kalır',
      (tester) async {
    final (container, portfoy) = await _kur(tester, 12);

    await tester.tap(find.text('Tümünü kaydet (12)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 kalemi kaydet, kalanı sepette bırak'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(portfoy.eklenen, hasLength(10));
    expect(container.read(bulkCartProvider), hasLength(2));
    expect(find.text('2 kalem sepette bekliyor'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 2));
  });

  testWidgets('#3 Premium seçilip paywall kapanınca sheet bir kez daha sorar',
      (tester) async {
    final (container, portfoy) = await _kur(tester, 12);

    await tester.tap(find.text('Tümünü kaydet (12)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text("Premium'a geç, hepsini ekle"));
    await tester.pumpAndSettle();
    // İkinci soru geldi.
    expect(find.text("Premium'a geç, hepsini ekle"), findsOneWidget);

    await tester.tap(find.text("Premium'a geç, hepsini ekle"));
    await tester.pumpAndSettle();
    // Döngü yok: üçüncü kez sorulmaz, hiçbir şey yazılmaz.
    expect(find.text("Premium'a geç, hepsini ekle"), findsNothing);
    expect(portfoy.eklenen, isEmpty);
    expect(container.read(bulkCartProvider), hasLength(12));
  });

  testWidgets('#5 hiç kalem sığmıyorsa ayrı gövde', (tester) async {
    await _kur(tester, 2, kullanilan: 10);

    await tester.tap(find.text('Tümünü kaydet (2)'));
    await tester.pumpAndSettle();
    expect(
        find.text("Ücretsiz plandaki 10 varlık dolu. Sepetteki 2 kalem "
            "Premium'la eklenir; sepet bekler."),
        findsOneWidget);
    expect(find.textContaining('0 tanesi sığıyor'), findsNothing);
  });

  testWidgets('#2 kendiRotasiniKapat üstteki rotayı değil kendi rotasını kapatır',
      (tester) async {
    late BuildContext formCtx;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('kök')),
    ));
    final sonuc = nav.currentState!.push<Object?>(MaterialPageRoute(
        builder: (ctx) {
      formCtx = ctx;
      return const Scaffold(body: Text('form'));
    }));
    await tester.pumpAndSettle();
    nav.currentState!.push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('hedef'))));
    await tester.pumpAndSettle();

    kendiRotasiniKapat(formCtx, true);
    await tester.pumpAndSettle();

    expect(find.text('hedef'), findsOneWidget);
    expect(await sonuc, true);
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    // Form yığından gitti: hedef kapanınca köke dönülür.
    expect(find.text('kök'), findsOneWidget);
    expect(find.text('form', skipOffstage: false), findsNothing);
  });

  testWidgets('#2 rota üstteyse bugünkü pop', (tester) async {
    late BuildContext formCtx;
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: const Scaffold(body: Text('kök')),
    ));
    final sonuc = nav.currentState!.push<Object?>(MaterialPageRoute(
        builder: (ctx) {
      formCtx = ctx;
      return const Scaffold(body: Text('form'));
    }));
    await tester.pumpAndSettle();
    kendiRotasiniKapat(formCtx, 'x');
    await tester.pumpAndSettle();
    expect(await sonuc, 'x');
    expect(find.text('kök'), findsOneWidget);
  });

  test('#2 formun ve toplu eklemenin kapanışı kendi rotasından', () {
    final form = ekranKaynagiSync('lib/screens/add_asset_screen.dart');
    expect(form, contains('kendiRotasiniKapat(context, sonuc);'));
    expect(form, isNot(contains('Navigator.pop(context, sonuc)')));
    expect(form, isNot(contains('Navigator.of(context).pop(true)')));
    final toplu = ekranKaynagiSync('lib/screens/bulk_add_asset_screen.dart');
    expect(toplu, contains('kendiRotasiniKapat(context, true);'));
    expect(toplu, isNot(contains('Navigator.of(context).pop(true)')));
  });

  test('#6 son üç hak satırı paywall açar, etiketli ve ≥44 pt', () {
    final src = ekranKaynagiSync('lib/screens/add_asset_screen.dart');
    final i = src.indexOf('l.varlikKotasiKalan(kalan, kota.sinir)');
    expect(i, greaterThan(0));
    final blok = src.substring(i - 1400, i + 400);
    expect(blok, contains("source: 'asset_limit_form'"));
    expect(blok, contains('label: l.varlikKotasiPremiumuGor'));
    expect(blok, contains('SandikTouch.min'));
    expect(blok, contains('Icons.chevron_right_rounded'));
  });
}
