import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/l10n/l10n.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/secili_donem_provider.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart'
    show seciliYorumlanabilir;
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';

import 'helpers/kaynak.dart';

/// YB (yıl başından beri) dönemi — müşteri raporu 2026-11-08 12:30 #2.
///
/// Kilitler: (1) pencere 1 Ocak'tan başlar, yılın ilk günü dahil;
/// (2) yeni değer enum'un SONUNDA, 0–6'nın anlamı kaymaz; (3) yalnız
/// Performans şeridinde ve 1Y'nin hemen önünde, sembol yüzeyleri 1Y'ye
/// düşer; (4) etiket "YB"/"YTD", ekran okuyucu "Yıl başından beri".
void main() {
  group('pencere', () {
    test('Kasım: 1 Ocak 00:00\'dan bugüne', () {
      final now = DateTime(2026, 11, 8, 14, 30);
      final p = PeriodSummaryService.pencere(SummaryPeriod.yilBasi, now);
      expect(p.start, DateTime(2026, 1, 1));
      expect(p.end, now);
    });

    test('1 Ocak\'ın kendisi: pencere o günün başı', () {
      final now = DateTime(2027, 1, 1, 0, 30);
      final p = PeriodSummaryService.pencere(SummaryPeriod.yilBasi, now);
      expect(p.start, DateTime(2027, 1, 1),
          reason: 'geçen yılın 1 Ocak\'ına kaymamalı');
      expect(p.start.isAfter(p.end), isFalse);
    });

    test('31 Aralık: hâlâ bu yılın 1 Ocak\'ı', () {
      final p = PeriodSummaryService.pencere(
          SummaryPeriod.yilBasi, DateTime(2026, 12, 31, 23, 59));
      expect(p.start, DateTime(2026, 1, 1));
    });

    test('Ocak başında 1Y geçen yıla, YB bu yıla bakar', () {
      final now = DateTime(2027, 1, 3, 10);
      expect(PeriodSummaryService.pencere(SummaryPeriod.yilBasi, now).start,
          DateTime(2027, 1, 1));
      expect(PeriodSummaryService.pencere(SummaryPeriod.birYil, now).start,
          DateTime(2026, 1, 3));
    });

    test('yilBasiGunu yerel 1 Ocak', () {
      expect(yilBasiGunu(DateTime(2026, 7, 15, 9)), DateTime(2026, 1, 1));
      expect(yilBasiGunu(DateTime(2026, 7, 15)), dayKey(DateTime(2026)));
    });
  });

  group('gün sayısı', () {
    test('1 Ocak\'tan geçen gün, ilk hafta en az 7', () {
      expect(SummaryPeriod.yilBasindanGun(DateTime(2026, 1, 1, 9)), 7);
      expect(SummaryPeriod.yilBasindanGun(DateTime(2026, 1, 5, 9)), 7);
      expect(SummaryPeriod.yilBasindanGun(DateTime(2026, 1, 20, 9)), 19);
      expect(SummaryPeriod.yilBasindanGun(DateTime(2026, 11, 8, 9)), 311);
      // Artık yıl: 31 Aralık 2024 → 365 gün geçmiş.
      expect(SummaryPeriod.yilBasindanGun(DateTime(2024, 12, 31, 9)), 365);
    });

    test('YB\'nin günü bugünün takvim değeriyle aynı, 7–366 arası', () {
      final d = SummaryPeriod.yilBasi.days;
      expect(d, SummaryPeriod.yilBasindanGun(DateTime.now()));
      expect(d, inInclusiveRange(7, 366));
    });

    test('YB 1Y değildir: yıllık oran ve 1Y kartları ona bağlanmaz', () {
      expect(SummaryPeriod.yilBasi.ayGeri, isNull);
      expect(SummaryPeriod.yilBasi.intraday, isFalse);
      expect(SummaryPeriod.yilBasi.days > SummaryPeriod.birYil.days, isFalse);
    });
  });

  group('portföy 1 Ocak\'tan sonra başladıysa', () {
    test('pencere yine 1 Ocak, uçlar ilk ölçümden', () {
      final now = DateTime(2026, 11, 8, 15);
      // İlk alım 10 Mart: seri o gün başlar.
      final total = <int, double>{};
      for (var i = 0; i < 200; i++) {
        final d = DateTime(2026, 3, 10 + i, 18);
        if (d.isAfter(now)) break;
        total[d.millisecondsSinceEpoch] = i == 0 ? 10000.0 : 11000.0;
      }
      final lot = Asset(
        id: 'ilk',
        userId: 'u',
        name: 'ilk',
        ticker: 'THYAO',
        type: AssetType.hisse,
        quantity: 100,
        purchasePrice: 100,
        currency: 'TRY',
        notes: '',
        isManualPrice: false,
        currentPrice: 110,
        addedDate: DateTime(2026, 3, 10),
      );
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.yilBasi,
        assets: [lot],
        breakdown: PortfolioHistoryBreakdown(
          total: total,
          byType: {AssetType.hisse: total},
          byPosition: const {},
          positionType: const {},
        ),
        now: now,
      );
      expect(s.period, SummaryPeriod.yilBasi);
      expect(s.start, DateTime(2026, 1, 1));
      // Dönem başı değeri uydurulmaz: seri Mart'ta başlıyor, ilk ölçüm
      // dönem başıdır (Ocak–Mart için sıfır yazılmaz).
      expect(s.baslangicTRY, 10000.0);
      expect(s.sonTRY, 11000.0);
    });
  });

  group('sıra ve yüzeyler', () {
    test('YB enum\'un sonunda; 0–6 aynı', () {
      expect(SummaryPeriod.values.last, SummaryPeriod.yilBasi);
      expect(SummaryPeriod.birYil.index, 5);
      expect(SummaryPeriod.besYil.index, 6);
    });

    test('Performans sırası: YB 1Y\'nin hemen önünde, her dönem bir kez', () {
      const s = SummaryPeriod.performansSirasi;
      expect(s.toSet(), SummaryPeriod.values.toSet());
      expect(s.length, SummaryPeriod.values.length);
      expect(s.indexOf(SummaryPeriod.yilBasi) + 1,
          s.indexOf(SummaryPeriod.birYil));
      expect(s.map((p) => p.label).toList(),
          ['GÜNLÜK', '1H', '1A', '3A', '6A', 'YB', '1Y', '5Y']);
    });

    test('sembol yüzeyleri YB\'siz, indeksler values ile aynı', () {
      final s = SummaryPeriod.sembolDonemleri;
      expect(s.contains(SummaryPeriod.yilBasi), isFalse);
      for (var i = 0; i < s.length; i++) {
        expect(s[i].index, i);
      }
      expect(SummaryPeriod.yilBasi.sembolKarsiligi, SummaryPeriod.birYil);
      expect(SummaryPeriod.altiAy.sembolKarsiligi, SummaryPeriod.altiAy);
      expect(SummaryPeriod.yilBasi.sembolGunu, 365);
    });

    test('ortak dönem YB iken sembol yüzeyi 1Y gösterir', () {
      expect(
          gosterilebilirDonem(
              SummaryPeriod.yilBasi, SummaryPeriod.sembolDonemleri),
          SummaryPeriod.birYil);
      // Elle fiyatlanan varlık (GÜNLÜK'süz) da 1Y'ye düşer, 5Y'ye değil.
      expect(
          gosterilebilirDonem(SummaryPeriod.yilBasi,
              SummaryPeriod.sembolDonemleri.skip(1).toList()),
          SummaryPeriod.birYil);
      // YB'yi gösteren yüzey kendisini alır.
      expect(
          gosterilebilirDonem(
              SummaryPeriod.yilBasi, SummaryPeriod.performansSirasi),
          SummaryPeriod.yilBasi);
    });

    test('yalnız Performans şeridi YB çizer', () {
      expect(
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart'),
          contains('SummaryPeriod.performansSirasi'));
      for (final f in [
        'lib/screens/watchlist_screen.dart',
        'lib/screens/comparison_screen.dart',
        'lib/screens/varlik_sayfasi.dart',
        'lib/screens/asset_detail_screen.dart',
      ]) {
        final k = ekranKaynagiSync(f);
        expect(k, contains('SummaryPeriod.sembolDonemleri'), reason: f);
        expect(k.contains('donemler: SummaryPeriod.values'), isFalse,
            reason: f);
      }
    });

    test('YB seçili dönem yorumu istenmez (sunucu tanımıyor)', () {
      expect(seciliYorumlanabilir(SummaryPeriod.yilBasi), isFalse);
      expect(seciliYorumlanabilir(SummaryPeriod.birYil), isTrue);
    });

    test('cümle içi adı', () {
      expect(PeriodSummaryService.donemAdi(SummaryPeriod.yilBasi),
          'Yıl başından beri');
    });
  });

  group('etiket ve ekran okuyucu', () {
    test('TR "YB", EN "YTD"; okunuşu sözcükle', () {
      final tr = AppLocalizationsTr(), en = AppLocalizationsEn();
      expect(donemEtiketi(tr, 'YB'), 'YB');
      expect(donemEtiketi(en, 'YB'), 'YTD');
      expect(donemSemantigi(tr, 'YB'), 'Yıl başından beri');
      expect(donemSemantigi(en, 'YB'), 'Year to date');
      // Diğer dönemler etiketiyle okunur.
      expect(donemSemantigi(tr, '1Y'), donemEtiketi(tr, '1Y'));
    });

    Future<void> kur(WidgetTester t, double genislik,
        {double olcek = 1, SummaryPeriod secili = SummaryPeriod.yilBasi}) async {
      t.view.physicalSize = Size(genislik, 200);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      const sira = SummaryPeriod.performansSirasi;
      await t.pumpWidget(MaterialApp(
        theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('tr'),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(genislik, 200), textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: SandikSpace.md),
              child: DonemSecici(
                donemler: sira,
                secili: sira.indexOf(secili),
                onSec: (_) {},
              ),
            ),
          ),
        ),
      ));
      await t.pump();
    }

    for (final genislik in [360.0, 320.0]) {
      testWidgets('${genislik.round()}pt: sekiz dönem taşmaz, YB 1 yıl\'ın '
          'solunda', (t) async {
        await kur(t, genislik);
        expect(t.takeException(), isNull);
        const etiketler = [
          'Bugün', '1 hf', '1 ay', '3 ay', '6 ay', 'YB', '1 yıl', '5 yıl' //
        ];
        for (final e in etiketler) {
          expect(find.text(e), findsOneWidget, reason: e);
        }
        final yb = t.getCenter(find.text('YB')).dx;
        expect(yb, lessThan(t.getCenter(find.text('1 yıl')).dx));
        expect(yb, greaterThan(t.getCenter(find.text('6 ay')).dx));
      });
    }

    testWidgets('büyük metinde (x2) de taşmaz', (t) async {
      await kur(t, 360, olcek: 2);
      expect(t.takeException(), isNull);
      expect(find.text('YB'), findsOneWidget);
    });

    testWidgets('dokunma yüksekliği 44pt ve çip "Yıl başından beri" okunur',
        (t) async {
      final h = t.ensureSemantics();
      await kur(t, 360);
      expect(find.bySemanticsLabel('Yıl başından beri'), findsOneWidget);
      expect(find.bySemanticsLabel('YB'), findsNothing);
      expect(t.getSize(find.byType(DonemSecici)).height,
          greaterThanOrEqualTo(SandikTouch.min));
      h.dispose();
    });
  });
}
