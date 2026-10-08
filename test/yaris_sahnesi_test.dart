import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/widgets/yaris_sahnesi.dart';

/// Yarış sahnesi (kullanıcı kararı 2026-09-29): canlı liste + 3+ kişide
/// kürsü; tam 2 kişide düello arenası (2026-10-04, `duello_arenasi_test`).
/// Eski 2 kişilik düello kartı (`_Duello`, `halatOrani`) bayrak
/// `yaris_duello_arena` ile 2026-10-05'te silindi; onu sınayan testler de.
/// Sahne saf widget; ekransız pump edilir.
YarisKatilimci _k(String id, double? roi,
        {bool ben = false, String? ad, int renk = 1}) =>
    YarisKatilimci(
      id: id,
      ad: ad ?? id,
      ben: ben,
      roi: roi,
      renkSirasi: ben ? 0 : renk,
    );

List<YarisKatilimci> _sirala(List<YarisKatilimci> k) => [...k]..sort((a, b) {
    if (a.roi == null) return 1;
    if (b.roi == null) return -1;
    return b.roi!.compareTo(a.roi!);
  });

Future<void> _pump(
  WidgetTester tester,
  List<YarisKatilimci> k, {
  int yenileme = 1,
  int donem = 7,
  double genislik = 390,
  double olcek = 1,
  bool hareketsiz = false,
}) async {
  tester.view.physicalSize = Size(genislik * 3, 1800 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: ThemeData.dark(),
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(genislik, 1800),
        textScaler: TextScaler.linear(olcek),
        disableAnimations: hareketsiz,
      ),
      child: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: YarisSahnesi(
            katilimcilar: _sirala(k),
            yenileme: yenileme,
            sonGuncelleme: DateTime.now(),
            donemGun: donem,
          ),
        ),
      ),
    ),
  ));
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('vitrin kuralı', () {
    test('tam 2 kişi → arena (biri veri yok olsa da)', () {
      expect(yarisVitrini([_k('sen', 1, ben: true), _k('a', 2)]),
          YarisVitrini.arena);
      expect(yarisVitrini([_k('sen', 1, ben: true), _k('a', null)]),
          YarisVitrini.arena);
    });
    test('getirisi olan 3+ kişi → kürsü', () {
      expect(yarisVitrini([_k('sen', 1, ben: true), _k('a', 2), _k('b', -1)]),
          YarisVitrini.kursu);
    });
    test('3 kişi ama yalnızca 2 getiri → vitrin yok (boş basamak olmaz)', () {
      expect(yarisVitrini([_k('sen', 1, ben: true), _k('a', 2), _k('b', null)]),
          YarisVitrini.yok);
    });
    test('tek başına → vitrin yok', () {
      expect(yarisVitrini([_k('sen', 1, ben: true)]), YarisVitrini.yok);
    });
  });

  testWidgets('3 kişi: kürsü, arena yok', (tester) async {
    await _pump(tester, [
      _k('sen', 4.1, ben: true, ad: 'Sen Kişi'),
      _k('ayse', 6.3, ad: 'Ayşe'),
      _k('mert', 2.2, ad: 'Mert', renk: 2),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('VS'), findsNothing);
    // Kürsüde kısa ad + listede tam ad.
    expect(find.text('Ayşe'), findsNWidgets(2));
    expect(find.text('Lidere 2,2 puan'), findsOneWidget);
  });

  testWidgets('canlı yenilemede sıra değişirse ▲/▼ çipi belirir ve söner',
      (tester) async {
    // 3 kişi: canlı liste yalnız kürsüyle çizilir (2 kişide arena).
    final once = [
      _k('sen', -2.7, ben: true),
      _k('ayse', -3.2),
      _k('mert', -5.0, renk: 2),
    ];
    await _pump(tester, once, yenileme: 1);
    await tester.pumpAndSettle();
    expect(find.text('▲1'), findsNothing);

    await _pump(
        tester,
        [
          _k('sen', -3.4, ben: true),
          _k('ayse', -3.0),
          _k('mert', -5.0, renk: 2),
        ],
        yenileme: 2);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('▲1'), findsOneWidget, reason: 'Ayşe öne geçti');
    expect(find.text('▼1'), findsOneWidget, reason: 'sen geriye düştün');

    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('▲1'), findsNothing, reason: 'çip birkaç saniyede söner');
  });

  testWidgets('dönem değişimi canlı olay değildir: çip yok', (tester) async {
    await _pump(
        tester,
        [_k('sen', -2.7, ben: true), _k('ayse', -3.2), _k('m', -5, renk: 2)],
        yenileme: 1,
        donem: 7);
    await tester.pumpAndSettle();
    await _pump(
        tester,
        [_k('sen', 4.1, ben: true), _k('ayse', 6.3), _k('m', -5, renk: 2)],
        yenileme: 2,
        donem: 30);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('▲1'), findsNothing);
    expect(find.text('▼1'), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('liderliği canlı alınca konfeti ve taç zıplaması hatasız',
      (tester) async {
    // 3 kişi (kürsü): konfeti kürsünün üstünde oynar.
    await _pump(
        tester,
        [
          _k('sen', -3.4, ben: true),
          _k('ayse', -3.0, ad: 'Ayşe'),
          _k('m', -5, renk: 2),
        ],
        yenileme: 1);
    await tester.pumpAndSettle();
    await _pump(
        tester,
        [
          _k('sen', -2.0, ben: true),
          _k('ayse', -3.0, ad: 'Ayşe'),
          _k('m', -5, renk: 2),
        ],
        yenileme: 2);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('hareketi azalt: animasyonsuz kurulur', (tester) async {
    await _pump(
      tester,
      [_k('sen', 4.1, ben: true), _k('a', 6.3), _k('b', 2.2, renk: 2)],
      hareketsiz: true,
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpAndSettle();
  });

  group('taşma', () {
    final uzun = [
      _k('sen', 12.4, ben: true, ad: 'Çok Uzun Bir Kullanıcı Adı Soyadı'),
      _k('p1', -123.4, ad: 'Mehmet Emin Karahanoğlu'),
      _k('p2', 44.7, ad: 'Ayşe Nur Büyükçelebioğlu', renk: 2),
      _k('p3', null, ad: 'Deniz', renk: 3),
    ];
    for (final (w, o) in [(320.0, 1.0), (320.0, 1.6), (375.0, 2.0)]) {
      testWidgets('${w.toInt()}pt × $o metin ölçeği', (tester) async {
        await _pump(tester, uzun, genislik: w, olcek: o);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
      testWidgets('2 kişi (arena) ${w.toInt()}pt × $o', (tester) async {
        await _pump(tester, uzun.take(2).toList(), genislik: w, olcek: o);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }
  });
}
