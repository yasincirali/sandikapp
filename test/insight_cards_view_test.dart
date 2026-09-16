import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/contribution_history_service.dart';
import 'package:portfoy_takip/services/insight_metrics_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

/// Yeni içgörü kartlarının GÖRSEL kapısı.
///
/// `period_summary_view_test` ile aynı gerekçe: emülatörler Flutter'ı
/// render edemiyor, "doğru görünüyor mu" sorusu yalnızca burada
/// yanıtlanabilir.
///
/// Kovalanan şeyler:
///   1. Veri yokken kart HİÇ çizilmiyor (uydurulmuş sayı yok).
///   2. Reel getiri kartı üç ham girdiyi de yazıyor — doğrulanabilirlik.
///   3. Negatif katkı kutlanmıyor, "riskli" hükmü verilmiyor.
///   4. 320pt'de taşma yok, iki temada da çiziliyor.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  PeriodSummary ozet({
    SummaryPeriod period = SummaryPeriod.birYil,
    double? pct = 48.10,
    double? tufePct,
    double? reel,
    double? fark,
    double? temettu,
    double? komisyon,
    // TÜFE karşılaştırmasının KENDİ nominali. Varsayılanı [pct]: üretimde
    // `_tufeIle` üç alanı (nominal, TÜFE, aralık) birlikte doldurur ve
    // TÜFE varken nominalin boş kalması gerçekte olmayan bir durumdur.
    // Ayrı alan olmasının gerekçesi `PeriodSummary.tufeNominalPct`
    // notunda: iki pencere örtüşmüyor.
    double? tufeNominal,
  }) =>
      PeriodSummary(
        period: period,
        start: DateTime(2025, 9, 14),
        end: DateTime(2026, 9, 13),
        baslangicTRY: 100000,
        sonTRY: 160000,
        katkiTRY: 12000,
        piyasaTRY: 48000,
        getiriPct: pct,
        tufePct: tufePct,
        reelGetiriPct: reel,
        tufeFarki: fark,
        tufeNominalPct: tufePct == null ? null : (tufeNominal ?? pct),
        tufeBaslangic: tufePct == null ? null : DateTime(2025, 8, 31),
        tufeBitis: tufePct == null ? null : DateTime(2026, 8, 31),
        temettuTRY: temettu,
        komisyonTRY: komisyon,
      );

  Future<void> pump(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = Size(width, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          extensions: [
            brightness == Brightness.light
                ? SandikPalette.light
                : SandikPalette.dark,
          ],
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: child,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  ContributionSummary katkiOzeti({
    required List<double> netler,
    bool sonKismi = true,
  }) {
    final kovalar = <ContributionBucket>[];
    for (var i = 0; i < netler.length; i++) {
      final ay = DateTime(2026, 4 + i, 1);
      kovalar.add(ContributionBucket(
        start: ay,
        end: DateTime(ay.year, ay.month + 1, 0),
        netTRY: netler[i],
        kismi: sonKismi && i == netler.length - 1,
      ));
    }
    return ContributionHistoryService.summarize(kovalar)!;
  }

  group('Reel getiri kartı', () {
    testWidgets('üç ham girdiyi de yazar — doğrulanabilirlik', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(pct: 48.10, tufePct: 36.70, reel: 8.34, fark: 11.40),
        ),
      );

      expect(find.textContaining('Reel getiri'), findsOneWidget);
      expect(find.text('Nominal getiri'), findsOneWidget);
      expect(find.text('Dönem TÜFE'), findsOneWidget);
      expect(find.text('Puan farkı'), findsOneWidget);
      // Ana rakam bileşik reel getiri, puan farkı DEĞİL.
      expect(find.textContaining('%8,34'), findsOneWidget);
      expect(find.textContaining('11,4 puan'), findsOneWidget);
    });

    testWidgets('dönem etiketi kartın başlığında', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(reel: 8.34, tufePct: 36.7, fark: 11.4),
        ),
      );
      expect(find.textContaining('son 1 yıl'), findsWidgets);
    });

    testWidgets('reel getiri yoksa kart çizilmez', (t) async {
      await pump(t, PeriodSummaryView(summary: ozet()));
      expect(find.textContaining('Reel getiri'), findsNothing);
      expect(find.text('Dönem TÜFE'), findsNothing);
    });

    testWidgets('6A döneminde de reel getiri kartı çizilir', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(
            period: SummaryPeriod.altiAy,
            pct: 22.0,
            tufePct: 18.0,
            reel: 3.39,
            fark: 4.0,
          ),
        ),
      );
      expect(find.textContaining('son 6 ay'), findsWidgets);
      expect(find.text('Dönem TÜFE'), findsOneWidget);
    });

    testWidgets('negatif reel getiride kutlama dili yok', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(pct: 20.0, tufePct: 36.70, reel: -12.22, fark: -16.70),
        ),
      );
      expect(find.textContaining('alım gücün geriledi'), findsOneWidget);
      for (final k in ['Tebrikler', 'Harika', '🎉', 'Dikkat', 'Acele']) {
        expect(find.textContaining(k), findsNothing);
      }
    });
  });

  group('TÜFE verisi bekleniyor hâli', () {
    testWidgets('endeks boşken sebebi SÖYLENİR, sessiz kalınmaz', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(period: SummaryPeriod.birYil),
          enflasyonVerisiBekleniyor: true,
        ),
      );
      expect(find.text('TÜFE verisi henüz yüklenmedi.'), findsOneWidget);
      expect(find.textContaining('Tahmini bir sayı gösterilmiyor'),
          findsOneWidget);
    });

    testWidgets('1A ve 6A dönemlerinde de görünür', (t) async {
      for (final p in [SummaryPeriod.birAy, SummaryPeriod.altiAy]) {
        await pump(
          t,
          PeriodSummaryView(
            summary: ozet(period: p),
            enflasyonVerisiBekleniyor: true,
          ),
        );
        expect(find.text('TÜFE verisi henüz yüklenmedi.'), findsOneWidget,
            reason: '$p bloğunda bekleyen-veri hâli yok');
      }
    });

    testWidgets('endeks VARSA ama dönem ucu yoksa sessiz kalınır', (t) async {
      // `enflasyonVerisiBekleniyor: false` + reel getiri null: kullanıcıya
      // özel, geçici bir durum. Kart çizilmemeli.
      await pump(
        t,
        PeriodSummaryView(summary: ozet(period: SummaryPeriod.birYil)),
      );
      expect(find.text('TÜFE verisi henüz yüklenmedi.'), findsNothing);
      expect(find.textContaining('Reel getiri'), findsNothing);
    });

    testWidgets('reel getiri VARSA bekleyen-veri hâli çizilmez', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(tufePct: 36.7, reel: 8.34, fark: 11.4),
          enflasyonVerisiBekleniyor: true,
        ),
      );
      expect(find.text('TÜFE verisi henüz yüklenmedi.'), findsNothing);
      expect(find.text('Dönem TÜFE'), findsOneWidget);
    });

    testWidgets('bekleyen-veri hâli uyarı tonu taşımaz', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(period: SummaryPeriod.birYil),
          enflasyonVerisiBekleniyor: true,
        ),
      );
      // Kullanıcının düzeltebileceği bir şey yok — hata dili kullanılmaz.
      for (final k in ['Hata', 'hata', 'Dikkat', 'başarısız', 'Uyarı']) {
        expect(find.textContaining(k), findsNothing);
      }
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });
  });

  group('Köprü — temettü ve komisyon satırları', () {
    testWidgets('ikisi de varsa yazılır', (t) async {
      await pump(
        t,
        PeriodSummaryView(summary: ozet(temettu: 1250, komisyon: 340)),
      );
      expect(find.text('Bunun nakit temettüsü'), findsOneWidget);
      expect(find.text('Ödenen komisyon'), findsOneWidget);
    });

    testWidgets('null iken satır HİÇ çizilmez — ₺0 yazılmaz', (t) async {
      await pump(t, PeriodSummaryView(summary: ozet()));
      expect(find.text('Bunun nakit temettüsü'), findsNothing);
      expect(find.text('Ödenen komisyon'), findsNothing);
    });
  });

  group('Birikim kartı', () {
    testWidgets('katkı varken toplam ve satırlar çizilir', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(period: SummaryPeriod.birAy),
          katkiKarti: ContributionKarti(
            ozet: katkiOzeti(netler: [1000, 1500, 1200, 2000, 1800, 500]),
            aralik: ContributionInterval.aylik,
          ),
        ),
      );
      expect(find.text('Birikim disiplinin'), findsOneWidget);
      expect(find.text('Katkı yapılan dönem'), findsOneWidget);
      expect(find.text('6 / 6'), findsOneWidget);
    });

    testWidgets('hiç katkı yoksa dürüst boş hâl — sayı uydurulmaz', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(period: SummaryPeriod.birAy),
          katkiKarti: ContributionKarti(
            ozet: katkiOzeti(netler: [0, 0, 0, 0, 0, 0]),
            aralik: ContributionInterval.aylik,
          ),
        ),
      );
      expect(
        find.text('Bu pencerede portföyüne yeni para girmemiş.'),
        findsOneWidget,
      );
      expect(find.text('Katkı yaptığın ay ortalaması'), findsNothing);
    });

    testWidgets('GÜNLÜK dönemde birikim kartı çizilmez', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(period: SummaryPeriod.gunluk),
          katkiKarti: ContributionKarti(
            ozet: katkiOzeti(netler: [1000, 1500, 1200]),
            aralik: ContributionInterval.aylik,
          ),
        ),
      );
      expect(find.text('Birikim disiplinin'), findsNothing);
    });

    testWidgets('aralık seçici dokunuşu geri bildirir', (t) async {
      ContributionInterval? secilen;
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(period: SummaryPeriod.birAy),
          katkiKarti: ContributionKarti(
            ozet: katkiOzeti(netler: [1000, 1500, 1200]),
            aralik: ContributionInterval.aylik,
            onAralik: (a) => secilen = a,
          ),
        ),
      );
      await t.tap(find.text('Haftalık'));
      await t.pumpAndSettle();
      expect(secilen, ContributionInterval.haftalik);
    });
  });

  group('Sağlık kartı', () {
    testWidgets('üç metrik de çizilir, "riskli" hükmü YOK', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(),
          saglik: const SaglikKarti(
            donemEtiketi: 'son 1 yıl',
            drawdown: Drawdown(
              yuzde: 14.2,
              zirveTs: 0,
              dipTs: 1,
              toparlanmaGun: 23,
            ),
            volatilite: 18.5,
            yogunlasma: Concentration(
              enBuyukEtiket: 'THYAO',
              enBuyukPay: 52.0,
              pozisyonSayisi: 6,
              hhi: 0.34,
              turPaylari: {AssetType.hisse: 100},
            ),
          ),
        ),
      );

      expect(find.text('En büyük düşüş'), findsOneWidget);
      expect(find.text('Oynaklık'), findsOneWidget);
      expect(find.text('Yoğunlaşma'), findsOneWidget);
      expect(find.textContaining('23 günde toparladı'), findsOneWidget);

      // Hüküm YOK: risk skoru, "riskli", "güvenli" gibi ifadeler
      // kullanıcının risk toleransı hakkında varsayım yapar.
      for (final k in ['riskli', 'Riskli', 'güvenli', 'risk skoru']) {
        expect(find.textContaining(k), findsNothing);
      }
    });

    testWidgets('hiç metrik yoksa kart çizilmez', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(),
          saglik: const SaglikKarti(donemEtiketi: 'son 1 yıl'),
        ),
      );
      expect(find.text('Oynaklık'), findsNothing);
      expect(find.textContaining('Portföy sağlığı'), findsNothing);
    });

    testWidgets('düşüş yoksa "gerilemedi" der, %0 yazmaz', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(),
          saglik: const SaglikKarti(
            donemEtiketi: 'son 1 yıl',
            drawdown: Drawdown(yuzde: 0, zirveTs: 0, dipTs: 1),
          ),
        ),
      );
      expect(find.textContaining('zirvesinden gerilemedi'), findsOneWidget);
    });

    testWidgets('toparlanmadıysa öyle yazar', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(),
          saglik: const SaglikKarti(
            donemEtiketi: 'son 1 yıl',
            drawdown: Drawdown(yuzde: 9.1, zirveTs: 0, dipTs: 1),
          ),
        ),
      );
      expect(find.textContaining('henüz o seviyeye dönmedi'), findsOneWidget);
    });
  });

  group('XIRR kartı', () {
    testWidgets('iki sayının çelişmediğini açıkça yazar', (t) async {
      await pump(
        t,
        PeriodSummaryView(summary: ozet(pct: 48.10), xirr: 31.4),
      );
      expect(find.text('Paranın getirisi (yıllık)'), findsOneWidget);
      expect(find.text('Dönem piyasa getirisi'), findsOneWidget);
      expect(find.textContaining('İki sayı çelişmez'), findsOneWidget);
    });

    testWidgets('xirr null iken kart çizilmez', (t) async {
      await pump(t, PeriodSummaryView(summary: ozet()));
      expect(find.text('Paranın getirisi (yıllık)'), findsNothing);
    });
  });

  group('Yerleşim', () {
    testWidgets('320pt dar ekranda taşma yok — tüm kartlar açık', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(
            tufePct: 36.70,
            reel: 8.34,
            fark: 11.40,
            temettu: 1250,
            komisyon: 340,
          ),
          xirr: 31.4,
          katkiKarti: ContributionKarti(
            ozet: katkiOzeti(netler: [1000, 1500, 1200, 2000, 1800, 500]),
            aralik: ContributionInterval.aylik,
            onAralik: (_) {},
          ),
          saglik: const SaglikKarti(
            donemEtiketi: 'son 1 yıl',
            drawdown: Drawdown(yuzde: 14.2, zirveTs: 0, dipTs: 1),
            volatilite: 18.5,
            yogunlasma: Concentration(
              enBuyukEtiket: 'Cumhuriyet Altını',
              enBuyukPay: 52.0,
              pozisyonSayisi: 6,
              hhi: 0.34,
              turPaylari: {AssetType.altin: 100},
            ),
          ),
        ),
        width: 320,
      );
      expect(t.takeException(), isNull);
    });

    testWidgets('koyu temada çizilir', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(tufePct: 36.7, reel: 8.34, fark: 11.4),
          xirr: 31.4,
        ),
        brightness: Brightness.dark,
      );
      expect(find.textContaining('Reel getiri'), findsOneWidget);
    });
  });
}
