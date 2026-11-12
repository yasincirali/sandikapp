import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/elde_tutma.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/premium_provider.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/elde_tutma_satiri.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart';

import 'helpers/kaynak.dart';

/// Elde tutma süresi ve yıllık ortalama getiri (Ar-Ge 7 Kas 20:30 #6).
///
/// Kilitlenen: (1) tek alışta yıllık oran `(son/maliyet)^(1/yıl) − 1`;
/// ara akışta para ağırlıklı (kesin IRR) ile yıllıklandırma; (2) 12 aydan
/// kısa, kapanmış, maliyeti bilinmeyen ya da değeri bilinmeyen pozisyonda
/// satır yok; (3) tamamen satılıp yeniden alınan pozisyonda süre yeni
/// alıştan; (4) satır Premium görünmüyorsa yok, kilitliyse kilit satırı;
/// (5) 3.1× ve 320 pt'de taşma yok, ekran okuyucu tek cümle.
Asset _lot(
  String id,
  AssetKind kind,
  DateTime tarih, {
  double miktar = 10,
  double fiyat = 100,
  double? satis,
  double temettu = 0,
  bool? maliyetYok,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Ak Portföy',
      ticker: 'TEFAS:AFT',
      type: AssetType.fon,
      quantity: miktar,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      dividendAmount: temettu,
      addedDate: tarih,
    )..maliyetBilinmiyor = maliyetYok;

void main() {
  final simdi = DateTime(2026, 11, 7, 12);

  group('eldeTutma (hesap)', () {
    test('tek alış: süre takvimden, yıllık oran bileşik', () {
      // 2 yıl 3 ay önce 1.000 TL, bugün 1.800 TL.
      final alis = DateTime(2024, 8, 7);
      final e = eldeTutma(
        lotlar: [_lot('b', AssetKind.buy, alis)],
        guncelDegerTRY: 1800,
        simdi: simdi,
      )!;
      expect((e.yil, e.ay), (2, 3));
      final gun = simdi.difference(alis).inMinutes / Duration.minutesPerDay;
      final beklenen = (math.pow(1.8, 365.25 / gun) - 1) * 100;
      expect(e.yillikPct, closeTo(beklenen, 1e-6));
    });

    test('zarar: işaret eksi', () {
      final e = eldeTutma(
        lotlar: [_lot('b', AssetKind.buy, DateTime(2024, 11, 7))],
        guncelDegerTRY: 810,
        simdi: simdi,
      )!;
      expect((e.yil, e.ay), (2, 0));
      expect(e.yillikPct, closeTo(-10, 0.05));
    });

    test('ara alış: para ağırlıklı, akış denklemini sağlar', () {
      final b1 = DateTime(2023, 11, 7);
      final b2 = DateTime(2025, 11, 7);
      final e = eldeTutma(
        lotlar: [
          _lot('b1', AssetKind.buy, b1),
          _lot('b2', AssetKind.buy, b2, fiyat: 200),
        ],
        guncelDegerTRY: 4000,
        simdi: simdi,
      )!;
      // 1000·(1+y)^t1 + 2000·(1+y)^t2 = 4000 (t yıl cinsinden).
      double yil(DateTime t) =>
          simdi.difference(t).inMinutes / Duration.minutesPerDay / 365.25;
      final y = e.yillikPct / 100;
      final deger =
          1000 * math.pow(1 + y, yil(b1)) + 2000 * math.pow(1 + y, yil(b2));
      expect(deger, closeTo(4000, 0.5));
    });

    test('12 aydan kısa: satır yok', () {
      expect(
          eldeTutma(
            lotlar: [_lot('b', AssetKind.buy, DateTime(2025, 11, 8))],
            guncelDegerTRY: 1500,
            simdi: simdi,
          ),
          isNull);
      // Tam 12. ay: satır var.
      expect(
          eldeTutma(
            lotlar: [_lot('b', AssetKind.buy, DateTime(2025, 11, 7))],
            guncelDegerTRY: 1500,
            simdi: simdi,
          )?.yil,
          1);
    });

    test('kapanmış, maliyeti ya da değeri bilinmeyen: satır yok', () {
      final alis = DateTime(2023, 1, 2);
      expect(
          eldeTutma(lotlar: [
            _lot('b', AssetKind.buy, alis),
            _lot('s', AssetKind.sell, DateTime(2024, 1, 2), satis: 150),
          ], guncelDegerTRY: 1, simdi: simdi),
          isNull);
      expect(
          eldeTutma(
              lotlar: [_lot('b', AssetKind.buy, alis, maliyetYok: true)],
              guncelDegerTRY: 1500,
              simdi: simdi),
          isNull);
      expect(
          eldeTutma(
              lotlar: [_lot('b', AssetKind.buy, alis)],
              guncelDegerTRY: 0,
              simdi: simdi),
          isNull);
    });

    test('tamamen satılıp yeniden alındı: süre yeni alıştan', () {
      final e = eldeTutma(lotlar: [
        _lot('b1', AssetKind.buy, DateTime(2020, 1, 2)),
        _lot('s1', AssetKind.sell, DateTime(2021, 1, 2), satis: 300),
        _lot('b2', AssetKind.buy, DateTime(2024, 5, 7)),
      ], guncelDegerTRY: 1210, simdi: simdi)!;
      expect((e.yil, e.ay), (2, 6));
      // Eski turun %200 kârı yeni turun oranına sızmaz.
      expect(e.yillikPct, lessThan(10));
    });

    test('silinmiş lot hesaba girmez', () {
      final silinmis = Asset(
        id: 'x',
        userId: 'u1',
        name: 'Ak Portföy',
        ticker: 'TEFAS:AFT',
        type: AssetType.fon,
        quantity: 10,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        addedDate: DateTime(2019, 1, 1),
        deletedAt: DateTime(2019, 2, 1),
      );
      final e = eldeTutma(lotlar: [
        silinmis,
        _lot('b', AssetKind.buy, DateTime(2024, 11, 7)),
      ], guncelDegerTRY: 1210, simdi: simdi)!;
      expect(e.yil, 2);
    });
  });

  group('EldeTutmaSatiri (arayüz)', () {
    const ozet = EldeTutma(yil: 2, ay: 3, yillikPct: 31.24);

    Future<void> pump(
      WidgetTester tester, {
      required bool gorunur,
      bool kilitli = false,
      double olcek = 1,
      double genislik = 400,
      EldeTutma e = ozet,
    }) async {
      tester.view.physicalSize = Size(genislik, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          premiumOzellikleriGorunurProvider.overrideWithValue(gorunur),
          premiumKilitliProvider.overrideWithValue(kilitli),
        ],
        child: MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark],
          ),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(genislik, 800),
                textScaler: TextScaler.linear(olcek)),
            child: Scaffold(
              body: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: EldeTutmaSatiri(ozet: e),
              ),
            ),
          ),
        ),
      ));
    }

    testWidgets('Premium: süre, işaretli yıllık oran, tek cümle etiket',
        (tester) async {
      await pump(tester, gorunur: true);
      expect(find.text('2 yıl 3 aydır tutuyorsun · yıllık ortalama +%31,2'),
          findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp(
              r'^2 yıl 3 aydır tutuyorsun\. .*yıllık ortalama getirin \+%31,2\.$')),
          findsOneWidget);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('tam yıl ve eksi yön: "2 yıldır", eksi işaret', (tester) async {
      await pump(tester,
          gorunur: true, e: const EldeTutma(yil: 2, ay: 0, yillikPct: -4.06));
      expect(find.text('2 yıldır tutuyorsun · yıllık ortalama −%4,1'),
          findsOneWidget);
    });

    testWidgets('ücretsiz (kilitli): süre açık, oran yok, 44 pt',
        (tester) async {
      await pump(tester, gorunur: true, kilitli: true);
      expect(find.byType(KilitSatiri), findsOneWidget);
      // Yarı açık: süre kendi defterinden ücretsiz, yıllık oran kilitli.
      expect(
          find.text("2 yıl 3 aydır tutuyorsun · yıllık ortalaman Premium'da"),
          findsOneWidget);
      expect(find.textContaining('31,2'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(tester.getSize(find.byType(KilitSatiri)).height,
          greaterThanOrEqualTo(SandikTouch.min));
    });

    testWidgets('Premium görünmüyorsa hiçbir şey', (tester) async {
      await pump(tester, gorunur: false);
      expect(find.textContaining('tutuyorsun'), findsNothing);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    for (final kilitli in [false, true]) {
      testWidgets('3.1× ve 320 pt: taşma yok (kilitli: $kilitli)',
          (tester) async {
        await pump(tester,
            gorunur: true, kilitli: kilitli, olcek: 3.1, genislik: 320);
        expect(tester.takeException(), isNull);
      });
    }

    test('varlık ekranı satırı pozisyon satırının altında çizer', () {
      final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(k, contains('EldeTutmaSatiri(ozet: e)'));
      expect(k, contains('eldeTutma('));
    });
  });
}
