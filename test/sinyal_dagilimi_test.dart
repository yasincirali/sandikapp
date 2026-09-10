import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/screens/performance_screen.dart';

/// Varlık performans ekranındaki sinyal DAĞILIMI görselleştirmesi.
///
/// Kullanıcı isteği (2026-09-10): "hangi algoritmalar al ve sat verenleri ve
/// yüzdesi görsel olarak da tatmin edici ve göz alıcı şekilde sadece varlık
/// performans ekranına eklenmeli."
///
/// ## Neden bu testler
/// Bu ortamda cihaz/emülatör yok; "çiz ve bak" adımı gözle yapılamıyor.
/// Onun yerine widget gerçekten pump ediliyor ve iki şey ölçülüyor:
///
///   1. **Taşma.** Üç rozetli lejant ve grup başlıkları dar ekranda (320pt)
///      ve büyük sistem yazı tipinde (2,0×) taşmamalı. RenderFlex taşması
///      `tester.takeException()` ile yakalanır.
///   2. **Renk TEK BAŞINA anlam taşımamalı.** Marka yeşili ile kırmızısı
///      koyu temada deuteranopi altında ΔE ≈ 7,6 ayrışıyor (ölçüldü:
///      dataviz palet doğrulayıcısı). Bu, "yalnızca ikincil kodlama ile
///      yasal" bandın içinde — yani her yön bir GLİF ve METİN etiketi
///      taşımak ZORUNDA. Testler bunu kilitliyor: glif ya da başlık
///      düşerse kırmızıya döner.
TechnicalIndicator _ind(String name, SignalType signal, double value) =>
    TechnicalIndicator(
      name: name,
      value: value,
      signal: signal,
      description: 'test açıklaması',
    );

/// 4 AL · 2 SAT · 1 NÖTR — üç grubun da dolu olduğu tipik bir küme.
List<TechnicalIndicator> _karisik() => [
      _ind('RSI', SignalType.buy, 28.4),
      _ind('MACD', SignalType.buy, 1.2),
      _ind('Bollinger', SignalType.buy, 0.94),
      _ind('EMA', SignalType.buy, 105.5),
      _ind('Stochastic', SignalType.sell, 81.0),
      _ind('ADX', SignalType.sell, 34.2),
      _ind('CCI', SignalType.neutral, 12.0),
    ];

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double width = 375,
  double textScale = 1.0,
  Brightness parlaklik = Brightness.dark,
}) async {
  tester.view.physicalSize = Size(width * 3, 900 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: parlaklik == Brightness.dark
          ? ThemeData.dark()
          : ThemeData.light(),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  group('SinyalDagilimi — oran çubuğu', () {
    testWidgets('AL/SAT/NÖTR yüzdelerini ve SAYILARINI yazar', (tester) async {
      await _pump(tester, SinyalDagilimi(indicators: _karisik()));

      // 4/7 ≈ %57, 2/7 ≈ %29, 1/7 ≈ %14.
      expect(find.text('%57 · 4'), findsOneWidget);
      expect(find.text('%29 · 2'), findsOneWidget);
      expect(find.text('%14 · 1'), findsOneWidget);
    });

    testWidgets('her yön GLİF taşır — renk tek başına bırakılmaz',
        (tester) async {
      await _pump(tester, SinyalDagilimi(indicators: _karisik()));

      expect(find.text('▲'), findsWidgets, reason: 'AL glifi yok');
      expect(find.text('▼'), findsWidgets, reason: 'SAT glifi yok');
      expect(find.text('◆'), findsWidgets, reason: 'NÖTR glifi yok');
      // Metin etiketleri de şart: glif tek başına ekran okuyucuya bir şey
      // söylemez.
      expect(find.text('AL'), findsOneWidget);
      expect(find.text('SAT'), findsOneWidget);
      expect(find.text('NÖTR'), findsOneWidget);
    });

    testWidgets('NÖTR yoksa o rozet hiç çizilmez', (tester) async {
      await _pump(
        tester,
        SinyalDagilimi(indicators: [
          _ind('RSI', SignalType.buy, 28.4),
          _ind('MACD', SignalType.sell, 1.2),
        ]),
      );
      expect(find.text('NÖTR'), findsNothing,
          reason: '"%0 · 0" rozeti yer kaplar, bilgi vermez');
      expect(find.text('%50 · 1'), findsNWidgets(2));
    });

    testWidgets('boş gösterge listesinde hiç çizilmez', (tester) async {
      await _pump(tester, const SinyalDagilimi(indicators: []));
      expect(find.text('AL'), findsNothing);
    });
  });

  group('GostergeGruplari — hangi algoritma ne diyor', () {
    testWidgets('AL ve SAT başlıkları ayrı ayrı çıkar', (tester) async {
      await _pump(tester, GostergeGruplari(indicators: _karisik()));

      expect(find.text('AL DİYENLER'), findsOneWidget);
      expect(find.text('SAT DİYENLER'), findsOneWidget);
      expect(find.text('KARARSIZ'), findsOneWidget);
    });

    testWidgets('gösterge adları doğru grupta listelenir', (tester) async {
      await _pump(tester, GostergeGruplari(indicators: _karisik()));

      for (final ad in ['RSI', 'MACD', 'Bollinger', 'EMA']) {
        expect(find.text(ad), findsOneWidget);
      }
      expect(find.text('Stochastic'), findsOneWidget);
      expect(find.text('ADX'), findsOneWidget);
    });

    testWidgets('göstergenin HAM değeri gösterilir', (tester) async {
      await _pump(tester, GostergeGruplari(indicators: _karisik()));
      // fmtNumFlex(28.4, maxDigits: 2) → "28,4"
      expect(find.text('28,4'), findsOneWidget);
      expect(find.text('81'), findsOneWidget);
    });

    testWidgets('boş grup başlığı çizilmez', (tester) async {
      await _pump(
        tester,
        GostergeGruplari(indicators: [_ind('RSI', SignalType.buy, 28.4)]),
      );
      expect(find.text('AL DİYENLER'), findsOneWidget);
      expect(find.text('SAT DİYENLER'), findsNothing);
      expect(find.text('KARARSIZ'), findsNothing);
    });
  });

  group('taşma — dar ekran ve büyük yazı tipi', () {
    // 320pt en dar desteklenen genişlik; 2,0× iOS Dynamic Type'ın üst
    // kademelerinden biri ve erişilebilirlik ayarı açık her kullanıcıda
    // gerçek. Lejant üç rozetli, grup başlıkları uzun — ikisi de burada
    // kırılır.
    for (final genislik in [320.0, 375.0, 430.0]) {
      for (final olcek in [1.0, 1.5, 2.0]) {
        testWidgets('dağılım ${genislik.toInt()}pt @ $olcek× taşmaz',
            (tester) async {
          await _pump(
            tester,
            Column(children: [
              SinyalDagilimi(indicators: _karisik()),
              const SizedBox(height: 16),
              GostergeGruplari(indicators: _karisik()),
            ]),
            width: genislik,
            textScale: olcek,
          );
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets('açık temada da taşmaz', (tester) async {
      await _pump(
        tester,
        Column(children: [
          SinyalDagilimi(indicators: _karisik()),
          const SizedBox(height: 16),
          GostergeGruplari(indicators: _karisik()),
        ]),
        width: 320,
        textScale: 1.5,
        parlaklik: Brightness.light,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('panel — dağılım YALNIZCA detaylı modda', () {
    // Kullanıcı isteğinin "sadece" kısmı: takip listesi detayında bu
    // görselleştirme olmamalı. Bayrak varsayılan `false` olduğu için yeni
    // bir çağrı yeri eklendiğinde ağır sürüm kazara sızmaz.
    test('varsayılan detayli=false', () {
      const panel = TechnicalSignalPanel(
          ticker: 'THYAO.IS', type: AssetType.hisse);
      expect(panel.detayli, isFalse);
    });

    test('performans ekranı paneli detayli=true ile kurar', () {
      // Kaynak denetimi: canlı yol ağ istediği için widget testiyle
      // doğrulanamıyor (projede aynı örüntü var — bkz.
      // varlik_sinyal_karti_test.dart).
      final kaynak =
          File('lib/screens/performance_screen.dart').readAsStringSync();
      expect(
        kaynak.contains('key: _sinyalPaneliKey, detayli: true'),
        isTrue,
        reason: 'Performans ekranı paneli detaylı modda kurmuyor.',
      );
    });

    test('takip listesi detayı bayrağı GEÇMEZ', () {
      final kaynak =
          File('lib/screens/watchlist_detail_screen.dart').readAsStringSync();
      expect(kaynak.contains('detayli'), isFalse,
          reason: 'Dağılım takip listesine sızmış — istek "sadece varlık '
              'performans ekranı" diyordu.');
    });
  });
}
