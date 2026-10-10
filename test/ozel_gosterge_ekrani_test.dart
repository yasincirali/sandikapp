import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/ozel_gosterge.dart';
import 'package:portfoy_takip/providers/ozel_gosterge_provider.dart';
import 'package:portfoy_takip/screens/ozel_gosterge_screen.dart';
import 'package:portfoy_takip/services/gosterge_betigi/betik.dart';
import 'package:portfoy_takip/services/gosterge_betigi/katalog.dart';
import 'package:portfoy_takip/widgets/sandik_async_button.dart';

/// Kendi göstergeni yaz — düzenleyici ve liste davranışı.
class _Gostergeler extends OzelGostergelerNotifier {
  _Gostergeler(this._l);
  final List<OzelGosterge> _l;
  final ayarlar = <(String, bool)>[];

  @override
  Future<List<OzelGosterge>> build() async => _l;

  @override
  Future<void> grafikteAyarla(String id, bool acik) async {
    ayarlar.add((id, acik));
    state = AsyncData(
        [for (final g in _l) g.id == id ? g.kopya(grafikte: acik) : g]);
  }
}

BetikVerisi _veri() => BetikVerisi.yalnizKapanis(
      [for (var i = 0; i < 120; i++) i.toDouble()],
      [for (var i = 0; i < 120; i++) 100.0 + (i % 17)],
    );

Widget _uygulama(Widget ekran, _Gostergeler n) => ProviderScope(
      overrides: [ozelGostergelerProvider.overrideWith(() => n)],
      child: MaterialApp(home: ekran),
    );

void main() {
  testWidgets('düzenleyici: geçerli şablon özet, hatalı kod satır ve '
      'Kaydet pasif', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_uygulama(
      OzelGostergeEditorScreen(
        sablon: kBetikSablonlari.first,
        onizleme: _veri(),
        varlikAdi: 'THYAO',
      ),
      _Gostergeler(const []),
    ));
    await tester.pump();
    expect(find.textContaining('Geçerli · 2 çizgi'), findsOneWidget);
    expect(find.text('EMA kesişimi'), findsWidgets);

    await tester.enterText(find.byType(TextField).at(1), 'plot(close +)');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('Satır 1'), findsOneWidget);
    final dugme =
        tester.widget<SandikAsyncButton>(find.byType(SandikAsyncButton));
    expect(dugme.onPressed, isNull);
  });

  testWidgets('liste: hatalı gösterge işaretli, anahtar grafikte aç/kapa',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final n = _Gostergeler(const [
      OzelGosterge(id: 'a', userId: 'u', ad: 'RSI', kod: 'plot(rsi(close,14))'),
      OzelGosterge(
          id: 'b', userId: 'u', ad: 'Bozuk', kod: 'plot(', grafikte: false),
    ]);
    await tester.pumpWidget(
        _uygulama(const Scaffold(body: OzelGostergeListesi()), n));
    await tester.pump();
    expect(find.text('Hatalı, düzenle'), findsOneWidget);
    expect(find.text('Fiyatın üstünde'), findsOneWidget);
    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(n.ayarlar, [('a', false)]);
    // Hatalı göstergenin anahtarı pasif: grafikte açılamaz.
    expect(tester.widget<Switch>(find.byType(Switch).last).onChanged, isNull);
  });
}
