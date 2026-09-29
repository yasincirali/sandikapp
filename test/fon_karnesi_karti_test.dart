import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/fon_karnesi_provider.dart';
import 'package:portfoy_takip/services/tefas_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/fon_karnesi_karti.dart';

import 'helpers/kaynak.dart';

/// Fon karnesi kartı ve portföy panel satırı (F4). Katalog ve bayrak
/// provider override'larıyla verilir — testte ağ yok.
const _hisse = 'Hisse Senedi Şemsiye Fonu';

TefasFund _fon(String kod, double? yil1, {double? ay1, double? yb}) =>
    TefasFund(
      code: kod,
      name: '$kod Fonu',
      price: 0,
      fundType: 'YAT',
      managerName: '',
      return1m: ay1,
      return1y: yil1,
      returnYtd: yb,
      kategori: _hisse,
    );

final _katalog = [
  _fon('AAA', 50, ay1: 1, yb: 20),
  _fon('BBB', 40, ay1: 3, yb: 10),
  _fon('CCC', 30, ay1: 2, yb: 30),
  _fon('DDD', 10, ay1: 4, yb: 5),
];

Future<void> _kur(
  WidgetTester t,
  Widget child, {
  bool acik = true,
  List<TefasFund>? katalog,
  double genislik = 390,
  double olcek = 1,
}) async {
  t.view.physicalSize = Size(genislik, 1200);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(ProviderScope(
    overrides: [
      fonKarnesiAcikProvider.overrideWithValue(acik),
      fonKatalogProvider.overrideWith((ref) async => katalog ?? _katalog),
    ],
    child: MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('tr'),
      home: MediaQuery(
        data: MediaQueryData(
            size: Size(genislik, 1200), textScaler: TextScaler.linear(olcek)),
        child: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SandikSpace.smd),
            child: child,
          ),
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  const kart = FonKarnesiKarti(tur: AssetType.fon, ticker: 'TEFAS:CCC');

  testWidgets('kart: kategori, sıra, ortanca ve puan farkı', (t) async {
    await _kur(t, kart);
    expect(find.byType(SandikCard), findsOneWidget);
    expect(find.text('FON KARNESİ'), findsOneWidget);
    expect(find.text('$_hisse · 4 fon'), findsOneWidget);
    expect(find.text('1 yıl'), findsOneWidget);
    expect(find.text('Yılbaşından beri'), findsOneWidget);
    expect(find.text('1 ay'), findsOneWidget);
    // 1 yıl: CCC %30 → 3.; ortanca (30+40)/2 = 35 → 5 puan altında.
    expect(find.text('4 fondan 3.'), findsNWidgets(2)); // 1 yıl ve 1 ay
    expect(find.text('4 fondan 1.'), findsOneWidget); // yılbaşı %30
    expect(find.text('Getirisi %30,00 · kategori ortancası %35,00'),
        findsOneWidget);
    expect(find.text('Ortancanın 5,0 puan altında'), findsOneWidget);
    expect(find.text('Ortancanın 15,0 puan üstünde'), findsOneWidget);
  });

  testWidgets('bayrak kapalıyken hiçbir şey çizilmez', (t) async {
    await _kur(t, kart, acik: false);
    expect(find.byType(SandikCard), findsNothing);
    expect(find.text('FON KARNESİ'), findsNothing);
  });

  testWidgets('fon değilse ya da karne kurulamıyorsa çizilmez', (t) async {
    await _kur(t, const FonKarnesiKarti(tur: AssetType.hisse, ticker: 'CCC'));
    expect(find.byType(SandikCard), findsNothing);

    // Eski önbellek: kategori yok → karne yok (tahmin edilmez).
    await _kur(t, kart, katalog: [
      const TefasFund(
          code: 'CCC',
          name: 'C',
          price: 0,
          fundType: 'YAT',
          managerName: '',
          return1y: 5),
      _fon('AAA', 50),
    ]);
    expect(find.byType(SandikCard), findsNothing);
  });

  testWidgets('dar ekranda (320pt, büyük metin) taşma yok', (t) async {
    final uzun = [
      for (final f in _katalog)
        TefasFund(
          code: f.code,
          name: f.name,
          price: 0,
          fundType: 'YAT',
          managerName: '',
          return1m: f.return1m,
          return1y: f.return1y,
          returnYtd: f.returnYtd,
          kategori: 'Fon Sepeti Şemsiye Fonu (Yabancı Hisse Senedi Yoğun)',
        ),
    ];
    for (final olcek in [1.0, 1.3]) {
      await _kur(t, kart, katalog: uzun, genislik: 320, olcek: olcek);
      expect(t.takeException(), isNull, reason: 'ölçek $olcek');
      expect(find.byType(SandikCard), findsOneWidget);
    }
  });

  testWidgets('portföy panel satırı: 1 yıl özeti', (t) async {
    await _kur(t, const FonKarnesiSatiri(tur: AssetType.fon, ticker: 'CCC'));
    expect(find.text('Kategorisinde 4 fondan 3. (1 yıl)'), findsOneWidget);
  });

  testWidgets('portföy panel satırı bayrak kapalıyken yok', (t) async {
    await _kur(t, const FonKarnesiSatiri(tur: AssetType.fon, ticker: 'CCC'),
        acik: false);
    expect(find.textContaining('Kategorisinde'), findsNothing);
  });

  test('giriş noktaları: detay, varlık sayfası, portföy paneli', () {
    expect(ekranKaynagiSync('lib/screens/asset_detail_screen.dart'),
        contains('FonKarnesiKarti('));
    expect(ekranKaynagiSync('lib/screens/varlik_sayfasi.dart'),
        contains('FonKarnesiKarti('));
    expect(ekranKaynagiSync('lib/screens/portfolio_screen.dart'),
        contains('FonKarnesiSatiri('));
  });
}
