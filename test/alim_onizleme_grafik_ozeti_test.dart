// Hızlı Al ortalama maliyet önizlemesi, fon satışı stopaj notu ve grafiğin
// ekran okuyucu özeti (Ar-Ge 6 Kas 22:30).
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/utils/grafik_ozeti.dart';
import 'package:portfoy_takip/widgets/quick_adjust_dialog.dart';
import 'package:portfoy_takip/widgets/zoomable_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _BosPortfoy extends PortfolioNotifier {
  @override
  Future<PortfolioState> build() async => const PortfolioState();
}

Asset _varlik({
  AssetType tur = AssetType.hisse,
  double adet = 500,
  double maliyet = 100,
  double fiyat = 108.4,
}) =>
    Asset(
      id: 'h1',
      userId: 'u',
      name: 'Deneme',
      ticker: 'DENEM',
      type: tur,
      quantity: adet,
      purchasePrice: maliyet,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: DateTime(2026, 1, 1),
    );

Future<void> _ac(WidgetTester tester, Asset a, QuickAdjustMode mod) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [portfolioProvider.overrideWith(_BosPortfoy.new)],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => TextButton(
            onPressed: () =>
                showQuickAdjustDialog(context, ref, asset: a, mode: mod),
            child: const Text('ac'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('ac'));
  await tester.pumpAndSettle();
}

const _ortalama = ValueKey('alim_ortalama_onizleme');
const _stopaj = ValueKey('satis_fon_stopaj_notu');

void main() {
  final tr = lookupAppLocalizations(const Locale('tr'));

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    SharedPreferences.setMockInitialValues({});
    await initPreferencesCache();
  });

  group('yeniOrtalamaMaliyet', () {
    test('ağırlıklı ortalama', () {
      expect(
          yeniOrtalamaMaliyet(
              eskiAdet: 10, eskiMaliyet: 100, yeniAdet: 10, fiyat: 80),
          90);
      expect(
          yeniOrtalamaMaliyet(
              eskiAdet: 3, eskiMaliyet: 50, yeniAdet: 1, fiyat: 70),
          55);
    });

    test('boş/0 miktar, fiyat, eldeki adet ya da maliyet → null', () {
      double? f(
              {double eA = 10,
              double? eM = 100,
              double? yA = 1,
              double? p = 5}) =>
          yeniOrtalamaMaliyet(
              eskiAdet: eA, eskiMaliyet: eM, yeniAdet: yA, fiyat: p);
      expect(f(yA: null), isNull);
      expect(f(yA: 0), isNull);
      expect(f(p: null), isNull);
      expect(f(p: 0), isNull);
      expect(f(eA: 0), isNull, reason: 'Yeni pozisyonda "şimdi" anlamsız.');
      expect(f(eM: 0), isNull);
      expect(f(eM: null), isNull);
    });
  });

  group('Hızlı Al sayfası', () {
    testWidgets('miktar ve fiyat yazılınca renksiz ortalama satırı',
        (tester) async {
      await _ac(tester, _varlik(), QuickAdjustMode.add);
      expect(find.byKey(_ortalama), findsNothing);
      // Küçük fiyat: Ahem fontunda uzun "Toplam maliyet" tutarı taşmasın.
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(_ortalama)).data,
          'Yeni ortalama maliyetin ₺99,80 (şimdi ₺100,00)');
    });

    testWidgets('elde olmayan varlıkta (yeni pozisyon) satır yok',
        (tester) async {
      await _ac(tester, _varlik(adet: 0), QuickAdjustMode.add);
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump();
      expect(find.byKey(_ortalama), findsNothing);
    });

    testWidgets('satışta ortalama satırı yok', (tester) async {
      await _ac(tester, _varlik(), QuickAdjustMode.remove);
      await tester.enterText(find.byType(TextField).first, '1');
      await tester.pump();
      expect(find.byKey(_ortalama), findsNothing);
    });
  });

  group('fon satışı stopaj notu', () {
    testWidgets('fonda kâr satırının altında', (tester) async {
      await _ac(tester, _varlik(tur: AssetType.fon), QuickAdjustMode.remove);
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.pump();
      expect(find.byKey(const ValueKey('satis_kar_onizleme')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(_stopaj)).data,
          'Brüt tutar; fon stopajı kârdan kesilebilir.');
    });

    testWidgets('hissede not yok', (tester) async {
      await _ac(tester, _varlik(), QuickAdjustMode.remove);
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.pump();
      expect(find.byKey(_stopaj), findsNothing);
    });
  });

  group('grafik özeti', () {
    const spots = [
      FlSpot(0, 100),
      FlSpot(1, 90),
      FlSpot(2, 120),
      FlSpot(3, 104.2),
    ];

    test('görünen pencere: yüzde, en düşük, en yüksek', () {
      final o = gorunenAralikOzeti(spots, 0, 3)!;
      expect(o.degisimYuzde, closeTo(4.2, 1e-9));
      expect(o.enDusuk, 90);
      expect(o.enYuksek, 120);
      expect(grafikOzetMetni(tr, o, tutar: (v) => '₺${v.round()}'),
          'Görünen aralıkta yüzde 4,2 arttı; en düşük ₺90, en yüksek ₺120');
    });

    test('pencere daralınca özet pencereden çıkar', () {
      final o = gorunenAralikOzeti(spots, 1.5, 3)!;
      expect(o.degisimYuzde, closeTo(-13.1667, 1e-3));
      expect(grafikOzetMetni(tr, o), 'Görünen aralıkta yüzde 13,2 azaldı');
    });

    test('tutar yok (bakiye gizli) → yalnız yüzde; tek nokta → null', () {
      expect(grafikOzetMetni(tr, gorunenAralikOzeti(spots, 0, 3)),
          'Görünen aralıkta yüzde 4,2 arttı');
      expect(gorunenAralikOzeti(spots, 2.5, 3), isNull);
      expect(grafikOzetMetni(tr, null), isNull);
    });

    test('değişmeyen ve sıfırdan başlayan seri', () {
      final duz =
          gorunenAralikOzeti(const [FlSpot(0, 50), FlSpot(1, 50.01)], 0, 1);
      expect(grafikOzetMetni(tr, duz), 'Görünen aralıkta değişmedi');
      final sifir =
          gorunenAralikOzeti(const [FlSpot(0, 0), FlSpot(1, 10)], 0, 1)!;
      expect(sifir.degisimYuzde, isNull);
      expect(grafikOzetMetni(tr, sifir), isNull);
    });

    test('karşılaştırma: seri başına, 0 tabanlı yüzde', () {
      // Dönem başı %0 → %10: görünen pencerede %10 artış; %10 → %−1:
      // 110'dan 99'a, %10 azalış.
      expect(
          karsilastirmaOzeti(
              tr,
              [
                ('BIST', const [FlSpot(0, 0), FlSpot(1, 10)]),
                ('Altın', const [FlSpot(0, 10), FlSpot(1, -1)]),
              ],
              0,
              1),
          'BIST: Görünen aralıkta yüzde 10,0 arttı; '
          'Altın: Görünen aralıkta yüzde 10,0 azaldı');
    });

    testWidgets('ZoomableChart özeti semantik değere yazar', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ZoomableChart(
            semanticLabel: 'Deneme fiyat grafiği',
            fullMinX: 0,
            fullMaxX: 3,
            height: 200,
            builder: (a, b) => LineChartData(
              minX: a,
              maxX: b,
              lineBarsData: [LineChartBarData(spots: spots)],
            ),
            semanticValueBuilder: (a, b) =>
                grafikOzetMetni(tr, gorunenAralikOzeti(spots, a, b)),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(
        find.semantics.byPredicate((n) =>
            n.label.startsWith('Deneme fiyat grafiği') &&
            n.value == 'Görünen aralıkta yüzde 4,2 arttı'),
        findsOneWidget,
      );
      handle.dispose();
    });
  });
}
