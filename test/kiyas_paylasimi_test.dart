import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/screens/comparison_screen.dart';
import 'package:portfoy_takip/services/history_service.dart'
    show NormalizedSeries, normalizeSeries;
import 'package:portfoy_takip/services/kiyas_paylasimi.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:portfoy_takip/widgets/share_card.dart' show KiyasPaylasKarti;

/// Karşılaştır › "Kıyası paylaş" (Ar-Ge 7 Kas 04:03, YAP 1).
///
/// Kilitlenen sözleşme: kart yalnız YÜZDE taşır (tutar yok), ortak
/// portföyü dışarı çıkmaz, tek varlık kıyas sayılmaz, eksik seri `0`
/// uydurmaz; app bar'da 44 pt, etiketli paylaş düğmesi var ve veri
/// yokken kapalı.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  const thy = SymbolHit(ticker: 'THYAO.IS', name: 'THY', source: 'BIST');
  const altin = SymbolHit(ticker: 'ALTIN', name: 'Gram altın', source: 'Altın');
  const benim = SymbolHit(
      ticker: PortfolioSeries.mine, name: 'Portföyüm', source: 'Portföy');
  const ortak = SymbolHit(
      ticker: '${PortfolioSeries.partnerPrefix}abc',
      name: 'Ayşe · tüm portföyü',
      source: 'Portföy');

  NormalizedSeries seri(double bas, double son,
          {int t0 = 1000, int t1 = 2000}) =>
      normalizeSeries({t0: bas, t1: son})!;

  String etiket(SymbolHit h) => h.ticker;

  group('kiyasPaylasimiKur', () {
    test('getiriye göre sıralar, tarih penceresi uçlardan', () {
      final k = kiyasPaylasimiKur(
        secili: const [altin, thy],
        seriler: {
          'ALTIN': seri(100, 104, t0: 500),
          'THYAO.IS': seri(10, 11.5, t1: 3000),
        },
        etiket: etiket,
      )!;
      expect(k.satirlar.map((s) => s.ad), ['THYAO.IS', 'ALTIN']);
      expect(k.satirlar.first.pct, closeTo(15, 1e-9));
      expect(k.baslangic.millisecondsSinceEpoch, 500);
      expect(k.bitis.millisecondsSinceEpoch, 3000);
    });

    test('özet satırı yüzde, tutar yok', () {
      final k = kiyasPaylasimiKur(
        secili: const [benim, thy],
        seriler: {
          // Portföy serisinin ham değeri TUTAR'dır; metne girmemeli.
          PortfolioSeries.mine: seri(250000, 240000),
          'THYAO.IS': seri(10, 11.23),
        },
        etiket: etiket,
      )!;
      expect(k.ozetSatiri, 'THYAO.IS +%12,3 · ${PortfolioSeries.mine} −%4,0');
      expect(k.ozetSatiri, isNot(contains('250')));
      expect(k.ozetSatiri, isNot(contains('240')));
    });

    test('ortak portföyü atlanır; geriye tek satır kalırsa null', () {
      expect(
        kiyasPaylasimiKur(
          secili: const [thy, ortak],
          seriler: {
            'THYAO.IS': seri(10, 11),
            ortak.ticker: seri(100, 120),
          },
          etiket: etiket,
        ),
        isNull,
      );
    });

    test('serisi gelmemiş sembol atlanır, 0 uydurulmaz', () {
      expect(
        kiyasPaylasimiKur(
          secili: const [thy, altin],
          seriler: {'THYAO.IS': seri(10, 11)},
          etiket: etiket,
        ),
        isNull,
      );
      final k = kiyasPaylasimiKur(
        secili: const [thy, altin, benim],
        seriler: {'THYAO.IS': seri(10, 11), 'ALTIN': seri(100, 90)},
        etiket: etiket,
      )!;
      expect(k.satirlar, hasLength(2));
    });

    test('boş seçim null', () {
      expect(
        kiyasPaylasimiKur(secili: const [], seriler: const {}, etiket: etiket),
        isNull,
      );
    });
  });

  testWidgets('kart: başlık, aralık ve işaretli yüzdeler; taşma yok',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: KiyasPaylasKarti(
            baslik: '3 ay kıyası',
            tarihAraligi: '7 Ağu 2026 - 7 Kas 2026',
            satirlar: [
              (ad: 'THYAO.IS', pct: 12.34),
              (ad: 'Portföyüm', pct: -4),
            ],
          ),
        ),
      ),
    ));
    expect(find.text('3 ay kıyası'), findsOneWidget);
    expect(find.text('7 Ağu 2026 - 7 Kas 2026'), findsOneWidget);
    expect(find.text('+%12,3'), findsOneWidget);
    expect(find.text('−%4,0'), findsOneWidget);
    expect(find.text('sandık ile kıyasladım'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Karşılaştır app bar: etiketli, 44 pt, veri yokken kapalı',
      (tester) async {
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: ComparisonScreen())));
    await tester.pump();

    final dugme = find.byTooltip('Kıyası paylaş');
    expect(dugme, findsOneWidget);
    final boyut = tester.getSize(
        find.ancestor(of: dugme, matching: find.byType(IconButton)).first);
    expect(boyut.width, greaterThanOrEqualTo(44));
    expect(boyut.height, greaterThanOrEqualTo(44));
    final ib = tester.widget<IconButton>(
        find.ancestor(of: dugme, matching: find.byType(IconButton)).first);
    expect(ib.onPressed, isNull, reason: 'kıyasta veri yokken paylaşılamaz');
  });
}
