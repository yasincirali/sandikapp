import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/hizli_hesap.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/screens/add_asset_screen.dart';
import 'package:portfoy_takip/screens/genel_arama_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Genel aramada hızlı hesap ("5 çeyrek", "100 dolar"), 2026-10-24.
///
/// Değişmezler: yalnız TAM kalıp ("sayı + bilinen birim") tanınır; sayı
/// formla aynı kuralla (`parseTrNumber`) okunur; fon/hisse ve ons yok;
/// fiyat yoksa tutar yok. Form ön seçimi o tür + miktarla açılır.

class _FakePortfolio extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => PortfolioState(
      assets: const <Asset>[], usdTry: 42.0, eurTry: 46.0, gbpTry: 54.0);
}

class _NoLookup implements AddAssetPriceLookup {
  const _NoLookup();
  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => null;
  @override
  Future<String?> companyName(String ticker) async => null;
}

Future<void> _pump(WidgetTester tester, Widget ekran) async {
  tester.view.physicalSize = const Size(375 * 3, 812 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      portfolioProvider.overrideWith(_FakePortfolio.new),
      addAssetPriceLookupProvider.overrideWithValue(const _NoLookup()),
    ],
    child: MaterialApp(theme: ThemeData.dark(), home: ekran),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

const _abd = VarlikKimligi(
    ticker: 'APPL', name: 'Apple', type: AssetType.hisse, currency: 'USD');
const _kripto = VarlikKimligi(
    ticker: 'KRIPTO:BTC',
    name: 'Bitcoin',
    type: AssetType.kripto,
    currency: 'TRY');

bool _alanVar(WidgetTester t, String metin) => t
    .widgetList<EditableText>(find.byType(EditableText))
    .any((e) => e.controller.text == metin);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('hizliHesapCoz', () {
    test('altın türleri: ad, ek ve aksansız yazım', () {
      expect(hizliHesapCoz('5 çeyrek'),
          const HizliHesap(miktar: 5, altin: GoldSubCategory.ceyrek));
      expect(hizliHesapCoz('5 ceyrek altin'),
          const HizliHesap(miktar: 5, altin: GoldSubCategory.ceyrek));
      expect(hizliHesapCoz('  2  Yarım Altın '),
          const HizliHesap(miktar: 2, altin: GoldSubCategory.yarim));
      expect(hizliHesapCoz('1 tam')?.altin, GoldSubCategory.tam);
      expect(hizliHesapCoz('3 cumhuriyet altını')?.altin,
          GoldSubCategory.cumhuriyet);
      expect(hizliHesapCoz('1 ata')?.altin, GoldSubCategory.ata);
      expect(hizliHesapCoz('1 reşat')?.altin, GoldSubCategory.resat);
      expect(hizliHesapCoz('1 beşli')?.altin, GoldSubCategory.besli);
      expect(hizliHesapCoz('1 gremse')?.altin, GoldSubCategory.gremse);
      expect(hizliHesapCoz('1 ikibuçuk')?.altin, GoldSubCategory.ikibucuk);
      expect(hizliHesapCoz('10 gram 22 ayar')?.altin, GoldSubCategory.gr22);
      expect(hizliHesapCoz('4 has altın')?.altin, GoldSubCategory.has);
    });

    test('"gram" yalnız başına 24 ayar (piyasadaki "gram altın")', () {
      expect(hizliHesapCoz('10 gram')?.altin, GoldSubCategory.gr24);
      expect(hizliHesapCoz('10 gram altın')?.altin, GoldSubCategory.gr24);
      expect(hizliHesapCoz('10 gr')?.altin, GoldSubCategory.gr24);
    });

    test('dövizler: yalnız USD/EUR/GBP ve eş anlamlıları', () {
      for (final g in ['100 dolar', '100 USD', '100 abd doları']) {
        expect(hizliHesapCoz(g), const HizliHesap(miktar: 100, doviz: 'USD'),
            reason: g);
      }
      for (final g in ['50 euro', '50 avro', '50 EUR']) {
        expect(hizliHesapCoz(g)?.doviz, 'EUR', reason: g);
      }
      for (final g in ['20 sterlin', '20 GBP', '20 İngiliz sterlini']) {
        expect(hizliHesapCoz(g)?.doviz, 'GBP', reason: g);
      }
      expect(hizliHesapCoz('100 frank'), isNull);
      expect(hizliHesapCoz('100 chf'), isNull);
      expect(hizliHesapCoz('100 yen'), isNull);
      // Döviz etiketi `dovizOptions`'ta olmalı; yoksa `dovizOptFor` sessizce
      // USD'ye düşer ve sterlin yazan dolar görürdü.
      for (final g in ['1 dolar', '1 euro', '1 sterlin']) {
        expect(dovizOptions.map((o) => o.label),
            contains(hizliHesapCoz(g)!.doviz));
      }
    });

    test('sayı formla aynı kuralla okunur (parseTrNumber)', () {
      expect(hizliHesapCoz('1.000 dolar')?.miktar, 1000);
      expect(hizliHesapCoz('2,5 gram')?.miktar, 2.5);
      expect(hizliHesapCoz('1.234,5 euro')?.miktar, 1234.5);
      expect(hizliHesapCoz('5çeyrek')?.miktar, 5);
    });

    test('kalıp dışı her şey null: arama bozulmaz', () {
      for (final g in [
        '',
        '5',
        'çeyrek',
        'çeyrek 5',
        '5 altın', // hangi altın belirsiz: uydurma tür seçilmez
        '5 ons', // USD kote, ≈ ₺ ikinci çevrim isterdi
        '0 çeyrek',
        '5 çeyrek aldım',
        '100 THYAO',
        '2025 raporu',
        '3 ay',
        '10 adet',
        '-5 dolar',
      ]) {
        expect(hizliHesapCoz(g), isNull, reason: g);
      }
    });

    // İkinci adım (2026-10-25): ters yön ve hisse/fon adedi.
    test('ters: "<sayı> tl|₺ <birim>" TL tutarıdır', () {
      expect(hizliHesapCoz('10.000 tl çeyrek'),
          const HizliHesap(
              miktar: 10000, altin: GoldSubCategory.ceyrek, ters: true));
      expect(hizliHesapCoz('10000 TL dolar'),
          const HizliHesap(miktar: 10000, doviz: 'USD', ters: true));
      expect(hizliHesapCoz('5000 ₺ gram'),
          const HizliHesap(miktar: 5000, altin: GoldSubCategory.gr24, ters: true));
      expect(hizliHesapCoz('5000₺ gram altın')?.altin, GoldSubCategory.gr24);
      expect(hizliHesapCoz('2.500,5 tl euro')?.miktar, 2500.5);
      expect(hizliHesapCoz('10.000tl cumhuriyet altını')?.ters, isTrue);
      for (final g in [
        '10 tl', // birim yok
        '10 tl ons',
        '10 tl frank',
        '0 tl çeyrek',
        '10 tl çeyrek aldım',
        '10 tlx çeyrek',
        '10 tl 5 çeyrek',
      ]) {
        expect(hizliHesapCoz(g), isNull, reason: g);
      }
    });

    test('ters: adet SATIŞ fiyatından; satış yoksa null', () {
      const h = HizliHesap(
          miktar: 10000, altin: GoldSubCategory.ceyrek, ters: true);
      expect(h.alinabilecekAdet(4000), 2.5);
      expect(h.alinabilecekAdet(null), isNull);
      expect(h.alinabilecekAdet(0), isNull);
      // Ters kalıpta "≈ ₺" anlamsız; miktar TL, forma adet diye yazılmaz.
      expect(h.tutar(4000), isNull);
      expect(h.adetOnDolgu, isNull);
      expect(const HizliHesap(miktar: 5, altin: GoldSubCategory.ceyrek)
          .alinabilecekAdet(4000), isNull);
    });

    const thy = VarlikKimligi(
        ticker: 'THYAO.IS',
        name: 'Türk Hava Yolları',
        type: AssetType.hisse,
        currency: 'TRY');
    const aft = VarlikKimligi(
        ticker: 'TEFAS:AFT',
        name: 'Ak Portföy Yeni Teknolojiler',
        type: AssetType.fon,
        currency: 'TRY');
    VarlikKimligi? bul(String kod) =>
        {'THYAO': thy, 'AFT': aft, 'APPL': _abd, 'BTC': _kripto}[kod];

    test('adet: yalnız birebir BIST hissesi / TEFAS fonu', () {
      expect(hizliHesapCoz('100 THYAO', sembolBul: bul),
          const HizliHesap(miktar: 100, kimlik: thy));
      expect(hizliHesapCoz('100 thyao', sembolBul: bul)?.tur, AssetType.hisse);
      expect(hizliHesapCoz('1000 AFT', sembolBul: bul)?.kimlik?.ticker,
          'TEFAS:AFT');
      expect(hizliHesapCoz('1.000 aft', sembolBul: bul)?.miktar, 1000);
      for (final g in [
        '100 THYAO', // kaynak verilmedi: sembol tahmin edilmez
      ]) {
        expect(hizliHesapCoz(g), isNull, reason: g);
      }
      for (final g in [
        '100 THY', // yarım kod
        '100 THYAOX',
        '100 APPL', // ABD hissesi: TL kote değil, kapsam BIST + TEFAS
        '100 BTC', // kripto
        '2025 raporu',
        '3 ay',
        '10 tl',
        '10 adet',
        '100 thy hava',
        'THYAO 100',
        '0 THYAO',
      ]) {
        expect(hizliHesapCoz(g, sembolBul: bul), isNull, reason: g);
      }
      // Kaynak gevşek eşleşse bile (kodu "THY" için THYAO döndürse)
      // ayrıştırıcı birebirliği kendisi denetler.
      expect(hizliHesapCoz('100 THY', sembolBul: (_) => thy), isNull);
      // Altın/döviz birimi koddan önce gelir: "100 usd" döviz kalır.
      expect(hizliHesapCoz('100 usd', sembolBul: bul)?.doviz, 'USD');
    });

    test('kod adayı: biçim + bilinen sözcük elemesi', () {
      expect(hizliHesapKodAdayi('100 thyao'), 'THYAO');
      expect(hizliHesapKodAdayi('1000 AFT'), 'AFT');
      expect(hizliHesapKodAdayi('100 dolar'), isNull);
      expect(hizliHesapKodAdayi('5 çeyrek'), isNull);
      expect(hizliHesapKodAdayi('10 tl'), isNull);
      expect(hizliHesapKodAdayi('3 ay'), isNull);
      expect(hizliHesapKodAdayi('100 thy hava'), isNull);
      expect(hizliHesapKodAdayi('THYAO'), isNull);
      expect(hizliHesapKodAdayi('0 THYAO'), isNull);
    });

    test('tutar: fiyat bilinmiyorsa null (uydurma sayı yok)', () {
      const h = HizliHesap(miktar: 5, altin: GoldSubCategory.ceyrek);
      expect(h.tutar(null), isNull);
      expect(h.tutar(0), isNull);
      expect(h.tutar(-1), isNull);
      expect(h.tutar(10000), 50000);
      expect(h.tur, AssetType.altin);
      expect(const HizliHesap(miktar: 1, doviz: 'USD').tur, AssetType.doviz);
    });

    test('sembol formun kaydedeceği sembol', () {
      expect(
          hizliHesapSembolu(
              const HizliHesap(miktar: 5, altin: GoldSubCategory.ceyrek)),
          goldTickerMap['Çeyrek Altın']);
      expect(hizliHesapSembolu(const HizliHesap(miktar: 1, doviz: 'GBP')),
          'GBPTRY=X');
      // Tanınan her altın türünün bir sembolü var: aksi halde satır hiç
      // çıkmaz ve kullanıcı nedenini bilmez.
      for (final g in GoldSubCategory.values) {
        if (g == GoldSubCategory.ons) continue;
        expect(hizliHesapSembolu(HizliHesap(miktar: 1, altin: g)), isNotNull,
            reason: g.name);
      }
    });
  });

  group('Varlık Ekle hızlı hesapla', () {
    testWidgets('5 yarım altın: tür, alt tür ve miktar dolu', (tester) async {
      await _pump(
          tester,
          const AddAssetScreen(
              hizliHesap: HizliHesap(miktar: 5, altin: GoldSubCategory.yarim)));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp(r'Seçili altın türü: Yarım Altın')),
          findsOneWidget);
      expect(_alanVar(tester, '5'), isTrue);
      // İleri kalıp Adet kipinde kalır ("Tutar" alanı yalnız Tutar kipinde).
      expect(find.text('Tutar'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('100 sterlin: GBP seçili, miktar dolu', (tester) async {
      await _pump(
          tester,
          const AddAssetScreen(
              hizliHesap: HizliHesap(miktar: 100, doviz: 'GBP')));
      await tester.pump();
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^GBP')).first),
          isSemantics(isSelected: true));
      expect(tester.getSemantics(find.bySemanticsLabel(RegExp(r'^USD')).first),
          isSemantics(isSelected: false));
      expect(_alanVar(tester, '100'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('ters "10.000 tl çeyrek": Tutar kipinde TL yazılı, adet boş',
        (tester) async {
      await _pump(
          tester,
          const AddAssetScreen(
              hizliHesap: HizliHesap(
                  miktar: 10000,
                  altin: GoldSubCategory.ceyrek,
                  ters: true)));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp(r'Seçili altın türü: Çeyrek Altın')),
          findsOneWidget);
      // TL tutarı adet alanına "10000 çeyrek" diye yazılmaz.
      expect(_alanVar(tester, '10000'), isTrue);
      expect(find.text('Tutar'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('2,5 gram: ondalık miktar formun biçimiyle', (tester) async {
      await _pump(
          tester,
          const AddAssetScreen(
              hizliHesap:
                  HizliHesap(miktar: 2.5, altin: GoldSubCategory.gr24)));
      await tester.pump();
      expect(_alanVar(tester, '2,5'), isTrue);
    });
  });
}
