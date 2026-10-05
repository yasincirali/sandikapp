import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/user_model.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/ortak_secici.dart';

import 'helpers/kaynak.dart';

/// Segment ve seçicilerin ekran okuyucu sözleşmesi (2026-09-29 emülatör
/// testi #28): etiket + SEÇİLİ durumu + ETKİN dokunma eylemi.
///
/// Bulunan kalıp: `Semantics(label, selected) + ExcludeSemantics(düğme)`.
/// `ExcludeSemantics` düğmenin kendi dokunma eylemini de siliyordu — düğüm
/// okunuyor, "seçili" deniyor ama TalkBack'te etkinleştirilemiyordu.
/// Tema/seviye/dil/baz para segmentleri ise seçili durumu hiç bildirmiyordu.
Widget _kabuk(Widget child) => MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: const [SandikPalette.dark],
      ),
      home: Scaffold(body: Center(child: SizedBox(width: 360, child: child))),
    );

AppUser _ortak(String id, String ad) => AppUser(
    id: id, email: '$id@x.com', displayName: ad, createdAt: DateTime(2026));

void main() {
  testWidgets('SandikTappable(selected) seçili durumu ve eylemi bildirir',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(_kabuk(Row(children: [
      SandikTappable(
          semanticLabel: 'Koyu tema',
          selected: true,
          onTap: () {},
          child: const SizedBox(width: 60, height: 44)),
      SandikTappable(
          semanticLabel: 'Açık tema',
          selected: false,
          onTap: () {},
          child: const SizedBox(width: 60, height: 44)),
    ])));
    expect(
        tester.getSemantics(find.bySemanticsLabel('Koyu tema')),
        isSemantics(
            isButton: true,
            hasSelectedState: true,
            isSelected: true,
            hasTapAction: true));
    expect(
        tester.getSemantics(find.bySemanticsLabel('Açık tema')),
        isSemantics(
            hasSelectedState: true, isSelected: false, hasTapAction: true));
    semantics.dispose();
  });

  for (final cift in <(String, Widget Function(ValueChanged<String?>))>[
    // 2026-10-05: eski iki kabuk (`ModernTabSelector`, `KapsamKisiSecici`)
    // bayrak `tek_ortak_secici` ile silindi; tek kabuk sınanır.
    (
      'OrtakSecici',
      (f) => OrtakSecici(
          partners: [_ortak('p1', 'Ayşe Y'), _ortak('p2', 'Can K')],
          selectedId: '',
          onChanged: f)
    ),
  ]) {
    testWidgets('${cift.$1}: "Kimin portföyü" segmentleri etkin ve seçili '
        'durumlu', (tester) async {
      final semantics = tester.ensureSemantics();
      String? secilen = 'baslangic';
      await tester.pumpWidget(_kabuk(cift.$2((v) => secilen = v)));

      final ben = find.bySemanticsLabel('Kimin portföyü: Ben');
      final birlikte = find.bySemanticsLabel('Kimin portföyü: Birlikte');
      final ortaklar = find.bySemanticsLabel('Kimin portföyü: Ortaklar');
      expect(
          tester.getSemantics(ben),
          isSemantics(
              isButton: true, isSelected: true, hasTapAction: true));
      expect(tester.getSemantics(birlikte),
          isSemantics(isSelected: false, hasTapAction: true));
      expect(tester.getSemantics(ortaklar),
          isSemantics(hasTapAction: true),
          reason: 'Çok ortakta menü segmenti de ekran okuyucudan açılmalı.');

      // Ekran okuyucunun "çift dokun"u = semantik tap eylemi.
      tester.semantics.tap(find.semantics.byLabel('Kimin portföyü: Birlikte'));
      await tester.pumpAndSettle();
      expect(secilen, isNull, reason: 'Birlikte = null sözleşmesi');

      tester.semantics.tap(find.semantics.byLabel('Kimin portföyü: Ortaklar'));
      await tester.pumpAndSettle();
      expect(find.text('Ayşe'), findsWidgets,
          reason: 'Ortak menüsü semantik eylemle açılmalı.');
      semantics.dispose();
    });
  }

  test('Ayarlar segmentleri seçili durumu SandikTappable\'a verir', () {
    final k = ekranKaynagiSync('lib/screens/settings_screen.dart');
    for (final ifade in [
      'selected: current == mode',
      'selected: current == birim',
      'selected: current == s',
      'selected: current == kod',
    ]) {
      expect(k, contains(ifade), reason: '$ifade eksik');
    }
  });

  test('Portföy: karşılaştır/sırala düğmeleri ve kart oku etiketli', () {
    final k = ekranKaynagiSync('lib/screens/portfolio_screen.dart');
    expect(k, contains('semanticLabel: context.l10n.compare'));
    expect(k, contains('semanticLabel: context.l10n.sortAssetsSemantics'));
    expect(k, contains('context.l10n.showDetailsSemantics'));
    expect(k, contains('expanded: expanded'));
  });
}
