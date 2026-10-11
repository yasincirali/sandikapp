import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/ohlc.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/mum_verisi.dart';
import 'package:portfoy_takip/utils/hareketli_ortalama.dart';
import 'package:portfoy_takip/utils/mum_turetici.dart';
import 'package:portfoy_takip/widgets/grafik_arac_cubugu.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Grafik göstergelerinin dört yüzeyde tutarlılığı (yasin, 2026-10-11
/// TestFlight):
///  · "EMA50 EMA200 ya yanlış çiziliyor ya hiç çizilmiyor" → ortalama
///    seçili sıklığın çubuklarından, ısınmayla (`cubukOrtalamasi`).
///  · "mum seçili değilken sıklık gelmiyor" → gösterge açıkken de var.
///  · "gösterge değişince grafik bozulup tekrar çiziliyor" → çubuk sayısı
///    değişince morf yok, bant fiyattan.
///  · "zaman değişikliğinde zoom defaultunda açılmalı" → sıfırlama anahtarı.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  // Günlük çubuklar: 2026-01-01'den itibaren, kapanış = 100 + i.
  List<OhlcBar> gunluk(int adet) => [
        for (var i = 0; i < adet; i++)
          OhlcBar(
            t: DateTime(2026, 1, 1).add(Duration(days: i)).millisecondsSinceEpoch,
            acilis: 100.0 + i,
            enYuksek: 101.0 + i,
            enDusuk: 99.0 + i,
            kapanis: 100.0 + i,
          ),
      ];

  group('cubukOrtalamasi', () {
    test('ısınma sayesinde EMA200 dönemin İLK çubuğundan başlar', () {
      final barlar = gunluk(260); // 200 ısınma + 60 dönem
      final donemBas = barlar[200].t;
      final ema = cubukOrtalamasi(barlar,
          aralik: MumAraligi.gun1,
          periyot: 200,
          tur: OrtalamaTuru.ustel,
          gorunurBasMs: donemBas);
      expect(ema.length, 60);
      // X çubuğun ORTASI (mumun merkezXi ile aynı).
      expect(ema.first.x, donemBas + MumAraligi.gun1.ms / 2);
      // Isınma yokken (yalnız dönem çubukları) EMA200 hiç çizilemezdi.
      final isinmasiz = cubukOrtalamasi(barlar.sublist(200),
          aralik: MumAraligi.gun1,
          periyot: 200,
          tur: OrtalamaTuru.ustel,
          gorunurBasMs: donemBas);
      expect(isinmasiz, isEmpty);
    });

    test('SMA20 = son 20 kapanışın ortalaması', () {
      final barlar = gunluk(30);
      final sma = cubukOrtalamasi(barlar,
          aralik: MumAraligi.gun1,
          periyot: 20,
          tur: OrtalamaTuru.basit,
          gorunurBasMs: barlar.first.t);
      // Son çubuk: kapanışlar 110..129 → ortalama 119,5.
      expect(sma.last.y, closeTo(119.5, 1e-9));
      expect(sma.length, 11);
    });

    test('ölçek ve birim: kesirli gün uzayına taşınır', () {
      final barlar = gunluk(60);
      final bas = barlar[10].t.toDouble();
      final ema = cubukOrtalamasi(barlar,
          aralik: MumAraligi.gun1,
          periyot: 50,
          tur: OrtalamaTuru.ustel,
          gorunurBasMs: barlar[10].t,
          baslangicMs: bas,
          birimMs: 86400000);
      expect(ema.first.x, closeTo(39.5, 1e-9)); // 49. çubuk, ortası
    });

    test('bozuk kapanış atlanır, yetersiz çubukta boş (uydurma yok)', () {
      final barlar = [
        ...gunluk(10),
        OhlcBar(
            t: DateTime(2026, 2, 1).millisecondsSinceEpoch,
            acilis: 1,
            enYuksek: 1,
            enDusuk: 1,
            kapanis: double.nan),
      ];
      expect(
          cubukOrtalamasi(barlar,
              aralik: MumAraligi.gun1,
              periyot: 20,
              tur: OrtalamaTuru.basit,
              gorunurBasMs: 0),
          isEmpty);
    });

    test('donemCubuklari ısınma çubuklarını mumdan ayıklar', () {
      final barlar = gunluk(10);
      final d = donemCubuklari(barlar, MumAraligi.gun1, barlar[4].t);
      expect(d.length, 6);
      expect(d.first.t, barlar[4].t);
    });
  });

  group('sıklık', () {
    test('seçici mum YA DA gösterge açıkken gerekir', () {
      bool g({bool mum = false, bool ma = false, bool e50 = false,
              bool e200 = false, bool ozel = false}) =>
          aralikGerekli(
              mum: mum, ma20: ma, ema50: e50, ema200: e200, ozel: ozel);
      expect(g(), isFalse, reason: 'yalnız çizgi: değiştirecek bir şey yok');
      expect(g(mum: true), isTrue);
      expect(g(ma: true), isTrue);
      expect(g(e50: true), isTrue);
      expect(g(e200: true), isTrue);
      expect(g(ozel: true), isTrue);
    });

    testWidgets('mum kapalı, EMA açık: sıklık menüsü görünür', (t) async {
      Widget cubuk({required bool ema}) => ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: GrafikAracCubugu(
                  katmanlar: true,
                  ma20Acik: false,
                  ema50Acik: ema,
                  aralik: MumAraligi.gun1,
                  gecerliAraliklar: const [
                    MumAraligi.saat1,
                    MumAraligi.gun1,
                  ],
                  pencereDakika: 365 * 1440.0,
                ),
              ),
            ),
          );
      await t.pumpWidget(cubuk(ema: false));
      expect(find.byType(MumAraligiMenusu), findsNothing);
      await t.pumpWidget(cubuk(ema: true));
      expect(find.byType(MumAraligiMenusu), findsOneWidget);
    });

    test('Performans: türetilmiş mumda her mum en az iki nokta', () {
      // 1A, günlük nokta (~30): saatlik mum tek noktalı olurdu → sunulmaz.
      final g = turetilmisAraliklar(spanDakika: 30 * 1440, noktaSayisi: 30);
      expect(g.contains(MumAraligi.saat1), isFalse);
      expect(g.contains(MumAraligi.gun1), isFalse,
          reason: 'günlük noktada günlük mum tek nokta');
      expect(g.contains(MumAraligi.hafta1), isTrue);
      // GÜNLÜK, 5 dk nokta (288): 15 dk, 30 dk, 1 sa, 4 sa.
      final gi = turetilmisAraliklar(spanDakika: 1440, noktaSayisi: 288);
      expect(gi.first, MumAraligi.dk15);
      expect(gi.contains(MumAraligi.dk5), isFalse);
      expect(turetilmisAraliklar(spanDakika: 1440, noktaSayisi: 1), isEmpty);
    });

    test('seçili sıklık kovası türetilmiş muma uygulanır', () {
      final bas = DateTime(2026, 1, 5).millisecondsSinceEpoch.toDouble();
      // 4 hafta, günlük nokta, ekran X'i kesirli gün.
      final spots = [
        for (var i = 0; i < 28; i++) FlSpot(i.toDouble(), 100.0 + i),
      ];
      final haftalik = mumlariGrafikUzayinda(spots,
          baslangicMs: bas,
          birimMs: 86400000,
          kovaMs: MumAraligi.hafta1.ms.toDouble());
      expect(haftalik.length, 4);
      expect(haftalik.first.noktaSayisi, 7);
    });

    test('gecerliIcindenAralik: seçim > TradingView varsayılanı > en yakın',
        () {
      const g = [MumAraligi.saat4, MumAraligi.gun1, MumAraligi.hafta1];
      expect(gecerliIcindenAralik(g, 365 * 1440, MumAraligi.hafta1),
          MumAraligi.hafta1);
      expect(gecerliIcindenAralik(g, 365 * 1440, null), MumAraligi.gun1);
      expect(gecerliIcindenAralik(g, 365 * 1440, MumAraligi.dk1),
          MumAraligi.gun1, reason: 'geçersiz seçim yok sayılır');
      expect(gecerliIcindenAralik(const [], 1440, null), isNull);
    });
  });

  group('grafik sabit kalır', () {
    LineChartData veri(double minX, double maxX, {int katman = 0}) =>
        LineChartData(
          minX: minX,
          maxX: maxX,
          minY: 0,
          maxY: 10,
          lineBarsData: [
            for (var i = 0; i < katman; i++)
              LineChartBarData(spots: const [FlSpot(0, 5), FlSpot(10, 6)]),
            LineChartBarData(spots: const [FlSpot(0, 1), FlSpot(10, 9)]),
          ],
        );

    Widget grafik({Object? anahtar, int katman = 0, double max = 10}) =>
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: ZoomableChart(
                fullMinX: 0,
                fullMaxX: max,
                height: 200,
                sifirlamaAnahtari: anahtar,
                builder: (mn, mx) => veri(mn, mx, katman: katman),
              ),
            ),
          ),
        );

    double gorunenMinX(WidgetTester t) =>
        t.widget<LineChart>(find.byType(LineChart)).data.minX;

    testWidgets('dönem değişince yakınlaştırma sıfırlanır', (t) async {
      await t.pumpWidget(grafik(anahtar: 30));
      // Çift dokunuş yerine yakınlaştırma: iki parmak.
      final merkez = t.getCenter(find.byType(LineChart));
      final p1 = await t.startGesture(merkez - const Offset(20, 0));
      final p2 = await t.startGesture(merkez + const Offset(20, 0));
      await t.pump();
      await p1.moveBy(const Offset(-80, 0));
      await p2.moveBy(const Offset(80, 0));
      await t.pump();
      await p1.up();
      await p2.up();
      await t.pumpAndSettle();
      expect(gorunenMinX(t), greaterThan(0.5), reason: 'yakınlaştı');

      // Aynı anahtar, aralık değişti (dakika dönümü): pencere korunur.
      await t.pumpWidget(grafik(anahtar: 30, max: 10.01));
      await t.pumpAndSettle();
      expect(gorunenMinX(t), greaterThan(0.5));

      // Dönem değişti: tam aralık.
      await t.pumpWidget(grafik(anahtar: 365, max: 10.01));
      await t.pumpAndSettle();
      expect(gorunenMinX(t), 0);
    });

    testWidgets('katman eklenince morf yok: fiyat çizgisi kımıldamaz',
        (t) async {
      await t.pumpWidget(grafik());
      await t.pumpAndSettle();
      await t.pumpWidget(grafik(katman: 1));
      // Tek kare: morf olsaydı ilk çubuk (yeni EMA) eski fiyat çizgisinden
      // kendi noktalarına doğru ara değerde olurdu.
      await t.pump(const Duration(milliseconds: 16));
      final cizim = t.widget<LineChart>(find.byType(LineChart));
      expect(cizim.duration, Duration.zero);
    });

    test('bant fiyattan: ortalamalar ve kendi göstergen eksene girmez', () {
      final fiyat = ekranKaynagiSync('lib/widgets/fiyat_grafigi.dart');
      expect(fiyat.contains('ozelBant'), isFalse);
      expect(fiyat.contains('for (final o in ortalamalar) {\n      for (final p in o.spots) {\n        kat('),
          isFalse);
      final detay = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(detay.contains('for (final e in emaCizgileri) ...e.spots'),
          isFalse);
      final yuzde =
          ekranKaynagiSync('lib/widgets/percent_comparison_chart.dart');
      expect(yuzde.contains('for (final o in k.ortalamalar) {\n        for'),
          isFalse);
    });

    test('dört yüzey çubuktan ortalama ve sıfırlama anahtarı kullanır', () {
      for (final yol in [
        'lib/screens/asset_detail/grafik_katmanlari.dart',
        'lib/widgets/katmanli_fiyat_grafigi.dart',
        'lib/screens/comparison_screen.dart',
      ]) {
        expect(ekranKaynagiSync(yol).contains('cubukOrtalamasi('), isTrue,
            reason: yol);
      }
      for (final yol in [
        'lib/screens/asset_detail_screen.dart',
        'lib/widgets/katmanli_fiyat_grafigi.dart',
        'lib/screens/comparison_screen.dart',
      ]) {
        expect(ekranKaynagiSync(yol).contains('sifirlamaAnahtari'), isTrue,
            reason: yol);
      }
      expect(
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
              .contains('MumAraligiMenusu('),
          isTrue);
    });
  });
}
