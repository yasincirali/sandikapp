import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/temettu_tahmini_provider.dart';
import 'package:portfoy_takip/screens/temettu_tahmini_screen.dart';
import 'package:portfoy_takip/services/temettu_gecmisi.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/yazi_olcegi.dart';

/// Temettü tahmini kartının iki kişisel satırı (2026-11-13): "ayda
/// ortalama · maliyetine göre" ve "geçen 12 ayda aldın · tahmin".
TemettuOlayi _o(int y, int m, double pay) =>
    TemettuOlayi(hakTarihi: DateTime.utc(y, m, 15), tutarPay: pay);

TahminSatiri _satir(String ad, double brut, double? maliyet) => TahminSatiri(
      ad: ad,
      sembol: '$ad.IS',
      lot: 10,
      brutPay: brut / 10,
      brutTry: brut,
      netTry: brut * 0.85,
      aylar: const [6],
      maliyet: maliyet,
    );

// Net 8.500 + 1.700 = 10.200 → ayda 850. Verim yalnız maliyeti bilinen
// Tüpraş'tan: 8.500 / 100.000 = %8,5. Geçen yıl 6.000 → tahmin +%70.
final _tahmin = TemettuTahmini(
  satirlar: [_satir('Tüpraş', 10000, 100000), _satir('Ford', 2000, null)],
  aylik: [0, 0, 0, 0, 0, 12000, 0, 0, 0, 0, 0, 0],
  alinanNet: 6000,
);

void main() {
  final simdi = DateTime.utc(2026, 10, 10);

  group('hesap', () {
    test('ayda ortalama, kısmi maliyetle verim, kayıt toplamı', () {
      final t = temettuTahmini([
        TahminGirdisi(
            ad: 'A',
            sembol: 'A.IS',
            lot: 100,
            olaylar: [_o(2026, 5, 10), _o(2025, 11, 2)],
            maliyet: 20000,
            kaydedilenNet: 900),
        // Maliyeti bilinmeyen dağıtan: ne paya ne paydaya girer.
        TahminGirdisi(
            ad: 'B',
            sembol: 'B.IS',
            lot: 10,
            olaylar: [_o(2026, 3, 6)],
            kaydedilenNet: 40),
        // Yahoo'da olay yok ama defterde kayıt var: alınana girer.
        TahminGirdisi(
            ad: 'C',
            sembol: 'C.IS',
            lot: 5,
            olaylar: const [],
            maliyet: 500,
            kaydedilenNet: 60),
        // Lotu kalmamış: hiçbir yere girmez.
        TahminGirdisi(
            ad: 'D',
            sembol: 'D.IS',
            lot: 0,
            olaylar: [_o(2026, 3, 6)],
            maliyet: 999,
            kaydedilenNet: 999),
      ], stopaj: 0.15, simdi: simdi);
      // Net: A 1200×0,85=1020, B 60×0,85=51 → 1071.
      expect(t.netTry, closeTo(1071, 1e-9));
      expect(t.aylikOrtalama, closeTo(1071 / 12, 1e-9));
      expect(t.maliyeteGoreVerim, closeTo(1020 / 20000 * 100, 1e-9));
      expect(t.gecenYilAlinan, 1000);
      expect(t.tahminFarkiYuzde, closeTo(7.1, 1e-9));
    });

    test('hiçbir dağıtanın maliyeti bilinmiyorsa verim yok', () {
      final t = temettuTahmini([
        TahminGirdisi(
            ad: 'A',
            sembol: 'A.IS',
            lot: 10,
            olaylar: [_o(2026, 5, 10)],
            maliyet: 0),
        TahminGirdisi(
            ad: 'B', sembol: 'B.IS', lot: 10, olaylar: [_o(2026, 5, 10)]),
      ], stopaj: 0.15, simdi: simdi);
      expect(t.maliyeteGoreVerim, isNull);
      expect(t.aylikOrtalama, closeTo(170 / 12, 1e-9));
    });

    test('defterde 12 ayda kayıt yoksa kıyas yok', () {
      final t = temettuTahmini([
        TahminGirdisi(
            ad: 'A',
            sembol: 'A.IS',
            lot: 10,
            olaylar: [_o(2026, 5, 10)],
            maliyet: 1000),
      ], stopaj: 0.15, simdi: simdi);
      expect(t.alinanNet, 0);
      expect(t.gecenYilAlinan, isNull);
      expect(t.tahminFarkiYuzde, isNull);
    });

    test('stopaj bilinmiyorsa tutar kalır, yüzde kıyas yok; verim brütle', () {
      final t = temettuTahmini([
        TahminGirdisi(
            ad: 'A',
            sembol: 'A.IS',
            lot: 10,
            olaylar: [_o(2026, 5, 10)],
            maliyet: 1000,
            kaydedilenNet: 80),
      ], stopaj: null, simdi: simdi);
      expect(t.yillikBeklenen, 100);
      expect(t.maliyeteGoreVerim, closeTo(10, 1e-9));
      expect(t.gecenYilAlinan, 80);
      expect(t.tahminFarkiYuzde, isNull);
    });
  });

  Future<ProviderContainer> ac(WidgetTester tester,
      {bool gizli = false, double genislik = 390}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = Size(genislik, 900) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        premiumKilitliProvider.overrideWithValue(false),
        temettuTahminiProvider.overrideWith((ref) async => _tahmin),
      ],
      child: MaterialApp(
        locale: const Locale('tr'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
            brightness: Brightness.dark,
            extensions: const [SandikPalette.dark]),
        home: const TemettuTahminiScreen(),
      ),
    ));
    final c = ProviderScope.containerOf(
        tester.element(find.byType(TemettuTahminiScreen)));
    await c.read(balanceHiddenProvider.notifier).set(gizli);
    await tester.pumpAndSettle();
    return c;
  }

  group('ekran', () {
    testWidgets('iki satır görünür, ekran okuyucu tam cümle okur',
        (tester) async {
      final semantik = tester.ensureSemantics();
      await ac(tester);
      expect(find.text('Ayda ortalama ₺850 · maliyetine göre %8,5'),
          findsOneWidget);
      expect(find.text('Geçen 12 ayda ₺6.000 aldın · tahmin +%70'),
          findsOneWidget);
      // Kart tek düğüme birleşir; okunan cümleler "·" kısaltması değil.
      final okunan = tester.semantics
          .find(find.textContaining('Ayda ortalama'))
          .getSemanticsData()
          .label;
      expect(
          okunan,
          contains('Tahmin ayda ortalama ₺850 ediyor. Bu, temettü dağıtan '
              'hisselerinin maliyetinin yılda %8,5 kadarı.'));
      expect(
          okunan,
          contains('Geçen 12 ayda deftere kaydettiğin net temettü ₺6.000. '
              'Önümüzdeki 12 ayın tahmini buna göre +%70.'));
      expect(okunan, isNot(contains('Ayda ortalama ₺850 ·')));
      semantik.dispose();
    });

    testWidgets('bakiye gizliyken tutarlar maskeli, yüzdeler açık',
        (tester) async {
      await ac(tester, gizli: true);
      expect(find.text('Ayda ortalama ₺•••• · maliyetine göre %8,5'),
          findsOneWidget);
      expect(
          find.text('Geçen 12 ayda ₺•••• aldın · tahmin +%70'), findsOneWidget);
      expect(find.textContaining('₺850'), findsNothing);
      expect(find.textContaining('₺6.000'), findsNothing);
    });

    testWidgets(
        'bakiye gizliyken ekranda ve ekran okuyucuda hiçbir TL tutarı yok '
        '(büyük toplam, ay çubukları, satırlar)', (tester) async {
      await ac(tester, gizli: true);
      // Pay başı tutar bilerek açık (varlık sayfasındaki kural): lot
      // yazmadığı için portföy büyüklüğünü ele vermez. Onu çıkarınca geriye
      // rakamlı "₺" kalmamalı.
      final payBasi = RegExp(r'pay başına ₺[\d.,]+');
      final rakamliTl = RegExp(r'₺\s?\d');
      final metinler = [
        for (final w in tester.widgetList<Text>(find.byType(Text)))
          w.data ?? w.textSpan?.toPlainText() ?? '',
        for (final w in tester.widgetList<Semantics>(find.byType(Semantics)))
          w.properties.label ?? '',
      ];
      expect(metinler, isNotEmpty);
      for (final m in metinler) {
        expect(rakamliTl.hasMatch(m.replaceAll(payBasi, '')), isFalse,
            reason: 'gizliyken tutar açık: "$m"');
      }
      expect(find.text('₺••••'), findsWidgets);
      // Yüzdeler açık kalır.
      expect(find.textContaining('%8,5'), findsOneWidget);
    });

    yaziOlcegiEkseni(() {
      testWidgets('büyük yazıda ve dar ekranda taşma yok', (tester) async {
        yaziOlceginiUygula(tester);
        await ac(tester, genislik: 320);
        expect(find.textContaining('Ayda ortalama'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    });
  });
}
