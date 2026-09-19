import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Ratchet: `onPressed: _x` / `onTap: _x` ile bağlanan async handler'lar.
///
/// Böyle bir handler'ın döndürdüğü future'ı KİMSE beklemez. Gövdede `await`
/// varsa ve genel bir `try` yoksa, ağ hatası zone handler'ına düşer ve
/// Crashlytics ÇÖKME sayar; kullanıcı da işlemin olmadığını öğrenmez.
/// `add_asset_screen._save` 2026-09-19'da böyleydi (kapandı). Bu test aynı
/// deseni ekranların tamamında tarar; `arka_plan_hatasi_fatal_degil_test`
/// ailesinin "ikinci yüzü" (TECHNICAL_DEBT).
///
/// Sezgisel tarama: yalnızca gövdesinde bir servis/provider çağrısı olan
/// handler'lar sayılır (dialog/tarih seçici gibi yerel işler fırlatmaz).
/// Yanlış pozitif çıkarsa `_izinli`ye GEREKÇEYLE ekle; sessizce genişletme.
void main() {
  test('await eden buton handler\'ı try olmadan servis çağırmaz', () {
    final baglayici = RegExp(
      r'on(?:Pressed|Tap|Changed|Submitted|LongPress|Refresh|Confirm|Save)\s*:\s*(_\w+)\b',
    );
    final servis = RegExp(r'Service\.instance\.|Service\(\)\.|\.notifier\)\.');
    final sucustu = <String>[];

    for (final dosya in _dartDosyalari('lib/screens')
        .followedBy(_dartDosyalari('lib/widgets'))) {
      final kaynak = dosya.readAsStringSync();
      final adlar = baglayici.allMatches(kaynak).map((m) => m.group(1)!).toSet();
      for (final ad in adlar) {
        final govde = _asyncGovde(kaynak, ad);
        if (govde == null) continue;
        if (!govde.contains('await ')) continue;
        if (govde.contains('try {') || govde.contains('try{')) continue;
        if (!servis.hasMatch(govde)) continue;
        final anahtar = '${_kisa(dosya.path)}#$ad';
        if (_izinli.containsKey(anahtar)) continue;
        sucustu.add(anahtar);
      }
    }

    expect(
      sucustu,
      isEmpty,
      reason: 'Bu handler\'ların future\'ını kimse beklemiyor; hata zone '
          'handler\'ına düşer. try/catch ile `friendlyError` göster ve '
          '`CrashReporter.report` et, ya da gerekçeyle `_izinli`ye ekle.',
    );
  });
}

/// Gerekçeli istisnalar — her satır bir karardır.
const _izinli = <String, String>{
  'main_navigation_screen.dart#_showAddAsset':
      'Yalnızca navigasyon; ağ işi zaten CrashReporter.arkaPlan içinde.',
  'bulk_add_asset_screen.dart#_confirmClear':
      'Onay diyaloğu + senkron sepet temizliği; await eden tek şey diyalog.',
};

String _kisa(String yol) => yol.replaceAll('\\', '/').split('/').last;

/// `Future<...> ad(...) async {` gövdesini parantez sayarak alır.
String? _asyncGovde(String kaynak, String ad) {
  final bas = RegExp('Future<[^>]*>\\s+$ad\\s*\\([^)]*\\)\\s*async\\s*\\{')
      .firstMatch(kaynak);
  if (bas == null) return null;
  var derinlik = 1;
  var i = bas.end;
  while (i < kaynak.length && derinlik > 0) {
    final c = kaynak[i];
    if (c == '{') derinlik++;
    if (c == '}') derinlik--;
    i++;
  }
  return kaynak.substring(bas.end, i);
}

Iterable<File> _dartDosyalari(String kok) sync* {
  for (final e in Directory(kok).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
