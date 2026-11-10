import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Kodda hiç geçmeyen (.arb'da duran ama `lib/` okumayan) çeviri anahtarı
/// sayısı YALNIZ AZALABİLİR.
///
/// ## Neden (Ar-Ge 7 Kas 18:06 #4, rapor 1830 YAP)
/// `app_tr.arb`'ın ~%5'i ölüydü (158 anahtar silindi): her biri iki dilde
/// çeviri bakımı, gen-l10n çıktısında boş getter ve metin düzeltilirken
/// yanlış anahtarı değiştirme riski. Ekran kalkınca anahtarı bırakmak
/// sessizdir; bu kilit onu görünür kılar (design_token_leak deseni).
///
/// ## Ölçü
/// Anahtar adı `lib/` altında (üretilen `lib/l10n/generated/` hariç)
/// tanımlayıcı olarak geçmiyorsa ölü sayılır. Getter'lar dinamik çağrılamaz
/// (Dart'ta yansıma yok), o yüzden ad araması kesindir.
///
/// ## Kalanlar sıfır (10 Kas 2026)
/// 7 Kas'ta bırakılan 9 anahtar (`breakdownUpAmount`, `breakdownDownAmount`,
/// `cpiWindowNote`, `notificationsUpper`, `assetDeleted`, `nActiveAlerts`,
/// `dataExported`, `todayUp`, `todayDown`) yalnız testlerin okuduğu
/// metinlerdi; ekranda karşılıkları yoktu. Silindi, onları okuyan test
/// satırları kaldırıldı ya da canlı anahtara (`settingsNotifications`)
/// çevrildi. Tavan artık sıfır: test için anahtar tutulmaz.
void main() {
  test('ölü .arb anahtarı sayısı artmamalı', () {
    final sozluk = jsonDecode(File('lib/l10n/app_tr.arb').readAsStringSync())
        as Map<String, dynamic>;
    final anahtarlar = sozluk.keys.where((k) => !k.startsWith('@'));

    final tanimlayicilar = <String>{};
    final kimlik = RegExp(r'[A-Za-z_]\w*');
    for (final f in Directory('lib').listSync(recursive: true)) {
      final yol = f.path.replaceAll(r'\', '/');
      if (f is! File || !yol.endsWith('.dart')) continue;
      if (yol.contains('lib/l10n/generated/')) continue;
      final metin = ekranKaynagiSync(f.path);
      for (final m in kimlik.allMatches(metin)) {
        tanimlayicilar.add(m.group(0)!);
      }
    }

    final olu = [
      for (final k in anahtarlar)
        if (!tanimlayicilar.contains(k)) k,
    ];
    // 2026-11-07: 167 → 9; 2026-11-10: 9 → 0. Ölü anahtar yok.
    expect(olu, isEmpty,
        reason: 'Kullanılmayan anahtarı iki .arb\'dan sil ve gen-l10n koş:\n'
            '${olu.join('\n')}');
  });

  test('iki .arb aynı anahtar kümesini taşır', () {
    Set<String> oku(String yol) =>
        (jsonDecode(File(yol).readAsStringSync()) as Map<String, dynamic>)
            .keys
            .where((k) => !k.startsWith('@'))
            .toSet();
    expect(oku('lib/l10n/app_en.arb'), oku('lib/l10n/app_tr.arb'));
  });
}
