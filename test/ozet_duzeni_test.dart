import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/services/recap_service.dart';
import 'package:portfoy_takip/services/tufe_koprusu.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/aralik_cipi.dart';
import 'package:portfoy_takip/widgets/period_summary_view.dart';

/// Özet düzeni A + aralık çipi + TÜFE köprü satırı (kullanıcı kararları
/// 2026-10-01).
///
/// Emülatör 1Y'de üst kart "+%23,05" (1 Eki 25 → bugün), reel kart "+8,3
/// puan önde" (Ağustos → Ağustos) yazıyordu; kullanıcı çelişki okudu.
/// Kovalanan:
///   1. Her getiri yüzdesi ölçüldüğü aralığı çipte taşır (ana rakam
///      "... - bugün", reel "Ağu 25 - Ağu 26", XIRR "İlk alımdan bugüne").
///   2. Köprü satırı (D2): TÜFE penceresi sonundan bugüne, ölçülmüşse ve
///      arada ≥1 gün varsa; yoksa çizilmez (uydurma sayı yok).
///   3. Sıra A: SONUÇ (ana rakam, reel) → NEDEN (köprü, seyir, uçlar,
///      dağılım, kıyas) → AYRINTI (birikim, derinlik).
///   4. Kıyas slotu null'da hiçbir şey çizmez.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    await initializeDateFormatting('en_US');
  });

  /// 1Y özeti: 1 Eki 25 → 1 Eki 26, reel kart Ağu 25 → Ağu 26.
  PeriodSummary ozet({
    SummaryPeriod period = SummaryPeriod.birYil,
    bool reel = true,
    bool pencere = true,
    DateTime? tufeBas,
    DateTime? tufeBit,
  }) =>
      PeriodSummary(
        period: period,
        start: DateTime(2025, 10, 1),
        end: DateTime(2026, 10, 1, 9),
        baslangicTRY: 2000000,
        sonTRY: 2600000,
        katkiTRY: 140000,
        piyasaTRY: 460000,
        getiriPct: 23.05,
        enIyi: const RecapAsset('AAA', 41.2),
        enZayif: const RecapAsset('BBB', -8.4),
        sparkline: const [100, 104, 101, 110, 123],
        dagilimBasi: const {AssetType.altin: 1000000, AssetType.hisse: 1000000},
        dagilimSonu: const {AssetType.altin: 1400000, AssetType.hisse: 1200000},
        tufePct: reel ? 31.51 : null,
        tufeNominalPct: reel ? 39.77 : null,
        tufeFarki: reel ? 8.26 : null,
        reelGetiriPct: reel ? 6.28 : null,
        tufeBaslangic:
            reel && pencere ? (tufeBas ?? DateTime(2025, 8, 31)) : null,
        tufeBitis: reel && pencere ? (tufeBit ?? DateTime(2026, 8, 31)) : null,
      );

  final simdi = DateTime(2026, 10, 1, 12);
  final kopru =
      TufeKoprusu(pencereSonu: DateTime(2026, 8, 31), getiriPct: -5.15);

  Future<void> kur(
    WidgetTester t,
    Widget child, {
    Locale? locale,
    double width = 390,
  }) async {
    t.view.physicalSize = Size(width, 4000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(extensions: [SandikPalette.light]),
      localizationsDelegates:
          locale == null ? null : AppLocalizations.localizationsDelegates,
      supportedLocales: locale == null
          ? const [Locale('en', 'US')]
          : AppLocalizations.supportedLocales,
      locale: locale,
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(SandikSpace.lgs),
          child: child,
        ),
      ),
    ));
    await t.pumpAndSettle();
  }

  double y(WidgetTester t, Finder f) => t.getTopLeft(f).dy;

  group('aralık çipi', () {
    testWidgets('ana rakam: "Paranın getirisi" + "1 Eki 25 - bugün"',
        (t) async {
      await kur(t, PeriodSummaryView(summary: ozet(), simdi: simdi));
      expect(find.text('Paranın getirisi · 1Y'), findsOneWidget);
      expect(find.text('1 Eki 25 - bugün'), findsOneWidget);
      // Eski başlık ve "→" aralık satırı kalmadı.
      expect(find.textContaining('piyasa getirisi'), findsNothing);
      expect(find.textContaining('→'), findsNothing);
    });

    testWidgets('pencere bugünde bitmiyorsa sağ uç tarihtir', (t) async {
      await kur(
        t,
        PeriodSummaryView(summary: ozet(), simdi: DateTime(2026, 10, 3)),
      );
      expect(find.text('1 Eki 25 - 1 Eki 26'), findsOneWidget);
    });

    testWidgets('reel getiri: göreli "son 1 yıl" yerine "Ağu 25 - Ağu 26"',
        (t) async {
      await kur(t, PeriodSummaryView(summary: ozet(), simdi: simdi));
      expect(find.text('Enflasyona göre'), findsOneWidget);
      expect(find.text('Ağu 25 - Ağu 26'), findsOneWidget);
      expect(find.textContaining('son 1 yıl'), findsNothing);
    });

    testWidgets('reel getiri 1A: tek ay ADIYLA ("Ağustos 2026")', (t) async {
      await kur(
        t,
        PeriodSummaryView(
          summary: ozet(
            period: SummaryPeriod.birAy,
            tufeBas: DateTime(2026, 7, 31),
            tufeBit: DateTime(2026, 8, 31),
          ),
          simdi: simdi,
        ),
      );
      expect(find.text('Ağustos 2026'), findsOneWidget);
    });

    testWidgets('XIRR: "Başlangıçtan beri (yıllık)" + "İlk alımdan bugüne"',
        (t) async {
      await kur(
        t,
        PeriodSummaryView(summary: ozet(), xirr: 31.4, simdi: simdi),
      );
      expect(find.text('Başlangıçtan beri (yıllık)'), findsOneWidget);
      expect(find.text('İlk alımdan bugüne'), findsOneWidget);
      expect(find.text('Paranın getirisi (yıllık)'), findsNothing);
    });

    testWidgets('çip tek ortak widget — üç kartta üç AralikCipi', (t) async {
      await kur(
        t,
        PeriodSummaryView(summary: ozet(), xirr: 31.4, simdi: simdi),
      );
      expect(find.byType(AralikCipi), findsNWidgets(3));
    });
  });

  group('TÜFE köprü satırı (D2)', () {
    testWidgets('ölçüldüyse: "Ağu sonundan bugüne −%5,15" + açıklama tarihi',
        (t) async {
      await kur(
        t,
        PeriodSummaryView(summary: ozet(), tufeKoprusu: kopru, simdi: simdi),
      );
      // Bir sonraki TÜFE notu kartın gövdesinde (2026-10-01 sadeleştirme):
      // "Eylül TÜFE'si 3 Ekim tarihinde açıklanınca karşılaştırma Eylül
      // ayını da kapsar."
      expect(
        find.textContaining("Eylül TÜFE'si 3 Ekim tarihinde açıklanınca"),
        findsOneWidget,
      );
      // Köprü satırı katlanır "Nasıl hesaplandı" bölümünde, nominal
      // satırının altında.
      expect(find.text('Ağu sonundan bugüne'), findsNothing);
      await t.tap(find.text('Nasıl hesaplandı'));
      await t.pumpAndSettle();
      expect(find.text('Ağu sonundan bugüne'), findsOneWidget);
      expect(find.text('−%5,15'), findsOneWidget);
      expect(y(t, find.text('Ağu sonundan bugüne')),
          greaterThan(y(t, find.text('Bu aralıkta senin getirin'))));
    });

    testWidgets('açıklama günü geçtiyse tarih yazılmaz', (t) async {
      await kur(
        t,
        PeriodSummaryView(
          summary: ozet(),
          tufeKoprusu: kopru,
          simdi: DateTime(2026, 10, 4),
        ),
      );
      expect(find.textContaining('yüklenince'), findsOneWidget);
      expect(find.textContaining('3 Ekim'), findsNothing);
    });

    testWidgets('ölçüm yoksa satır YOK (uydurma sayı yasak)', (t) async {
      await kur(t, PeriodSummaryView(summary: ozet(), simdi: simdi));
      expect(find.textContaining('sonundan bugüne'), findsNothing);
      expect(find.textContaining('Üstteki rakam bu süreyi'), findsNothing);
    });

    testWidgets('TÜFE penceresi bilinmiyorsa köprü de çizilmez', (t) async {
      await kur(
        t,
        PeriodSummaryView(
          summary: ozet(pencere: false),
          tufeKoprusu: kopru,
          simdi: simdi,
        ),
      );
      expect(find.textContaining('sonundan bugüne'), findsNothing);
    });

    testWidgets('reel kart yoksa köprü de yok', (t) async {
      await kur(
        t,
        PeriodSummaryView(
          summary: ozet(reel: false),
          tufeKoprusu: kopru,
          simdi: simdi,
        ),
      );
      expect(find.textContaining('sonundan bugüne'), findsNothing);
    });
  });

  group('düzen A — Sonuç → Neden → Ayrıntı', () {
    Widget tam({Widget? kiyas, SummaryPeriod period = SummaryPeriod.birYil}) =>
        PeriodSummaryView(
          summary: ozet(period: period),
          simdi: simdi,
          tufeKoprusu: kopru,
          xirr: 31.4,
          karakter: PortfolioCharacter.dengeli,
          onShare: () {},
          katkiKarti: const Text('BİRİKİM-KARTI'),
          kiyasKarti: kiyas,
        );

    testWidgets('kart sırası soru sırasında', (t) async {
      await kur(t, tam(kiyas: const Text('KIYAS-KARTI')));

      final sira = [
        find.text('SONUÇ'),
        find.text('Paranın getirisi · 1Y'),
        find.text('Enflasyona göre'),
        find.text('Özetini paylaş'),
        find.text('NEDEN'),
        find.text('Nereden geldi'),
        find.text('Yıl eğrisi'),
        find.text('KIYAS-KARTI'),
        find.text('AYRINTI'),
        find.text('BİRİKİM-KARTI'),
        find.text('DERİNLİK'),
      ];
      for (final f in sira) {
        expect(f, findsOneWidget, reason: '$f yok');
      }
      for (var i = 1; i < sira.length; i++) {
        expect(y(t, sira[i]), greaterThan(y(t, sira[i - 1])),
            reason: '${sira[i]} → ${sira[i - 1]} altında olmalı');
      }
      // Eski başlıklar kalmadı.
      expect(find.text('BU DÖNEM'), findsNothing);
      expect(find.text('VARLIKLAR'), findsNothing);
    });

    testWidgets('kıyas slotu null iken hiçbir şey çizilmez', (t) async {
      await kur(t, tam());
      expect(find.text('KIYAS-KARTI'), findsNothing);
      // Slot boşken NEDEN'in son kartı uçlar kartıdır — araya boş kutu
      // girmedi: AYRINTI başlığı hemen ardından gelir.
      expect(find.text('NEDEN'), findsOneWidget);
    });

    testWidgets('kıyas kartı uçlardan SONRA, AYRINTI\'dan önce', (t) async {
      // 6A: uçlar kartı var (1Y bloğunda uçlar yok — o dönemin bağlamı
      // eğri ve Derinlik'teki karakter/sabır).
      await kur(t,
          tam(kiyas: const Text('KIYAS-KARTI'), period: SummaryPeriod.altiAy));
      expect(y(t, find.text('BBB')),
          greaterThan(y(t, find.text('Nereden geldi'))));
      expect(
          y(t, find.text('KIYAS-KARTI')), greaterThan(y(t, find.text('BBB'))));
      expect(
          y(t, find.text('KIYAS-KARTI')), lessThan(y(t, find.text('AYRINTI'))));
    });

    testWidgets('birikim kartı yoksa AYRINTI başlığı da yok', (t) async {
      await kur(
        t,
        PeriodSummaryView(
          summary: ozet(),
          simdi: simdi,
          karakter: PortfolioCharacter.dengeli,
        ),
      );
      expect(find.text('AYRINTI'), findsNothing);
      expect(find.text('DERİNLİK'), findsOneWidget);
    });

    testWidgets('320pt\'de çipler ve köprü taşmıyor', (t) async {
      await kur(t, tam(kiyas: const Text('KIYAS-KARTI')), width: 320);
      expect(t.takeException(), isNull);
    });
  });

  group('İngilizce', () {
    testWidgets('bölüm başlıkları, çip ve köprü çevrilmiş', (t) async {
      await kur(
        t,
        PeriodSummaryView(
          summary: ozet(),
          simdi: simdi,
          tufeKoprusu: kopru,
          katkiKarti: const SizedBox.shrink(),
        ),
        locale: const Locale('en'),
      );
      expect(find.text('RESULT'), findsOneWidget);
      expect(find.text('WHY'), findsOneWidget);
      expect(find.text('DETAIL'), findsOneWidget);
      expect(find.text('Return on your money · 1Y'), findsOneWidget);
      expect(find.text('1 Oct 25 - today'), findsOneWidget);
      expect(find.text('Aug 25 - Aug 26'), findsOneWidget);
      expect(find.textContaining('September CPI is published on 3 October'),
          findsOneWidget);
      await t.tap(find.text('How it was computed'));
      await t.pumpAndSettle();
      expect(find.text('Since end of Aug'), findsOneWidget);
    });
  });
}
