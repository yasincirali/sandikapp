import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

import 'helpers/kaynak.dart';

/// Bugün kartının hareket satırı cihazda "₺13 · %%0,00 eksi" basıyordu
/// (2026-09-21, ekran görüntüsü): şablon yüzde işaretini kendisi taşır
/// (TR `%{pct}`, EN `{pct}%`), `fmtPct` de taşıyınca ikilendi.
void main() {
  test('todayUp/todayDown tek yüzde işareti üretir (TR ve EN)', () {
    final tr = lookupAppLocalizations(const Locale('tr'));
    final en = lookupAppLocalizations(const Locale('en'));
    final yuzde = fmtNum(0.42);
    for (final m in [
      tr.todayUp('₺13', yuzde),
      tr.todayDown('₺13', yuzde),
      en.todayUp('₺13', yuzde),
      en.todayDown('₺13', yuzde),
    ]) {
      expect('%'.allMatches(m).length, 1, reason: m);
      expect(m, isNot(contains('%%')));
    }
  });

  test('kart şablona fmtPct vermez', () {
    final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart');
    expect(src, isNot(matches(RegExp(r'today(Up|Down)\([^)]*fmtPct'))),
        reason: 'fmtPct zaten % taşır; şablona çıplak sayı (fmtNum) ver.');
  });
}
