import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/kilometre_tasi_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/milestone_service.dart';
import 'package:portfoy_takip/widgets/kilometre_tasi_seridi.dart';
import 'package:portfoy_takip/widgets/milestone_sheet.dart';
import 'package:portfoy_takip/widgets/share_card.dart' show KilometreTasiPaylasKarti;
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/kaynak.dart';

/// Profil "Kilometre taşların" şeridi (Ar-Ge 1 Kas 20:45 #1; yasin
/// "önerini uygula": ücretsiz).
///
/// Kilitlenenler (müşteri raporu 1 Kas 21:15 koşulları):
/// 1. Geçilen eşik KALICI: toplam düşse de sunucu kaydındaki taş görünür.
/// 2. Bakiye gizliyken tutar taşıyan taş tutarsız; altın adedi kalır.
/// 3. Sıradaki taş bugünkü veriden; uydurma yok, hepsi geçildiyse yok.
/// 4. Şerit kutlamayı tetiklemez, Premium kapısı yok.
void main() {
  group('MilestoneService koleksiyon', () {
    test('sunucu kaydı bugünkü hesapla birleşir: düşüşte taş kalır', () {
      final k = MilestoneService.koleksiyon(
        kayitli: {'portfolio_value:100000', 'gold_count:ALTIN_CEYREK:5'},
        bugun: const [], // toplam 60 binde: bugün 100 bin geçilmiş değil
        totalTRY: 60000,
      );
      expect(k.kazanilan.map((m) => m.toString()),
          containsAll(['portfolio_value:100000', 'gold_count:ALTIN_CEYREK:5']));
      // Sıradaki, en yüksek GEÇİLMİŞ eşiğin üstü: 250 bin (60 bin değil).
      expect(k.siradaki!.rank, 250000);
    });

    test('tanınmayan ya da bozuk kayıt rozet üretmez', () {
      final k = MilestoneService.koleksiyon(
        kayitli: {'portfolio_value:123', 'yok:1', 'bozuk', 'gold_count:X:5'},
        bugun: const [],
        totalTRY: 0,
      );
      expect(k.kazanilan, isEmpty);
      expect(k.siradaki!.rank, 10000);
    });

    test('anahtardan bütün türleri kurar', () {
      for (final (kind, value) in [
        ('portfolio_value', '1000000'),
        ('gold_count', 'ALTIN_GRAM:10'),
        ('portfolio_age', '2y'),
        ('diversification', '3types'),
        ('contribution_streak', '6m'),
      ]) {
        final m = MilestoneService.anahtardan(kind, value);
        expect(m, isNotNull, reason: '$kind:$value');
        expect(m!.value, value);
      }
    });

    test('hepsi geçildiyse sıradaki yok', () {
      final k = MilestoneService.koleksiyon(
        kayitli: const {},
        bugun: const [],
        totalTRY: 20000000,
      );
      expect(k.siradaki, isNull);
    });

    test('vitrin her türün en yükseğini, altında her altın cinsini tutar', () {
      final k = MilestoneService.koleksiyon(
        kayitli: {
          'portfolio_value:10000',
          'portfolio_value:25000',
          'gold_count:ALTIN_GRAM:1',
          'gold_count:ALTIN_GRAM:5',
          'gold_count:ALTIN_CEYREK:1',
          'portfolio_age:1y',
        },
        bugun: const [],
        totalTRY: 30000,
      );
      final v = MilestoneService.vitrin(k.kazanilan).map((m) => '$m');
      expect(v, [
        'portfolio_age:1y',
        'portfolio_value:25000',
        'gold_count:ALTIN_GRAM:5',
        'gold_count:ALTIN_CEYREK:1',
      ]);
    });

    // Ar-Ge 5 Kas 21:00 #1: sıradaki taşta ilerleme ve kalan.
    test('ilerleme = toplam / eşik, kalan = eşik − toplam', () {
      final k = MilestoneService.koleksiyon(
          kayitli: {'portfolio_value:250000'}, bugun: const [], totalTRY: 430000);
      expect(k.siradaki!.rank, 500000);
      expect(k.ilerleme, closeTo(0.86, 1e-9));
      expect(k.kalan, 70000);
      expect(MilestoneService.kalanKisa(70000), '70 bin ₺');
      expect(MilestoneService.kalanKisa(69200), '70 bin ₺'); // yukarı
      expect(MilestoneService.kalanKisa(300), '1 bin ₺');
      final bos = MilestoneService.koleksiyon(
          kayitli: const {}, bugun: const [], totalTRY: 0);
      expect(bos.ilerleme, isNull, reason: 'toplam bilinmiyor: bayrak');
      expect(bos.kalan, isNull);
    });

    test('gizli: tutar taşı tutarsız, altın aynen', () {
      final deger = MilestoneService.anahtardan('portfolio_value', '100000')!;
      final g = MilestoneService.gizli(deger);
      expect('${g.title} ${g.body}', isNot(contains('100')));
      final altin = MilestoneService.anahtardan('gold_count', 'ALTIN_GRAM:5')!;
      expect(MilestoneService.gizli(altin).title, altin.title);
    });
  });

  group('satır (Profil yeniden tasarımı, 7 Kas)', () {
    final veri = MilestoneService.koleksiyon(
      kayitli: {
        'portfolio_value:10000',
        'portfolio_value:100000',
        'gold_count:ALTIN_GRAM:5',
      },
      bugun: const [],
      totalTRY: 120000,
    );

    Future<ProviderContainer> pump(WidgetTester tester,
        {bool gizli = false,
        double olcek = 1,
        double genislik = 390,
        ({
          List<Milestone> kazanilan,
          Milestone? siradaki,
          double? ilerleme,
          double? kalan,
        })? ozel}) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(genislik, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final v = ozel ?? veri;
      await tester.pumpWidget(ProviderScope(
        overrides: [kilometreTaslariProvider.overrideWithValue(v)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(
                size: Size(genislik, 844),
                textScaler: TextScaler.linear(olcek)),
            child: const Scaffold(
              body: SingleChildScrollView(
                padding: EdgeInsets.all(16),
                child: KilometreTasiSeridi(),
              ),
            ),
          ),
        ),
      ));
      final c = ProviderScope.containerOf(
          tester.element(find.byType(KilometreTasiSeridi)));
      await c.read(balanceHiddenProvider.notifier).set(gizli);
      await tester.pump();
      return c;
    }

    final satir = find.byKey(const ValueKey('kilometreTasiSatiri'));

    testWidgets('sıradaki, kalan ve merdivendeki yer tek satırda',
        (tester) async {
      await pump(tester);
      expect(find.text('Kilometre taşların'), findsOneWidget);
      expect(find.text('Sıradaki: 250 bin ₺'), findsOneWidget);
      // 10 bin, 25 bin, 50 bin, 100 bin geçildi → merdivende 4 / 10.
      expect(find.text('4 / 10'), findsOneWidget);
      expect(find.text('130 bin ₺ kaldı'), findsOneWidget);
      // Rozet şeridi ve eşit kartlar yok; geçilen taş adı satırda yazmaz.
      expect(find.text('100 bin ₺ geçildi'), findsNothing);
      expect(find.text('Tümü ›'), findsNothing);
      // Halka/gösterge değil, statik çubuk.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(
          find.bySemanticsLabel(RegExp(
              r'^Sıradaki kilometre taşı: 250 bin ₺, yüzde 48, 130 bin ₺ kaldı\. '
              r'10 portföy eşiğinden 4 tanesi geçildi\.')),
          findsOneWidget);
    });

    testWidgets('dokununca tam liste açılır', (tester) async {
      await pump(tester);
      await tester.tap(satir);
      await tester.pumpAndSettle();
      expect(find.text('10 bin ₺ geçildi'), findsOneWidget);
      expect(find.text('100 bin ₺ geçildi'), findsOneWidget);
      expect(find.text('5 gram altın'), findsOneWidget);
      expect(find.text('Sıradaki: 250 bin ₺'), findsWidgets);
    });

    testWidgets('bakiye gizliyken tutar yok; çubuk ve sayaç kalır',
        (tester) async {
      await pump(tester, gizli: true);
      expect(find.textContaining('bin ₺'), findsNothing);
      expect(find.textContaining('kaldı'), findsNothing);
      expect(find.text('Sıradaki: Portföy eşiği'), findsOneWidget);
      expect(find.text('4 / 10'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
      await tester.tap(satir);
      await tester.pumpAndSettle();
      expect(find.textContaining('bin ₺'), findsNothing);
      expect(find.text('5 gram altın'), findsOneWidget);
    });

    testWidgets('hepsi geçildiyse uydurma hedef yok', (tester) async {
      await pump(tester,
          ozel: MilestoneService.koleksiyon(
              kayitli: const {}, bugun: const [], totalTRY: 20000000));
      // Kazanılan yok, sıradaki yok → satır hiç çizilmez.
      expect(satir, findsNothing);
      final hepsi = MilestoneService.koleksiyon(
          kayitli: {'portfolio_value:10000000'},
          bugun: const [],
          totalTRY: 20000000);
      await pump(tester, ozel: hepsi);
      expect(find.text('Bütün portföy eşiklerini geçtin'), findsOneWidget);
      expect(find.text('10 / 10'), findsOneWidget);
      expect(find.textContaining('kaldı'), findsNothing);
      expect(find.byType(FractionallySizedBox), findsNothing);
    });

    testWidgets('toplam bilinmiyorsa çubuk ve kalan yok', (tester) async {
      await pump(tester,
          ozel: MilestoneService.koleksiyon(
              kayitli: {'gold_count:ALTIN_GRAM:5'},
              bugun: const [],
              totalTRY: 0));
      expect(find.text('Sıradaki: 10 bin ₺'), findsOneWidget);
      expect(find.text('0 / 10'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsNothing);
      expect(find.textContaining('kaldı'), findsNothing);
    });

    testWidgets('kutlamada Paylaş: listeden açılır, tutarsız kart',
        (tester) async {
      await pump(tester);
      await tester.tap(satir);
      await tester.pumpAndSettle();
      await tester.tap(find.text('5 gram altın'));
      await tester.pumpAndSettle();
      expect(find.byType(MilestoneSheet), findsOneWidget);
      expect(find.text('Toplam 5 gram altın biriktirdin.'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('kilometreTasiPaylas')));
      await tester.pumpAndSettle();
      expect(find.byType(KilometreTasiPaylasKarti), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(KilometreTasiPaylasKarti),
              matching: find.textContaining('₺')),
          findsNothing);
    });

    testWidgets('Dynamic Type 3.1× ve 320 pt: taşma yok', (tester) async {
      await pump(tester, olcek: 3.1, genislik: 320);
      expect(tester.takeException(), isNull);
      await tester.tap(satir);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('dokunma alanı ≥44 pt', (tester) async {
      await pump(tester);
      final kutu = tester.getSize(satir);
      expect(kutu.height, greaterThanOrEqualTo(44));
      expect(kutu.width, greaterThanOrEqualTo(44));
    });
  });

  test('esikSayaci: merdivendeki yer, hepsi geçildiyse dolu', () {
    final s = MilestoneService.esikSayaci(
        MilestoneService.koleksiyon(
                kayitli: const {}, bugun: const [], totalTRY: 2700000)
            .siradaki);
    expect((s.gecilen, s.toplam), (8, 10));
    final h = MilestoneService.esikSayaci(null);
    expect((h.gecilen, h.toplam), (10, 10));
  });

  test('şerit yalnız gösterir', () {
    final k = ekranKaynagiSync('lib/widgets/kilometre_tasi_seridi.dart') +
        ekranKaynagiSync('lib/providers/kilometre_tasi_provider.dart');
    for (final yasak in [
      'recordReached',
      'markCelebrated',
      'markShown',
      'premiumKilitliProvider',
      'effectivePremiumProvider',
    ]) {
      expect(k.contains(yasak), isFalse, reason: yasak);
    }
    expect(k, contains('tekrar: true'));
  });
}
