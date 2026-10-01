import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/contribution_history_service.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/inflation_service.dart';
import 'package:portfoy_takip/services/insight_metrics_service.dart';
import 'package:portfoy_takip/services/para_agirlikli_getiri.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';
import 'package:portfoy_takip/widgets/portfolio_summary_widget.dart';

/// Getiri motoru — "tek getiri dili, XIRR her yerde" (kullanıcı kararı
/// 2026-10-01).
///
/// Kilitlenen dört karar:
///   K3 — nakit temettü dönem getirisine ÇIKIŞ akışı olarak girer
///        (`getiriAkisi`); köprü `baş + net katkı + piyasa = son` korunur,
///        "Bunun nakit temettüsü" satırı gerçekten piyasanın içindedir.
///   K2 — ≤1Y yıllığa çevrilmez; >1 yıl ölçülen 5Y'de yıllık oran.
///   K4 — reel getiri akışları kendi tarihinin TÜFE düzeyinde taşır; akış
///        yoksa ve enflasyon düzgünse `(1+n)/(1+e)−1` ile birebir.
///   Oynaklık — bar getirisi akıştan arındırılır.
///   Ana ekran — kâr satırının adı "Maliyetine göre kâr".
///
/// Beklenen sayılar elle / Python ile, aynı formülle hesaplandı.
Asset _lot(
  String id,
  double qty,
  DateTime added, {
  double fiyat = 100,
  AssetKind kind = AssetKind.buy,
  double? satis,
  double temettu = 0,
  String ticker = 'THYAO',
}) =>
    Asset(
      id: id,
      userId: 'u',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: added,
      kind: kind,
      sellPrice: satis,
      dividendAmount: temettu,
    );

Asset _temettu(String id, double tutar, DateTime t, {String ticker = 'THYAO'}) =>
    _lot(id, 0, t, fiyat: 0, kind: AssetKind.dividend, temettu: tutar,
        ticker: ticker);

/// Günlük seri: her gün 18:00, `deger(i)`.
Map<int, double> _gunluk(DateTime bas, int gun, double Function(int i) deger) =>
    {
      for (var i = 0; i < gun; i++)
        DateTime(bas.year, bas.month, bas.day + i, 18).millisecondsSinceEpoch:
            deger(i),
    };

PortfolioHistoryBreakdown _bd(Map<int, double> total, {DateTime? seansGunu}) =>
    PortfolioHistoryBreakdown(
      total: total,
      byType: {AssetType.hisse: total},
      byPosition: const {},
      positionType: const {},
      seansGunu: seansGunu,
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  // ════════════════════════════════════════════════════════════════════
  // K3 — temettü getiriye dahil
  // ════════════════════════════════════════════════════════════════════
  group('K3 getiriAkisi: tek kural', () {
    final t = DateTime(2026, 9, 1);
    test('alım +, satış −, nakit temettü −, silinen 0', () {
      final alim = _lot('a', 10, t);
      final satis =
          _lot('s', 10, t, kind: AssetKind.sell, satis: 120);
      final tem = _temettu('d', 750, t);
      final silinen = _lot('x', 10, t, kind: AssetKind.deleteLog);
      expect(getiriAkisi(alim), 1000);
      expect(getiriAkisi(satis), -1200);
      expect(getiriAkisi(tem), -750,
          reason: 'nakit portföyden cebe çıktı — satış geliri gibi');
      expect(getiriAkisi(silinen), 0);
    });

    test('flowOf (KATKI sorusu) temettüyü saymaz, alım/satımda aynı', () {
      final tem = _temettu('d', 750, t);
      expect(PeriodSummaryService.flowOf(tem), 0);
      final alim = _lot('a', 10, t);
      expect(PeriodSummaryService.flowOf(alim), getiriAkisi(alim));
    });

    test('birikim disiplini (netInflow varsayılanı) temettüyü saymaz', () {
      final lotlar = [_temettu('d', 750, DateTime(2026, 9, 10))];
      final bas = DateTime(2026, 9, 1);
      final son = DateTime(2026, 9, 30);
      expect(PeriodSummaryService.netInflow(lotlar, bas, son), 0);
      expect(
          PeriodSummaryService.netInflow(lotlar, bas, son, temettuCikis: true),
          -750);
      final kova = ContributionHistoryService.buckets(lotlar,
          aralik: ContributionInterval.aylik,
          now: DateTime(2026, 9, 30),
          kovaSayisi: 1);
      expect(kova.single.netTRY, 0,
          reason: '"bu ay ne kadar para koydum" sorusunda temettü yok');
    });
  });

  group('K3 Özet: temettü piyasanın içinde, köprü tutar', () {
    // 1.000 lot × ₺100. 10 Eylül'de hisse başına ₺5 temettü: fiyat 95'e
    // iner (seride), ₺5.000 nakit cebe çıkar (seride YOK).
    final bas = DateTime(2026, 9, 1);
    final now = DateTime(2026, 9, 20, 20);
    final seri = _gunluk(bas, 20, (i) => i < 10 ? 100000 : 95000);
    final lotlar = [
      _lot('ilk', 1000, DateTime(2026, 1, 5)),
      _temettu('tem', 5000, DateTime(2026, 9, 10, 12)),
    ];

    PeriodSummary ozet(List<Asset> l) => PeriodSummaryService.compute(
          period: SummaryPeriod.birAy,
          assets: l,
          breakdown: _bd(seri),
          now: now,
          pencereBaslangici: bas,
        );

    test('temettü kadar düşen fiyat KAYIP sayılmaz: piyasa 0, %0', () {
      final s = ozet(lotlar);
      expect(s.baslangicTRY, 100000);
      expect(s.sonTRY, 95000);
      expect(s.katkiTRY, -5000, reason: 'net katkı: temettü çıkış');
      expect(s.piyasaTRY, closeTo(0, 1e-9));
      expect(s.getiriPct, closeTo(0, 1e-9));
      expect(s.temettuTRY, 5000);
    });

    test('köprü değişmezi: baş + net katkı + piyasa = son', () {
      final s = ozet(lotlar);
      expect(s.baslangicTRY! + s.katkiTRY! + s.piyasaTRY!,
          closeTo(s.sonTRY!, 1e-9));
    });

    test('"Bunun nakit temettüsü" piyasa rakamına GERÇEKTEN eklenen tutar',
        () {
      final temettusuz = ozet([lotlar.first]);
      final s = ozet(lotlar);
      expect(s.piyasaTRY! - temettusuz.piyasaTRY!, closeTo(s.temettuTRY!, 1e-9));
    });

    test('taban ölçümünden ÖNCE ödenen temettü satıra da piyasaya da girmez',
        () {
      // Seri 1 Eyl 18:00'de başlıyor; 1 Eyl 09:00'daki temettü tabanın
      // ölçüldüğü andan önce — piyasa kapısının dışında.
      final s = ozet([
        lotlar.first,
        _temettu('erken', 3000, DateTime(2026, 9, 1, 9)),
      ]);
      expect(s.temettuTRY, isNull);
      expect(s.katkiTRY, 0);
    });

    test('para ağırlıklı yüzde temettüyü sayar ve XIRR ile aynı yönde', () {
      // Fiyat sabit 100 kalsaydı (temettü fiyattan düşmeseydi) ₺5.000
      // saf kazançtır: %5'e yakın, akış dönemde ~yarım kaldığı için biraz
      // fazlası.
      final sabit = _gunluk(bas, 20, (_) => 100000);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: lotlar,
        breakdown: _bd(sabit),
        now: now,
        pencereBaslangici: bas,
      );
      expect(s.piyasaTRY, closeTo(5000, 1e-9));
      expect(s.getiriPct!, greaterThan(5.0));
      expect(s.getiriPct!, lessThan(5.3));
    });
  });

  group('K3 Σ parça == bütün (varlık ekranı, tür filtresi)', () {
    final bas = DateTime(2026, 9, 1);
    final end = DateTime(2026, 9, 20, 20);
    final a = [
      _lot('a1', 100, DateTime(2026, 1, 5), ticker: 'AAA'),
      _temettu('ad', 400, DateTime(2026, 9, 8, 12), ticker: 'AAA'),
    ];
    final b = [
      _lot('b1', 50, DateTime(2026, 1, 5), ticker: 'BBB'),
      _lot('b2', 50, DateTime(2026, 9, 12, 12), ticker: 'BBB'),
    ];
    // AAA birim: 100 → temettüde 96 → 101. BBB birim: 200 → 210.
    double birimA(int i) => i < 8 ? 100 : (i < 15 ? 96 : 101);
    double birimB(int i) => i < 12 ? 200 : 210;
    final birimSeriA = _gunluk(bas, 20, birimA);
    final seriA = _gunluk(bas, 20, (i) => 100 * birimA(i));
    // b2 12 Eyl 12:00'de alındı: 12 Eyl 18:00 slotunda (i = 11) elde.
    final seriB = _gunluk(bas, 20, (i) => (i < 11 ? 50 : 100) * birimB(i));
    final toplam = {
      for (final k in seriA.keys) k: seriA[k]! + seriB[k]!,
    };

    test('pozisyon etkileri toplamı = toplam serinin etkisi (temettü dahil)',
        () {
      final pa = PeriodSummaryService.piyasaEtkisi(
          seri: seriA, lotlar: a, start: bas, end: end)!;
      final pb = PeriodSummaryService.piyasaEtkisi(
          seri: seriB, lotlar: b, start: bas, end: end)!;
      final pt = PeriodSummaryService.piyasaEtkisi(
          seri: toplam, lotlar: [...a, ...b], start: bas, end: end)!;
      expect(pa.piyasa + pb.piyasa, closeTo(pt.piyasa, 1e-6));
      expect(pa.temettu, 400);
      expect(pt.temettu, 400);
      // AAA: 100 × (101 − 100) + 400 temettü = 500.
      expect(pa.piyasa, closeTo(500, 1e-6));
    });

    test('varlık ekranı (birim seri) = pozisyon serisinin piyasa etkisi', () {
      final birim = PeriodSummaryService.birimPiyasaEtkisi(
          birimSeri: birimSeriA, lotlar: a, start: bas, end: end)!;
      final poz = PeriodSummaryService.piyasaEtkisi(
          seri: seriA, lotlar: a, start: bas, end: end)!;
      expect(birim.piyasa, closeTo(poz.piyasa, 1e-6));
    });
  });

  group('K3 GÜNLÜK (ana sayfa, widget, Live Activity) aynı kural', () {
    final gun = DateTime(2026, 9, 10);
    final now = DateTime(2026, 9, 10, 14, 2);
    Map<int, double> seans() {
      final out = <int, double>{};
      var i = 0;
      for (var dk = 600; dk <= 840; dk += 5) {
        out[gun.add(Duration(minutes: dk)).millisecondsSinceEpoch] =
            1000000 + 500.0 * i++;
      }
      return out;
    }

    final taban = _lot('taban', 10000, DateTime(2026, 1, 5), fiyat: 102.5);
    final tem = _temettu('tem', 5000, DateTime(2026, 9, 10, 11));

    test('gün içi temettü akıştan düşülür: değişim temettü kadar yüksek',
        () {
      final state0 = PortfolioState(assets: [taban], usdTry: 42);
      final state1 = PortfolioState(assets: [taban, tem], usdTry: 42);
      final d0 = DailySummary.from(
          state: state0, series: seans(), now: now, seansGunu: gun);
      final d1 = DailySummary.from(
          state: state1, series: seans(), now: now, seansGunu: gun);
      expect(d1.inflowTRY, -5000);
      expect(d1.changeTRY! - d0.changeTRY!, closeTo(5000, 1e-6));
      expect(d1.changePct!, greaterThan(d0.changePct!));
    });

    test('Özet GÜNLÜK köprüsü tutar ve DailySummary ile birebir', () {
      final assets = [taban, tem];
      final state = PortfolioState(assets: assets, usdTry: 42);
      final d = DailySummary.from(
          state: state, series: seans(), now: now, seansGunu: gun);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.gunluk,
        assets: assets,
        breakdown: _bd(seans(), seansGunu: gun),
        now: now,
        gunlukOzet: d,
      );
      expect(s.piyasaTRY, d.changeTRY);
      expect(s.getiriPct, d.changePct);
      expect(s.baslangicTRY! + s.katkiTRY! + s.piyasaTRY!,
          closeTo(s.sonTRY!, 1e-6));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // K2 — 1 yıldan kısa dönem yıllığa çevrilmez
  // ════════════════════════════════════════════════════════════════════
  group('K2 yıllık oran yalnız > 1 yıl', () {
    final now = DateTime(2026, 9, 30, 20);
    final lot = _lot('ilk', 1000, DateTime(2020, 1, 5));

    PeriodSummary ozet(SummaryPeriod p, Map<int, double> seri) =>
        PeriodSummaryService.compute(
            period: p, assets: [lot], breakdown: _bd(seri), now: now);

    test('5Y, iki yıl ölçülmüş: %21 toplam → yıllık %10,00', () {
      // 30 Eyl 2024 18:00 → 30 Eyl 2026 18:00 = 730 gün.
      final bas = DateTime(2024, 9, 30);
      final seri = _gunluk(bas, 731, (i) => i < 730 ? 100000 : 121000);
      final s = ozet(SummaryPeriod.besYil, seri);
      expect(s.getiriPct, closeTo(21.0, 1e-9));
      // 1,21^(365/730) − 1 = %10
      expect(s.yillikGetiriPct, closeTo(10.0, 1e-9));
    });

    test('1Y: yıllıklandırılmaz (dönem toplamı tek sayı)', () {
      final bas = DateTime(2025, 9, 30);
      final seri = _gunluk(bas, 366, (i) => i < 365 ? 100000 : 110000);
      final s = ozet(SummaryPeriod.birYil, seri);
      expect(s.getiriPct, closeTo(10.0, 1e-9));
      expect(s.yillikGetiriPct, isNull);
    });

    test('3A: yıllıklandırılmaz (GIPS)', () {
      final bas = DateTime(2026, 7, 1);
      final seri = _gunluk(bas, 92, (i) => i < 91 ? 100000 : 108000);
      final s = ozet(SummaryPeriod.ucAy, seri);
      expect(s.getiriPct, closeTo(8.0, 1e-9));
      expect(s.yillikGetiriPct, isNull);
    });

    test('5Y seçili ama portföy 8 aylık: yıllıklandırılmaz', () {
      final bas = DateTime(2026, 1, 30);
      final seri = _gunluk(bas, 244, (i) => i < 243 ? 100000 : 112000);
      final s = ozet(SummaryPeriod.besYil, seri);
      expect(s.getiriPct, isNotNull);
      expect(s.yillikGetiriPct, isNull,
          reason: 'ölçülen pencere < 1 yıl — olmamış bir gelecek varsayılmaz');
    });
  });

  group('K2 ana rakam kartı', () {
    Future<void> kur(WidgetTester t, PeriodSummary s) async {
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [SandikPalette.light]),
        home: Scaffold(
          body: SingleChildScrollView(child: PeriodSummaryView(summary: s)),
        ),
      ));
      await t.pumpAndSettle();
    }

    PeriodSummary ozet(SummaryPeriod p, {double? yillik}) => PeriodSummary(
          period: p,
          start: DateTime(2024, 9, 30),
          end: DateTime(2026, 9, 30),
          baslangicTRY: 100000,
          sonTRY: 121000,
          katkiTRY: 0,
          piyasaTRY: 21000,
          getiriPct: 21,
          yillikGetiriPct: yillik,
        );

    testWidgets('5Y: rozet yıllık oran, dönem toplamı yanında küçük',
        (t) async {
      await kur(t, ozet(SummaryPeriod.besYil, yillik: 10));
      expect(find.text('+%10,00 yıllık'), findsOneWidget);
      expect(find.text('Dönem toplamı +%21,00'), findsOneWidget);
    });

    testWidgets('1Y: rozet dönem toplamı, "yıllık" yok', (t) async {
      await kur(t, ozet(SummaryPeriod.birYil));
      expect(find.text('+%21,00'), findsWidgets);
      expect(find.textContaining('yıllık'), findsNothing);
      expect(find.textContaining('Dönem toplamı'), findsNothing);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // K4 — reel para ağırlıklı getiri
  // ════════════════════════════════════════════════════════════════════
  group('K4 tufeDuzeyi: ay sonu çapaları, ay içi sabit hız', () {
    final e = {DateTime(2026, 7, 1): 100.0, DateTime(2026, 8, 1): 102.5};
    test('çapada tam o ayın endeksi', () {
      expect(tufeDuzeyi(e, DateTime(2026, 7, 31)), 100);
      expect(tufeDuzeyi(e, DateTime(2026, 8, 31)), 102.5);
    });
    test('ay ortası: geometrik ara değer', () {
      final t = DateTime(2026, 8, 15, 12);
      final pay = t.difference(DateTime(2026, 7, 31)).inMilliseconds /
          DateTime(2026, 8, 31).difference(DateTime(2026, 7, 31)).inMilliseconds;
      expect(tufeDuzeyi(e, t),
          closeTo(100 * math.pow(1.025, pay).toDouble(), 1e-9));
    });
    test('gereken ay yoksa null — uydurma yok', () {
      expect(tufeDuzeyi(e, DateTime(2026, 9, 5)), isNull,
          reason: 'Eylül açıklanmadı');
      expect(tufeDuzeyi(e, DateTime(2026, 7, 15)), isNull,
          reason: 'Haziran tabloda yok');
    });
  });

  group('K4 reelParaAgirlikliGetiriPct', () {
    // Ağustos 2025 = 100; Eyl–Şub her ay %4, Mar–Ağu her ay %0,5.
    final endeks = <DateTime, double>{DateTime(2025, 8, 1): 100};
    var v = 100.0;
    for (var m = 1; m <= 12; m++) {
      v *= m <= 6 ? 1.04 : 1.005;
      endeks[DateTime(2025, 8 + m, 1)] = v;
    }
    final e = (v / 100 - 1) * 100; // %30,3756
    final basAn = DateTime(2025, 8, 31);
    final sonAn = DateTime(2026, 8, 31);

    test('akış yok: (1+n)/(1+e) − 1 ile birebir', () {
      final r = reelParaAgirlikliGetiriPct(
        bas: 100000,
        son: 140000,
        basAn: basAn,
        sonAn: sonAn,
        akislar: const [],
        endeks: endeks,
      )!;
      expect(r, closeTo(InflationService.realReturnPct(40, e), 1e-9));
    });

    test('enflasyon yıl başında yığılmış, para Mart\'ta eklenmiş: hüküm DÖNER',
        () {
      // ₺100.000 ile başlıyor; 1 Mar 2026'da ₺100.000 ekleniyor; sonda
      // ₺240.000. Nominal para ağırlıklı %27,186.
      //   Kapalı formül: 1,27186 / 1,30376 − 1 = −%2,446 → "altında"
      //   Reel (her akış kendi düzeyinde): +%3,637 → "üstünde"
      // Mart'ta eklenen para Eylül–Şubat'ın %4'lük aylarını YAŞAMADI.
      final t = DateTime(2026, 3, 1);
      final w = sonAn.difference(t).inMilliseconds /
          sonAn.difference(basAn).inMilliseconds;
      final n = paraAgirlikliGetiriPct(
          bas: 100000, son: 240000, akislar: [(f: 100000, w: w)])!;
      expect(n, closeTo(27.186050, 1e-5));
      final kapali = InflationService.realReturnPct(n, e);
      expect(kapali, closeTo(-2.446451, 1e-5));
      final r = reelParaAgirlikliGetiriPct(
        bas: 100000,
        son: 240000,
        basAn: basAn,
        sonAn: sonAn,
        akislar: [(f: 100000, w: w, an: t)],
        endeks: endeks,
      )!;
      expect(r, closeTo(3.636777, 1e-5));
      expect(InflationService.hukum(r), EnflasyonHukmu.ustunde);
      expect(InflationService.hukum(kapali), EnflasyonHukmu.altinda);
    });

    test('düzgün enflasyonda akış varken de kapalı formülle aynı (1A)', () {
      // Tek ay: ay içi sabit hız = pencere boyunca düzgün → cebirsel
      // olarak (1+n)/(1+e) − 1.
      final e1 = {DateTime(2026, 7, 1): 100.0, DateTime(2026, 8, 1): 102.5};
      final b = DateTime(2026, 7, 31);
      final s = DateTime(2026, 8, 31);
      final t = DateTime(2026, 8, 16, 10);
      final w = s.difference(t).inMilliseconds / s.difference(b).inMilliseconds;
      final n = paraAgirlikliGetiriPct(
          bas: 10000, son: 20600, akislar: [(f: 10200, w: w)])!;
      final r = reelParaAgirlikliGetiriPct(
        bas: 10000,
        son: 20600,
        basAn: b,
        sonAn: s,
        akislar: [(f: 10200, w: w, an: t)],
        endeks: e1,
      )!;
      expect(r, closeTo(InflationService.realReturnPct(n, 2.5), 1e-6));
    });

    test('akış tarihinin endeksi yoksa null', () {
      final eksik = Map.of(endeks)..remove(DateTime(2026, 2, 1));
      expect(
          reelParaAgirlikliGetiriPct(
            bas: 100000,
            son: 240000,
            basAn: basAn,
            sonAn: sonAn,
            akislar: [(f: 100000, w: 0.5, an: DateTime(2026, 2, 15))],
            endeks: eksik,
          ),
          isNull);
    });

    test('compute(tufeEndeksi:) reeli bu yoldan doldurur', () {
      // 1A, akış yok: reel = kapalı formül.
      final e1 = {DateTime(2026, 7, 1): 100.0, DateTime(2026, 8, 1): 102.5};
      final seri = _gunluk(DateTime(2026, 7, 31), 32,
          (i) => i < 31 ? 100000 : 103000);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: [_lot('ilk', 1000, DateTime(2026, 1, 5))],
        breakdown: _bd({
          for (final k in seri.keys)
            // 18:00 yerine 00:00 slot: TÜFE penceresinin uçları.
            DateTime.fromMillisecondsSinceEpoch(k)
                .subtract(const Duration(hours: 18))
                .millisecondsSinceEpoch: seri[k]!,
        }),
        now: DateTime(2026, 8, 31),
        pencereBaslangici: DateTime(2026, 7, 31),
        tufeEndeksi: e1,
      );
      expect(s.getiriPct, closeTo(3.0, 1e-9));
      expect(s.reelGetiriPct,
          closeTo(InflationService.realReturnPct(3.0, 2.5), 1e-9));
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Oynaklık — akıştan arındırılmış
  // ════════════════════════════════════════════════════════════════════
  group('oynaklık: para girişi sıçrama sayılmaz', () {
    final bas = DateTime(2026, 6, 1);
    // Fiyat: hafif dalga. 30. günde aynı miktar kadar alım (portföy ikiye
    // katlanır) — ham seride tek barda ~+%100.
    double fiyat(int i) => 100 * (1 + 0.01 * math.sin(i.toDouble()));
    const gun = 60;
    final fiyatSerisi = _gunluk(bas, gun, (i) => 1000 * fiyat(i));
    final degerSerisi =
        _gunluk(bas, gun, (i) => (i < 30 ? 1000 : 2000) * fiyat(i));
    final lotlar = [
      _lot('ilk', 1000, DateTime(2026, 1, 5)),
      // 30. günün slotundan (18:00) önce, slot fiyatından.
      _lot('ek', 1000, DateTime(2026, 6, 31, 10), fiyat: fiyat(30)),
    ];

    test('ham hesap şişer, arındırılmış hesap saf fiyat oynaklığına eşit', () {
      final saf = InsightMetricsService.annualizedVolatility(fiyatSerisi,
          barSuresiGun: 1)!;
      final ham = InsightMetricsService.annualizedVolatility(degerSerisi,
          barSuresiGun: 1)!;
      final arinmis = InsightMetricsService.annualizedVolatility(degerSerisi,
          barSuresiGun: 1, lotlar: lotlar)!;
      expect(ham, greaterThan(saf * 5), reason: 'giriş sıçraması şişiriyor');
      expect(arinmis, closeTo(saf, 1e-9));
    });

    test('düşüş (maxDrawdown) bilinçli olarak ham kalır', () {
      // İmza değişmedi: lot almaz.
      expect(InsightMetricsService.maxDrawdown(degerSerisi), isNotNull);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // Ana ekran — "Maliyetine göre kâr"
  // ════════════════════════════════════════════════════════════════════
  group('ana ekran kâr satırının adı', () {
    Future<void> kur(WidgetTester t, PortfolioState s) async {
      t.view.physicalSize = const Size(390 * 3, 844 * 3);
      t.view.devicePixelRatio = 3.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(
            brightness: Brightness.dark, extensions: const [SandikPalette.dark]),
        home: Scaffold(
          body: SingleChildScrollView(child: PortfolioSummaryWidget(state: s)),
        ),
      ));
      await t.pump();
    }

    Asset lot(double cur) => Asset(
          id: 'b',
          userId: 'u',
          name: 'THYAO',
          ticker: 'THYAO',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: cur,
          addedDate: DateTime(2026, 1, 1),
        );

    testWidgets('kârda "Maliyetine göre kâr" — görünür ve ekran okuyucuda',
        (t) async {
      final semantik = t.ensureSemantics();
      await kur(t, PortfolioState(assets: [lot(120)]));
      expect(find.text('Maliyetine göre kâr'), findsOneWidget);
      expect(
          find.bySemanticsLabel(RegExp('Maliyetine göre kâr ₺200')),
          findsOneWidget);
      semantik.dispose();
    });

    testWidgets('zararda "Maliyetine göre zarar"', (t) async {
      await kur(t, PortfolioState(assets: [lot(80)]));
      expect(find.text('Maliyetine göre zarar'), findsOneWidget);
      expect(find.text('Maliyetine göre kâr'), findsNothing);
    });
  });
}
