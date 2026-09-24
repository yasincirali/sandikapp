import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/daily_summary.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

import 'helpers/kaynak.dart';

/// PR #16 kod incelemesi (2026-09-24) — dört yüzeyin ORTAK kuralları.
///
/// 1. Gün içi akış açılış ölçümünden SONRASI için sayılır; açılış slotunda
///    zaten olan lot tabandadır. Geçmiş seansta (hafta sonu → Cuma) akış
///    yoktur: motor o seansta tarih kapısı uygulamaz.
/// 2. Her şey satıldıysa canlı uç 0 bir ÖLÇÜMDÜR. Eskiden "ölçüm yok"
///    sayılıyordu ve piyasa etkisi satış tutarı kadar şişiyordu.
/// 3. Özet'in eğrisi ve dağılımı rakamla aynı (canlı) uca bakar.
void main() {
  Asset lot(
    String id,
    double qty,
    double fiyat,
    DateTime t, {
    AssetKind kind = AssetKind.buy,
    AssetType type = AssetType.hisse,
    String ticker = 'THYAO.IS',
  }) =>
      Asset(
        id: id,
        userId: 'u',
        name: id,
        ticker: ticker,
        type: type,
        quantity: qty,
        purchasePrice: fiyat,
        sellPrice: kind == AssetKind.sell ? fiyat : null,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: fiyat,
        addedDate: t,
        kind: kind,
      );

  group('gunIciKatki — açılış slotu tabandadır', () {
    final bugun = DateTime(2026, 9, 24);
    final acilis = DateTime(2026, 9, 24, 10).millisecondsSinceEpoch;
    final simdi = DateTime(2026, 9, 24, 14);

    test('açılıştan önce ve açılış slotu içinde girilen alım sayılmaz', () {
      final lotlar = [
        lot('gece', 10, 100, DateTime(2026, 9, 24)), // tarih seçici 00:00
        lot('once', 10, 100, DateTime(2026, 9, 24, 9, 30)),
        lot('slotta', 10, 100, DateTime(2026, 9, 24, 10, 2)), // 10:00 kovası
      ];
      expect(
          DailySummary.gunIciKatki(lotlar,
              acilisMs: acilis, seansGunu: bugun, now: simdi),
          0);
    });

    test('açılış slotundan sonraki alım ve satış sayılır', () {
      final lotlar = [
        lot('al', 10, 100, DateTime(2026, 9, 24, 10, 5)),
        lot('sat', 4, 120, DateTime(2026, 9, 24, 13),
            kind: AssetKind.sell),
      ];
      expect(
          DailySummary.gunIciKatki(lotlar,
              acilisMs: acilis, seansGunu: bugun, now: simdi),
          1000 - 480);
    });

    test('geçmiş seans (hafta sonu → Cuma) akış taşımaz', () {
      final cuma = DateTime(2026, 9, 18);
      final lotlar = [lot('cuma', 10, 100, DateTime(2026, 9, 18, 14))];
      expect(
          DailySummary.gunIciKatki(lotlar,
              acilisMs: DateTime(2026, 9, 18, 10).millisecondsSinceEpoch,
              seansGunu: cuma,
              now: DateTime(2026, 9, 20, 12)),
          0);
    });

    test('Grafik kartı gün içinde aynı fonksiyona gider', () {
      final lotlar = [lot('once', 10, 100, DateTime(2026, 9, 24, 9, 30))];
      expect(
          PeriodSummaryService.grafikKatkisi(lotlar,
              start: bugun, end: simdi, tabanMs: acilis, intraday: true),
          0);
      // Diğer dönemler: taban damgasından SONRASI (değişmedi).
      expect(
          PeriodSummaryService.grafikKatkisi(lotlar,
              start: DateTime(2026, 9, 17),
              end: simdi,
              tabanMs: DateTime(2026, 9, 17).millisecondsSinceEpoch,
              intraday: false),
          1000);
    });
  });

  group('tamamen satış — 0 bir ölçümdür', () {
    final now = DateTime(2026, 9, 24, 14);
    final bd = PortfolioHistoryBreakdown(
      total: {
        DateTime(2026, 9, 17).millisecondsSinceEpoch: 100 * 300.0,
        DateTime(2026, 9, 24).millisecondsSinceEpoch: 100 * 306.0,
      },
      byType: const {},
      byPosition: const {},
      positionType: const {},
    );

    test('bugün hepsi satıldıysa piyasa etkisi fiyat hareketidir', () {
      final lotlar = [
        lot('al', 100, 300, DateTime(2026, 9, 10)),
        lot('sat', 100, 305, DateTime(2026, 9, 24, 11), kind: AssetKind.sell),
      ];
      expect(DailySummary.acikPozisyonYok(lotlar), isTrue);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: lotlar,
        breakdown: bd,
        now: now,
        canliSon: 0,
      );
      // 300 → 305'ten satış: +₺500. Eskiden uç 30.600'de kalıyordu:
      // 30.600 − 30.000 + 30.500 = +₺31.100.
      expect(s.sonTRY, 0);
      expect(s.piyasaTRY, closeTo(500, 1e-6));
    });

    test('elde pozisyon varken canlı 0 "fiyat yok"tur — uç seriden', () {
      final lotlar = [
        lot('al', 100, 300, DateTime(2026, 9, 10)),
        lot('sat', 50, 305, DateTime(2026, 9, 24, 11), kind: AssetKind.sell),
      ];
      expect(DailySummary.acikPozisyonYok(lotlar), isFalse);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birHafta,
        assets: lotlar,
        breakdown: bd,
        now: now,
        canliSon: 0,
      );
      expect(s.sonTRY, 100 * 306.0);
    });

    test('gün içi liste satış sonrası sıfırları taşır, baştakileri atar', () {
      final g = DateTime(2026, 9, 24);
      int t(int h, int m) =>
          DateTime(g.year, g.month, g.day, h, m).millisecondsSinceEpoch;
      final seri = {
        t(9, 55): 0.0, // borsa açılmadan: veri yok
        t(10, 0): 30000.0,
        t(10, 5): 30100.0,
        t(10, 10): 0.0, // her şey satıldı
      };
      final simdi = DateTime(2026, 9, 24, 10, 12);
      expect(
          DailySummary.dayValues(seri, simdi, 0,
              seansGunu: g, acikPozisyonYok: true),
          [30000.0, 30100.0, 0.0]);
      expect(DailySummary.acilisDamgasi(seri, simdi), t(10, 0));
    });

    test('Grafik kartı: canlı 0 uç olur, taban ardındaki sıfır ölçümdür', () {
      String kod(String yol) => ekranKaynagiSync(yol)
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ');
      final kartlar = kod('lib/screens/portfolio_performance/kartlar.dart');
      expect(kartlar.contains('currentTotalOverride: canliUc'), isTrue);
      expect(kartlar.contains('DailySummary.acikPozisyonYok('), isTrue);
      final ekran = kod('lib/screens/portfolio_performance_screen.dart');
      expect(ekran.contains('if (s.y <= 0) continue; // `uclar` ile AYNI kural'),
          isFalse,
          reason: 'her sıfırı atlamak satış sonrası ucu kaybettiriyordu');
    });
  });

  group('Özet eğrisi ve dağılımı canlı uca bakar', () {
    test('eğri canlı değerle biter, dağılım canlıdan okunur', () {
      final now = DateTime(2026, 9, 24, 14);
      final lotlar = [
        lot('eski', 100, 300, DateTime(2026, 9, 10)),
        lot('bugun', 20, 305, DateTime(2026, 9, 24, 11)),
      ];
      final bd = PortfolioHistoryBreakdown(
        total: {
          DateTime(2026, 9, 17).millisecondsSinceEpoch: 30000.0,
          DateTime(2026, 9, 24).millisecondsSinceEpoch: 30600.0,
        },
        byType: {
          AssetType.hisse: {
            DateTime(2026, 9, 17).millisecondsSinceEpoch: 30000.0,
            DateTime(2026, 9, 24).millisecondsSinceEpoch: 30600.0,
          },
        },
        byPosition: const {},
        positionType: const {},
      );
      const canli = 37200.0;
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: lotlar,
        breakdown: bd,
        now: now,
        canliSon: canli,
        canliDagilim: const {AssetType.hisse: canli},
      );
      expect(s.sparkline, [30000.0, 30600.0, canli]);
      expect(s.dagilimSonu, {AssetType.hisse: canli});
    });
  });
}
