import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Takip listesi satırlarındaki "Portföyüme ekle" (+) düğmesi her satırda
/// AYNI x'te durmalı (kullanıcı bildirimi, 2026-09-29).
///
/// Fiyat sütunu gevşek `Flexible` iken metin kadar daralıyor, + düğmesi
/// fiyatın hemen ardına yapışıyordu: ₺4.950.000,00 ile ₺38,46 satırlarında
/// düğme farklı yerlerdeydi. Uzunlukları çok farklı fiyatlarla ölçülür.
class _SabitListe extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => [
        _kalem('1', 'ISATR', 'İş Bankası (A)', 4950000, null),
        _kalem('2', 'SISE', 'Şişe Cam', 38.46, -2.93),
        _kalem('3', 'THYAO', 'Türk Hava Yolları', 292.75, -3.14),
        _kalem('4', 'XU100', 'BIST 100 Endeksi', 12439.14, -13.22),
      ];
}

WatchlistItem _kalem(
        String id, String ticker, String ad, double fiyat, double? pct) =>
    WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ad,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: fiyat,
      periodChangePct: pct,
    );

Future<void> _pump(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      watchlistProvider.overrideWith(_SabitListe.new),
      watchlistChartProvider.overrideWith((ref) async => const {}),
      activePartnersProvider.overrideWithValue(const []),
      watchlistLimitProvider.overrideWithValue(1 << 30),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: const Scaffold(body: WatchlistBody()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final w in <double>[320, 375, 430]) {
    testWidgets('${w.toInt()}pt — + düğmeleri aynı x\'te', (tester) async {
      await _pump(tester, w);
      final ikonlar = find.byIcon(Icons.add_circle_outline_rounded);
      expect(ikonlar, findsNWidgets(4));
      final xler = [
        for (var i = 0; i < 4; i++) tester.getCenter(ikonlar.at(i)).dx,
      ];
      for (final x in xler) {
        expect(x, moreOrLessEquals(xler.first, epsilon: 0.5),
            reason: 'x değerleri: $xler');
      }
      expect(tester.takeException(), isNull);
    });
  }
}
