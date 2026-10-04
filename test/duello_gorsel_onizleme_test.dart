@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/main.dart' show SandikApp;
import 'package:portfoy_takip/services/lider_seridi.dart';
import 'package:portfoy_takip/services/zirve_kiyas.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/yaris_sahnesi.dart';
import 'package:portfoy_takip/widgets/zirve_donem_secici.dart';

/// Düello arenasının (bayrak `yaris_duello_arena`) GÖRSEL önizlemesi —
/// `build/gorsel/` altına PNG; onaylı prototiple (`Duello.dc.html`)
/// karşılaştırmak için. Assert etmez; `gorsel` etiketi CI'da atlanır.
///   flutter test --run-skipped test/duello_gorsel_onizleme_test.dart
///
/// Sayılar DEMO (prototipteki örnek rakamlar); şerit örnek, canlı değil.

const _gunluk = [
  0, 0, 0, 1, 1, 1, 1, 1, 0, 0, 0, 0, 1, 1, 1, //
  0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
];

LiderSeridi _serit(int gun) {
  final List<int> c = switch (gun) {
    7 => const [1, 1, 0, 1, 1, 1, 1],
    30 => _gunluk,
    _ => const [1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0],
  };
  return LiderSeridi(
    cubuklar: [for (final x in c) x == 0 ? SeritLider.ben : SeritLider.rakip],
    baslangic: DateTime(2026, 10, 4).subtract(Duration(days: gun - 1)),
    aylik: gun > 31,
    donemGun: gun,
  );
}

const _degerler = {
  7: (ben: 1.2, rakip: 1.8),
  30: (ben: 6.4, rakip: 4.1),
  365: (ben: 31.5, rakip: 27.8),
};

class _Onizleme extends StatefulWidget {
  const _Onizleme({required this.donem, this.rakipVeriYok = false});
  final ZirveDonem donem;
  final bool rakipVeriYok;
  @override
  State<_Onizleme> createState() => _OnizlemeState();
}

class _OnizlemeState extends State<_Onizleme> {
  late ZirveDonem donem = widget.donem;
  int yenileme = 1;

  @override
  Widget build(BuildContext context) {
    final d = _degerler[donem.gun]!;
    final k = [
      YarisKatilimci(id: 'sen', ad: 'Deneme', ben: true, roi: d.ben),
      YarisKatilimci(
        id: 'ayse',
        ad: 'Ayşe Yılmaz',
        ben: false,
        roi: widget.rakipVeriYok ? null : d.rakip,
        renkSirasi: 1,
      ),
    ]..sort((a, b) {
        if (a.roi == null) return 1;
        if (b.roi == null) return -1;
        return b.roi!.compareTo(a.roi!);
      });
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(title: const Text('Sıralama')),
      body: ListView(
        padding: const EdgeInsets.all(SandikSpace.smd),
        children: [
          ZirveDonemSecici(
            secili: donem,
            kayan: true,
            onSec: (x) => setState(() {
              donem = x;
              yenileme++;
            }),
          ),
          const SizedBox(height: SandikSpace.md),
          YarisSahnesi(
            katilimcilar: k,
            yenileme: yenileme,
            sonGuncelleme: null,
            donemGun: donem.gun,
            arena: true,
            liderSeridi: widget.rakipVeriYok ? null : _serit(donem.gun),
          ),
        ],
      ),
    );
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
    final dm = FontLoader(kSandikFontFamily);
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      dm.addFont(rootBundle.load('assets/fonts/DMSans-$w.ttf'));
    }
    await dm.load();
  });

  Future<void> kaydet(WidgetTester tester, Key k, String ad) async {
    await tester.runAsync(() async {
      final b = tester.renderObject<RenderRepaintBoundary>(find.byKey(k));
      final img = await b.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory('build/gorsel').createSync(recursive: true);
      File('build/gorsel/$ad.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> kur(WidgetTester tester, Widget ekran,
      {bool acik = false, double genislik = 390}) async {
    tester.view.physicalSize = Size(genislik * 2, 844 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('kok'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: acik
            ? SandikApp.buildTheme(SandikPalette.light, Brightness.light)
            : SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
        home: ekran,
      ),
    ));
  }

  for (final acik in [false, true]) {
    final tema = acik ? 'acik' : 'koyu';
    testWidgets('arena $tema — giriş sonu, ortası; dönem değişimi ortası',
        (tester) async {
      const k = ValueKey('kok');
      await kur(tester, const _Onizleme(donem: ZirveDonem.ay), acik: acik);
      // Giriş ortası (~%45: sayaç yolda, halat esniyor).
      await tester.pump(const Duration(milliseconds: 1150));
      await kaydet(tester, k, 'duello_${tema}_giris_orta');
      await tester.pumpAndSettle();
      await kaydet(tester, k, 'duello_${tema}_son');
      // Hafta: lider değişir → taç zıplar, kıvılcım (~%75).
      await tester.tap(find.text('1H'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1250));
      await kaydet(tester, k, 'duello_${tema}_tac_orta');
      await tester.pumpAndSettle();
      await kaydet(tester, k, 'duello_${tema}_hafta_son');
      await tester.tap(find.text('1Y'));
      await tester.pump();
      await tester.pumpAndSettle();
      await kaydet(tester, k, 'duello_${tema}_yil_son');
    });
  }

  testWidgets('arena — ortak verisi yok, 320pt', (tester) async {
    await kur(tester,
        const _Onizleme(donem: ZirveDonem.ay, rakipVeriYok: true),
        genislik: 320);
    await tester.pumpAndSettle();
    await kaydet(tester, const ValueKey('kok'), 'duello_veri_yok_320');
  });
}
