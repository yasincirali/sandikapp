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
            SinyalDagilimi(indicators: _karisik()),
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
        SinyalDagilimi(indicators: _karisik()),
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

    test('detaylı modda DÜZ LİSTE de çizilir', () {
      // Kullanıcı bildirimi (2026-09-10, ikinci tur): "hangi algoritmalar
      // bunu dedi ekranın en altında görmeyi bekliyorum … tasarımı da
      // store'da şu an olan şekliyle olmalı."
      //
      // İlk sürüm detaylı modda düz listeyi KALDIRIP yerine gruplu kutular
      // koymuştu. Çubuk oranı verir, kimliği düz liste verir; ikisi birlikte
      // durmalı. Bu denetim listenin bir daha `else` dalına düşmesini
      // engelliyor.
      final kaynak =
          File('lib/screens/performance_screen.dart').readAsStringSync();
      expect(
        kaynak.contains('''if (widget.detayli) ...[
          SinyalDagilimi(indicators: indicators),
          const SizedBox(height: SandikSpace.md),
        ],'''),
        isTrue,
        reason: 'Düz gösterge listesi detaylı modda yine gizlenmiş.',
      );
      expect(kaynak.contains('GostergeGruplari'), isFalse,
          reason: 'Gruplu kutular düz listenin bilgisini tekrarlıyordu; '
              'geri gelmiş.');
    });

    test('fiyat geçmişi yoksa panel ÖLÜ bir cümle bırakmaz', () {
      // Üstteki şerit aynı boş seride kayıtlı bildirime düşüp "2/3 gösterge
      // · güven %67" yazıyor. Alt panel yalnızca "geçmiş yok" derse
      // kullanıcı üstte sinyal, altta hiçbir şey görür — bildirilen hata
      // buydu.
      final kaynak =
          File('lib/screens/performance_screen.dart').readAsStringSync();
      expect(kaynak.contains('Widget _gecmisYok(BuildContext context)'), isTrue);
      // Elde ne varsa gösterilir: kayıtlı bildirimin gerçek sayıları.
      expect(kaynak.contains("'SON BİLDİRİM'"), isTrue);
      // Ve istek tekrarlanabilir — başarısız future ömür boyu saklanmaz.
      expect(kaynak.contains("'Tekrar dene'"), isTrue);
      expect(kaynak.contains(r"'${widget.subCategory ?? ''}|$_deneme'"), isTrue,
          reason: 'Yeniden deneme sayacı önbellek anahtarında değil — '
              '"Tekrar dene" hiçbir şey yapmaz.');
    });

    test('UYDURMA seriye geri dönülmedi', () {
      // Store sürümünde liste hep doluydu çünkü fiyat geçmişi yokken
      // `_simulate()` rastgele seri üretiyordu. Liste geri geldi ama o
      // tuzak geri gelmemeli: 30 nokta eşiği yerinde.
      final kaynak =
          File('lib/screens/performance_screen.dart').readAsStringSync();
      expect(kaynak.contains('if (prices.length < 30) return _gecmisYok(context);'),
          isTrue);
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
