import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/para_akisi_karti.dart' show KilitSatiri;
import 'package:portfoy_takip/widgets/period_summary_view.dart';

/// "Dönemin en iyi ve en zor günü" (Premium, 2026-11-11).
///
/// Kovalanan hatalar:
///  1. Alım yapılan gün "en iyi gün" sanılması — günlük getiri akıştan
///     arındırılmalı (`InsightMetricsService.annualizedVolatility` kuralı).
///  2. Boşluktan sonraki gün (birden çok günün hareketi) tek gün sayılması.
///  3. Kapanmamış bugünün ve kısa dönemin sayı üretmesi.
///  4. Ekranda yalnız renkle anlatım, kilitliyken sayının sızması, 3.1×
///     yazı boyutunda taşma.

Asset _alim(DateTime added, {double qty = 5, double fiyat = 100}) => Asset(
      id: 'a${added.millisecondsSinceEpoch}',
      userId: 'u',
      name: 'THYAO',
      ticker: 'THYAO',
      type: AssetType.hisse,
      quantity: qty,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: added,
    );

/// Gün kapanış serisi: her gün 18:00 damgası, değer bir önceki × çarpan
/// (+ o günün alımı). İlk gün 1000.
Map<int, double> _seri(List<(DateTime, double)> gunler,
    {Map<DateTime, double> alim = const {}}) {
  final out = <int, double>{};
  var v = 1000.0;
  for (var i = 0; i < gunler.length; i++) {
    final (g, carpan) = gunler[i];
    if (i > 0) v = v * carpan;
    v += alim[g] ?? 0;
    out[DateTime(g.year, g.month, g.day, 18).millisecondsSinceEpoch] = v;
  }
  return out;
}

/// Hafta içi günler (Cts/Paz yok — saatlik ızgara gibi).
List<DateTime> _haftaIci(DateTime bas, DateTime bit) => [
      for (var d = bas;
          !d.isAfter(bit);
          d = DateTime(d.year, d.month, d.day + 1))
        if (d.weekday != DateTime.saturday && d.weekday != DateTime.sunday) d,
    ];

final _bugun = DateTime(2026, 11, 11, 12);
final _from = DateTime(2026, 10, 1).millisecondsSinceEpoch;
final _to = _bugun.millisecondsSinceEpoch;

({DonemGunu enIyi, DonemGunu? enZor})? _hesap(Map<int, double> seri,
        {List<Asset> lotlar = const []}) =>
    PeriodSummaryService.enIyiEnZorGun(seri,
        lotlar: lotlar, fromMs: _from, toMs: _to, bugun: _bugun);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('enIyiEnZorGun — saf hesap', () {
    test('alım günü arındırılır: değer zıplaması en iyi gün sayılmaz', () {
      final g = _haftaIci(DateTime(2026, 11, 2), DateTime(2026, 11, 10));
      // 2 Kas taban, 3 +%1, 4 +%0,5 ve ₺500 alım, 5 +%2, 6 −%1,
      // 9 +%3 (en iyi), 10 −%2 (en zor).
      const carpan = [1.0, 1.01, 1.005, 1.02, 0.99, 1.03, 0.98];
      final alimGunu = DateTime(2026, 11, 4);
      final seri = _seri([for (var i = 0; i < g.length; i++) (g[i], carpan[i])],
          alim: {alimGunu: 500});
      final r = _hesap(seri, lotlar: [_alim(DateTime(2026, 11, 4, 10))])!;
      expect(r.enIyi.gun, DateTime(2026, 11, 9));
      expect(r.enIyi.pct, closeTo(3, 1e-9));
      expect(r.enZor!.gun, DateTime(2026, 11, 10));
      expect(r.enZor!.pct, closeTo(-2, 1e-9));

      // Kontrol: akış verilmezse alım günü ~+%50 "en iyi gün" olurdu.
      expect(_hesap(seri)!.enIyi.gun, alimGunu);
    });

    test('boşluktan sonraki gün (eksik iş günü) aday değildir', () {
      final g = _haftaIci(DateTime(2026, 10, 26), DateTime(2026, 11, 10))
        ..remove(DateTime(2026, 11, 5)); // Perşembe eksik
      final seri = _seri([
        for (final d in g)
          (
            d,
            d == DateTime(2026, 11, 6)
                ? 1.10 // iki günün hareketi — tek gün sayılmamalı
                : d == DateTime(2026, 10, 28)
                    ? 1.02
                    : d == DateTime(2026, 10, 29)
                        ? 0.97
                        : 1.001,
          ),
      ]);
      final r = _hesap(seri)!;
      expect(r.enIyi.gun, DateTime(2026, 10, 28));
      expect(r.enZor!.gun, DateTime(2026, 10, 29));
    });

    test('Cuma → Pazartesi ardışıktır; hafta sonu düz noktaları aday değil',
        () {
      // Günlük ızgara gibi Cts/Paz da var ama değer taşınmış (çarpan 1).
      final g = [
        for (var d = DateTime(2026, 10, 26);
            !d.isAfter(DateTime(2026, 11, 10));
            d = DateTime(d.year, d.month, d.day + 1))
          d,
      ];
      final seri = _seri([
        for (final d in g)
          (
            d,
            (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday)
                ? 1.0
                : d == DateTime(2026, 11, 2)
                    ? 1.04 // Pazartesi, önceki nokta Pazar (düz)
                    : 1.002,
          ),
      ]);
      final r = _hesap(seri)!;
      expect(r.enIyi.gun, DateTime(2026, 11, 2));
      // Hepsi artı: en zor gün de artıda (ekran "en az yükselen" yazar),
      // ama asla düz bir hafta sonu günü değil.
      expect(r.enZor!.pct, greaterThan(0));
      expect(r.enZor!.gun.weekday, lessThan(DateTime.saturday));
    });

    test('bugün (kapanmamış gün) ölçülmez', () {
      final g = _haftaIci(DateTime(2026, 11, 2), DateTime(2026, 11, 11));
      final seri = _seri([
        for (final d in g)
          (
            d,
            d == DateTime(2026, 11, 11) ? 1.10 : (d.day.isEven ? 1.01 : 0.995)
          ),
      ]);
      final r = _hesap(seri)!;
      expect(r.enIyi.gun, isNot(DateTime(2026, 11, 11)));
      expect(r.enIyi.pct, closeTo(1, 1e-9));
    });

    test('beşten az ölçülen gün → null; ilk gün ölçülmez', () {
      // 5 nokta = 4 günlük getiri (ilk günün öncesi yok).
      final g = _haftaIci(DateTime(2026, 11, 2), DateTime(2026, 11, 6));
      final seri = _seri([for (final d in g) (d, 1.01)]);
      expect(_hesap(seri), isNull);
      expect(_hesap(const {}), isNull);
    });

    test('hiç artı gün yoksa en iyi gün eksidir (işaret korunur)', () {
      final g = _haftaIci(DateTime(2026, 11, 2), DateTime(2026, 11, 10));
      const carpan = [1.0, 0.99, 0.995, 0.98, 0.999, 0.97, 0.99];
      final seri =
          _seri([for (var i = 0; i < g.length; i++) (g[i], carpan[i])]);
      final r = _hesap(seri)!;
      expect(r.enIyi.pct, closeTo(-0.1, 1e-9));
      expect(r.enZor!.pct, closeTo(-3, 1e-9));
    });

    test('compute alanı doldurur (1A, günlük seri)', () {
      final g = _haftaIci(DateTime(2026, 10, 13), DateTime(2026, 11, 10));
      final seri = _seri([
        for (final d in g) (d, d == DateTime(2026, 11, 4) ? 1.03 : 1.001),
      ]);
      final lot = _alim(DateTime(2026, 10, 1), qty: 10);
      final s = PeriodSummaryService.compute(
        period: SummaryPeriod.birAy,
        assets: [lot],
        breakdown: PortfolioHistoryBreakdown(
          total: seri,
          byType: const {},
          byPosition: const {},
          positionType: const {},
        ),
        now: _bugun,
      );
      expect(s.enIyiEnZorGun?.enIyi.gun, DateTime(2026, 11, 4));
    });
  });

  group('PeriodSummaryView — en iyi / en zor gün kartı', () {
    final varsayilan = (
      enIyi: DonemGunu(DateTime(2026, 11, 4), 3.2),
      enZor: DonemGunu(DateTime(2026, 10, 23), -2.1),
    );
    PeriodSummary ozet(({DonemGunu enIyi, DonemGunu? enZor}) g) =>
        PeriodSummary(
          period: SummaryPeriod.birAy,
          start: DateTime(2026, 10, 11),
          end: _bugun,
          baslangicTRY: 100000,
          sonTRY: 103000,
          katkiTRY: 0,
          piyasaTRY: 3000,
          getiriPct: 3,
          enIyiEnZorGun: g,
        );

    Future<void> kur(WidgetTester tester,
        {required bool gorunur,
        bool kilitli = false,
        double olcek = 1,
        double genislik = 390,
        ({DonemGunu enIyi, DonemGunu? enZor})? gunler}) async {
      tester.view.physicalSize = Size(genislik, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
            brightness: Brightness.light, extensions: [SandikPalette.light]),
        home: MediaQuery(
          data: MediaQueryData(
              size: Size(genislik, 2400), textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: PeriodSummaryView(
                summary: ozet(gunler ?? varsayilan),
                simdi: _bugun,
                // Tek akış (Performans'ın bugünkü düzeni): ana rakam kartı
                // grafiğin kartında. Ana rakam kartının kendi 3.1× davranışı
                // bu testin konusu değil.
                anaRakamGizli: true,
                enIyiGunGorunur: gorunur,
                enIyiGunKilitli: kilitli,
              ),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('Premium: iki satır — metin + işaret + renk', (tester) async {
      await kur(tester, gorunur: true);
      expect(find.text('Dönemin en iyi ve en zor günü'), findsOneWidget);
      expect(find.text('En iyi gün · 4 Kasım'), findsOneWidget);
      expect(find.text('En zor gün · 23 Ekim'), findsOneWidget);
      expect(find.text('+%3,2'), findsOneWidget);
      expect(find.text('−%2,1'), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('ücretsiz: yalnız en iyi günün tarihi açık, yüzde sızmaz',
        (tester) async {
      await kur(tester, gorunur: true, kilitli: true);
      expect(find.byType(KilitSatiri), findsOneWidget);
      expect(find.text("En iyi günün 4 Kasım · ne kadar olduğu Premium'da"),
          findsOneWidget);
      // En zor gün ve hiçbir yüzde açılmaz.
      expect(find.textContaining('23 Ekim'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      final kilit = tester.widget<KilitSatiri>(find.byType(KilitSatiri));
      expect(kilit.kaynak, 'en_iyi_gun');
    });

    testWidgets('ücretsiz, hiç artı gün yok: "en az düşen gün" (kutlama yok)',
        (tester) async {
      await kur(tester,
          gorunur: true,
          kilitli: true,
          gunler: (
            enIyi: DonemGunu(DateTime(2026, 11, 4), -0.3),
            enZor: DonemGunu(DateTime(2026, 10, 23), -2.1),
          ));
      expect(
          find.text("En az düşen günün 4 Kasım · ne kadar olduğu Premium'da"),
          findsOneWidget);
      expect(find.textContaining('En iyi'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('görünür değilse (paywall kapalı) kart hiç yok',
        (tester) async {
      await kur(tester, gorunur: false);
      expect(find.text('Dönemin en iyi ve en zor günü'), findsNothing);
      expect(find.byType(KilitSatiri), findsNothing);
    });

    testWidgets('3.1× yazı boyutunda 320pt\'de taşma yok', (tester) async {
      await kur(tester, gorunur: true, olcek: 3.1, genislik: 320);
      expect(tester.takeException(), isNull);
      expect(find.text('En iyi gün · 4 Kasım'), findsOneWidget);
    });

    testWidgets('3.1× kilitli satır da taşmaz', (tester) async {
      await kur(tester,
          gorunur: true, kilitli: true, olcek: 3.1, genislik: 320);
      expect(tester.takeException(), isNull);
    });
  });
}
