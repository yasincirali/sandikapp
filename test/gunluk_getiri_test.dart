import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/gunluk_getiri.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/money_format.dart';
import 'package:portfoy_takip/widgets/gunluk_getiri_satiri.dart';

import 'helpers/kaynak.dart';

/// Para piyasası fonunda "Son 30 günde günde ortalama ~₺X" (müşteri raporu
/// 7 Kas 22:30 #1).
///
/// Kilitlenen: (1) kazanç bugünkü payların 30 günde kazandığı, gerçek gün
/// sayısına bölünür; (2) seri 30 gün geriye uzanmıyorsa, delikliyse, değer
/// ya da fiyat bilinmiyorsa `null`; (3) kategori yalnız TEFAS kategorisinden,
/// `null` tahmin edilmez; (4) satır bakiye gizliyken ve sayı yokken yok,
/// 3.1× ve 320 pt'de taşmaz; (5) yalnız varlık ekranında, Portföy liste
/// satırında değil.
void main() {
  final simdi = DateTime(2026, 11, 7, 12);
  int gunOnce(int g) =>
      DateTime(2026, 11, 7).subtract(Duration(days: g)).millisecondsSinceEpoch;

  group('gunlukOrtalamaGetiri (hesap)', () {
    test('30 gün önce 1,00, bugün 1,04: 10.400 TL tutarda kazanç 400 TL', () {
      final seri = {gunOnce(40): 0.99, gunOnce(30): 1.0, gunOnce(10): 1.02};
      final g = gunlukOrtalamaGetiri(
        seriler: [seri],
        guncelBirim: 1.04,
        guncelDegerTRY: 10400,
        simdi: simdi,
      )!;
      // Pencere başı gece yarısı, şimdi öğlen: 30,5 gün.
      expect(g, closeTo(400 / 30.5, 1e-9));
    });

    test('pencere başı hafta sonuna denk: önceki iş günü, gerçek gün sayısı',
        () {
      final seri = {gunOnce(32): 1.0, gunOnce(28): 1.01};
      final g = gunlukOrtalamaGetiri(
        seriler: [seri],
        guncelBirim: 1.05,
        guncelDegerTRY: 1050,
        simdi: simdi,
      )!;
      expect(g, closeTo(50 / 32.5, 1e-9));
    });

    test('ilk seri kısa: sıradaki seri kullanılır', () {
      final kisa = {gunOnce(20): 1.0, gunOnce(5): 1.01};
      final uzun = {gunOnce(30): 1.0};
      expect(
        gunlukOrtalamaGetiri(
          seriler: [kisa, null, uzun],
          guncelBirim: 1.03,
          guncelDegerTRY: 1030,
          simdi: simdi,
        ),
        closeTo(30 / 30.5, 1e-9),
      );
    });

    test('seri 30 günden kısa: null', () {
      expect(
        gunlukOrtalamaGetiri(
          seriler: [
            {gunOnce(29): 1.0, gunOnce(1): 1.03}
          ],
          guncelBirim: 1.03,
          guncelDegerTRY: 1030,
          simdi: simdi,
        ),
        isNull,
      );
    });

    test('seride delik (pencere başına en yakın nokta 5 günden eski): null',
        () {
      expect(
        gunlukOrtalamaGetiri(
          seriler: [
            {gunOnce(36): 1.0, gunOnce(20): 1.02}
          ],
          guncelBirim: 1.03,
          guncelDegerTRY: 1030,
          simdi: simdi,
        ),
        isNull,
      );
    });

    test('değer, fiyat ya da dönem başı bilinmiyor: null', () {
      final seri = {gunOnce(30): 1.0};
      for (final (deger, birim) in [
        (0.0, 1.03),
        (1030.0, 0.0),
        (double.nan, 1.0)
      ]) {
        expect(
          gunlukOrtalamaGetiri(
            seriler: [seri],
            guncelBirim: birim,
            guncelDegerTRY: deger,
            simdi: simdi,
          ),
          isNull,
        );
      }
      expect(
        gunlukOrtalamaGetiri(
          seriler: [
            {gunOnce(30): 0.0}
          ],
          guncelBirim: 1.03,
          guncelDegerTRY: 1030,
          simdi: simdi,
        ),
        isNull,
      );
      expect(
        gunlukOrtalamaGetiri(
            seriler: const [], guncelBirim: 1, guncelDegerTRY: 1, simdi: simdi),
        isNull,
      );
    });

    test('fiyat düştüyse eksi yazılır, gizlenmez', () {
      final g = gunlukOrtalamaGetiri(
        seriler: [
          {gunOnce(30): 1.0}
        ],
        guncelBirim: 0.99,
        guncelDegerTRY: 990,
        simdi: simdi,
      )!;
      expect(g, lessThan(0));
    });
  });

  group('paraPiyasasiKategorisiMi', () {
    test('TEFAS kategorisinden; harf büyüklüğü fark etmez', () {
      expect(paraPiyasasiKategorisiMi('Para Piyasası Şemsiye Fonu'), isTrue);
      expect(paraPiyasasiKategorisiMi('PARA PİYASASI ŞEMSİYE FONU'), isTrue);
      expect(paraPiyasasiKategorisiMi('Hisse Senedi Şemsiye Fonu'), isFalse);
      expect(
          paraPiyasasiKategorisiMi(
              'Kısa Vadeli Borçlanma Araçları Şemsiye Fonu'),
          isFalse);
    });

    test('kategori bilinmiyorsa tahmin edilmez', () {
      expect(paraPiyasasiKategorisiMi(null), isFalse);
      expect(paraPiyasasiKategorisiMi(''), isFalse);
    });
  });

  group('GunlukGetiriSatiri (arayüz)', () {
    const lira = BazPara(BaseCurrency.try_, 1);

    Future<void> pump(
      WidgetTester tester, {
      double? tutar = 12.4,
      BazPara baz = lira,
      double olcek = 1,
      double genislik = 400,
    }) async {
      tester.view.physicalSize = Size(genislik, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(genislik, 800), textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GunlukGetiriSatiri(tutarTRY: tutar, baz: baz),
            ),
          ),
        ),
      ));
    }

    testWidgets('tutar yazılır, ekran okuyucu "yaklaşık" der', (tester) async {
      await pump(tester);
      expect(find.text('Son 30 günde günde ortalama ~₺12'), findsOneWidget);
      expect(find.bySemanticsLabel('Son 30 günde günde ortalama yaklaşık ₺12.'),
          findsOneWidget);
    });

    testWidgets('bakiye gizliyken satır yok', (tester) async {
      await pump(tester, baz: lira.gizlenmis());
      expect(find.textContaining('günde ortalama'), findsNothing);
    });

    testWidgets('sayı yoksa satır yok', (tester) async {
      await pump(tester, tutar: null);
      expect(find.textContaining('günde ortalama'), findsNothing);
    });

    testWidgets('3.1× ve 320 pt: taşma yok', (tester) async {
      await pump(tester, olcek: 3.1, genislik: 320, tutar: 123456.7);
      expect(tester.takeException(), isNull);
    });

    test('yalnız varlık ekranında, fon için; Portföy liste satırında yok', () {
      final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(k, contains('GunlukGetiriSatiri(tutarTRY: _gunlukGetiri(pnl)'));
      expect(k, contains('paraPiyasasiFonuProvider(kod)'));
      expect(k, contains('if (!_canli.acik) return null;'));
      final liste = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
      expect(liste, isNot(contains('GunlukGetiriSatiri')));
    });
  });
}
