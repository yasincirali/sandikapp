import 'dart:convert';
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

/// `lib/l10n/app_tr.arb` içindeki bir anahtarın TÜRKÇE metni.
///
/// 3.20 sonrası kaynak tarayan testler ekranda ham metin bulamaz; metin
/// sözlüğe taşındı. "Kullanıcıya şu söyleniyor" iddiası iki parçaya ayrılır:
/// ekran doğru ANAHTARI kullanıyor mu (kaynakta `l10n.anahtar`) ve o anahtarın
/// metni hâlâ o şeyi söylüyor mu (bu yardımcı). İkisi birden kontrol edilince
/// iddia bölme öncesiyle aynı gücü korur.
String trMetni(String anahtar) {
  final ham = File('lib/l10n/app_tr.arb').readAsStringSync();
  final sozluk = jsonDecode(ham) as Map<String, dynamic>;
  final deger = sozluk[anahtar];
  if (deger is! String) {
    throw StateError('app_tr.arb içinde "$anahtar" yok.');
  }
  return deger;
}
