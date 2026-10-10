import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/widgets/varlik_guncelle.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Varlığı güncelle" (yasin 2026-10-10): yanlış girilmiş varlık tek kayıtla
/// yeniden yazılır; davranış "sil + yeniden ekle"dir, öncesinde kaç
/// hareketin gideceği söylenir.

Asset _lot(String id, double adet, double fiyat,
        {AssetKind kind = AssetKind.buy,
        String? portfoyId,
        String? sozlesmeId,
        AssetType tur = AssetType.hisse,
        DateTime? tarih}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: tur,
      quantity: adet,
      purchasePrice: fiyat,
      sellPrice: kind == AssetKind.sell ? fiyat : null,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: 300,
      kind: kind,
      portfoyId: portfoyId,
      sozlesmeId: sozlesmeId,
      addedDate: tarih ?? DateTime(2025, 3, 1),
    );

class _Kayit {
  List<Asset>? silinen;
  int ekleme = 0;
  double? miktar;
  String? portfoy;
}

class _SahtePortfoy extends PortfolioNotifier {
  _SahtePortfoy(this.k);
  final _Kayit k;

  @override
  Future<PortfolioState> build() async => const PortfolioState();

  @override
  Future<void> pozisyonuYenidenKur(
      List<Asset> lotlar, Future<void> Function() yeniKayit) async {
    k.silinen = lotlar;
    await yeniKayit();
  }

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
    k.ekleme++;
    k.miktar = quantity;
    k.portfoy = portfoyId;
  }
}

class _Fiyatsiz implements AddAssetPriceLookup {
  const _Fiyatsiz();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

void main() {
  group('görünürlük', () {
    VarlikGuncellemeDurumu d({
      bool bayrak = true,
      bool demo = false,
      bool paywall = true,
      bool admin = false,
      bool kilitli = false,
    }) =>
        varlikGuncellemeDurumu(
            bayrak: bayrak,
            demo: demo,
            paywall: paywall,
            admin: admin,
            premiumKilitli: kilitli);

    test('bayrak kapalıyken herkes için gizli (canlı birebir eski)', () {
      expect(d(bayrak: false), VarlikGuncellemeDurumu.gizli);
      expect(d(bayrak: false, admin: true), VarlikGuncellemeDurumu.gizli);
    });
    test('demo modunda gizli', () {
      expect(d(demo: true), VarlikGuncellemeDurumu.gizli);
    });
    test('paywall kapalıyken yalnız admin görür (tek anahtar kuralı)', () {
      expect(d(paywall: false), VarlikGuncellemeDurumu.gizli);
      expect(d(paywall: false, admin: true), VarlikGuncellemeDurumu.acik);
    });
    test('paywall açık: ücretsizde kilitli, Premium\'da açık', () {
      expect(d(kilitli: true), VarlikGuncellemeDurumu.kilitli);
      expect(d(), VarlikGuncellemeDurumu.acik);
    });
  });

  group('hangi pozisyon güncellenir', () {
    test('düz hisse pozisyonu evet', () {
      final p = aggregatePositions([_lot('a', 10, 100), _lot('b', 5, 120)]);
      expect(varlikGuncellenebilir(p.single.asDisplayAsset(), p.single.lots),
          isTrue);
    });
    test('sözleşmeli (mevduat) hayır: sözleşme kopardı', () {
      final l = _lot('a', 1, 1000, tur: AssetType.mevduat, sozlesmeId: 's1');
      final p = aggregatePositions([l]).single;
      expect(varlikGuncellenebilir(p.asDisplayAsset(), p.lots), isFalse);
    });
    test('lotları iki portföye dağılmış ("Tümü") hayır', () {
      final p = aggregatePositions(
          [_lot('a', 10, 100, portfoyId: 'p1'), _lot('b', 5, 120)]).single;
      expect(p.asDisplayAsset().portfoyKarisik, isTrue);
      expect(varlikGuncellenebilir(p.asDisplayAsset(), p.lots), isFalse);
    });
  });

  group('sil + yeniden ekle', () {
    test('başarıda geri alma çağrılmaz', () async {
      final adimlar = <String>[];
      await silVeYenidenEkle<int>(
        sil: () async {
          adimlar.add('sil');
          return 7;
        },
        ekle: () async => adimlar.add('ekle'),
        geriAl: (_) async => adimlar.add('geriAl'),
      );
      expect(adimlar, ['sil', 'ekle'], reason: 'Önce sil: kota boşalsın');
    });

    test('ekleme düşerse silme makbuzla geri alınır, hata yine fırlar',
        () async {
      int? geriAlinan;
      await expectLater(
        silVeYenidenEkle<int>(
          sil: () async => 7,
          ekle: () async => throw StateError('ağ koptu'),
          geriAl: (m) async => geriAlinan = m,
        ),
        throwsStateError,
      );
      expect(geriAlinan, 7, reason: 'Kullanıcı varlığını kaybetmemeli');
    });

    test('geri alma da düşerse bildirilir, ASIL hata fırlar', () async {
      Object? bildirilen;
      await expectLater(
        silVeYenidenEkle<int>(
          sil: () async => 7,
          ekle: () async => throw StateError('ekleme'),
          geriAl: (_) async => throw ArgumentError('geri alma'),
          geriAlmaHatasi: (e, _) => bildirilen = e,
        ),
        throwsStateError,
      );
      expect(bildirilen, isArgumentError);
    });

    test('silinecek bir şey yoksa (makbuz yok) geri alma denenmez', () async {
      var geriAl = false;
      await expectLater(
        silVeYenidenEkle<int>(
          sil: () async => null,
          ekle: () async => throw StateError('x'),
          geriAl: (_) async => geriAl = true,
        ),
        throwsStateError,
      );
      expect(geriAl, isFalse);
    });
  });

  group('form', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<_Kayit> ac(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      final k = _Kayit();
      final lotlar = [
        _lot('a', 10, 100, portfoyId: 'p1'),
        _lot('b', 5, 120, portfoyId: 'p1'),
        _lot('c', 3, 150, kind: AssetKind.sell, portfoyId: 'p1'),
      ];
      final p = aggregatePositions(lotlar).single;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          portfolioProvider.overrideWith(() => _SahtePortfoy(k)),
          addAssetPriceLookupProvider.overrideWithValue(const _Fiyatsiz()),
        ],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: AddAssetScreen(
            editingAsset: p.asDisplayAsset(),
            yerineGecenLotlar: p.lots,
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      return k;
    }

    testWidgets('uyarı kaydetmeden önce görünür, hareket sayısıyla',
        (tester) async {
      await ac(tester);
      expect(find.text('Varlığı güncelle'), findsOneWidget);
      expect(find.text('Tek kayıt olarak yeniden yazılır'), findsOneWidget);
      expect(find.textContaining('3 hareketi'), findsOneWidget);
    });

    testWidgets('vazgeçince hiçbir şey silinmez', (tester) async {
      final k = await ac(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Güncelle'));
      await tester.pumpAndSettle();
      expect(find.text('3 hareket silinsin mi?'), findsOneWidget);
      await tester.tap(find.text('İptal'));
      await tester.pumpAndSettle();
      expect(k.silinen, isNull);
      expect(k.ekleme, 0);
    });

    testWidgets('onayda lotlar silinir, form TEK kayıt olarak eklenir',
        (tester) async {
      final k = await ac(tester);
      // Net miktar 12 dolu gelir; kullanıcı 20'ye düzeltir.
      final miktar = find.widgetWithText(TextField, '12');
      expect(miktar, findsOneWidget, reason: 'Net miktar (10+5−3) dolu gelmeli');
      await tester.enterText(miktar, '20');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Güncelle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Güncelle').last);
      await tester.pumpAndSettle();
      expect(k.silinen?.map((l) => l.id), ['a', 'b', 'c']);
      expect(k.ekleme, 1);
      expect(k.miktar, 20);
      expect(k.portfoy, 'p1', reason: 'Eski pozisyonun portföyünde kalmalı');
    });
  });
}
