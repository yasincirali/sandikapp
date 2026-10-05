import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/position.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

import 'helpers/kaynak.dart';

/// 2026-09-29 emülatör testi, G4 (Performans / Özet tutarlılığı) bulguları.
///
///   #4  Özet 1A: "piyasa getirisi −₺48.092 · Bu ay ekside" yanında reel
///       getiri kartı "▲%6,18 … alım gücün arttı · Senin getirin %8,14".
///       Kök neden: iki kart FARKLI aralıkları ölçüyor (dönem kartı bugüne
///       kadarki son 30 gün, reel kart son açıklanmış TÜFE ayı). Kart bunu
///       hüküm cümlesinin altında söylemeli, nominal satırı "bu aralıkta".
///   #6  Ana rakam rozeti tutar işaretliyken yüzdeyi işaretsiz yazıyordu.
///   #11 Tür dökümü ekran okuyucusu birikim değişimini "kazanç/kayıp" okuyordu.
///   #23 GÜNLÜK "en çok hareket eden" ham `ARDYZ.IS` yazıyordu.
///   #26 Bugün kartı "Geçen hafta" etiketi kayan 7 günü anlatıyordu.
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  PeriodSummary ozet({
    double piyasa = -48092,
    double pct = -3.35,
    double? tufePct,
    double? reel,
    double? nominal,
    bool pencere = true,
  }) =>
      PeriodSummary(
        period: SummaryPeriod.birAy,
        start: DateTime(2026, 8, 29),
        end: DateTime(2026, 9, 29),
        baslangicTRY: 1400000,
        sonTRY: 1400000 + piyasa,
        katkiTRY: 0,
        piyasaTRY: piyasa,
        getiriPct: pct,
        tufePct: tufePct,
        reelGetiriPct: reel,
        tufeFarki: (nominal != null && tufePct != null)
            ? nominal - tufePct
            : null,
        tufeNominalPct: nominal,
        tufeBaslangic: pencere && tufePct != null ? DateTime(2026, 7, 31) : null,
        tufeBitis: pencere && tufePct != null ? DateTime(2026, 8, 31) : null,
      );

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [SandikPalette.light]),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ));
    await tester.pumpAndSettle();
  }

  group('#6 ana rakam rozeti yönlü yüzde', () {
    testWidgets('kayıpta yüzde de eksi işaretli (U+2212)', (t) async {
      await pump(t, PeriodSummaryView(summary: ozet()));
      expect(find.text('−%3,35'), findsOneWidget);
      // Eski biçimler yok: işaretsiz ya da sayının içinde eksi.
      expect(find.text('%3,35'), findsNothing);
      expect(find.text('%-3,35'), findsNothing);
    });

    testWidgets('kazançta "+%"', (t) async {
      await pump(t, PeriodSummaryView(summary: ozet(piyasa: 48092, pct: 3.35)));
      expect(find.text('+%3,35'), findsOneWidget);
    });
  });

  group('#4 reel getiri kartı aralığını söyler', () {
    testWidgets('TÜFE penceresi biliniyorsa not + "bu aralıkta" etiketi',
        (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(tufePct: 1.85, nominal: 8.14, reel: 6.18),
        ),
      );
      // Hüküm (dönem kartı eksi, reel kart artı) kendi başına çelişki gibi
      // okunuyordu; aralık artık cümlenin İLK kelimesinde (2026-10-01).
      expect(find.textContaining('Ağustos 2026 ayında birikimin %8,1 arttı'),
          findsOneWidget);
      // Renk/yön ilgili metrikten: dönem kartı eksi, reel kart kendi ▲'sı.
      expect(find.text('▲'), findsOneWidget);
      // Ham girdi katlanır bölümde, "bu aralıkta" etiketiyle.
      await t.tap(find.text('Nasıl hesaplandı'));
      await t.pumpAndSettle();
      expect(find.text(trMetni('nominalReturnInWindow')), findsOneWidget);
      expect(find.text(trMetni('nominalReturn')), findsNothing);
      expect(find.text('+%8,14'), findsOneWidget);
    });

    testWidgets('eksi nominal yönlü yazılır, "%-" değil', (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary: ozet(tufePct: 1.85, nominal: -3.10, reel: -4.86),
        ),
      );
      expect(find.text('▼'), findsOneWidget);
      expect(find.textContaining('birikimin %3,1 azaldı'), findsOneWidget);
      await t.tap(find.text('Nasıl hesaplandı'));
      await t.pumpAndSettle();
      expect(find.text('−%3,10'), findsOneWidget);
      expect(find.text('−%4,86'), findsOneWidget);
      expect(find.textContaining('%-'), findsNothing);
    });

    testWidgets('pencere yoksa not da yok (ölçülmemiş şey anlatılmaz)',
        (t) async {
      await pump(
        t,
        PeriodSummaryView(
          summary:
              ozet(tufePct: 1.85, nominal: 8.14, reel: 6.18, pencere: false),
        ),
      );
      expect(find.text(trMetni('cpiWindowNote')), findsNothing);
      expect(find.textContaining('ayında birikimin'), findsNothing);
      await t.tap(find.text('Nasıl hesaplandı'));
      await t.pumpAndSettle();
      expect(find.text(trMetni('nominalReturn')), findsOneWidget);
    });

    test('not iki dilde de "farklı aralık" der', () {
      expect(trMetni('cpiWindowNote'), contains('farklı'));
      expect(lookupAppLocalizations(const Locale('en')).cpiWindowNote,
          contains('different windows'));
    });
  });

  group('#11 tür dökümü ekran okuyucu metni', () {
    final src = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');

    test('satır her dönemde piyasanın kattığı — "kazanç/kayıp" doğru', () {
      // 2026-10-01: satır artık her dönemde arındırılmış (akış düşülmüş);
      // "artış/azalış" ayrımına gerek kalmadı, ekran okuyucu da kazanç/kayıp
      // der. Akış ve birikim değişimi alt satırda ("Alım +₺… · birikim +₺…").
      expect(src, contains('gainAmount('));
      expect(src, contains('lossAmount('));
      expect(src.contains('breakdownUpAmount('), isFalse);
      expect(src, contains('bool get _net => !widget.simulate;'));
      expect(src, contains('flowBuyBalance('));
      expect(src, contains('flowSellBalance('));
      // Ham Türkçe literal kalmadı.
      expect(src.contains("'değişim yok'"), isFalse);
      expect(trMetni('breakdownDownAmount'), startsWith('azalış'));
      expect(trMetni('breakdownUpAmount'), startsWith('artış'));
    });
  });

  group('#23 pozisyon etiketi ham sembol göstermez', () {
    test('pozisyonKodu kaynak öneki ve .IS sonekini atar', () {
      expect(pozisyonKodu('ARDYZ.IS'), 'ARDYZ');
      expect(pozisyonKodu('TEFAS:AFT'), 'AFT');
      expect(pozisyonKodu('KRIPTO:BTC'), 'BTC');
      expect(pozisyonKodu('TUPRS'), 'TUPRS');
      // Boşa düşen kod ham çekirdeği korur (uydurma etiket yok).
      expect(pozisyonKodu('.IS'), '.IS');
    });

    // Gövde 2026-10-04'te `pozisyonEtiketi`'ne taşındı (Bugün kartı da okur).
    test('pozisyonEtiketi sembol çekirdeğini pozisyonKodu ile sadeleştirir', () {
      final src = ekranKaynagiSync('lib/utils/pozisyon_etiketi.dart');
      final i = src.indexOf('String pozisyonEtiketi(');
      expect(i, greaterThanOrEqualTo(0));
      final govde = src.substring(i, src.indexOf('\n}', i));
      expect(govde, contains('pozisyonKodu(core)'));
    });
  });

  group('#26 Bugün kartı haftalık satırı', () {
    // Kartta "Son 7 gün" kutusu D düzeniyle 2026-10-05'te kalktı
    // (`todayWeekLabel` silindi); hesap hâlâ yapılır (gösterim ölçümü).
    test('hesap Özet 1H ile aynı pencere (kayan, ucu canlı)', () {
      final src = ekranKaynagiSync('lib/services/bugun_yukleyici.dart');
      final i = src.indexOf('static Future<double?> haftalik(');
      final govde = src.substring(i, src.indexOf('BugunYukleyici.haftalik', i));
      expect(govde, contains('SummaryPeriod.birHafta'));
      expect(govde, contains('canliSon:'));
    });

    test('tur adımı etiketle aynı adı kullanır', () {
      final src = ekranKaynagiSync('lib/screens/onboarding_screen.dart');
      expect(src, contains('son 7 gün'));
      expect(src.contains('durumun, geçen hafta'), isFalse);
    });
  });
}
