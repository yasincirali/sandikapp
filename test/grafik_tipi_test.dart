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
/// eldeki noktalardan kova bazında OHLC türetiyor.
///
/// ## Yalnız Çizgi ve Mum (2026-10-05)
/// Alan/Taban/Çubuk 2026-10-04'ten beri seçicide yoktu (`performans_ayar_sade`);
/// bayrakla birlikte enum'dan ve çizimden silindi. Onların dolgu/gradyan/
/// çubuk kaynak denetimleri de bu dosyadan kalktı.
void main() {
  setUp(() => grafikTipiNotifier.value = GrafikTipi.varsayilan);
  tearDown(() => grafikTipiNotifier.value = GrafikTipi.varsayilan);

  group('varsayılan', () {
    test('Line', () {
      expect(GrafikTipi.varsayilan, GrafikTipi.line);
      expect(grafikTipiNotifier.value, GrafikTipi.line);
    });

    test('iki tip var — Çizgi ve Mum', () {
      expect(GrafikTipi.values.map((e) => e.name).toList(),
          ['line', 'candle']);
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
      grafikTipiNotifier.value = GrafikTipi.candle;
      expect(grafikTipiNotifier.value, GrafikTipi.candle);
    });

    test('dinleyiciye ULAŞIR', () {
      final gelen = <GrafikTipi>[];
      void dinle() => gelen.add(grafikTipiNotifier.value);
      grafikTipiNotifier.addListener(dinle);
      addTearDown(() => grafikTipiNotifier.removeListener(dinle));

      grafikTipiNotifier.value = GrafikTipi.candle;
      grafikTipiNotifier.value = GrafikTipi.line;

      expect(gelen, [GrafikTipi.candle, GrafikTipi.line]);
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
    testWidgets('iki seçeneği de listeler', (tester) async {
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
      await tester.tap(find.text(GrafikTipi.candle.etiket).last);
      await tester.pumpAndSettle();

      expect(grafikTipiNotifier.value, GrafikTipi.candle);
    });

    testWidgets('seçili tip chip\'te görünür', (tester) async {
      grafikTipiNotifier.value = GrafikTipi.candle;
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: GrafikTipiSecici())),
      ));
      await tester.pump();

      expect(find.text(GrafikTipi.candle.etiket), findsOneWidget);
    });
  });

  group('çizim bağlantısı — kaynak denetimi', () {
    final ekran = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
        .replaceAll('\r\n', '\n');

    test('Çizgi tipi dolgusuz', () {
      expect(ekran.contains('belowBarData: BarAreaData(show: false)'), isTrue);
    });

    test('tip değişince grafik YENİDEN çizilir', () {
      expect(ekran.contains('valueListenable: grafikTipiNotifier'), isTrue,
          reason: 'Dinleyici yok — seçim görsele yansımaz.');
    });

    test('kapalı kuyruk HER tipte nötr kalır', () {
      // Hafta sonu kuyruğu gerçek işlem değil; birikim gibi görünmemeli:
      // kesikli çizilir (dolgu artık hiçbir tipte yok).
      expect(ekran.contains('seg.piyasaKapali ? const [4, 4]'), isTrue);
    });
  });
}
