import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/main.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/tur_filtre_cipleri.dart';

import 'helpers/kaynak.dart';

/// Seçici kuralı (seçici denetimi 2026-10-12, `docs/TASARIM_DILI.md` §4):
/// mod değiştirmek kayan segment (`SandikSegment`), liste süzmek tek süzme
/// çipi (`SandikFiltreCipi`), çoklu aç/kapa grafik çipi.
///
/// Kilitlenen:
/// - süzme ekranları ortak çipi kullanır (bayrak `goz_alici` açıkken);
/// - "seçili" bilgisi etiketle AYNI düğümde: dışta ayrı bir
///   `Semantics(selected:)` + içte etiketli `SandikTappable` VoiceOver'a iki
///   düğüm okutuyordu;
/// - Material'in sekme/çip seçicileri (`TabBar`, `ChoiceChip`) yalnız
///   bayrak kapalı eski yolda kalır; sayı yalnız azalabilir.
void main() {
  test('süzme ekranları ortak süzme çipini kullanır', () {
    for (final yol in [
      'lib/screens/add_watchlist_screen.dart',
      'lib/screens/all_transactions_screen.dart',
    ]) {
      expect(ekranKaynagiSync(yol), contains('SandikFiltreCipi('),
          reason: yol);
    }
  });

  test('seçili bilgisi etiketle aynı düğümde (iç içe Semantics yok)', () {
    final desen = RegExp(
        r'Semantics\(\s*selected:\s*\w+,\s*child:\s*SandikTappable\(');
    for (final yol in [
      'lib/screens/add_watchlist_screen.dart',
      'lib/screens/all_transactions_screen.dart',
      'lib/widgets/sozlesme_formu_ortak.dart',
    ]) {
      expect(desen.hasMatch(ekranKaynagiSync(yol)), isFalse, reason: yol);
    }
  });

  test('Material sekme/çip seçicileri yalnız azalabilir', () {
    // 2026-10-12: karşılaştırma seçicisindeki TabBar ve geri bildirimdeki
    // ChoiceChip'in yalnız bayrak kapalı dalı kaldı.
    const tavan = {'TabBar(': 1, 'ChoiceChip(': 1};
    final kaynaklar = [
      for (final f in Directory('lib').listSync(recursive: true))
        if (f is File &&
            f.path.endsWith('.dart') &&
            !f.path.contains('generated'))
          f.readAsStringSync(),
    ];
    tavan.forEach((desen, ust) {
      final n = kaynaklar.fold<int>(
          0, (a, k) => a + RegExp(RegExp.escape(desen)).allMatches(k).length);
      expect(n, lessThanOrEqualTo(ust), reason: desen);
    });
  });

  testWidgets('süzme çipi: 44 pt, seçiliyken onay işareti ve tek düğüm',
      (t) async {
    final h = t.ensureSemantics();
    await t.pumpWidget(MaterialApp(
      theme: SandikApp.buildTheme(SandikPalette.dark, Brightness.dark),
      home: Scaffold(
        body: Center(
          child: Wrap(children: [
            SandikFiltreCipi(ad: 'Tümü', secili: true, onTap: () {}),
            SandikFiltreCipi(
                ad: 'Hisse',
                secili: false,
                onTap: () {},
                ikon: Icons.show_chart_rounded),
          ]),
        ),
      ),
    ));
    expect(t.getSize(find.byType(SandikFiltreCipi).first).height,
        greaterThanOrEqualTo(SandikTouch.min));
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    expect(find.byIcon(Icons.show_chart_rounded), findsOneWidget);
    expect(
      t.getSemantics(find.text('Tümü')),
      matchesSemantics(
        label: 'Tümü',
        isButton: true,
        isSelected: true,
        hasSelectedState: true,
        hasTapAction: true,
      ),
    );
    h.dispose();
  });
}
