import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/sandik_app_bar.dart';

/// Tek üst çubuk — `SandikAppBar`.
///
/// 2026-09 denetimi: 14 ekranda `AppBar(` ayrı kurulmuştu (3 zemin, 3 başlık
/// stili, 5 kopya geri ikonu). Bu test kopyaların geri gelmesini ve geri
/// okunun davranışını kilitler.
void main() {
  testWidgets('kök ekranda geri oku yok, push edilen ekranda var', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(appBar: SandikAppBar(title: 'Kök'), body: SizedBox()),
    ));
    expect(find.byTooltip('Geri'), findsNothing);

    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(
                    appBar: SandikAppBar(title: 'Alt'), body: SizedBox()),
              ),
            ),
            child: const Text('git'),
          ),
        ),
      ),
    ));
    await t.tap(find.text('git'));
    await t.pumpAndSettle();
    expect(find.byTooltip('Geri'), findsOneWidget);
    await t.tap(find.byTooltip('Geri'));
    await t.pumpAndSettle();
    expect(find.text('Alt'), findsNothing);
  });

  testWidgets('uzun başlık tek satırda kesilir, taşma yok', (t) async {
    t.view.physicalSize = const Size(320 * 3, 640 * 3);
    t.view.devicePixelRatio = 3.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        appBar: SandikAppBar(
            title: 'Performans: Yapı Kredi Koray Gayrimenkul Yatırım Ortaklığı'),
        body: SizedBox(),
      ),
    ));
    expect(t.takeException(), isNull);
  });

  test("ekranlarda ham 'appBar: AppBar(' kalmadı", () {
    final hits = <String>[];
    for (final f in Directory('lib/screens').listSync().whereType<File>()) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('appBar: AppBar(')) hits.add('${f.path}:${i + 1}');
      }
    }
    expect(hits, isEmpty, reason: 'SandikAppBar kullan:\n${hits.join('\n')}');
  });
}
