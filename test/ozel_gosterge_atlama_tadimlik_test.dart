import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/ozel_gosterge.dart';
import 'package:portfoy_takip/providers/ozel_gosterge_provider.dart';
import 'package:portfoy_takip/screens/ozel_gosterge_screen.dart';
import 'package:portfoy_takip/services/gosterge_betigi/betik.dart';
import 'package:portfoy_takip/services/gosterge_betigi/katalog.dart';
import 'package:portfoy_takip/services/ozel_gosterge_calistirici.dart';
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/widgets/gosterge_cizimi.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';

/// ƒx: (1) açık ama çizilemeyen gösterge nedeniyle raporlanır ve satırında
/// söylenir, çip yalnız çizileni sayar; (2) ücretsiz kullanıcı tadımlığı —
/// sayfa ve önizleme açık, kaydet paywall'a gider, hiçbir şey yazılmaz.
/// (2026-11-13)
class _Gostergeler extends OzelGostergelerNotifier {
  _Gostergeler(this._l);
  final List<OzelGosterge> _l;
  var okundu = false;
  final eklenen = <String>[];

  @override
  Future<List<OzelGosterge>> build() async {
    okundu = true;
    return _l;
  }

  @override
  Future<OzelGosterge> ekle({required String ad, required String kod}) async {
    eklenen.add(ad);
    return _g(ad, kod);
  }
}

/// Gerçek mumu olmayan seri (fon/endeks gibi): yalnız kapanış.
BetikVerisi _kapanis([int n = 120]) => BetikVerisi.yalnizKapanis(
      [for (var i = 0; i < n; i++) i.toDouble()],
      [for (var i = 0; i < n; i++) 100.0 + (i % 17)],
    );

OzelGosterge _g(String id, String kod) =>
    OzelGosterge(id: id, userId: 'u', ad: id, kod: kod);

void main() {
  group('çalıştırıcı atlama nedeni', () {
    test('hacim yok, OHLC yok, çizilen ayrımı; çip sayısı = çizilen', () {
      final r = ozelGostergeleriCalistirRapor([
        _g('hacim', 'plot(volume)'),
        _g('aralik', 'plot(high - low)'),
        _g('kapanis', 'plot(sma(close, 5))'),
      ], _kapanis());
      expect(r.cizilen.map((s) => s.g.id), ['kapanis']);
      expect(r.atlanan, {
        'hacim': OzelAtlamaNedeni.hacimYok,
        'aralik': OzelAtlamaNedeni.ohlcYok,
      });
      // Eski imza yalnız çizilenleri döndürür (üç ekranın çipi bunu sayar).
      expect(
          ozelGostergeleriCalistir(
                  [_g('hacim', 'plot(volume)'), _g('k', 'plot(close)')],
                  _kapanis())
              .length,
          1);
    });

    test('işlem bütçesi aşımı "ağır" diye ayrılır ve önbelleğe girer', () {
      const kod = 'float s = 0.0\n'
          'for i = 0 to 4999\n'
          '    for j = 0 to 99\n'
          '        s := s + j\n'
          'plot(s)\n';
      final g = _g('agir', kod);
      final veri = _kapanis(400);
      expect(ozelGostergeleriCalistirRapor([g], veri).atlanan,
          {'agir': OzelAtlamaNedeni.agir});
      // İkinci çağrı betiği yeniden koşmaz (önbellek): hızlı döner.
      final sw = Stopwatch()..start();
      expect(ozelGostergeleriCalistirRapor([g], veri).atlanan,
          {'agir': OzelAtlamaNedeni.agir});
      expect(sw.elapsedMilliseconds, lessThan(50));
    });
  });

  Widget uygulama(Widget ekran, _Gostergeler n,
          {List<NavigatorObserver> gozlem = const []}) =>
      ProviderScope(
        overrides: [ozelGostergelerProvider.overrideWith(() => n)],
        child: MaterialApp(home: ekran, navigatorObservers: gozlem),
      );

  void buyukEkran(WidgetTester tester) {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
  }

  testWidgets('liste: çizilemeyen açık göstergenin altında nötr neden satırı',
      (tester) async {
    buyukEkran(tester);
    final n = _Gostergeler([
      _g('h', 'plot(volume)'),
      _g('k', 'plot(close)'),
    ]);
    await tester.pumpWidget(
        uygulama(Scaffold(body: OzelGostergeListesi(onizleme: _kapanis())), n));
    await tester.pump();
    final satir = find.byKey(const ValueKey('ozgAtlama-h'));
    expect(satir, findsOneWidget);
    expect(
        find.text('Bu grafikte çizilemedi: hacim verisi yok'), findsOneWidget);
    expect(find.byKey(const ValueKey('ozgAtlama-k')), findsNothing);
    // Bilgi ikonu yanında, kırmızı değil (kod hatası değil).
    expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
    final ctx = tester.element(satir);
    final renk = tester.widget<Text>(satir).style?.color;
    expect(renk, isNot(Theme.of(ctx).colorScheme.error));
  });

  testWidgets(
      'tadımlık: kilitli liste kayıtlıları okumaz, şablon önizlemesi çizer, '
      'kaydet paywall açar ve hiçbir şey yazılmaz', (tester) async {
    buyukEkran(tester);
    RemoteConfigService.testAcik = {'paywall_enabled'};
    addTearDown(() => RemoteConfigService.testAcik = {});
    final itilen = <String?>[];
    final gozlem = _Gozlem(itilen);
    final n = _Gostergeler([_g('eski', 'plot(close)')]);
    await tester.pumpWidget(uygulama(
        Scaffold(
            body: OzelGostergeListesi(
                onizleme: _kapanis(), varlikAdi: 'TTE', kilitli: true)),
        n,
        gozlem: [gozlem]));
    await tester.pump();
    expect(n.okundu, isFalse, reason: 'kilitliyken sağlayıcı izlenmez');
    expect(find.text('eski'), findsNothing);

    await tester.tap(find.text(kBetikSablonlari.first.adTr));
    await tester.pumpAndSettle();
    expect(find.byType(OzelGostergeEditorScreen), findsOneWidget);
    // Önizleme varlığın çubuklarında çizilir.
    expect(find.byType(BetikOnizleme), findsOneWidget);
    expect(find.text('Kaydet ve grafikte tut'), findsOneWidget);

    itilen.clear();
    await tester.tap(find.byType(SandikAsyncButton));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(itilen, isNotEmpty, reason: 'paywall rotası itildi');
    expect(n.eklenen, isEmpty);
    expect(n.okundu, isFalse);
    // Paywall ağacının test ortamındaki eksik servisleri bu testin konusu
    // değil.
    tester.takeException();
  });

  testWidgets('Premium: kaydet düz "Kaydet" ve sağlayıcıya yazar',
      (tester) async {
    buyukEkran(tester);
    final n = _Gostergeler(const []);
    await tester.pumpWidget(uygulama(
        OzelGostergeEditorScreen(
            sablon: kBetikSablonlari.first, onizleme: _kapanis()),
        n));
    await tester.pump();
    expect(find.text('Kaydet ve grafikte tut'), findsNothing);
    await tester.tap(find.byType(SandikAsyncButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(n.eklenen, hasLength(1));
  });
}

class _Gozlem extends NavigatorObserver {
  _Gozlem(this.itilen);
  final List<String?> itilen;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      itilen.add(route.settings.name);
}
