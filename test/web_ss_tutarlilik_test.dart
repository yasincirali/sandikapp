import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/utils/tr_iyelik.dart';
import 'package:portfoy_takip/widgets/sandik_segment.dart';

import 'helpers/kaynak.dart';

/// 2026-10-08 web ekran görüntülerinde (gerçek uygulama, açık + koyu tema)
/// görülen tutarsızlıkların kilidi.
void main() {
  group('sayı ayrılma eki (%30\'undan)', () {
    for (final (n, ek) in [
      (1, 'inden'), (2, 'sinden'), (3, 'ünden'), (4, 'ünden'), (5, 'inden'),
      (6, 'sından'), (7, 'sinden'), (8, 'inden'), (9, 'undan'),
      (10, 'undan'), (20, 'sinden'), (30, 'undan'), (40, 'ından'),
      (50, 'sinden'), (60, 'ından'), (70, 'inden'), (80, 'inden'),
      (90, 'ından'), (100, 'ünden'), (73, 'ünden'), (0, 'ından'),
    ]) {
      test('$n → $ek', () => expect(trSayiAyrilmaEki(n), ek));
    }

    test('sabit "\'inden" kalmadı', () {
      final arb = ekranKaynagiSync('lib/l10n/app_tr.arb');
      expect(arb, isNot(contains("}'inden")));
      final serit = ekranKaynagiSync('lib/widgets/percentile_strip.dart');
      expect(serit, isNot(contains("'inden\"")));
    });
  });

  group('segment açık temada görünür', () {
    Future<List<BoxDecoration>> kutular(
        WidgetTester t, ThemeData tema, SandikPalette p) async {
      await t.pumpWidget(MaterialApp(
        theme: tema.copyWith(extensions: [p]),
        home: Scaffold(
          body: SandikSegment(
            adet: 2,
            secili: 0,
            onSec: (_) {},
            oge: (_, i, __) => Text('$i'),
          ),
        ),
      ));
      return t
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(SandikSegment),
              matching: find.byType(DecoratedBox)))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .toList();
    }

    testWidgets('açık: kabukta kenar, hapta kenar + gölge', (t) async {
      final d = await kutular(
          t, ThemeData(brightness: Brightness.light), SandikPalette.light);
      // `surface1` kabuk üstünde `surface2` hap: #FBFAF6 / #FFFFFF — ton
      // farkı tek başına görünmüyordu.
      final kabuk = d.firstWhere((b) => b.color == SandikPalette.light.surface1);
      final hap = d.firstWhere((b) => b.color == SandikPalette.light.surface2);
      expect(kabuk.border, isNotNull);
      expect(hap.border, isNotNull);
      expect(hap.boxShadow, isNotEmpty);
    });

    testWidgets('koyu: kabukta kenar (kart içinde de görünür), hap sade',
        (t) async {
      final d = await kutular(
          t, ThemeData(brightness: Brightness.dark), SandikPalette.dark);
      final kabuk = d.firstWhere((b) => b.color == SandikPalette.dark.surface1);
      final hap = d.firstWhere((b) => b.color == SandikPalette.dark.surface2);
      expect(kabuk.border, isNotNull);
      expect(hap.border, isNull);
      expect(hap.boxShadow, isNull);
    });
  });

  test('Ayarlar: tek anahtar dili ve tema yazı stili', () {
    final k = ekranKaynagiSync('lib/screens/settings_screen.dart');
    expect(k, isNot(contains('CupertinoSwitch(')),
        reason: 'Satırlar `Switch.adaptive` kullanır (Android Material).');
    expect(k, isNot(contains('activeTrackColor: context.c.amberFill')),
        reason: 'Açık track her anahtarda `amberText`.');
    // `_SettingsTile` CupertinoButton içinde ham `TextStyle` → Cupertino
    // yazı ailesi sızıyordu.
    final i = k.indexOf('class _SettingsTile ');
    final govde = k.substring(i, k.indexOf('\n}\n', i));
    expect(govde, isNot(contains('style: TextStyle(')));
  });
}
