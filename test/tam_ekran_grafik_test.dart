import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/fullscreen_chart_route.dart';

/// Tam ekran grafik — "büyütme butonu efektif çalışmıyor" (kullanıcı,
/// 2026-09-17).
///
/// İki şikâyet: (1) yan çevirince ekran izlenebilir değildi — route ekranın
/// TAMAMINI kaydırarak basıyordu; (2) telefon dikeye çevrilince normal
/// ekrana dönmüyordu — yön yataya kilitliydi.
///
/// Yeni sözleşme: yön serbest (cihaz karar verir), yatay bir kez görüldükten
/// sonra dikeye dönüş route'u kapatır, içerik yalnızca grafiktir
/// (`sadeceGrafik`).
void main() {
  Widget uygulama() => MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Builder(
          builder: (c) => Scaffold(
            body: TextButton(
              onPressed: () => FullscreenChartRoute.open(
                c,
                builder: (_) => const Text('GRAFIK'),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      );

  group('FullscreenChartRoute yön davranışı', () {
    testWidgets('yatay görüldükten sonra dikeye dönünce KENDİNİ KAPATIR',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 360); // telefon yan
      addTearDown(tester.view.reset);

      await tester.pumpWidget(uygulama());
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(find.text('GRAFIK'), findsOneWidget);

      tester.view.physicalSize = const Size(360, 800); // telefon dik
      await tester.pumpAndSettle();

      expect(find.text('GRAFIK'), findsNothing,
          reason: 'dikeye dönüş "normal ekrana dön" demektir — route '
              'kapanmalı, kullanıcı X aramamalı');
      expect(find.text('aç'), findsOneWidget);
    });

    testWidgets('dik açıldıysa (yatay hiç görülmedi) kendiliğinden KAPANMAZ',
        (tester) async {
      // Aksi halde telefonu dik tutan kullanıcı düğmeye basar basmaz
      // sayfa açılıp kapanırdı.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(360, 800);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(uygulama());
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(find.text('GRAFIK'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('GRAFIK'), findsOneWidget);

      // Çıkış X ile.
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.text('GRAFIK'), findsNothing);
    });
  });

  group('tam ekran yalnızca grafiği içerir', () {
    final rota = File('lib/widgets/fullscreen_chart_route.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final varlik = File('lib/screens/asset_detail_screen.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final kap = File('lib/screens/portfolio_performance/grafik_kabi.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');
    final kartlar = File('lib/screens/portfolio_performance/kartlar.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n');

    test('yön KİLİTLENMEZ: açılışta yatay + dikey birlikte serbest', () {
      final acilis = rota.indexOf('void initState()');
      final kapanis = rota.indexOf('void dispose()');
      final ilkDikey = rota.indexOf('DeviceOrientation.portraitUp');
      expect(ilkDikey, greaterThan(acilis));
      expect(ilkDikey, lessThan(kapanis),
          reason: 'initState dikeyi de serbest bırakmalı; yalnızca yataya '
              'kilitlenirse cihaz dikeye çevrilince hiçbir şey olmaz');
    });

    test('iki ekran da tam ekranı sadeceGrafik ile açar', () {
      expect(varlik.contains('sadeceGrafik: true,'), isTrue,
          reason: 'varlık ekranı tüm sayfayı kaydırarak basıyor');
      expect(kap.contains('sadeceGrafik: true,'), isTrue,
          reason: 'performans ekranı tüm sayfayı kaydırarak basıyor');
      // Virgüllü biçim: alan doc'u eski yolu anlatırken aynı metni geçiriyor.
      expect(varlik.contains('initialScrollOffset: 240,'), isFalse);
      expect(kap.contains('initialScrollOffset: 96,'), isFalse);
    });

    test('sadeceGrafik modunda grafik dışı bölümler gizlenir', () {
      // Varlık ekranı: çubuk, sekmeler, sinyal kartı, alarm şeridi, grafik altı.
      expect(varlik.contains('appBar: widget.sadeceGrafik'), isTrue);
      expect(varlik.contains('!widget.showBackButton && !widget.sadeceGrafik'),
          isTrue);
      // Sinyal yüzeyleri getter'da kapılı (mevcut seviye testi literali korur).
      final getter = varlik.indexOf('bool get _sinyalYuzeyleri');
      expect(getter, greaterThan(0));
      expect(
          varlik
              .substring(getter, getter + 200)
              .contains('!widget.sadeceGrafik &&'),
          isTrue,
          reason: 'sinyal kartı/paneli tam ekrana sızıyor');
      expect(varlik.contains('_alarmSembolu != null && !widget.sadeceGrafik'),
          isTrue);
      // Performans ekranı: kapsam denetimleri, özet, dönem kartı, döküm.
      expect(kartlar.contains('_ozetSekmesi && !widget.sadeceGrafik'), isTrue);
      expect('!widget.sadeceGrafik'.allMatches(kartlar).length,
          greaterThanOrEqualTo(5),
          reason: 'performans sayfasında grafik dışı bir bölüm tam ekrana '
              'sızıyor');
    });

    test('tam ekranda grafik yüksekliği ekrana göre, sabit 400/296 değil', () {
      expect(varlik.contains('height: 400,'), isFalse,
          reason: 'sabit 400 yatayda kaydırma gerektirir');
      expect(varlik.contains('height: grafikYuksekligi'), isTrue);
      expect(kap.contains('height: _grafikYuksekligi'), isTrue);
    });
  });
}
