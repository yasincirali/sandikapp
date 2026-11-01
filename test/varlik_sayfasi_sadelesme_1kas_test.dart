import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/grafik_alarm_cizgisi.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:portfoy_takip/services/varlik_istatistik.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/donem_istatistik.dart';

import 'helpers/kaynak.dart';

/// Varlık sayfası "yap" paketi (Ar-Ge 1 Kas 08:45, yasin "Yap dediklerini
/// yap"): maliyet çizgisi, istatistik ızgarasında tekrar ve boş kutu,
/// Bollinger "2σ", "Gün düşüğü/yükseği", teknik analiz başlığı.
void main() {
  group('maliyet çizgisinin yeri', () {
    test('aralık içi / üstü / altı', () {
      expect(maliyetCizgiKonumu(100, minY: 90, maxY: 110),
          AlarmCizgiKonumu.icinde);
      expect(maliyetCizgiKonumu(120, minY: 90, maxY: 110),
          AlarmCizgiKonumu.ustunde);
      expect(maliyetCizgiKonumu(80, minY: 90, maxY: 110),
          AlarmCizgiKonumu.altinda);
    });

    test('bilinmeyen maliyet ya da bozuk aralık: yer uydurulmaz', () {
      expect(maliyetCizgiKonumu(null, minY: 90, maxY: 110), isNull);
      expect(maliyetCizgiKonumu(0, minY: 90, maxY: 110), isNull);
      expect(maliyetCizgiKonumu(double.nan, minY: 90, maxY: 110), isNull);
      expect(maliyetCizgiKonumu(100, minY: 110, maxY: 90), isNull);
      expect(
          maliyetCizgiKonumu(100, minY: 90, maxY: double.infinity), isNull);
    });

    test('çizgi yalnız TRY ve ham fiyat kipinde (LOG/Karşılaştır yok)', () {
      final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(k, contains('_grafikMaliyeti('));
      expect(k, contains('_maliyetYatayCizgisi('));
      final a = ekranKaynagiSync('lib/screens/asset_detail/alarm_cizgileri.dart');
      expect(a, contains("currency != 'TRY'"));
      expect(a, contains('compareOn || logOn'));
    });
  });

  group('istatistik ızgarası', () {
    const ist = DonemIstatistigi(
      ilk: 280,
      son: 312.4,
      yuksek: 320,
      dusuk: 270,
      enBuyukDususPct: -4.2,
      oynaklikPct: null,
    );

    Future<void> izgara(WidgetTester tester,
        {bool? bugunGizli, int gun = 1}) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: DonemIstatistikIzgarasi(
            ist: ist,
            gun: gun,
            donemPct: 1.98,
            bugunPct: 1.98,
            donemGetirisiGizli: true,
            bugunGizli: bugunGizli,
          ),
        ),
      ));
    }

    testWidgets('GÜNLÜK varlık sayfası: tek hücre "En büyük düşüş"',
        (tester) async {
      await izgara(tester, bugunGizli: true);
      expect(find.text('DÖNEM GETİRİSİ'), findsNothing);
      expect(find.text('BUGÜN'), findsNothing);
      expect(find.text('EN BÜYÜK DÜŞÜŞ'), findsOneWidget);
      // Oynaklık bilinmiyor: ne "—" kutusu ne açıklama notu.
      expect(find.text('OYNAKLIK (YILLIK)'), findsNothing);
      expect(find.text('—'), findsNothing);
    });

    testWidgets('1 ay: Bugün kalır', (tester) async {
      await izgara(tester, bugunGizli: false, gun: 30);
      expect(find.text('BUGÜN'), findsOneWidget);
      expect(find.text('EN BÜYÜK DÜŞÜŞ'), findsOneWidget);
    });

    test('iskelet hücre sayısı ızgarayla aynı kuraldan', () {
      expect(
          DonemIstatistikIzgarasi.hucreSayisi(
              donemGetirisiGizli: true, bugunGizli: true, oynaklikVar: false),
          1);
      expect(
          DonemIstatistikIzgarasi.hucreSayisi(
              donemGetirisiGizli: true, bugunGizli: false, oynaklikVar: true),
          3);
      expect(
          DonemIstatistikIzgarasi.hucreSayisi(
              donemGetirisiGizli: false, bugunGizli: false, oynaklikVar: true),
          4);
      final ozet = ekranKaynagiSync('lib/screens/asset_detail/ozet.dart');
      expect(ozet, contains('DonemIstatistikIzgarasi.hucreSayisi('));
      expect(ozet, isNot(contains('days == 0 ? 2 : 3')));
    });

    test('varlık sayfası fiyatın altındaki sayıyı ızgarada tekrar etmez', () {
      final k = ekranKaynagiSync('lib/screens/varlik_sayfasi.dart');
      expect(k, contains('donemGetirisiGizli: true'));
      expect(k, contains('bugunGizli: gun == 1'));
    });
  });

  testWidgets('GÜNLÜK aralık çubuğu "Gün düşüğü/yükseği" der', (tester) async {
    Future<void> cubuk(bool gunIci) => tester.pumpWidget(MaterialApp(
          theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
          home: Scaffold(
            body: DonemAralikCubugu(
              dusuk: 100,
              yuksek: 110,
              konum: 0.4,
              bicim: NumberFormat.decimalPattern('tr_TR'),
              gunIci: gunIci,
            ),
          ),
        ));
    await cubuk(true);
    expect(find.text('Gün düşüğü'), findsOneWidget);
    expect(find.text('Gün yükseği'), findsOneWidget);
    await cubuk(false);
    expect(find.text('Dönem düşüğü'), findsOneWidget);
  });

  test('Bollinger etiketi "2.0σ" değil "2σ"; döviz 1.5σ kalır', () {
    final fiyat = [for (var i = 0; i < 40; i++) 100.0 + (i % 5)];
    expect(TechnicalAnalysisService.bollingerBands(fiyat, AssetType.hisse).name,
        'Bollinger (20, 2σ)');
    expect(TechnicalAnalysisService.bollingerBands(fiyat, AssetType.doviz).name,
        'Bollinger (20, 1.5σ)');
  });

  test('teknik analiz başlığı kırpılmaz; ayar bağlantısı 44 pt', () {
    final k = ekranKaynagiSync('lib/screens/asset_detail/sinyal_widgetlari.dart');
    final i = k.indexOf('context.l10n.technicalAnalysisUpper');
    final pencere = k.substring(i - 200, i + 300);
    expect(pencere, isNot(contains('TextOverflow.ellipsis')));
    expect(k, contains('context.l10n.configureShort'));
    expect(k, contains('minHeight: SandikTouch.min'));
  });
}
