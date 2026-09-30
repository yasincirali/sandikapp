import 'dart:convert';

import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'helpers/kaynak.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/widgets/piyasa_seridi.dart';

/// Kayan bant — erişilebilirlik ve döngü kuralları.
///
/// Bant dört sabit değer taşır; ekran okuyucu bunu TEK cümle okumalı,
/// "hareketi azalt" açıkken akış olmamalı; uzun basış tutmalı, bırakınca
/// akış sürmeli (2026-09-30, dokunuşla durdur/sürdür yerine).
///
/// 2026-09-21: bant `ListView` + `jumpTo`'dan boyama-tabanlı çizime geçti
/// (`_RenderBant`); testler artık scroll konumunu değil `KayanBantState`'in
/// kayma değerini okur.
void main() {
  const ogeler = [
    PiyasaOgesi(etiket: 'Dolar', deger: '48,79', degisimPct: 0.08),
    PiyasaOgesi(etiket: 'Euro', deger: '56,11', degisimPct: -0.08),
    PiyasaOgesi(etiket: 'BIST 100', deger: '11.482', degisimPct: null),
  ];

  Future<void> pump(WidgetTester tester, {bool hareketiAzalt = false}) async {
    tester.view.physicalSize = const Size(320 * 3, 200 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: hareketiAzalt),
          child: child!,
        ),
        home: const Scaffold(body: KayanBant(ogeler: ogeler)),
      ),
    );
    await tester.pump();
  }

  KayanBantState bant(WidgetTester tester) =>
      tester.state<KayanBantState>(find.byType(KayanBant));

  testWidgets('öğe metni: ad, değer, yön; değişimsiz öğe yüzde yazmaz',
      (tester) async {
    await pump(tester, hareketiAzalt: true);
    expect(find.text('Dolar'), findsWidgets);
    expect(find.text('48,79'), findsWidgets);
    expect(find.textContaining('▲'), findsWidgets);
    expect(find.textContaining('▼'), findsWidgets);
    expect(ogeler[2].metin, 'BIST 100 11.482');
    expect(ogeler[0].metin, contains('+'));
  });

  testWidgets('ekran okuyucu bandı tek cümle olarak okur', (tester) async {
    await pump(tester, hareketiAzalt: true);
    final s = tester.getSemantics(find.byType(KayanBant));
    expect(s.label, contains('Dolar 48,79'));
    expect(s.label, contains('Euro 56,11'));
    expect(s.label, contains('BIST 100 11.482'));
  });

  testWidgets('hareketi azalt: bant durur ve elle kaydırılır', (tester) async {
    await pump(tester, hareketiAzalt: true);
    final b = bant(tester);
    expect(b.akiyor, isFalse);
    final once = b.kaydirma;
    await tester.pump(const Duration(seconds: 1));
    expect(b.kaydirma, once,
        reason: 'Hareketi azalt açıkken kendiliğinden akmamalı.');

    // Parmak sola → içerik ileri (kayma artar).
    await tester.drag(find.byType(KayanBant), const Offset(-60, 0));
    await tester.pump();
    expect(b.kaydirma, greaterThan(once), reason: 'Dururken elle kaydırılır.');
  });

  testWidgets('akarken ilerler; kısa dokunuş bandı durdurmaz', (tester) async {
    await pump(tester);
    final b = bant(tester);
    expect(b.akiyor, isTrue);
    final once = b.kaydirma;
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    expect(b.kaydirma, greaterThan(once));

    // Eski davranış dokunuşla durdurmaktı; artık sayfayı kaydırırken
    // bandın üstünden geçen parmak bandı dondurmamalı.
    await tester.tap(find.byType(KayanBant));
    await tester.pump();
    expect(b.akiyor, isTrue);
    expect(b.tutuluyor, isFalse);
  });

  testWidgets('uzun basış tutar, sağa sola kaydırılır, bırakınca akış sürer',
      (tester) async {
    await pump(tester);
    final b = bant(tester);
    final g = await tester.startGesture(tester.getCenter(find.byType(KayanBant)));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(b.tutuluyor, isTrue);
    expect(b.akiyor, isFalse, reason: 'Tutarken bant kendiliğinden akmaz.');

    final tutus = b.kaydirma;
    await tester.pump(const Duration(milliseconds: 200));
    expect(b.kaydirma, tutus, reason: 'Parmak dururken bant da durur.');

    // Parmak sola → içerik ileri; sağa → geri. 1:1.
    await g.moveBy(const Offset(-60, 0));
    await tester.pump();
    expect(b.kaydirma - tutus, closeTo(60, 0.01));
    await g.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(b.kaydirma - tutus, closeTo(-30, 0.01));

    // Parmak durup bırakılır: hız ~0, bant yavaşça akış hızına çıkar.
    await tester.pump(const Duration(milliseconds: 300));
    final birakis = b.kaydirma;
    await g.up();
    await tester.pump();
    expect(b.tutuluyor, isFalse);
    expect(b.akiyor, isTrue, reason: 'Bırakınca akış kendiliğinden sürer.');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    final ilerleme = b.kaydirma - birakis;
    expect(ilerleme, greaterThan(0));
    expect(ilerleme, lessThan(PiyasaSeridi.hiz * 0.2),
        reason: 'Durgun bırakışta sıçrama yok: sıfırdan hıza yumuşak çıkış.');
  });

  testWidgets('fırlatış hızı akışa devredilir, sonra akış hızına iner',
      (tester) async {
    await pump(tester);
    final b = bant(tester);
    final g = await tester.createGesture();
    await g.down(tester.getCenter(find.byType(KayanBant)),
        timeStamp: Duration.zero);
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    expect(b.tutuluyor, isTrue);
    // Sola hızlı sürükleme: 16 ms'de 20 pt ≈ 1250 pt/sn.
    var t = kLongPressTimeout + const Duration(milliseconds: 50);
    for (var i = 0; i < 6; i++) {
      t += const Duration(milliseconds: 16);
      await g.moveBy(const Offset(-20, 0), timeStamp: t);
    }
    await g.up(timeStamp: t);
    await tester.pump();
    final birakis = b.kaydirma;
    await tester.pump(const Duration(milliseconds: 100));
    expect(b.kaydirma - birakis, greaterThan(PiyasaSeridi.hiz * 0.1 * 3),
        reason: 'Bırakış anında bant parmağın hızıyla devam etmeli.');

    // Birkaç zaman sabiti sonra hız yeniden akış hızıdır.
    await tester.pump(const Duration(seconds: 3));
    final a = b.kaydirma;
    await tester.pump(const Duration(milliseconds: 500));
    expect((b.kaydirma - a) / 0.5, closeTo(PiyasaSeridi.hiz, 1));
  });

  testWidgets('hareketi azalt: uzun basıp bırakınca bant durur kalır',
      (tester) async {
    await pump(tester, hareketiAzalt: true);
    final b = bant(tester);
    await tester.longPress(find.byType(KayanBant));
    await tester.pump(const Duration(milliseconds: 300));
    expect(b.akiyor, isFalse);
  });

  testWidgets('akarken uzun basışsız sürükleme bandı ötelemez', (tester) async {
    await pump(tester);
    final b = bant(tester);
    final once = b.kaydirma;
    await tester.drag(find.byType(KayanBant), const Offset(-200, 0));
    await tester.pump();
    // Sürükleme alınmadı: kayma yalnızca geçen süre kadar ilerledi.
    expect(b.kaydirma - once, lessThan(60),
        reason: 'Akarken parmak bandı 200 pt ötelememeli.');
  });

  testWidgets('kayma yalnızca boyar: sürüklerken widget ağacı yeniden kurulmaz',
      (tester) async {
    await pump(tester, hareketiAzalt: true);
    final onceki = tester.widget(find.text('Dolar'));
    await tester.drag(find.byType(KayanBant), const Offset(-60, 0));
    await tester.pump();
    expect(identical(tester.widget(find.text('Dolar')), onceki), isTrue,
        reason: 'Kayma değişince metin widget\'ı yeniden kurulmamalı.');
  });

  testWidgets('büyüteç: 44pt dokunma alanı, dokununca aramayı açar',
      (tester) async {
    var acildi = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: Row(children: [
            const Expanded(child: KayanBant(ogeler: ogeler)),
            PiyasaAramaDugmesi(onTap: () => acildi++),
          ]),
        ),
      ),
    );
    await tester.pump();
    final boyut = tester.getSize(find.byType(PiyasaAramaDugmesi));
    expect(boyut.width, greaterThanOrEqualTo(44));
    expect(boyut.height, greaterThanOrEqualTo(44));
    await tester.tap(find.byType(PiyasaAramaDugmesi));
    await tester.pump(const Duration(milliseconds: 300));
    expect(acildi, 1);
    // Büyütece dokunmak bandı durdurmaz.
    expect(bant(tester).akiyor, isTrue);
  });

  testWidgets('"Ara" çipi etiketli; tek başına da tam hap (seçenek C)',
      (tester) async {
    // Şeridin ucunda: büyüteç + "Ara" metni (ikon tek başına değil —
    // kullanıcı kararı 2026-09-28, keşfedilebilirlik).
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Row(children: [
          const Expanded(child: KayanBant(ogeler: ogeler, sagKose: false)),
          PiyasaAramaDugmesi(onTap: () {}),
        ]),
      ),
    ));
    await tester.pump();
    expect(find.text('Ara'), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    // Fiyat yokken çip tek başına: yine etiketli, dokunma alanı 44.
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.centerRight,
          child: PiyasaAramaDugmesi(onTap: () {}, cerceveli: false),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Ara'), findsOneWidget);
    expect(tester.getSize(find.byType(PiyasaAramaDugmesi)).height,
        greaterThanOrEqualTo(44));
  });

  // ── Bant kendi ritmi dışında SIFIRLANMAZ (kullanıcı kararı 2026-09-28) ──
  //
  // Ana sayfada görünüm (Ben → ortak) değişince ya da bandın üstündeki
  // koşullu şerit girip çıkınca bant AYNI element olarak kalmalı: state
  // (kotasyon, akış fazı) korunur, yalnızca yeniden çizilir.
  testWidgets('üst ağaç yeniden kurulunca bant durumu ve fazı korunur',
      (tester) async {
    var ekstra = false;
    late StateSetter kur;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          kur = setState;
          return Column(children: [
            if (ekstra) const SizedBox(key: ValueKey('x'), height: 10),
            // Her kurulumda YENİ liste örneği — ana sayfa da böyle yapar.
            KayanBant(key: const ValueKey('bant'), ogeler: List.of(ogeler)),
          ]);
        }),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final onceState = bant(tester);
    final onceKayma = onceState.kaydirma;
    expect(onceKayma, greaterThan(0));

    kur(() => ekstra = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final sonraState = bant(tester);
    expect(identical(onceState, sonraState), isTrue,
        reason: 'bant yeniden kurulmamalı — aynı State');
    expect(sonraState.kaydirma, greaterThan(onceKayma),
        reason: 'faz sıfırlanmadı, akış devam etti');
    expect(sonraState.akiyor, isTrue);
  });

  test('ana sayfa: şerit koşulsuz ve anahtarlı (görünümden bağımsız)', () {
    final kod = ekranKaynagiSync('lib/screens/home_screen.dart');
    final a = kod.indexOf('// Piyasa şeridi — dolar/euro/gram altın/BIST 100');
    final b = kod.indexOf('// Portfolio summary', a);
    expect(a, greaterThan(0));
    expect(b, greaterThan(a));
    final blok = kod.substring(a, b);
    expect(blok.contains("key: const ValueKey('piyasa-seridi')"), isTrue,
        reason: 'anahtar yoksa üstteki koşullu sliver bandı sıfırlar');
    // Yorum satırları dışında `if (ownView)` kalmamalı.
    final kodSatirlari = const LineSplitter()
        .convert(blok)
        .where((l) => !l.trimLeft().startsWith('//'))
        .join(' ');
    expect(kodSatirlari.contains('if (ownView)'), isFalse,
        reason: 'bant her görünümde çizilir (kullanıcı kararı 2026-09-28)');
    expect(kodSatirlari.contains('PiyasaAramaDugmesi('), isFalse,
        reason: 'arama artık şeridin içinde, ayrı dal yok');
  });

  // Emülatör bulgusu #14 (2026-09-29): bant "Gram altın" diye 22 ayar
  // (`ALTIN_GRAM`) fiyatı gösteriyordu; portföydeki "Gram Altın (24 Ayar)"
  // başka bir sayıydı. "Gram altın" gündelik dilde 24 ayardır.
  test('banttaki gram altın, "Gram Altın (24 Ayar)" varlığıyla AYNI sembol',
      () {
    expect(PiyasaSeridi.semboller, contains(PiyasaSeridi.altinSembolu));
    expect(PiyasaSeridi.altinSembolu,
        goldTickerMap[GoldSubCategory.gr24.label],
        reason: 'Bant ile portföydeki 24 ayar gram aynı fiyatı göstermeli.');
    expect(PiyasaSeridi.semboller, isNot(contains('ALTIN_GRAM')),
        reason: '`ALTIN_GRAM` 22 ayardır; "Gram altın" etiketiyle yanıltır.');
  });
}
