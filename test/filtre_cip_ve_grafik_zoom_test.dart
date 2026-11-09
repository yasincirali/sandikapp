import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy_grubu.dart';
import 'package:portfoy_takip/services/tur_filtre_ozeti.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';

/// TestFlight bulgusu 2026-10-12 (yasin):
///  1. Performans › Filtre: "filtreler değiştikçe hoplayıp zıplıyor, yer
///     değiştiriyor; sabit kalmalı."
///  2. Varlık grafiği "pek sağlıklı değil" (Gram Altın · Bugün · LOG):
///     gün içi eksen tam gün, LOG bandı verinin çok üstünde; zoom zayıf.
void main() {
  Widget sar(Widget w) => MaterialApp(
        theme: ThemeData(extensions: const [SandikPalette.dark]),
        home: Scaffold(body: Center(child: SizedBox(width: 390, child: w))),
      );

  group('filtre çipi sabit yer tutar', () {
    testWidgets('seçilince genişliği değişmez', (tester) async {
      Future<Size> boy(bool secili) async {
        await tester.pumpWidget(sar(Align(
          alignment: Alignment.topLeft,
          child: SandikFiltreCipi(ad: 'Altın', secili: secili, onTap: () {}),
        )));
        await tester.pumpAndSettle();
        return tester.getSize(find.byType(SandikFiltreCipi));
      }

      final secili = await boy(true);
      final degil = await boy(false);
      expect(secili.width, degil.width,
          reason: 'onay işareti çipi genişletip satırı yeniden kırıyordu');
      expect(secili.height, greaterThanOrEqualTo(SandikTouch.min));
    });

    testWidgets('kategori seçimi değişince hiçbir çip yer değiştirmez',
        (tester) async {
      const h = PortfoyGrubu(AssetType.hisse);
      const a = PortfoyGrubu(AssetType.altin);
      const d = PortfoyGrubu(AssetType.doviz);
      final ozet = TurFiltreOzeti(
          adet: {h: 2, a: 1, d: 1}, deger: {h: 900, a: 500, d: 100});
      final turlar =
          PortfoyGrubu.listesi(AssetType.values, pazarAyir: false);

      Future<Map<String, Offset>> konumlar(PortfoyGrubu? secili) async {
        await tester.pumpWidget(sar(TurFiltreCipleri(
          secili: secili,
          ozet: ozet,
          turlar: turlar,
          onSec: (_) {},
        )));
        await tester.pumpAndSettle();
        return {
          for (final e in tester.widgetList<SandikFiltreCipi>(
              find.byType(SandikFiltreCipi)))
            e.ad: tester.getTopLeft(find.byWidget(e)),
        };
      }

      final once = await konumlar(null);
      for (final s in [a, d, h]) {
        expect(await konumlar(s), once);
      }
    });

    test('sıra özeti verilince kişi değişse de sıra aynı kalır', () {
      const h = PortfoyGrubu(AssetType.hisse);
      const a = PortfoyGrubu(AssetType.altin);
      final turlar =
          PortfoyGrubu.listesi(AssetType.values, pazarAyir: false);
      final herkes =
          TurFiltreOzeti(adet: {h: 3, a: 2}, deger: {h: 900, a: 500});
      // Seçili kişide yalnız altın var: eskiden sıra altın öne geçiyordu.
      final kisi = TurFiltreOzeti(adet: {a: 1}, deger: {a: 50});
      final s = TurFiltreCipleri.sirala(turlar, herkes);
      expect(s.eldeki, [h, a]);
      expect(TurFiltreCipleri.sirala(turlar, kisi).eldeki, [a],
          reason: 'sıra özeti verilmeyen çağıranın eski davranışı');
    });
  });

  group('fiyat grafiği Y bandı (LOG)', () {
    test('LOG gün içi bant veriye oturur (Gram Altın 6.580–6.680)', () {
      double lg(double v) => math.log(v) / math.ln10;
      final lo = lg(6580), hi = lg(6680);
      final b = gorunurYBandi(
        dataMinY: lo,
        dataMaxY: hi,
        avgY: (lo + hi) / 2,
        asgariBantOrani: fiyatAsgariBantOrani(gunIci: true, log: true),
        asgariAralik:
            fiyatAsgariAraligi(log: true, ortalama: (lo + hi) / 2, gunIci: true),
      );
      final ust = math.pow(10, b.maxY).toDouble();
      final alt = math.pow(10, b.minY).toDouble();
      // Eskiden ₺6,92K'ya çıkıyordu (verinin %3,6 üstü); veri bandın
      // yarısından azını dolduruyordu.
      expect(ust, lessThan(6800));
      expect(alt, greaterThan(6450));
      expect((hi - lo) / (b.maxY - b.minY), greaterThan(0.45));
    });

    test('doğrusal oranlar aynen (gün içi %0,5, diğer %2)', () {
      expect(fiyatAsgariBantOrani(gunIci: true, log: false),
          gunIciAsgariBantOrani);
      expect(fiyatAsgariBantOrani(gunIci: false, log: false), 0.02);
      expect(fiyatAsgariBantOrani(gunIci: false, log: true), 0.0);
    });
  });

  group('gün içi X tick adımı', () {
    test('yuvarlak saat: 04:48 gibi adım yok', () {
      for (var dk = 30.0; dk <= 1800; dk += 7) {
        final a = gunIciTickDk(dk);
        expect(1440 % a == 0 || a % 1440 == 0, isTrue, reason: '$dk → $a');
        expect(dk / a, lessThanOrEqualTo(4.0 + 1e-9));
      }
      expect(gunIciTickDk(19 * 60), 360);
      expect(gunIciTickDk(120), 30);
    });
  });

  group('ZoomableChart çift dokunuş', () {
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

    testWidgets('yakınlaşır, ikinci çift dokunuş sıfırlar', (tester) async {
      final vp = ChartViewport(fullMinX: 0, fullMaxX: 10);
      addTearDown(vp.dispose);
      await tester.pumpWidget(sar(ZoomableChart(
        fullMinX: 0,
        fullMaxX: 10,
        height: 300,
        enableTimeScaleDrag: false,
        viewportController: vp,
        builder: veri,
      )));
      final merkez = tester.getCenter(find.byType(ZoomableChart));

      Future<void> ciftDokun() async {
        await tester.tapAt(merkez);
        await tester.pump(const Duration(milliseconds: 80));
        await tester.tapAt(merkez);
        await tester.pumpAndSettle();
      }

      await ciftDokun();
      expect(vp.maxX - vp.minX, closeTo(4.0, 1e-6));
      expect(vp.minX, lessThan(5));
      expect(vp.maxX, greaterThan(5), reason: 'dokunulan yer pencerede kalır');
      // Sıfırla çipi 44 pt dokunma alanıyla görünür.
      expect(find.text('Sıfırla'), findsOneWidget);
      final cip = find
          .ancestor(
              of: find.text('Sıfırla'), matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(cip).height, greaterThanOrEqualTo(SandikTouch.min));

      await ciftDokun();
      expect(vp.minX, 0);
      expect(vp.maxX, 10);
    });
  });
}
