import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bist_calendar.dart';

/// İstemci ve sunucu aynı tatil takvimini taşır (Ar-Ge 29 Eki #1).
///
/// Ayrışınca kilit ekranı uygulama kapalıyken "Canlı" (sunucu), açılınca
/// "Piyasa kapalı" (istemci) diyordu: 29 Ekim 2026 bütün gün. Bu test
/// sunucunun `BIST_TATIL` nesnesini JSON olarak okur ve iki takvimi her
/// gün için karşılaştırır.
void main() {
  final kaynak =
      File('supabase/functions/_shared/bist_tatil.ts').readAsStringSync();
  final bas = kaynak.indexOf('export const BIST_TATIL = ');
  final son = kaynak.indexOf(' as const;', bas);
  final veri = jsonDecode(
    kaynak.substring(bas + 'export const BIST_TATIL = '.length, son),
  ) as Map<String, dynamic>;

  List<String> liste(String anahtar, [int? yil]) {
    final v = veri[anahtar];
    if (yil == null) return (v as List).cast<String>();
    return ((v as Map)['$yil'] as List?)?.cast<String>() ?? const [];
  }

  String ayGun(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  test('son kapsanan yıl iki tarafta aynı', () {
    expect(veri['sonKapsananYil'], BistTakvimi.sonKapsananYil);
  });

  test('her gün için tatil ve yarım gün iki tarafta aynı', () {
    // Geçen yıldan kapsanmayan ilk yılın sonuna kadar: kapsanmayan yılda
    // iki taraf da dinî bayramı bilmemeli.
    var d = DateTime(BistTakvimi.sonKapsananYil - 1, 1, 1);
    final bitis = DateTime(BistTakvimi.sonKapsananYil + 1, 12, 31);
    while (!d.isAfter(bitis)) {
      final g = ayGun(d);
      final sunucuTatil = liste('sabitTamGun').contains(g) ||
          liste('diniTamGun', d.year).contains(g);
      final sunucuYarim = liste('sabitYarimGun').contains(g) ||
          liste('diniYarimGun', d.year).contains(g);
      expect(BistTakvimi.tatilMi(d), sunucuTatil, reason: 'tatil $d');
      expect(BistTakvimi.yarimGunMu(d), sunucuYarim, reason: 'yarım gün $d');
      d = DateTime(d.year, d.month, d.day + 1);
    }
  });

  test('yarım gün kapanışı iki tarafta aynı', () {
    final ts =
        File('supabase/functions/_shared/piyasa_takvimi.ts').readAsStringSync();
    expect(ts, contains('YARIM_GUN_KAPANIS_DK = 12 * 60 + 30'));
    expect(BistTakvimi.yarimGunKapanisDk, 12 * 60 + 30);
  });
}
