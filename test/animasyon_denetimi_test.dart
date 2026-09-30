import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/acilis_kapisi.dart';
import 'package:portfoy_takip/utils/friendly_error.dart';
import 'package:portfoy_takip/widgets/kapanan_satir.dart';
import 'package:portfoy_takip/widgets/sandik_acilir.dart';
import 'package:portfoy_takip/widgets/sekme_basa_don.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// Animasyon denetimi (2026-10-01) — birinci kademe: kullanıcının doğrudan
/// hissettiği dört hata. Her test bir hatanın geri gelmesini kilitler.
void main() {
  group('çıkış eğrisi', () {
    test('SandikMotion.exit, enter.flipped ile birebir aynı', () {
      for (var t = 0.0; t <= 1.0; t += 0.05) {
        expect(SandikMotion.exit.transform(t),
            closeTo(SandikMotion.enter.flipped.transform(t), 2e-3));
      }
    });

    test('tersten oynayınca ease-out: çıkışın ilk yarısında çoğu biter', () {
      // Ters yönde değer = exit(1 - geçen). Yarı sürede opaklık 0,5'in
      // ALTINDA olmalı — eski hâlde (enter tersten) 0,875'ti.
      final yaridaOpaklik = SandikMotion.exit.transform(0.5);
      expect(yaridaOpaklik, lessThan(0.2));
    });

    testWidgets('marka diyaloğu kapanırken yarı sürede büyük ölçüde solmuş',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.shrink();
        }),
      ));
      // ignore: unawaited_futures
      showAppInfo(ctx, title: 'Başlık', message: 'Mesaj');
      await tester.pumpAndSettle();

      Navigator.of(ctx).pop();
      await tester.pump();
      await tester.pump(SandikMotion.surface ~/ 2);

      final fade = tester.widget<FadeTransition>(find
          .ancestor(of: find.text('Başlık'), matching: find.byType(FadeTransition))
          .first);
      expect(fade.opacity.value, lessThan(0.3),
          reason: 'kapanış ease-in kalmış: diyalog yarı sürede hâlâ görünür');
      await tester.pumpAndSettle();
    });
  });

  group('SandikAcilir', () {
    Widget kur(bool acik, {bool azalt = false}) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: azalt),
            child: Scaffold(
              body: Column(children: [
                SandikAcilir(acik: acik, child: const Text('panel')),
              ]),
            ),
          ),
        );

    testWidgets('kapanırken içerik ilk karede silinmez, sonunda ağaçtan çıkar',
        (tester) async {
      await tester.pumpWidget(kur(true));
      expect(find.text('panel'), findsOneWidget);
      await tester.pumpWidget(kur(false));
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('panel'), findsOneWidget,
          reason: 'eskiden panel ilk karede siliniyor, boş kutu küçülüyordu');
      await tester.pumpAndSettle();
      expect(find.text('panel'), findsNothing,
          reason: 'kapalıyken ağaçta kalmamalı (hesap/çizim maliyeti sıfır)');
    });

    testWidgets('hareketi azalt: anında açılır/kapanır', (tester) async {
      await tester.pumpWidget(kur(false, azalt: true));
      await tester.pumpWidget(kur(true, azalt: true));
      await tester.pump();
      final boy = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(boy.sizeFactor.value, 1);
    });
  });

  group('KapananSatir', () {
    testWidgets('iş hata verirse satır geri açılır', (tester) async {
      late BuildContext satirCtx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: KapananSatir(
            child: Builder(builder: (c) {
              satirCtx = c;
              return const Text('satır');
            }),
          ),
        ),
      ));
      Object? yakalanan;
      final is_ = KapananSatir.kapatVeYap(
              satirCtx, () async => throw StateError('ağ'))
          .catchError((Object e) => yakalanan = e);
      await tester.pumpAndSettle();
      await is_;
      expect(yakalanan, isA<StateError>());
      final boy = tester.widget<SizeTransition>(find.byType(SizeTransition));
      expect(boy.sizeFactor.value, 1, reason: 'kullanıcı sildiğini sanmamalı');
    });
  });

  group('SekmeBasaDon', () {
    testWidgets('açık sekmeye yeniden dokunuş yalnız o sekmenin listesini başa alır',
        (tester) async {
      final c = ScrollController();
      addTearDown(c.dispose);
      late VoidCallback birak;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (ctx) {
          birak = SekmeBasaDon.dinle(
              7, () => SekmeBasaDon.basaKaydir(ctx, c));
          return ListView.builder(
            controller: c,
            itemCount: 200,
            itemBuilder: (_, i) => SizedBox(height: 60, child: Text('$i')),
          );
        }),
      ));
      addTearDown(() => birak());
      c.jumpTo(5000);
      await tester.pump();

      SekmeBasaDon.yayinla(8); // başka sekme
      await tester.pumpAndSettle();
      expect(c.offset, 5000);

      SekmeBasaDon.yayinla(7);
      await tester.pumpAndSettle();
      expect(c.offset, 0);
    });
  });

  group('rotaGecisiniBekle', () {
    testWidgets('sayfa kayarak girerken bekler, geçiş bitince tamamlanır',
        (tester) async {
      late NavigatorState nav;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          nav = Navigator.of(c);
          return const SizedBox.shrink();
        }),
      ));
      var bitti = false;
      // ignore: unawaited_futures
      nav.push(MaterialPageRoute<void>(builder: (c) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          rotaGecisiniBekle(c).then((_) => bitti = true);
        });
        return const SizedBox.shrink();
      }));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(bitti, isFalse, reason: 'geçiş sürerken kapı açılmamalı');
      await tester.pumpAndSettle();
      expect(bitti, isTrue);
    });
  });

  group('korunanPencere', () {
    (double, double) p(double lo, double hi, double yeniMax,
            {double eskiMax = 10, double yeniMin = 0}) =>
        ChartViewport.korunanPencere(
          minX: lo,
          maxX: hi,
          eskiMin: 0,
          eskiMax: eskiMax,
          yeniMin: yeniMin,
          yeniMax: yeniMax,
        );

    test('yakınlaştırılmamışsa yeni tam aralık', () {
      expect(p(0, 10, 12), (0.0, 12.0));
    });

    test('ortada yakınlaştırılmışsa aynı yerde kalır', () {
      expect(p(3, 5, 12), (3.0, 5.0));
    });

    test('sağ kenara dayalıysa kenarla birlikte kayar, genişlik korunur', () {
      expect(p(8, 10, 12), (10.0, 12.0));
    });

    test('aralık daralınca pencere içeri itilir', () {
      expect(p(6, 9, 8, eskiMax: 10), (5.0, 8.0));
    });

    test('pencere yeni aralıktan genişse tam aralık', () {
      expect(p(1, 9, 5, eskiMax: 10), (0.0, 5.0));
    });
  });

  group('ZoomableChart', () {
    LineChartData veri(double lo, double hi) => LineChartData(
          minX: lo,
          maxX: hi,
          minY: 0,
          maxY: 10,
          lineBarsData: [
            LineChartBarData(spots: [
              for (var i = 0; i <= 10; i++) FlSpot(i.toDouble(), i.toDouble()),
            ]),
          ],
        );

    Widget host(ChartViewport vp, {double fullMaxX = 10}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                child: ZoomableChart(
                  fullMinX: 0,
                  fullMaxX: fullMaxX,
                  height: 300,
                  enableTimeScaleDrag: false,
                  viewportController: vp,
                  builder: veri,
                ),
              ),
            ),
          ),
        );

    testWidgets('yakınlaştırılmışken tek parmak kaydırma parmağı takip eder',
        (tester) async {
      final vp = ChartViewport(fullMinX: 0, fullMaxX: 10)..set(2, 4);
      addTearDown(vp.dispose);
      await tester.pumpWidget(host(vp));

      final merkez = tester.getCenter(find.byType(ZoomableChart));
      final g = await tester.startGesture(merkez);
      for (var i = 0; i < 10; i++) {
        await g.moveBy(const Offset(20, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();

      // 800 px'lik alanda genişlik 2: 200 px'in kabul eşiğinden sonraki
      // ≥150 px'i pencereyi ≥0,375 sola taşır. Eski hata yalnız SON
      // karenin 20 px'ini uyguluyordu (0,05 → minX 1,95).
      expect(vp.minX, lessThan(1.7));
      expect(vp.maxX - vp.minX, closeTo(2, 1e-9), reason: 'kaydırma yakınlaştırmayı bozmamalı');
    });

    testWidgets('aralık uzayınca yakınlaştırma sıfırlanmaz', (tester) async {
      final vp = ChartViewport(fullMinX: 0, fullMaxX: 10)..set(3, 5);
      addTearDown(vp.dispose);
      await tester.pumpWidget(host(vp));
      await tester.pumpWidget(host(vp, fullMaxX: 11));
      await tester.pump();
      expect((vp.minX, vp.maxX), (3.0, 5.0));
      expect(vp.fullMaxX, 11);
    });
  });
}
