import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

/// **Takip'e yeni eklenen satır açılarak girer, bir kez tonlanır
/// (Ar-Ge 12 Kas §4).**
///
/// Çıkış animasyonunun (`takip_cikis_animasyonu_test`) aynası. Kilitlenen
/// sözleşme: yeni satır 0 yükseklikten açılır ve zemini amber %8'den
/// sıfıra söner; eski satırlarda ne denetleyici ne ton var; ilk kurulumda
/// giriş yok; hareketi azaltta açılma anlık, ton yine görünür; ekran
/// okuyucuya "… listeye eklendi" duyurulur; görünen alanın dışına eklenen
/// satıra kaydırılır.
class _Liste extends WatchlistNotifier {
  _Liste(this.ilk);
  final List<WatchlistItem> ilk;

  @override
  Future<List<WatchlistItem>> build() async => ilk;

  void ekle(WatchlistItem w) =>
      state = AsyncData([...(state.valueOrNull ?? const []), w]);
}

WatchlistItem _kalem(String id, String ticker, String ad) => WatchlistItem(
      id: id,
      userId: 'u1',
      ticker: ticker,
      name: ad,
      type: AssetType.hisse,
      currency: 'TRY',
      addedAt: DateTime(2026, 9, 1),
      currentPrice: 38.46,
      periodChangePct: -2.93,
    );

final _ikiSatir = [
  _kalem('1', 'SISE.IS', 'Şişe Cam'),
  _kalem('2', 'XU100.IS', 'BIST 100 Endeksi'),
];

final _yeni = _kalem('99', 'THYAO.IS', 'Türk Hava Yolları');

Future<void> _pump(WidgetTester tester, _Liste liste,
    {bool hareketiAzalt = false, double yukseklik = 2400}) async {
  tester.view.physicalSize = Size(390 * 3, yukseklik * 3);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      watchlistProvider.overrideWith(() => liste),
      watchlistChartProvider.overrideWith((ref) async => const {}),
      activePartnersProvider.overrideWithValue(const []),
      watchlistLimitProvider.overrideWithValue(1 << 30),
    ],
    child: MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
        child: child!,
      ),
      home: const Scaffold(body: WatchlistBody()),
    ),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

/// Satırın `_TakipCikisi` sarmalı (giriş/çıkış animasyonunun sahibi).
Finder _sarmal(String ad) => find.ancestor(
      of: find.text(ad),
      matching: find.byWidgetPredicate(
          (w) => w.runtimeType.toString() == '_TakipCikisi'),
    );

/// Satırın açılma oranı (0 = kapalı, 1 = tam boy).
double _acilma(WidgetTester tester, String ad) => tester
    .widget<SizeTransition>(find
        .descendant(of: _sarmal(ad), matching: find.byType(SizeTransition))
        .first)
    .sizeFactor
    .value;

/// Zemin tonu boyacısı takılı satır sayısı.
int _tonluSatir(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((c) => c.painter.runtimeType.toString() == '_ZeminTonu')
    .length;

RenderObject _tonKatmani(WidgetTester tester, String ad) => tester.renderObject(
    find
        .descendant(
            of: _sarmal(ad),
            matching: find.byWidgetPredicate((w) =>
                w is CustomPaint &&
                w.painter.runtimeType.toString() == '_ZeminTonu'))
        .first);

Color get _amber => SandikPalette.dark.amberFill;

void main() {
  late List<String> duyurular;

  setUpAll(() => initializeDateFormatting('tr_TR'));
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    duyurular = [];
  });

  void duyurulariDinle(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
        SystemChannels.accessibility, (mesaj) async {
      final m = mesaj as Map<dynamic, dynamic>;
      if (m['type'] == 'announce') {
        duyurular.add((m['data'] as Map<dynamic, dynamic>)['message'] as String);
      }
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
            SystemChannels.accessibility, null));
  }

  testWidgets('ilk kurulumda giriş yok, ton yok', (tester) async {
    duyurulariDinle(tester);
    await _pump(tester, _Liste(_ikiSatir));
    expect(_acilma(tester, 'Şişe Cam'), 1);
    expect(_tonluSatir(tester), 0,
        reason: 'Açılışta var olan satırlar "yeni" değil.');
    expect(duyurular, isEmpty);
  });

  testWidgets('yeni satır açılarak girer, ton söner; eski satırlar kımıldamaz',
      (tester) async {
    duyurulariDinle(tester);
    final liste = _Liste(_ikiSatir);
    await _pump(tester, liste);

    liste.ekle(_yeni);
    await tester.pump(); // yeni satır kuruldu, 0 boyda
    expect(_acilma(tester, 'Türk Hava Yolları'), 0,
        reason: 'Yeni satır ilk karede tam boy belirdi (açılma yok).');
    await tester.pump(); // kareden sonra giriş başlar
    await tester.pump(SandikMotion.state ~/ 2);
    final ara = _acilma(tester, 'Türk Hava Yolları');
    expect(ara, greaterThan(0));
    expect(ara, lessThan(1));
    expect(_acilma(tester, 'Şişe Cam'), 1);
    expect(_acilma(tester, 'BIST 100 Endeksi'), 1);
    expect(_tonluSatir(tester), 1,
        reason: 'Ton (ve denetleyici) yalnız yeni satırda.');
    expect(_tonKatmani(tester, 'Türk Hava Yolları'),
        paints..rrect(color: _amber.withValues(alpha: 0.08 * 1)),
        reason: 'Ton amber ~%8 ile başlamalı.');
    expect(duyurular, ['Türk Hava Yolları listeye eklendi']);

    await tester.pump(SandikMotion.state);
    expect(_acilma(tester, 'Türk Hava Yolları'), 1);
    await tester.pump(SandikMotion.flow * 2);
    expect(
        _tonKatmani(tester, 'Türk Hava Yolları'),
        isNot(paints
          ..rrect(
              color: _amber.withValues(alpha: 0.08 * 1)))
        ,
        reason: 'Ton sönmeli.');
    // Sonraki yeniden kurulumda giriş tekrar oynamaz, duyuru tekrarlanmaz.
    liste.ekle(_kalem('100', 'ASELS.IS', 'Aselsan'));
    await tester.pump();
    await tester.pump(SandikMotion.flow * 3);
    expect(_acilma(tester, 'Türk Hava Yolları'), 1);
    expect(duyurular,
        ['Türk Hava Yolları listeye eklendi', 'Aselsan listeye eklendi']);
  });

  testWidgets('hareketi azalt: açılma anlık, ton yine görünür', (tester) async {
    duyurulariDinle(tester);
    final liste = _Liste(_ikiSatir);
    await _pump(tester, liste, hareketiAzalt: true);

    liste.ekle(_yeni);
    await tester.pump();
    await tester.pump();
    await tester.pump();
    expect(_acilma(tester, 'Türk Hava Yolları'), 1,
        reason: 'Hareketi azalt açıkken satır yükseklikle açılmamalı.');
    expect(_tonKatmani(tester, 'Türk Hava Yolları'),
        paints..rrect(color: _amber.withValues(alpha: 0.08 * 1)),
        reason: 'Ton hareket değil renk: hareketi azaltta da görünür.');
    expect(duyurular, ['Türk Hava Yolları listeye eklendi']);
    await tester.pump(SandikMotion.flow);
    await tester.pump(SandikMotion.state);
    expect(_tonKatmani(tester, 'Türk Hava Yolları'),
        isNot(paints..rrect(color: _amber.withValues(alpha: 0.08 * 1))));
  });

  testWidgets('görünen alanın dışına eklenen satıra kaydırılır',
      (tester) async {
    final uzun = [
      for (var i = 0; i < 30; i++) _kalem('$i', 'S$i.IS', 'Sembol $i'),
    ];
    final liste = _Liste(uzun);
    await _pump(tester, liste, yukseklik: 800);
    expect(find.text('Türk Hava Yolları'), findsNothing);

    liste.ekle(_yeni);
    await tester.pump();
    // Liste önce kabaca sona kayar (satır henüz kurulmamış), satır
    // kurulunca kendisi görünür alana getirir ve açılır.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final satir = find.text('Türk Hava Yolları');
    expect(satir, findsOneWidget);
    final ekran = tester.view.physicalSize / tester.view.devicePixelRatio;
    final r = tester.getRect(satir);
    expect(r.top, greaterThanOrEqualTo(0));
    expect(r.bottom, lessThanOrEqualTo(ekran.height),
        reason: 'Yeni satır görünen alana getirilmeli.');
    expect(_acilma(tester, 'Türk Hava Yolları'), 1);
  });

  testWidgets('liste baştan değişince (hesap/demo geçişi) giriş yok',
      (tester) async {
    duyurulariDinle(tester);
    final liste = _Liste(_ikiSatir);
    await _pump(tester, liste);
    liste.state = AsyncData([_yeni, _kalem('98', 'ASELS.IS', 'Aselsan')]);
    await tester.pump();
    await tester.pump();
    expect(_acilma(tester, 'Türk Hava Yolları'), 1);
    expect(_tonluSatir(tester), 0);
    expect(duyurular, isEmpty);
  });
}
