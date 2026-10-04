import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/contribution_history_service.dart';
import 'package:portfoy_takip/services/inflation_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/aralik_cipi.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

import 'helpers/kaynak.dart';

/// Performans sadeleştirmesi — müşteri testi bulguları (2026-10-01/02).
///
/// Emülatörde gerçek hesapla yapılan turda birikimcinin takıldığı yerler:
///   1. Ana ekran "5,4 puan önde", Özet "4,5 puan" (farklı lot kümesi +
///      zoom'a bağlı seri) → tek kaynak, kanonik seri.
///   2. Enflasyon kartında dört yüzde → tek sayı (puan farkı), pencere
///      cümlede, ham girdiler katlanır.
///   3. 5Y'de enflasyon kartı sessizce yok → pencere veri olan aya çekilir
///      ve bunu söyler.
///   4. "Net katkı" iki kartta iki anlam → "Yatırdığın" tek tanım, temettü
///      kendi satırında; köprü toplanır.
///   5. Tek katkı ayında aynı rakam üç satırda → tek cümle.
///   6. 5Y çipi "1 Eki 21" (portföy yoktu) → ilk alımdan.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => InflationService.instance.resetForTest());
  tearDown(() => InflationService.instance.resetForTest());

  DateTime ay(int y, int m) => DateTime(y, m, 1);

  group('5Y: TÜFE penceresi veri olan aya çekilir (pencereKapsayan)', () {
    // Endeks Oca 2024'ten başlıyor; 60 ay geriye (Ağu 2021) gidemez.
    Map<DateTime, double> endeks() => {
          for (var i = 0; i < 32; i++) ay(2024, 1 + i): 100.0 * (1 + 0.02 * i),
        };

    test('tam pencere yoksa endeksin ilk ayına çekilir ve kısaltıldı der',
        () async {
      InflationService.instance.seedForTest(endeks());
      final now = DateTime(2026, 10, 1);
      expect(await InflationService.instance.pencere(1825, now: now), isNull,
          reason: 'eski davranış: kart hiç çizilmezdi');
      final w = await InflationService.instance
          .pencereKapsayan(1825, now: now);
      expect(w, isNotNull);
      expect(w!.kisaltildi, isTrue);
      expect(w.ilkAy, ay(2024, 1));
      expect(w.sonAy, ay(2026, 8));
      expect(w.pct, closeTo((1 + 0.02 * 31) / 1.0 * 100 - 100, 1e-9));
    });

    test('ilk alım endeksten sonraysa taban ilk alımın ayıdır', () async {
      InflationService.instance.seedForTest(endeks());
      final w = await InflationService.instance.pencereKapsayan(1825,
          now: DateTime(2026, 10, 1), enErken: DateTime(2025, 3, 14));
      // İlk alım Mart 2025 → seri Şubat SONUNDAN başlar (ilkAy = Şubat).
      expect(w!.ilkAy, ay(2025, 2));
      expect(w.kisaltildi, isTrue);
    });

    test('tam pencere varsa aynen döner, kısaltılmaz', () async {
      InflationService.instance.seedForTest({
        for (var i = 0; i < 14; i++) ay(2025, 7 + i): 100.0 + i,
      });
      final w = await InflationService.instance
          .pencereKapsayan(365, now: DateTime(2026, 10, 1));
      expect(w!.kisaltildi, isFalse);
      expect(w.ilkAy, ay(2025, 8));
    });

    test('kısaltılmış pencere bir aydan kısaysa null (uydurma yok)',
        () async {
      InflationService.instance.seedForTest({ay(2026, 8): 100.0});
      expect(
          await InflationService.instance
              .pencereKapsayan(1825, now: DateTime(2026, 10, 1)),
          isNull);
    });
  });

  group('AralikMetni.olculenAylar — çip ölçülen ayları yazar', () {
    final l = AppLocalizationsTr();
    test('tek ay adıyla', () {
      expect(
          AralikMetni.olculenAylar(l, 'tr_TR',
              bas: DateTime(2026, 7, 31), bitis: DateTime(2026, 8, 31)),
          'Ağustos 2026');
    });
    test('3A: "May 26 - Ağu 26" değil "Haz - Ağu 26"', () {
      expect(
          AralikMetni.olculenAylar(l, 'tr_TR',
              bas: DateTime(2026, 5, 31), bitis: DateTime(2026, 8, 31)),
          'Haz - Ağu 26');
    });
    test('12 ay TÜİK diliyle (Ağustos → Ağustos)', () {
      expect(
          AralikMetni.olculenAylar(l, 'tr_TR',
              bas: DateTime(2025, 8, 31), bitis: DateTime(2026, 8, 31)),
          'Ağu 25 - Ağu 26');
    });
  });

  group('ilk alım tarihi', () {
    Asset lot(String id, DateTime t, {AssetKind kind = AssetKind.buy}) =>
        Asset(
          id: id,
          userId: 'u',
          name: 'THYAO',
          ticker: 'THYAO.IS',
          type: AssetType.hisse,
          quantity: 10,
          purchasePrice: 100,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          currentPrice: 100,
          addedDate: t,
          kind: kind,
        );

    test('en eski aktif alım; satış ve silinmiş sayılmaz', () {
      final lotlar = [
        lot('a', DateTime(2024, 3, 5)),
        lot('b', DateTime(2023, 9, 14)),
        lot('c', DateTime(2022, 1, 1), kind: AssetKind.sell),
      ];
      expect(PeriodSummaryService.ilkAlimTarihi(lotlar), DateTime(2023, 9, 14));
      expect(PeriodSummaryService.ilkAlimTarihi(const []), isNull);
    });
  });

  // ── Widget: köprü, çip ve birikim cümlesi ─────────────────────────────
  PeriodSummary ozet({
    SummaryPeriod period = SummaryPeriod.altiAy,
    DateTime? start,
    DateTime? ilkAlim,
    double? temettu,
  }) =>
      PeriodSummary(
        period: period,
        start: start ?? DateTime(2026, 4, 1),
        end: DateTime(2026, 10, 1, 9),
        ilkAlim: ilkAlim,
        baslangicTRY: 918045,
        sonTRY: 1422472,
        // katkı = yatırdığın − temettü (temettü çıkış): 517.796 − 150.045
        katkiTRY: temettu == null ? 517796 : 517796 - temettu,
        piyasaTRY: 136676,
        getiriPct: 15.06,
        temettuTRY: temettu,
      );

  Future<void> pump(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(390, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [SandikPalette.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await t.pumpAndSettle();
  }

  group('köprü: Yatırdığın tek tanım, temettü kendi satırında', () {
    testWidgets('baş + yatırdığın − temettü + piyasa = şimdi', (t) async {
      await pump(t,
          PeriodSummaryView(summary: ozet(temettu: 150045), simdi: DateTime(2026, 10, 1, 12)));
      expect(find.text('Yatırdığın'), findsOneWidget);
      expect(find.text('+₺517.796'), findsOneWidget,
          reason: 'temettü hariç — Birikim disiplinin kartıyla aynı sayı');
      expect(find.text('Cebine aldığın temettü'), findsOneWidget);
      expect(find.text('−₺150.045'), findsOneWidget);
      expect(find.text('Fiyat etkisi'), findsOneWidget);
      // Ana rakam + köprü satırı: aynı sayı iki yerde.
      expect(find.text('+₺136.676'), findsNWidgets(2));
      expect(find.text('₺1.422.472'), findsOneWidget);
      // Eski etiketler kalmadı.
      expect(find.text('Net katkın'), findsNothing);
      expect(find.text('Bunun nakit temettüsü'), findsNothing);
      // Köprü gerçekten toplanıyor.
      expect(918045 + 517796 - 150045 + 136676, 1422472);
    });

    testWidgets('temettü yoksa satır yok', (t) async {
      await pump(t, PeriodSummaryView(summary: ozet(), simdi: DateTime(2026, 10, 1, 12)));
      expect(find.text('Cebine aldığın temettü'), findsNothing);
      expect(find.text('+₺517.796'), findsOneWidget);
    });
  });

  group('aralık çipi ilk alımdan başlar', () {
    testWidgets('5Y: pencere 2021, ilk alım 2023 → çip 14 Eyl 23', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(
            period: SummaryPeriod.besYil,
            start: DateTime(2021, 10, 1),
            ilkAlim: DateTime(2023, 9, 14),
          ),
          simdi: DateTime(2026, 10, 1, 12),
        ),
      );
      expect(find.text('14 Eyl 23 - bugün'), findsOneWidget);
      expect(find.text('1 Eki 21 - bugün'), findsNothing);
    });

    testWidgets('1Y: ilk alım pencereden eskiyse çip pencereden', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(
            period: SummaryPeriod.birYil,
            start: DateTime(2025, 10, 1),
            ilkAlim: DateTime(2023, 9, 14),
          ),
          simdi: DateTime(2026, 10, 1, 12),
        ),
      );
      expect(find.text('1 Eki 25 - bugün'), findsOneWidget);
    });
  });

  group('birikim disiplini: tek katkı ayı tek cümle', () {
    ContributionSummary kovalar(List<double> netler) {
      final k = <ContributionBucket>[];
      for (var i = 0; i < netler.length; i++) {
        final a = DateTime(2026, 5 + i, 1);
        k.add(ContributionBucket(
          start: a,
          end: DateTime(a.year, a.month + 1, 0),
          netTRY: netler[i],
          kismi: i == netler.length - 1,
        ));
      }
      return ContributionHistoryService.summarize(k)!;
    }

    testWidgets('bir katkı + bir çekim: cümle, dört satır yok', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(),
          simdi: DateTime(2026, 10, 1, 12),
          katkiKarti: ContributionKarti(
            ozet: kovalar([0, -12000, 0, 0, 529881, -86]),
            aralik: ContributionInterval.aylik,
          ),
        ),
      );
      expect(
          find.textContaining(
              'Son 6 ayın yalnızca birinde para yatırdın: Eylül ayında ₺529.881.'),
          findsOneWidget);
      expect(find.textContaining('Haziran ayında ₺12.000 çektin.'),
          findsOneWidget);
      expect(find.text('Katkı yaptığın ay ortalaması'), findsNothing);
      expect(find.text('En yüksek'), findsNothing);
      expect(find.text('Geçen aya göre'), findsNothing);
    });

    testWidgets('iki ve üzeri katkı ayında satırlar kalır', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(),
          simdi: DateTime(2026, 10, 1, 12),
          katkiKarti: ContributionKarti(
            ozet: kovalar([1000, 1500, 1200, 2000, 1800, 500]),
            aralik: ContributionInterval.aylik,
          ),
        ),
      );
      expect(find.text('Katkı yaptığın ay ortalaması'), findsOneWidget);
      expect(find.text('6 / 6'), findsOneWidget);
    });

    testWidgets('yalnızca satış: "yeni para girmemiş" yerine satışı söyler',
        (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(),
          simdi: DateTime(2026, 10, 1, 12),
          katkiKarti: ContributionKarti(
            ozet: kovalar([0, 0, 0, 0, -329473, 0]),
            aralik: ContributionInterval.aylik,
          ),
        ),
      );
      expect(
          find.textContaining(
              'Bu pencerede yeni para girmedi; satış var: Eylül ayında −₺329.473.'),
          findsOneWidget);
      expect(find.text(trMetni('noNewMoney')), findsNothing);
    });
  });

  group('kaynak sözleşmeleri', () {
    test('Ana kart ve Özet aynı lot kümesini (activeAssets) okur', () {
      final y = ekranKaynagiSync('lib/services/bugun_yukleyici.dart');
      expect(y.contains('RealReturnService.yillik(state.activeAssets)'), isTrue);
      expect(y.contains('assets: state.assets,'), isFalse,
          reason: 'haftalık getiri de aynı kümeyle');
    });

    test('geçmiş pencerenin reel getirisi oturum içinde hafızalanır', () {
      final s = ekranKaynagiSync('lib/services/real_return_service.dart');
      expect(s.contains('_hafizaAnahtari(assets, w)'), isTrue);
      expect(s.contains('static void hafizayiTemizle()'), isTrue);
      // Parmak izine FİYAT girmez: canlı fiyat geçmişi değiştirmemeli.
      expect(s.contains('currentPrice'), isFalse);
    });

    test('Grafik sekmesi: ham sembol ve "işlem hacmi" dili kalmadı', () {
      expect(trMetni('tradeVolumeUpper'), 'ALIM · SATIŞ');
      expect(trMetni('changeByTypeUpper'), contains('PİYASANIN KATTIĞI'));
      final o = ekranKaynagiSync(
          'lib/screens/portfolio_performance/ozet_yan_veri.dart');
      expect(o.contains("'EUR' => l.marketEuro"), isTrue,
          reason: 'EURTRY=X müşteriye sızmasın');
    });
  });
}
