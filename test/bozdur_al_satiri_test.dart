import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/add_asset_form_provider.dart';
import 'package:portfoy_takip/services/fiyat_kaynagi.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/bozdur_al_satiri.dart';
import 'helpers/kaynak.dart';
import 'helpers/yazi_olcegi.dart';

/// Varlık sayfası + varlık detayındaki "Bozdurursan · Alırsan · fark"
/// satırı (2026-10-25). Kilitlenen: satır yalnız sözleşme kapısı
/// ([gorunurSatisFiyati] → `maliyetSatisFiyati`) kabul edince görünür;
/// satış yoksa / kapı reddederse / USD-kote sembolde HİÇ görünmez; büyük
/// yazıda taşmaz; yüzde formdaki "Kuyumcu farkı" ile aynı sayıdır.

class _Kapi implements AddAssetPriceLookup, SatisFiyatiOkuyucu {
  _Kapi(this.k);
  final AlisSatis? k;
  final istenen = <String>[];
  @override
  Future<AlisSatis?> alisSatis(String ticker) async {
    istenen.add(ticker);
    return k;
  }

  @override
  Future<double?> historicalClose(String ticker, DateTime date) async => null;
  @override
  Future<double?> spot(String ticker) async => k?.alis;
  @override
  Future<String?> companyName(String ticker) async => null;
}

Future<void> _ac(
  WidgetTester tester, {
  required _Kapi kapi,
  String ticker = 'ALTIN_GRAM',
  String paraBirimi = 'TRY',
  double en = 375,
}) async {
  tester.view.physicalSize = Size(en * 3, 800 * 3);
  tester.view.devicePixelRatio = 3.0;
  yaziOlceginiUygula(tester);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [addAssetPriceLookupProvider.overrideWithValue(kapi)],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(SandikSpace.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BozdurAlSatiri(ticker: ticker, paraBirimi: paraBirimi),
            ],
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

final _satir = find.byKey(const ValueKey('bozdur-al-satiri'));

void main() {
  group('gorunurSatisFiyati', () {
    test('yurt içi + TRY + makas içinde → satış', () {
      expect(
          gorunurSatisFiyati(
              ticker: 'ALTIN_GRAM', paraBirimi: 'TRY', alis: 3000, satis: 3100),
          3100);
      expect(
          gorunurSatisFiyati(
              ticker: 'USDTRY=X', paraBirimi: 'TRY', alis: 41.9, satis: 42.1),
          42.1);
    });

    test('satış yok / satış < alış / makas sınır dışı → null', () {
      expect(
          gorunurSatisFiyati(
              ticker: 'ALTIN_GRAM', paraBirimi: 'TRY', alis: 3000, satis: null),
          isNull);
      expect(
          gorunurSatisFiyati(
              ticker: 'ALTIN_GRAM', paraBirimi: 'TRY', alis: 3000, satis: 2900),
          isNull);
      expect(
          gorunurSatisFiyati(
              ticker: 'ALTIN_GRAM',
              paraBirimi: 'TRY',
              alis: 3000,
              satis: 3000 * satisMakasiUstSinir + 1),
          isNull);
    });

    test('USD-kote ya da yurt dışı sembol → null', () {
      expect(
          gorunurSatisFiyati(
              ticker: 'ALTIN_GRAM', paraBirimi: 'USD', alis: 3000, satis: 3100),
          isNull);
      expect(
          gorunurSatisFiyati(
              ticker: 'GC=F', paraBirimi: 'TRY', alis: 3000, satis: 3100),
          isNull);
      expect(
          gorunurSatisFiyati(
              ticker: 'THYAO.IS', paraBirimi: 'TRY', alis: 300, satis: 301),
          isNull);
    });
  });

  yaziOlcegiEkseni(() {
    for (final en in [320.0, 430.0]) {
      testWidgets('satış var → satır, taşma yok ($en)', (tester) async {
        await _ac(tester, kapi: _Kapi((alis: 3000.0, satis: 3100.0)), en: en);
        expect(tester.takeException(), isNull);
        expect(_satir, findsOneWidget);
        final metin = tester.widget<Text>(_satir).data!;
        final fark =
            fmtPct(kuyumcuFarkiYuzde(alis: 3000, satis: 3100), digits: 1);
        expect(metin, contains('Bozdurursan'));
        expect(metin, contains('Alırsan'));
        expect(metin, contains(fark));
      });
    }
  });

  testWidgets('Semantics okunur cümle', (tester) async {
    final h = tester.ensureSemantics();
    await _ac(tester, kapi: _Kapi((alis: 3000.0, satis: 3100.0)));
    expect(find.bySemanticsLabel(RegExp('Bozdurursan eline .* geçer')),
        findsOneWidget);
    h.dispose();
  });

  testWidgets('satış yok → satır yok', (tester) async {
    await _ac(tester, kapi: _Kapi((alis: 3000.0, satis: null)));
    expect(_satir, findsNothing);
  });

  testWidgets('kapı reddeder (satış < alış) → satır yok', (tester) async {
    await _ac(tester, kapi: _Kapi((alis: 3000.0, satis: 2500.0)));
    expect(_satir, findsNothing);
  });

  testWidgets('USD-kote → satır yok', (tester) async {
    await _ac(tester,
        kapi: _Kapi((alis: 3000.0, satis: 3100.0)), paraBirimi: 'USD');
    expect(_satir, findsNothing);
  });

  testWidgets('hisse sembolü ağa çıkmaz, satır yok', (tester) async {
    final kapi = _Kapi((alis: 300.0, satis: 301.0));
    await _ac(tester, kapi: kapi, ticker: 'THYAO.IS');
    expect(_satir, findsNothing);
    expect(kapi.istenen, isEmpty);
  });

  test('iki ekran da satırı fiyat bloğunun altında çizer', () {
    expect(ekranKaynagiSync('lib/screens/varlik_sayfasi.dart'),
        contains('BozdurAlSatiri('));
    expect(ekranKaynagiSync('lib/screens/asset_detail_screen.dart'),
        contains('BozdurAlSatiri('));
  });
}
