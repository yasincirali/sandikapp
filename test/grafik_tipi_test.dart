import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/grafik_tipi.dart';
import 'package:portfoy_takip/widgets/grafik_tipi_secici.dart';
import 'helpers/kaynak.dart';

/// Grafik tipi seçici — varsayılan, oturum kalıcılığı ve menü.
///
/// Kullanıcı isteği (2026-09-12): "ekteki seçenekler gösterilmeli, görsel
/// seçime göre değişmeli, session bazlı tutulmalı bilgi; default olarak
/// da line chart şeklinde görülmeli."
///
/// ## Candle
/// 2026-09-14'e kadar yoktu (OHLC verisi yok diye). Artık `mum_turetici`
/// eldeki noktalardan kova bazında OHLC türetiyor; Candle beşinci tip.
void main() {
  setUp(() => grafikTipiNotifier.value = GrafikTipi.varsayilan);
  tearDown(() => grafikTipiNotifier.value = GrafikTipi.varsayilan);

  group('varsayılan', () {
    test('Line', () {
      expect(GrafikTipi.varsayilan, GrafikTipi.line);
      expect(grafikTipiNotifier.value, GrafikTipi.line);
    });

    test('beş tip var — TradingView kümesi tamam, Candle sonda', () {
      expect(GrafikTipi.values.length, 5);
      expect(GrafikTipi.values.map((e) => e.name).toList(),
          ['line', 'mountain', 'baseline', 'bar', 'candle']);
      expect(GrafikTipi.candle.etiket, 'Mum',
          reason: '"OHLC" değil: fitiller örneklenmiş noktaların uçları.');
    });

    test('her tipin etiketi ve ikonu var', () {
      for (final t in GrafikTipi.values) {
        expect(t.etiket.trim(), isNotEmpty, reason: '${t.name} etiketsiz.');
        expect(t.ikon, isNotNull, reason: '${t.name} ikonsuz.');
      }
    });
  });

  group('oturum durumu', () {
    test('seçim notifier üzerinden taşınır', () {
      grafikTipiNotifier.value = GrafikTipi.bar;
      expect(grafikTipiNotifier.value, GrafikTipi.bar);
    });

    test('dinleyiciye ULAŞIR', () {
      final gelen = <GrafikTipi>[];
      void dinle() => gelen.add(grafikTipiNotifier.value);
      grafikTipiNotifier.addListener(dinle);
      addTearDown(() => grafikTipiNotifier.removeListener(dinle));

      grafikTipiNotifier.value = GrafikTipi.mountain;
      grafikTipiNotifier.value = GrafikTipi.baseline;

      expect(gelen, [GrafikTipi.mountain, GrafikTipi.baseline]);
    });

    test('DİSKE yazılmaz — oturum bazlı', () {
      // Kullanıcı "session bazlı" dedi. SharedPreferences kullanılsaydı
      // uygulama yeniden açıldığında eski tip gelirdi.
      // Yorum satırları hariç — dosya gerekçeyi anlatırken
      // `SharedPreferences`'tan söz ediyor, KULLANMIYOR.
      final kod = File('lib/models/grafik_tipi.dart')
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(kod.contains('SharedPreferences'), isFalse,
          reason: 'Kalıcı depolama eklenmiş — istenen bu değildi.');
      expect(kod.contains('import'), isTrue);
      expect(kod.contains('shared_preferences'), isFalse,
          reason: 'Kalıcı depolama paketi import edilmiş.');
    });
  });

  group('menü', () {
    testWidgets('dört seçeneği de listeler', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GrafikTipiSecici())),
      ));

      await tester.tap(find.byType(GrafikTipiSecici));
      await tester.pumpAndSettle();

      for (final t in GrafikTipi.values) {
        expect(find.text(t.etiket), findsWidgets,
            reason: '${t.etiket} menüde yok.');
      }
    });

    testWidgets('seçim notifier\'ı GÜNCELLER', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GrafikTipiSecici())),
      ));

      await tester.tap(find.byType(GrafikTipiSecici));
      await tester.pumpAndSettle();
      await tester.tap(find.text(GrafikTipi.bar.etiket).last);
      await tester.pumpAndSettle();

      expect(grafikTipiNotifier.value, GrafikTipi.bar);
    });

    testWidgets('seçili tip chip\'te görünür', (tester) async {
      grafikTipiNotifier.value = GrafikTipi.mountain;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GrafikTipiSecici())),
      ));
      await tester.pump();

      expect(find.text(GrafikTipi.mountain.etiket), findsOneWidget);
    });
  });

  group('çizim bağlantısı — kaynak denetimi', () {
    final ekran = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
        .replaceAll('\r\n', '\n');

    test('dolgu YALNIZCA mountain\'da', () {
      expect(ekran.contains('tip == GrafikTipi.mountain'), isTrue,
          reason: 'Dolgu tipe bağlı değil — Line da dolgulu çizilir.');
    });

    test('bar tipinde çizgi gizlenir', () {
      expect(ekran.contains('tip == GrafikTipi.bar ? 0.0'), isTrue,
          reason: 'Çubukların üstüne bir de çizgi biner.');
    });

    test('baseline gradyanı bağlı', () {
      expect(ekran.contains('_baselineGradient('), isTrue);
      expect(ekran.contains('tip == GrafikTipi.baseline'), isTrue);
    });

    test('tip değişince grafik YENİDEN çizilir', () {
      expect(ekran.contains('valueListenable: grafikTipiNotifier'), isTrue,
          reason: 'Dinleyici yok — seçim görsele yansımaz.');
    });

    test('kapalı kuyruk HER tipte nötr kalır', () {
      // Hafta sonu kuyruğu gerçek işlem değil; dolgu/renk onu birikim
      // gibi göstermemeli.
      expect(ekran.contains('&& !seg.piyasaKapali'), isTrue);
    });
  });
}
