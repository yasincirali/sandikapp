import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

/// Dönem içi eklemeler yüzdeyi bozmaz — kullanıcı bildirimi, 2026-10-01.
///
/// Eylül özetinde iki arıza ölçüldü:
///   1. Payda `baş + katkı` idi: ayın son günlerinde eklenen para ayın
///      tamamında çalışmış sayılıyor, yüzde sıfıra eziliyordu. Kullanıcının
///      önerisiyle payda dönemin ORTALAMA sermayesi oldu.
///   2. TÜFE hizalı pencere bir SLOTTA (ay sonu 00:00) bitiyor ama katkı
///      gün sonuna kadar sayılıyordu: ayın son günü alım yapan kullanıcının
///      alımı değerde yok, katkıda vardı.
///   3. Kart "son 1 ay" yazıp Ağustos'u ölçüyordu; artık ayın adını yazar.
Asset _lot(String id, double tutar, DateTime t, {bool satis = false}) => Asset(
      id: id,
      userId: 'u',
      name: id,
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 1,
      purchasePrice: tutar,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: tutar,
      addedDate: t,
      kind: satis ? AssetKind.sell : AssetKind.buy,
      sellPrice: satis ? tutar : null,
    );

PortfolioHistoryBreakdown _bd(Map<int, double> total) =>
    PortfolioHistoryBreakdown(
      total: total,
      byType: const {},
      byPosition: const {},
      positionType: const {},
    );

/// TÜFE hizalı Eylül penceresi: 31 Ağu → 30 Eyl (`InflationWindow`).
final _bas = DateTime(2026, 8, 31);
final _son = DateTime(2026, 9, 30);

PeriodSummary _eylul(Map<int, double> seri, List<Asset> lotlar) =>
    PeriodSummaryService.compute(
      period: SummaryPeriod.birAy,
      assets: lotlar,
      breakdown: _bd(seri),
      now: _son,
      pencereBaslangici: _bas,
    );

void main() {
  test('ay sonunda eklenen para ayın getirisini sulandırmaz', () {
    // ₺100.000 ile başlıyor, piyasa ay boyunca %3; 28 Eyl 12:00'de
    // ₺100.000 ekleniyor (29 Eyl slotunda değerde).
    final g = pow(1.03, 1 / 30).toDouble();
    final eklemeAni = DateTime(2026, 9, 28, 12);
    final seri = <int, double>{};
    var v = 100000.0;
    for (var i = 0; i <= 30; i++) {
      final gun = DateTime(2026, 8, 31 + i);
      if (i > 0) v *= g;
      // Alımdan sonraki ilk slot (29 Eyl 00:00) alımı içerir.
      if (gun == DateTime(2026, 9, 29)) v += 100000;
      seri[gun.millisecondsSinceEpoch] = v;
    }
    final s = _eylul(seri, [_lot('ek', 100000, eklemeAni)]);

    expect(s.katkiTRY, 100000);
    // Eski payda (baş + katkı) %1,5 civarı yazıyordu.
    expect(s.getiriPct, closeTo(3.0, 0.1));
    expect(s.getiriPct!, greaterThan(2.9));
  });

  test('ayın son günü alım TÜFE penceresinde düşülmez (uç slotta)', () {
    // 31 Ağu 00:00 ₺100.000 → 30 Eyl 00:00 ₺103.000; 30 Eyl 14:00'te
    // ₺50.000 alım — uç slotta YOK, katkıya da girmemeli.
    final seri = {
      _bas.millisecondsSinceEpoch: 100000.0,
      DateTime(2026, 9, 15).millisecondsSinceEpoch: 101500.0,
      _son.millisecondsSinceEpoch: 103000.0,
    };
    final s = _eylul(seri, [_lot('sonGun', 50000, DateTime(2026, 9, 30, 14))]);

    expect(s.katkiTRY, 0);
    expect(s.piyasaTRY, closeTo(3000, 1e-6));
    expect(s.getiriPct, closeTo(3.0, 1e-9));
  });

  test('akış yoksa yüzde eski formülle birebir (son / baş − 1)', () {
    final seri = {
      _bas.millisecondsSinceEpoch: 80000.0,
      _son.millisecondsSinceEpoch: 81472.0,
    };
    final s = _eylul(seri, const []);
    expect(s.getiriPct, closeTo((81472 / 80000 - 1) * 100, 1e-9));
  });

  test('yüzde her zaman TRY piyasa satırının işaretini taşır', () {
    final r = Random(7);
    for (var n = 0; n < 200; n++) {
      final seri = <int, double>{};
      final lotlar = <Asset>[];
      var v = 50000 + r.nextDouble() * 100000;
      for (var i = 0; i <= 30; i++) {
        final gun = DateTime(2026, 8, 31 + i);
        if (i > 0) v *= 0.97 + r.nextDouble() * 0.06;
        if (i > 0 && i < 30 && r.nextDouble() < 0.15) {
          final tutar = 1000 + r.nextDouble() * 60000;
          final satis = r.nextBool() && tutar < v * 0.5;
          lotlar.add(_lot(
              'l$n$i', tutar, gun.subtract(const Duration(hours: 6)),
              satis: satis));
          v += satis ? -tutar : tutar;
        }
        seri[gun.millisecondsSinceEpoch] = v;
      }
      final s = _eylul(seri, lotlar);
      if (s.getiriPct == null || s.piyasaTRY!.abs() < 1e-6) continue;
      expect(s.getiriPct!.sign, s.piyasaTRY!.sign,
          reason: 'TRY ve yüzde aynı hikâyeyi anlatmalı (#$n)');
    }
  });

  group('reel getiri kartı ölçtüğü ayı ADIYLA yazar', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));

    testWidgets('1A: "son 1 ay" değil "Ağustos 2026"', (t) async {
      final ozet = PeriodSummary(
        period: SummaryPeriod.birAy,
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 10, 1),
        baslangicTRY: 2465668,
        sonTRY: 2544193,
        katkiTRY: 90788,
        piyasaTRY: -12264,
        getiriPct: -0.48,
        tufeFarki: 8.1,
        tufePct: 1.84,
        reelGetiriPct: 7.93,
        tufeNominalPct: 9.92,
        tufeBaslangic: DateTime(2026, 7, 31),
        tufeBitis: DateTime(2026, 8, 31),
      );
      await t.pumpWidget(MaterialApp(
        theme: ThemeData(extensions: [SandikPalette.light]),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: Scaffold(
          body: SingleChildScrollView(child: PeriodSummaryView(summary: ozet)),
        ),
      ));
      await t.pumpAndSettle();

      // Başlık Ana ekranla aynı + çip (D2, 2026-10-01): ay adı çipte.
      expect(find.text('Enflasyona göre'), findsOneWidget);
      expect(find.text('Ağustos 2026'), findsOneWidget);
      expect(find.textContaining('son 1 ay'), findsNothing);
      // Cümle de ayı adıyla söyler (2026-10-02 sadeleştirme).
      expect(find.textContaining('Ağustos 2026 ayında birikimin'),
          findsOneWidget);
      expect(find.textContaining('Temmuz'), findsNothing,
          reason: 'tek ay iki ay gibi okunmamalı');
      await t.tap(find.text('Nasıl hesaplandı'));
      await t.pumpAndSettle();
      expect(find.textContaining('Ölçülen ay: Ağustos 2026'), findsOneWidget);
      expect(find.textContaining('Temmuz'), findsNothing);
    });
  });
}
