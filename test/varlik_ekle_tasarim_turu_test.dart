import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';

import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Varlık Ekle tasarım turu (Ar-Ge 2026-11-12): toplam alt çubukta ve
/// komisyon dahil (#2), beliriş hareketi ve hareketi azalt (#3), ortalama
/// maliyet satırı (#5), boş fiyat ipucu (#6), 2× yazıda alt çubuk.

class _Portfoy extends PortfolioNotifier {
  _Portfoy(this._assets);
  final List<Asset> _assets;
  @override
  Future<PortfolioState> build() async =>
      PortfolioState(assets: _assets, ownerId: 'ben', usdTry: 42);
}

class _Kapi implements AddAssetPriceLookup {
  const _Kapi([this.fiyat]);
  final double? fiyat;
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => fiyat;
  @override
  Future<String?> companyName(String ticker) async => null;
}

// ignore: unused_element
Asset _gram(double qty, double fiyat, {bool? maliyetBilinmiyor}) {
  final g = GoldSubCategory.gr24;
  return Asset(
    id: 'g$qty',
    userId: 'ben',
    name: g.label,
    ticker: goldTickerMap[g.label]!,
    type: AssetType.altin,
    subCategory: g.label,
    unitType: g.unitType,
    quantity: qty,
    purchasePrice: fiyat,
    currency: 'TRY',
    notes: '',
    addedDate: DateTime(2026, 3, 1),
    maliyetBilinmiyor: maliyetBilinmiyor,
  );
}

Asset _diger({double commission = 0}) => Asset(
      id: 'd1',
      userId: 'ben',
      name: 'Tablo',
      ticker: '',
      type: AssetType.diger,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      commission: commission,
      addedDate: DateTime(2026, 3, 1),
    );

Future<void> _ac(
  WidgetTester tester, {
  required AddAssetScreen ekran,
  List<Asset> lotlar = const [],
  double? spot,
  double genislik = 390,
  double metinOlcegi = 1,
  bool hareketiAzalt = false,
}) async {
  tester.view.physicalSize = Size(genislik * 3, 844 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(() => _Portfoy(lotlar)),
      addAssetPriceLookupProvider.overrideWithValue(_Kapi(spot)),
    ],
    child: MaterialApp(
      theme: ThemeData.dark(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(metinOlcegi),
          disableAnimations: hareketiAzalt,
        ),
        child: child!,
      ),
      home: ekran,
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
}

final _toplam = find.byKey(const ValueKey('alt-cubuk-toplam'));
final _tutar = find.byKey(const ValueKey('alt-cubuk-toplam-tutar'));
// ignore: unused_element
final _ortalama = find.byKey(const ValueKey('form-ortalama-onizleme'));
final _ipucu = find.byKey(const ValueKey('fiyat-bos-ipucu'));

/// Miktar ve fiyat alanları: formdaki ilk iki sayı alanı (yan yana).
Future<void> _yaz(WidgetTester tester,
    {String? miktar, String? fiyat}) async {
  final alanlar = find.byWidgetPredicate((w) =>
      w is TextField &&
      w.keyboardType.index == TextInputType.number.index);
  if (miktar != null) await tester.enterText(alanlar.at(0), miktar);
  if (fiyat != null) await tester.enterText(alanlar.at(1), fiyat);
}

SizeTransition _acilir(WidgetTester tester, Finder icerik) =>
    tester.widget<SizeTransition>(
        find.ancestor(of: icerik, matching: find.byType(SizeTransition)).first);

void main() {
  setUpAll(() async => initializeDateFormatting('tr_TR'));
  setUp(() {
    RemoteConfigService.testAcik = {};
    SharedPreferences.setMockInitialValues({});
  });

  group('#2 toplam alt çubukta', () {
    testWidgets('komisyon dahil, kaydet düğmesinin hemen üstünde',
        (tester) async {
      await _ac(tester, ekran: AddAssetScreen(editingAsset: _diger(commission: 5)));
      expect(_tutar, findsOneWidget);
      expect(tester.widget<Text>(_tutar).data, fmtTRY(1005, digits: 2));
      expect(find.textContaining('komisyon dahil'), findsOneWidget);
      // Formun ortasındaki eski kart yok: toplam yalnız alt çubukta.
      expect(find.text('Toplam maliyet'), findsOneWidget);
      final dugme = find.widgetWithText(FilledButton, 'Güncelle');
      expect(tester.getBottomLeft(_toplam).dy,
          lessThanOrEqualTo(tester.getTopLeft(dugme).dy));
      expect(tester.getTopLeft(dugme).dy - tester.getBottomLeft(_toplam).dy,
          lessThan(24));
    });

    testWidgets('komisyonsuz: döküm adet × fiyat, "komisyon dahil" yok',
        (tester) async {
      await _ac(tester, ekran: AddAssetScreen(editingAsset: _diger()));
      expect(tester.widget<Text>(_tutar).data, fmtTRY(1000, digits: 2));
      expect(find.textContaining('komisyon dahil'), findsNothing);
    });

    testWidgets('ekran okuyucu toplamı tek düğüm okur', (tester) async {
      final h = tester.ensureSemantics();
      await _ac(tester, ekran: AddAssetScreen(editingAsset: _diger(commission: 5)));
      final dugum = tester.getSemantics(_toplam);
      expect(dugum.label, contains('Toplam maliyet'));
      expect(dugum.label, contains(fmtTRY(1005, digits: 2)));
      expect(dugum.label, contains('komisyon dahil'));
      h.dispose();
    });

    testWidgets('2× yazı, 320 pt: taşma yok, tutar kırpılmadan ekranda',
        (tester) async {
      await _ac(tester,
          ekran: AddAssetScreen(editingAsset: _diger(commission: 5)),
          genislik: 320,
          metinOlcegi: 2);
      expect(tester.takeException(), isNull);
      final r = tester.getRect(_tutar);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(320));
      // İki satıra iner: tutar açıklamanın altında.
      expect(r.top,
          greaterThanOrEqualTo(
              tester.getBottomLeft(find.text('Toplam maliyet')).dy));
    });
  });

  group('#3 beliriş hareketi', () {
    testWidgets('miktar ve fiyat yazılınca toplam yükseklikle açılır',
        (tester) async {
      await _ac(tester, ekran: const AddAssetScreen(prefillType: AssetType.diger));
      expect(_toplam, findsNothing);
      await _yaz(tester, miktar: '10', fiyat: '100');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final f = _acilir(tester, _toplam).sizeFactor.value;
      expect(f, greaterThan(0));
      expect(f, lessThan(1), reason: 'Tek karede belirmez, açılır.');
      await tester.pumpAndSettle();
      expect(_acilir(tester, _toplam).sizeFactor.value, 1);
    });

    testWidgets('hareketi azalt: ilk karede tam boy', (tester) async {
      await _ac(tester,
          ekran: const AddAssetScreen(prefillType: AssetType.diger),
          hareketiAzalt: true);
      await _yaz(tester, miktar: '10', fiyat: '100');
      await tester.pump();
      expect(_acilir(tester, _toplam).sizeFactor.value, 1);
    });

    testWidgets('düzenleme formu toplamla açılır, hareket yok', (tester) async {
      await _ac(tester, ekran: AddAssetScreen(editingAsset: _diger()));
      expect(_acilir(tester, _toplam).sizeFactor.value, 1);
    });
  });

  group('#6 boş fiyat ipucu', () {
    testWidgets('yeni kayıtta fiyat boşken görünür, yazınca kapanır',
        (tester) async {
      await _ac(tester, ekran: const AddAssetScreen(prefillType: AssetType.diger));
      expect(_ipucu, findsOneWidget);
      expect(find.text('Boş bırakırsan o günün fiyatı yazılır'), findsOneWidget);
      // Eski amber bilgi kutusu yok.
      await _yaz(tester, miktar: '10');
      await tester.pumpAndSettle();
      expect(find.textContaining('otomatik atanacak'), findsNothing);
      await _yaz(tester, fiyat: '100');
      await tester.pumpAndSettle();
      expect(_ipucu, findsNothing);
    });

    testWidgets('düzenlemede yok', (tester) async {
      final a = _diger();
      a.purchasePrice = 0;
      await _ac(tester, ekran: AddAssetScreen(editingAsset: a));
      expect(_ipucu, findsNothing);
    });
  });
}
