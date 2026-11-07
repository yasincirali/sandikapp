import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/altin_gram_ozeti.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';
import 'package:portfoy_takip/services/price_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/altin_gram_satiri.dart';

import 'helpers/kaynak.dart';

/// Portföyde altının toplam gramı (Ar-Ge 7 Kas 18:06 #1): ağırlık fiyat
/// tablosundan, bugünkü mülkiyetten; ons girmez; gizli bakiyede susar.
Asset _lot(
  String ticker,
  double qty, {
  AssetKind kind = AssetKind.buy,
  String id = '',
  AssetType type = AssetType.altin,
}) =>
    Asset(
      id: id.isEmpty ? 'a_$ticker' : id,
      userId: 'ben',
      name: ticker,
      ticker: ticker,
      type: type,
      // Altın pozisyonu alt türle anahtarlanır (`positionKey`).
      subCategory: type == AssetType.altin ? ticker : null,
      quantity: qty,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1,
      currentPrice: 100,
      addedDate: dayKey(DateTime(2026, 1, 2)),
      kind: kind,
    );

void main() {
  group('PriceService.altinGramKarsiligi', () {
    test('sikke: fiziksel gram = adet × kalıp, has = ×22/24', () {
      final k = PriceService.altinGramKarsiligi('ALTIN_CEYREK', 2)!;
      expect(k.gram, closeTo(3.5, 1e-9));
      expect(k.has, closeTo(3.5 * 22 / 24, 1e-9));
    });

    test('gram ürün: fiziksel gram = adet, has ayarı izler', () {
      final g24 = PriceService.altinGramKarsiligi('ALTIN_GRAM24', 10)!;
      expect(g24.gram, 10);
      expect(g24.has, closeTo(10, 1e-3));
      final g22 = PriceService.altinGramKarsiligi('ALTIN_GRAM', 10)!;
      expect(g22.gram, 10);
      expect(g22.has, closeTo(10 * 22 / 24, 1e-9));
      final g14 = PriceService.altinGramKarsiligi('ALTIN_14AYAR', 10)!;
      expect(g14.gram, 10);
      expect(g14.has, closeTo(10 * 14 / 24, 1e-3));
    });

    test('fiyat çarpanıyla tek kaynak: has × 24/22 = adet × çarpan', () {
      for (final t in ['ALTIN_RESAT', 'ALTIN_BESLI', 'ALTIN_HAS']) {
        final k = PriceService.altinGramKarsiligi(t, 3)!;
        expect(k.has * 24 / 22,
            closeTo(3 * PriceService.goldWeightFactor(t), 1e-9));
      }
    });

    test('ons ve bilinmeyen sembol null (ağırlık uydurulmaz)', () {
      expect(PriceService.altinGramKarsiligi('XAUUSD=X', 1), isNull);
      expect(PriceService.altinGramKarsiligi('GC=F', 1), isNull);
      expect(PriceService.altinGramKarsiligi('', 1), isNull);
    });
  });

  group('AltinGramOzeti', () {
    test('karışık altın toplanır, ons ve hisse girmez', () {
      final o = AltinGramOzeti.hesapla([
        _lot('ALTIN_CEYREK', 4), // 7 gr
        _lot('ALTIN_GRAM24', 10), // 10 gr
        _lot('XAUUSD=X', 2),
        _lot('THYAO.IS', 100, type: AssetType.hisse),
      ])!;
      expect(o.gram, closeTo(17, 1e-9));
      expect(o.has, closeTo(7 * 22 / 24 + 10, 1e-3));
    });

    test('satış düşer, tamamı satılan pozisyon girmez (aktifLotlar)', () {
      final o = AltinGramOzeti.hesapla([
        _lot('ALTIN_CEYREK', 4, id: 'c1'),
        _lot('ALTIN_CEYREK', 1, id: 'c2', kind: AssetKind.sell),
        _lot('ALTIN_GRAM', 5, id: 'g1'),
        _lot('ALTIN_GRAM', 5, id: 'g2', kind: AssetKind.sell),
      ])!;
      expect(o.gram, closeTo(3 * 1.75, 1e-9));
    });

    test('yalnız ons → null (satır çizilmez)', () {
      expect(AltinGramOzeti.hesapla([_lot('XAUUSD=X', 3)]), isNull);
      expect(AltinGramOzeti.hesapla(const []), isNull);
    });

    test('sahip başına defterler ayrı toplanır', () {
      final o = AltinGramOzeti.sahiplerdenHesapla([
        [_lot('ALTIN_GRAM', 2)],
        [_lot('ALTIN_GRAM', 3)],
      ])!;
      expect(o.gram, closeTo(5, 1e-9));
    });
  });

  test('fmtGram: 10 altı iki ondalık, üstü tek', () {
    expect(fmtGram(1.75), '1,75');
    expect(fmtGram(42.64), '42,6');
    expect(fmtGram(1250), '1.250,0');
  });

  group('AltinGramSatiri', () {
    const ozet = AltinGramOzeti(gram: 42.6, has: 39.1);

    Widget sar(Widget child, {double olcek = 1, double en = 390}) =>
        MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          locale: const Locale('tr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(en, 900), textScaler: TextScaler.linear(olcek)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(children: [child]),
              ),
            ),
          ),
        );

    testWidgets('metin ve ekran okuyucu etiketi', (tester) async {
      final h = tester.ensureSemantics();
      await tester
          .pumpWidget(sar(const AltinGramSatiri(ozet: ozet, gizli: false)));
      expect(find.text('Toplam 42,6 gr · 24 ayar karşılığı 39,1 gr'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(
              'Altının toplamı 42,6 gram, 24 ayar karşılığı 39,1 gram'),
          findsOneWidget);
      h.dispose();
    });

    testWidgets('gizli bakiyede ve özetsiz hiçbir şey çizilmez',
        (tester) async {
      await tester
          .pumpWidget(sar(const AltinGramSatiri(ozet: ozet, gizli: true)));
      expect(find.byType(Text), findsNothing);
      await tester
          .pumpWidget(sar(const AltinGramSatiri(ozet: null, gizli: false)));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('3.1× yazı, 320 pt: taşmaz, kesilmez', (tester) async {
      tester.view.physicalSize = const Size(320 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(sar(
          const AltinGramSatiri(
              ozet: AltinGramOzeti(gram: 1250.4, has: 1146.2), gizli: false),
          olcek: 3.1,
          en: 320));
      expect(tester.takeException(), isNull);
      final t = tester.widget<Text>(find.byType(Text));
      expect(t.maxLines, isNull);
      expect(t.overflow, isNull);
    });
  });

  test('Portföy ekranı satırı Altın süzgecinde ve halkada kullanır', () {
    // Ekran tipini içe aktarmak derlemeyi kilitler; kaynakta iki yer.
    expect(PortfolioScreen, isNotNull);
    final src = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
    expect('AltinGramSatiri('.allMatches(src).length, 2);
    expect(
        RegExp(r'AltinGramOzeti\s*\.sahiplerdenHesapla\(\s*ownerLots\)')
            .allMatches(src)
            .length,
        2);
  });
}
