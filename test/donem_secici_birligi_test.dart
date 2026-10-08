import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/varlik_sayfasi.dart'
    show varlikSayfasiDonemleri;
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_format.dart';
import 'package:portfoy_takip/widgets/donem_secici.dart';

import 'helpers/kaynak.dart';

/// Tüm dönem seçicileri AYNI küme ve AYNI bileşen (kullanıcı kararı
/// 2026-09-28: "Time interval seçimleri de aynı olmalı, data kaybı
/// olmasın"). Küme birleşimdir — hiçbir ekranın eski dönemi düşmez.
void main() {
  const ekranlar = {
    'Performans': 'lib/screens/portfolio_performance_screen.dart',
    'Takip': 'lib/screens/watchlist_screen.dart',
    'Karşılaştır': 'lib/screens/comparison_screen.dart',
    'Varlık detayı': 'lib/screens/asset_detail_screen.dart',
    'Varlık sayfası': 'lib/screens/varlik_sayfasi.dart',
  };

  for (final e in ekranlar.entries) {
    test('${e.key} ortak DonemSecici\'yi çizer', () {
      final k = ekranKaynagiSync(e.value);
      expect(k.contains('DonemSecici('), isTrue,
          reason: '${e.key} kendi seçicisini çiziyor.');
      // Elle yazılmış dönem dizisi geri gelmesin: etiket literali
      // yalnızca SummaryPeriod'da yaşar.
      expect(RegExp(r"label: '(1H|1A|3A|6A|1Y|5Y)'").hasMatch(k), isFalse,
          reason: '${e.key} kendi dönem listesini yazıyor.');
    });
  }

  test('küme eski beş listenin BİRLEŞİMİ — hiçbir dönem düşmedi', () {
    final etiketler = SummaryPeriod.values.map((p) => p.label).toSet();
    const eskiler = [
      ['GÜNLÜK', '1H', '1A', '6A', '1Y'], // Performans, Takip
      ['1H', '1A', '3A', '1Y', '5Y'], // Karşılaştır
      ['GÜNLÜK', '1H', '1A', '6A', '1Y', '5Y'], // detay, varlık sayfası
    ];
    for (final eski in eskiler) {
      expect(etiketler.containsAll(eski), isTrue, reason: '$eski');
    }
  });

  test('sembol yüzeyleri aynı sırada aynı günleri ister', () {
    expect(watchlistPeriods.map((p) => p.label).toList(),
        SummaryPeriod.values.map((p) => p.label).toList());
    expect(watchlistPeriods.map((p) => p.days).toList(),
        [1, 7, 30, 90, 180, 365, 1825]);
    expect(varlikSayfasiDonemleri, [1, 7, 30, 90, 180, 365, 1825]);
  });

  test('indeksle açılan rotalar sayı değil adla yazılır', () {
    final bugun = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
    expect(bugun, contains('SummaryPeriod.birYil.index'));
    expect(bugun, contains('SummaryPeriod.gunluk.index'));
    expect(ekranKaynagiSync('lib/services/notification_service.dart'),
        contains('SummaryPeriod.birAy.index'));
  });

  Future<void> kur(WidgetTester t, double genislik,
      {List<double?>? getiriler, double olcek = 1}) async {
    t.view.physicalSize = Size(genislik, 200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
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
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.md),
            child: DonemSecici(
              donemler: SummaryPeriod.values,
              secili: 5,
              getiriler: getiriler,
              onSec: (_) {},
            ),
          ),
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('320pt\'de yedi dönem taşmaz ve hepsi görünür', (t) async {
    await kur(t, 320);
    expect(t.takeException(), isNull);
    for (final p in ['Bugün', '1 hf', '1 ay', '3 ay', '6 ay', '1 yıl', '5 yıl']) {
      expect(find.text(p), findsOneWidget, reason: p);
    }
  });

  testWidgets('getiri satırı korunur (varlık ekranları)', (t) async {
    await kur(t, 390,
        getiriler: [0.4, -1.2, 3.5, null, 8.1, 21.3, 140.0], olcek: 2);
    expect(t.takeException(), isNull);
    for (final g in [21.3, -1.2, 140.0]) {
      expect(find.text(fmtPctIsaretli(g, digits: 1)), findsOneWidget,
          reason: '$g');
    }
  });
}
