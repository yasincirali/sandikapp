import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/kilometre_tasi_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/services/milestone_service.dart';
import 'package:portfoy_takip/widgets/kilometre_tasi_seridi.dart';
import 'package:portfoy_takip/widgets/milestone_sheet.dart';
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

    test('gizli: tutar taşı tutarsız, altın aynen', () {
      final deger = MilestoneService.anahtardan('portfolio_value', '100000')!;
      final g = MilestoneService.gizli(deger);
      expect('${g.title} ${g.body}', isNot(contains('100')));
      final altin = MilestoneService.anahtardan('gold_count', 'ALTIN_GRAM:5')!;
      expect(MilestoneService.gizli(altin).title, altin.title);
    });
  });

  group('şerit', () {
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
        {bool gizli = false, double olcek = 1}) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(ProviderScope(
        overrides: [kilometreTaslariProvider.overrideWithValue(veri)],
        child: MaterialApp(
          theme: ThemeData.dark(),
          home: MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
            child: const Scaffold(
              body: Padding(
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

    testWidgets('kazanılanlar, sıradaki ve Tümü', (tester) async {
      await pump(tester);
      expect(find.text('KİLOMETRE TAŞLARIN'), findsOneWidget);
      expect(find.text('100 bin ₺ geçildi'), findsOneWidget);
      // 10 bin vitrinde değil (aynı türün küçüğü), Tümü'nde.
      expect(find.text('10 bin ₺ geçildi'), findsNothing);
      expect(find.text('5 gram altın'), findsOneWidget);
      expect(find.text('Sıradaki'), findsOneWidget);
      expect(find.text('250 bin ₺'), findsOneWidget);

      await tester.tap(find.text('Tümü ›'));
      await tester.pumpAndSettle();
      expect(find.text('Kilometre taşların'), findsOneWidget);
      expect(find.text('10 bin ₺ geçildi'), findsOneWidget);
      expect(find.text('Sıradaki: 250 bin ₺'), findsOneWidget);
    });

    testWidgets('rozete dokununca kutlama sayfası yeniden açılır',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('5 gram altın'));
      await tester.pumpAndSettle();
      expect(find.byType(MilestoneSheet), findsOneWidget);
      expect(find.text('Toplam 5 gram altın biriktirdin.'), findsOneWidget);
    });

    testWidgets('bakiye gizliyken tutar görünmez', (tester) async {
      await pump(tester, gizli: true);
      expect(find.textContaining('bin ₺'), findsNothing);
      expect(find.text('Portföy eşiği geçildi'), findsOneWidget);
      expect(find.text('5 gram altın'), findsOneWidget);
      await tester.tap(find.text('Tümü ›'));
      await tester.pumpAndSettle();
      expect(find.textContaining('bin ₺'), findsNothing);
    });

    testWidgets('Dynamic Type 3.1×: taşma yok', (tester) async {
      await pump(tester, olcek: 3.1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('dokunma alanları ≥44 pt', (tester) async {
      await pump(tester);
      for (final t in ['5 gram altın', 'Tümü ›']) {
        final kutu = tester.getSize(find
            .ancestor(of: find.text(t), matching: find.byType(GestureDetector))
            .first);
        expect(kutu.height, greaterThanOrEqualTo(44), reason: t);
        expect(kutu.width, greaterThanOrEqualTo(44), reason: t);
      }
    });
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
