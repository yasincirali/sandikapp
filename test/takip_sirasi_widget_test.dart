import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SemanticsNode;
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/config/pref_keys.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/providers/auth_provider.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart';
import 'package:portfoy_takip/providers/watchlist_provider.dart';
import 'package:portfoy_takip/screens/watchlist_screen.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Takip listesi kendi sırasında durur (Ar-Ge 2026-10-24 12:45 #1, kabul
/// 13:15 #2): menüyle seçim, "Benim sıram"da sürükleme (44 pt tutamaç) ve
/// ekran okuyucu için "yukarı/aşağı taşı". Saf kurallar `takip_sirasi_test`.
class _Liste extends WatchlistNotifier {
  @override
  Future<List<WatchlistItem>> build() async => [
        // Sağlayıcının kendi sırası (değişime göre) burada bilerek karışık:
        // ilk açılış sırasını ekran değil saf fonksiyon kurar.
        _k('2', 'SISE', 'Şişe Cam', -2.0),
        _k('1', 'AKBNK', 'Akbank', 5.0),
        _k('3', 'THYAO', 'Türk Hava Yolları', 1.0),
      ];
}

WatchlistItem _k(String id, String ticker, String ad, double pct) =>
    WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ad,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: 10,
      periodChangePct: pct,
    );

Future<void> _pump(WidgetTester tester, {Map<String, Object>? onceki}) async {
  SharedPreferences.setMockInitialValues(onceki ?? {});
  await initPreferencesCache();
  tester.view.physicalSize = const Size(390 * 3, 2400 * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      watchlistProvider.overrideWith(_Liste.new),
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

/// Ekrandaki satır sırası (adların dikey konumuna göre).
List<String> _sira(WidgetTester tester) {
  const adlar = ['Akbank', 'Şişe Cam', 'Türk Hava Yolları'];
  final l = [...adlar]..sort((a, b) => tester
      .getTopLeft(find.text(a))
      .dy
      .compareTo(tester.getTopLeft(find.text(b)).dy));
  return l;
}

Future<List<String>?> _kayitliSira() async =>
    (await SharedPreferences.getInstance()).getStringList(PrefKeys.takipSirasi);

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  testWidgets('ilk açılış: bugünkü sıradan başlar ve o an kaydedilir',
      (tester) async {
    await _pump(tester);
    expect(_sira(tester), ['Akbank', 'Türk Hava Yolları', 'Şişe Cam']);
    expect(find.text('Benim sıram'), findsOneWidget);
    expect(await _kayitliSira(), ['1', '3', '2']);
  });

  testWidgets('kayıtlı sıra korunur, silinen düşer', (tester) async {
    await _pump(tester, onceki: {
      PrefKeys.takipSirasi: ['2', 'silinmis', '1', '3'],
    });
    expect(_sira(tester), ['Şişe Cam', 'Akbank', 'Türk Hava Yolları']);
    expect(await _kayitliSira(), ['2', '1', '3']);
  });

  testWidgets(
      'menüden "En çok düşen": sıra değişir, seçim kaydedilir, '
      'tutamaç yok', (tester) async {
    await _pump(tester);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(3));
    await tester.tap(find.text('Benim sıram'));
    await tester.pumpAndSettle();
    // Menü üç seçenek; seçili olan onay işaretli (yalnız renk değil).
    expect(find.text('En çok yükselen'), findsOneWidget);
    expect(find.text('En çok düşen'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    await tester.tap(find.text('En çok düşen'));
    await tester.pumpAndSettle();

    expect(_sira(tester), ['Şişe Cam', 'Türk Hava Yolları', 'Akbank']);
    expect(find.byIcon(Icons.drag_handle_rounded), findsNothing,
        reason: 'değişime göre sıralamada sürükleme anlamsız');
    expect(
        (await SharedPreferences.getInstance()).getInt(PrefKeys.takipSiralama),
        2);
    // Benim sıram kaybolmadı.
    expect(await _kayitliSira(), ['1', '3', '2']);
  });

  testWidgets('tutamaç 44 pt; sürükleyince sıra değişir ve kaydedilir',
      (tester) async {
    await _pump(tester);
    final tutamac = find.byIcon(Icons.drag_handle_rounded).first;
    final kutu = find.ancestor(of: tutamac, matching: find.byType(SizedBox));
    final boyut = tester.getSize(kutu.first);
    expect(boyut.width, greaterThanOrEqualTo(SandikTouch.min));
    expect(boyut.height, greaterThanOrEqualTo(SandikTouch.min));

    // Akbank'ı (ilk satır) en alta sürükle.
    final g = await tester.startGesture(tester.getCenter(tutamac));
    await tester.pump(const Duration(milliseconds: 50));
    for (var i = 0; i < 10; i++) {
      await g.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await g.up();
    await tester.pumpAndSettle();

    expect(_sira(tester), ['Türk Hava Yolları', 'Şişe Cam', 'Akbank']);
    expect(await _kayitliSira(), ['3', '2', '1']);
  });

  testWidgets('ekran okuyucu: "Aşağı taşı" / "Yukarı taşı" eylemleri',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester);

    SemanticsNode dugum(String ad) =>
        tester.getSemantics(find.bySemanticsLabel(RegExp('^$ad, ')));

    // İlk satırda yalnız aşağı, son satırda yalnız yukarı.
    expect(
        dugum('Akbank'),
        isSemantics(customActions: const [
          CustomSemanticsAction(label: 'Takipten çıkar'),
          CustomSemanticsAction(label: 'Aşağı taşı'),
        ]));
    expect(
        dugum('Şişe Cam'),
        isSemantics(customActions: const [
          CustomSemanticsAction(label: 'Takipten çıkar'),
          CustomSemanticsAction(label: 'Yukarı taşı'),
        ]));

    tester.semantics.customAction(find.semantics.byLabel(RegExp('^Akbank, ')),
        const CustomSemanticsAction(label: 'Aşağı taşı'));
    await tester.pumpAndSettle();
    expect(_sira(tester), ['Türk Hava Yolları', 'Akbank', 'Şişe Cam']);
    expect(await _kayitliSira(), ['3', '1', '2']);
    semantics.dispose();
  });
}
