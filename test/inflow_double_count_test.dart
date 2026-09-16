import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

/// Katkı ÇİFTE SAYILMAZ — taban hangi anda ölçüldüyse katkı ondan sonrasını
/// sayar (kullanıcı bildirimi, 2026-09-16).
///
/// ## Ölçülen arıza
/// Ana ekran rozeti "38,81 puan enflasyonun gerisindesin" diyordu; portföy o
/// dönemde ₺197 binden ₺782 bine çıkmıştı. Nominal getiri −%7,30 çıkıyordu,
/// doğrusu +%20,73.
///
/// Sebep: `netInflow` pencere BAŞINDAN (`p.start`) sayıyordu ama taban
/// (`u.first`) serinin ilk DOLU slotuydu ve o slot pencere başından sonraydı
/// (yeni kullanıcı — portföy 31 Ağustos'ta henüz boştu, ilk ölçüm 15
/// Eylül'de). Aradaki alım hem tabanın içinde hem katkıda sayılıyor, formül
/// onu iki kez düşüyordu.
void main() {
  Asset lot({
    required String id,
    required double qty,
    required double cur,
    required DateTime added,
    double purchase = 100,
  }) =>
      Asset(
        id: id,
        userId: 'u',
        name: id,
        ticker: 'THYAO',
        type: AssetType.hisse,
        quantity: qty,
        purchasePrice: purchase,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: cur,
        addedDate: added,
        kind: AssetKind.buy,
      );

  PortfolioHistoryBreakdown seri(Map<DateTime, double> noktalar) =>
      PortfolioHistoryBreakdown(
        total: {
          for (final e in noktalar.entries)
            e.key.millisecondsSinceEpoch: e.value,
        },
        byType: const {},
        byPosition: const {},
        positionType: const {},
      );

  test('taban ölçümünden ÖNCEKİ alım katkıya girmez', () {
    // Pencere 01.01 başlıyor ama seri 15.01'de; varlık 08.01'de alınmış,
    // yani 15.01 tabanının İÇİNDE. Katkıya da girerse iki kez sayılır.
    final bd = seri({
      DateTime(2026, 1, 15): 1000.0,
      DateTime(2026, 6, 30): 1200.0,
    });

    final s = PeriodSummaryService.compute(
      period: SummaryPeriod.altiAy,
      assets: [
        lot(id: 'a', qty: 10, cur: 120, purchase: 100,
            added: DateTime(2026, 1, 8)),
      ],
      breakdown: bd,
      now: DateTime(2026, 6, 30),
      pencereBaslangici: DateTime(2026, 1, 1),
    );

    // Alım tabanın içinde: katkı SIFIR, getiri saf piyasa hareketi.
    expect(s.katkiTRY, 0);
    expect(s.baslangicTRY, 1000.0);
    expect(s.sonTRY, 1200.0);
    expect(s.piyasaTRY, 200.0);
    expect(s.getiriPct, closeTo(20.0, 1e-9));
  });

  test('taban ölçümünden SONRAKİ alım katkıya GİRER', () {
    // Karşı durum: gerçek bir katkı ayıklanmaya devam etmeli, yoksa
    // düzeltme bu kez ters yöne kaçardı.
    final bd = seri({
      DateTime(2026, 1, 15): 1000.0,
      DateTime(2026, 6, 30): 2100.0,
    });

    final s = PeriodSummaryService.compute(
      period: SummaryPeriod.altiAy,
      assets: [
        lot(id: 'a', qty: 10, cur: 120, purchase: 100,
            added: DateTime(2026, 1, 8)),
        // Taban ölçümünden SONRA: ₺900 yatırıldı.
        lot(id: 'b', qty: 9, cur: 100, purchase: 100,
            added: DateTime(2026, 3, 10)),
      ],
      breakdown: bd,
      now: DateTime(2026, 6, 30),
      pencereBaslangici: DateTime(2026, 1, 1),
    );

    expect(s.katkiTRY, 900.0);
    // (2100 − 1000) − 900 = 200 saf piyasa
    expect(s.piyasaTRY, closeTo(200.0, 1e-9));
    // Payda katkıyı içerir: 200 / (1000 + 900)
    expect(s.getiriPct, closeTo(200 / 1900 * 100, 1e-9));
  });

  test('ölçülen arıza: 4 kat büyüyen portföy NEGATİF getiri göstermez', () {
    // Emülatördeki gerçek şekil: pencere 31.08 başlıyor, seri 15.09'da;
    // 08.09'da alınan büyük lot tabanın içinde.
    final bd = seri({
      DateTime(2025, 9, 15): 197803.15,
      DateTime(2026, 8, 31): 782131.89,
    });

    final s = PeriodSummaryService.compute(
      period: SummaryPeriod.birYil,
      assets: [
        // Taban İÇİNDE (08.09) — çifte sayılan lot buydu.
        lot(id: 'altin', qty: 25, cur: 10841, purchase: 7835.17,
            added: DateTime(2025, 9, 8)),
        // Taban ölçümünden sonra alınanlar: gerçek katkı.
        lot(id: 'sahol', qty: 1000, cur: 86, purchase: 92.6,
            added: DateTime(2025, 9, 16)),
        lot(id: 'aft', qty: 55000, cur: 0.98, purchase: 0.816965,
            added: DateTime(2026, 4, 12)),
        lot(id: 'dly', qty: 50000, cur: 6.235, purchase: 5.309472,
            added: DateTime(2026, 4, 14)),
        lot(id: 'usd', qty: 1000, cur: 48.65, purchase: 47.0366,
            added: DateTime(2026, 7, 14)),
      ],
      breakdown: bd,
      now: DateTime(2026, 8, 31),
      pencereBaslangici: DateTime(2025, 8, 31),
    );

    // Altının ₺195.879'u katkıya GİRMEZ (tabanın içinde).
    expect(s.katkiTRY, closeTo(450043.28, 1.0));
    // Arızalı hâlde −%7,30 çıkıyordu.
    expect(s.getiriPct, isNotNull);
    expect(s.getiriPct!, greaterThan(0),
        reason: 'portföy 4 kat büyürken getiri negatif olamaz');
    expect(s.getiriPct!, closeTo(20.73, 0.05));
  });

  test('pencere başı ile seri başı ÇAKIŞIYORSA davranış değişmez', () {
    // Olağan durum (geçmiş verisi olan kullanıcı): seri pencere başında
    // zaten dolu. Düzeltme buraya dokunmamalı.
    final bd = seri({
      DateTime(2026, 1, 1): 1000.0,
      DateTime(2026, 6, 30): 1500.0,
    });

    final s = PeriodSummaryService.compute(
      period: SummaryPeriod.altiAy,
      assets: [
        lot(id: 'a', qty: 10, cur: 100, purchase: 100,
            added: DateTime(2025, 6, 1)),
        lot(id: 'b', qty: 3, cur: 100, purchase: 100,
            added: DateTime(2026, 3, 10)),
      ],
      breakdown: bd,
      now: DateTime(2026, 6, 30),
      pencereBaslangici: DateTime(2026, 1, 1),
    );

    expect(s.katkiTRY, 300.0);
    expect(s.piyasaTRY, closeTo(200.0, 1e-9));
  });
}
