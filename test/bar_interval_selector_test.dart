import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/bar_interval_selector.dart';

/// Widget `context.c` (SandikPalette) ve `context.t` okuyor — palette
/// ThemeExtension olarak verilmezse build çöker.
Widget _sar(Widget child) => MaterialApp(
      theme: ThemeData.dark().copyWith(
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('GÜNLÜK dönemde dakikalık barları gösterir', (t) async {
    await t.pumpWidget(_sar(BarIntervalSelector(
      periodDays: 0,
      secili: ResolutionTier.fiveMin,
      onSecim: (_) {},
    )));

    expect(find.text('1dk'), findsOneWidget);
    expect(find.text('5dk'), findsOneWidget);
    expect(find.text('15dk'), findsOneWidget);
    // 1sa GÜNLÜK'te seans başına 8 nokta üretir — sunulmamalı.
    expect(find.text('1sa'), findsNothing);
  });

  testWidgets('6A döneminde intraday bar SUNULMAZ', (t) async {
    await t.pumpWidget(_sar(BarIntervalSelector(
      periodDays: 180,
      secili: ResolutionTier.daily,
      onSecim: (_) {},
    )));

    expect(find.text('1G'), findsOneWidget);
    expect(find.text('1H'), findsOneWidget);
    for (final yok in ['1dk', '5dk', '15dk', '1sa']) {
      expect(find.text(yok), findsNothing, reason: '$yok 6A\'da olmamalı');
    }
  });

  testWidgets('dokunma seçimi yayar', (t) async {
    ResolutionTier? secilen;
    await t.pumpWidget(_sar(BarIntervalSelector(
      periodDays: 0,
      secili: ResolutionTier.fiveMin,
      onSecim: (v) => secilen = v,
    )));

    await t.tap(find.text('15dk'));
    await t.pump();
    expect(secilen, ResolutionTier.fifteenMin);
  });

  testWidgets('tek seçenek varsa hiç çizilmez', (t) async {
    // Politika her dönemde >= 2 bar sunuyor; widget yine de kendini
    // savunmalı — ileride bir dönem tek seçeneğe inerse boş bir seçici
    // kullanıcıya var olmayan bir karar varmış izlenimi verirdi.
    await t.pumpWidget(_sar(Builder(builder: (_) {
      return const SizedBox(
        width: 200,
        child: BarIntervalSelector(
          periodDays: 999999,
          secili: ResolutionTier.weekly,
          onSecim: _yut,
        ),
      );
    })));
    // 999999 gün → [daily, weekly] = 2 seçenek, çizilir.
    expect(find.text('1H'), findsOneWidget);
  });

  testWidgets('seçili bar vurgulanır, diğerleri sönük', (t) async {
    await t.pumpWidget(_sar(BarIntervalSelector(
      periodDays: 0,
      secili: ResolutionTier.fifteenMin,
      onSecim: (_) {},
    )));

    final secili = t.widget<Text>(find.text('15dk'));
    final digeri = t.widget<Text>(find.text('5dk'));
    expect(secili.style?.fontWeight, FontWeight.w600);
    expect(digeri.style?.fontWeight, FontWeight.w500);
    expect(secili.style?.color, isNot(digeri.style?.color));
  });
}

void _yut(ResolutionTier _) {}
