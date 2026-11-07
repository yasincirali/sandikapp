import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Kapsam kilidi (yasin 2026-11-07): *"varolan tüm raporlarda kapsadığı ve
/// bilgileri verilen dataların zaman aralığı belirtilmeli raporlarda,
/// özetlerde vs kafa karışıklığı olmamalı"*.
///
/// Her rapor/özet yüzeyi kapsadığı günleri ORTAK biçimleyiciyle
/// (`fmtTarihAraligi`) yazar; yeni bir rapor yüzeyi eklenirse buraya
/// eklenir. Kaynak tarar: kapsam satırı silinirse ya da yüzey kendi tarih
/// kalıbına dönerse kırılır.
void main() {
  // Ekran / widget yüzeyleri: aralığı ortak biçimleyiciyle yazar.
  const yuzeyler = {
    'lib/screens/aylik_rapor_screen.dart': 'raporKapsam',
    'lib/screens/hafta_ozeti_screen.dart': 'raporKapsam',
    'lib/screens/recap_screen.dart': 'raporKapsam',
    'lib/widgets/portfoy_yorumu_karti.dart': 'fmtTarihAraligi',
    'lib/services/aylik_rapor_disa_aktarim.dart': 'raporKapsam',
    'lib/services/disa_aktarim/yorum_notu_pdf.dart': 'fmtTarihAraligi',
  };

  for (final MapEntry(key: yol, value: imza) in yuzeyler.entries) {
    test('$yol kapsamı açık tarihle yazar', () {
      final k = ekranKaynagiSync(yol);
      expect(k, contains('fmtTarihAraligi('), reason: yol);
      expect(k, contains(imza), reason: yol);
    });
  }

  test('her rapor belgesi (PDF/Excel) kapsam satırı taşır', () {
    final eksik = <String>[];
    for (final f in Directory('lib/services/disa_aktarim')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))) {
      final k = f.readAsStringSync();
      // `RaporBelgesi(` kurucusu çağrılan her yerde `kapsam:` olmalı.
      final kurucular = RegExp(r'return RaporBelgesi\(').allMatches(k).length;
      if (kurucular == 0) continue;
      final kapsam =
          RegExp(r'^\s+kapsam:', multiLine: true).allMatches(k).length;
      if (kapsam < kurucular) eksik.add(f.path);
    }
    expect(eksik, isEmpty, reason: 'kapsamsız rapor belgesi: $eksik');
  });

  test('haftalık ve TÜFE bildirimi hangi günleri anlattığını yazar', () {
    final h =
        File('supabase/functions/weekly-summary/index.ts').readAsStringSync();
    expect(h, contains('kisaAralik(fromMs, toMs)'));
    final c =
        File('supabase/functions/calendar-nudge/index.ts').readAsStringSync();
    expect(c, contains('buildInflationMessage(aylik, yillik, sonPeriod)'));
  });
}
