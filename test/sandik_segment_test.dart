import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

import 'helpers/kaynak.dart';

/// [SandikSegment] sözleşmesi + "tek seçici" ratchet'i (yol haritası 2.12,
/// 2026-10-08).
///
/// ## Neden bu dosya var
/// Uygulamada 2–4 seçenekli her "birini seç" kontrolü tek bileşenle
/// çizilir. Eski elle yazılmış kopyalar (`ModernTabSelector`, Portföy gövde
/// sekmesi, karşılaştırma arama sekmesi, birikim aralığı, sinyal eşiği,
/// Zirve kıyas çipleri) her biri dokunma hedefini ve semantiği kendisi
/// sağlıyordu; biri unutunca (eşik segmenti ~30 pt'ydi) hiçbir test
/// yakalamıyordu. Değişmezler artık TEK yerde, burada sınanır.
Widget _kabuk(Widget child) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))),
    );

void main() {
  testWidgets('her segmentin dokunma hedefi görsel yükseklikten bağımsız '
      '≥ 44 pt', (t) async {
    await t.pumpWidget(_kabuk(SandikSegment(
      adet: 4,
      secili: 0,
      yukseklik: 30,
      onSec: (_) {},
      oge: (_, i, __) => Text('s$i'),
    )));
    final dugmeler = find.byType(CupertinoButton);
    expect(dugmeler, findsNWidgets(4));
    for (final e in dugmeler.evaluate()) {
      final boy = t.getSize(find.byWidget(e.widget));
      expect(boy.height, greaterThanOrEqualTo(SandikTouch.min));
      expect(boy.width, greaterThanOrEqualTo(SandikTouch.min));
    }
  });

  testWidgets('segment düğme + seçili durum + etkin dokunma eylemi bildirir',
      (t) async {
    final semantics = t.ensureSemantics();
    final gelen = <int>[];
    await t.pumpWidget(_kabuk(SandikSegment(
      adet: 2,
      secili: 0,
      onSec: gelen.add,
      oge: (_, i, __) => Text(['Varlıklarım', 'Takip'][i]),
    )));
    expect(
        t.getSemantics(find.text('Varlıklarım')),
        isSemantics(
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true));
    expect(t.getSemantics(find.text('Takip')),
        isSemantics(hasSelectedState: true, isSelected: false));
    semantics.dispose();
  });

  testWidgets('özel semantik etiket verilince de eylem silinmez', (t) async {
    // `excludeSemantics` alttaki düğmenin eylemini de siler; bileşen eylemi
    // açıkça verir (emülatör testi #28). Rozetli gövde sekmesi ve Zirve
    // kıyası bu yolu kullanır.
    final semantics = t.ensureSemantics();
    final gelen = <int>[];
    await t.pumpWidget(_kabuk(SandikSegment(
      adet: 2,
      secili: 0,
      onSec: gelen.add,
      semantik: (i) => 'etiket $i',
      oge: (_, i, __) => Text('s$i'),
    )));
    expect(
        t.getSemantics(find.bySemanticsLabel('etiket 1')),
        isSemantics(
            isButton: true,
            isSelected: false,
            hasSelectedState: true,
            hasTapAction: true));
    t.semantics.tap(find.semantics.byLabel('etiket 1'));
    await t.pumpAndSettle();
    expect(gelen, [1]);
    semantics.dispose();
  });

  group('tek seçici ratchet', () {
    test('Material/eski segment kontrolleri lib/ içinde yok', () {
      // Marka kararı: Material `SegmentedButton` / `ToggleButtons`
      // KULLANILMAZ (tasarım dili); eski `ModernTabSelector` silindi.
      final ihlal = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final k = f
            .readAsLinesSync()
            .where((s) => !s.trimLeft().startsWith('//'))
            .join('\n');
        for (final yasak in [
          'SegmentedButton<',
          'SegmentedButton(',
          'ToggleButtons(',
          'ModernTabSelector(',
          'class ModernTabSelector',
        ]) {
          if (k.contains(yasak)) ihlal.add('${f.path}: $yasak');
        }
      }
      expect(ihlal, isEmpty);
    });

    test('2.12\'de taşınan seçiciler SandikSegment ile çizilir', () {
      for (final (yol, sinif) in [
        ('lib/screens/portfolio_screen.dart', 'class _BodyTabs'),
        ('lib/screens/comparison_screen.dart', 'class _SheetTabs'),
        ('lib/widgets/period_summary_view.dart', 'class _AralikSecici'),
        ('lib/screens/signal_settings_screen.dart', 'class _ThresholdSegment'),
        ('lib/screens/zirve_portfoyler_screen.dart', 'class _KiyasSecici'),
      ]) {
        final k = ekranKaynagiSync(yol);
        final i = k.indexOf(sinif);
        expect(i, greaterThanOrEqualTo(0), reason: '$yol: $sinif yok');
        final son = k.indexOf('\n}\n', i);
        final govde = k.substring(i, son);
        expect(govde, contains('SandikSegment('), reason: '$yol: $sinif');
        expect(govde, isNot(contains('amberFill : Colors.transparent')),
            reason: '$yol: elle seçim dolgusu geri gelmiş');
      }
    });
  });
}
