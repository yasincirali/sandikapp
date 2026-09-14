import 'dart:io';

/// Bir Dart dosyasını `part` dosyalarıyla BİRLİKTE okur.
///
/// Kaynak tarayan testler (`readAsStringSync` + `contains`) ekranı tek dosya
/// sanıyordu. 2026-09-14'te iki dev ekran part dosyalarına bölündü
/// (`portfolio_performance/`, `asset_detail/`); aranan desen artık başka bir
/// dosyada olabilir. Bu yardımcı ana dosyayı ve `part '...'` ile bağladığı
/// her dosyayı art arda ekler — test "ekran" derken kütüphanenin tamamını
/// görür, bölme öncesiyle aynı anlam.
String ekranKaynagiSync(String yol) {
  final ana = File(yol);
  final metin = ana.readAsStringSync();
  final buf = StringBuffer(metin);
  final dizin = ana.parent.path;
  for (final m in RegExp(r"^part '([^']+)';", multiLine: true).allMatches(metin)) {
    final parca = File('$dizin/${m.group(1)}');
    if (parca.existsSync()) {
      buf.writeln();
      buf.write(parca.readAsStringSync());
    }
  }
  return buf.toString();
}

Future<String> ekranKaynagi(String yol) async => ekranKaynagiSync(yol);
