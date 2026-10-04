/// Yasal metin INSERT üreteci — migration'da OLMAYAN katalog metinlerinin
/// `insert into public.yasal_metinler ...` satırlarını yazar.
///
/// ## Neden `flutter test` ile koşan bir "test"
/// Katalog (`YasalMetinKatalogu`) metinleri ekran sabitlerinden ve l10n'dan
/// okur; bunlar `package:flutter`'a bağlı, düz `dart run` ile yüklenemez.
/// Bu dosya `tool/` altında (CI `test/`'i koşar) ve `arac` etiketli
/// (`dart_test.yaml`'da varsayılan atlanır) — iki ayrı emniyet: yanlışlıkla
/// koşsa bile yalnız `build/` altına dosya yazar, hiçbir şeyi kırmaz.
///
/// ## Kullanım (metin değişti, kilit testi kırıldı)
/// 1. Değişen metnin sürümünü artır (ör. `LeaderboardService.zirveRizaMetniSurumu`,
///    `YasalMetinKatalogu.belgeSurumu`, kutular için `disclaimerVersion`
///    DEĞİL — kutu sürümünü katalogda ayır).
/// 2. `flutter test --run-skipped --tags arac tool/yasal_metin_uret_test.dart`
/// 3. `build/yasal_metin_ekleri.sql`'i yeni bir migration'a koy (iki
///    sunucuya birlikte, `supabase-deploy.yml` hedef `ikisi`).
/// 4. `flutter test test/yasal_metin_kilidi_test.dart` yeşil olmalı.
///
/// `YASAL_CIKTI=yol` ile başka dosyaya yazılır; `YASAL_HEPSI=1` migration'da
/// olanlar dahil hepsini yazar (0102 böyle üretildi).
@Tags(['arac'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/yasal_metin_katalogu.dart';

import '../test/helpers/yasal_migration.dart';

void main() {
  test('eksik yasal metin INSERT\'lerini üret', () {
    final ortam = Platform.environment;
    final hepsi = ortam['YASAL_HEPSI'] == '1';
    final mevcut = {for (final m in migrationMetinleri()) m.anahtar};
    final yazilacak = [
      for (final k in YasalMetinKatalogu.tumu())
        if (hepsi || !mevcut.contains(k.anahtar)) k,
    ];
    final cikti = File(ortam['YASAL_CIKTI'] ?? 'build/yasal_metin_ekleri.sql');
    cikti.parent.createSync(recursive: true);
    final buf = StringBuffer(
        '-- tool/yasal_metin_uret_test.dart çıktısı — elle düzenleme.\n');
    for (final k in yazilacak) {
      buf
        ..writeln()
        ..writeln('-- ${k.anahtar}  (${k.baslik})')
        ..write(k.sqlInsert());
    }
    cikti.writeAsStringSync(buf.toString());
    // ignore: avoid_print
    print('${yazilacak.length} metin → ${cikti.path}'
        '${yazilacak.isEmpty ? ' (eksik yok)' : ''}');
    for (final k in yazilacak) {
      // ignore: avoid_print
      print('  ${k.anahtar}  ${k.hash}');
    }
  });
}
