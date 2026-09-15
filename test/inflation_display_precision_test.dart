import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// TÜFE ve nominal getiri ekranda YUVARLANMADAN yazılmalı.
///
/// **Neden ratchet gerekiyor.** 2026-09-14'te ana ekran şeridi `digits: 0`
/// kullanıyordu ve TÜFE %31,51 ekranda "%32" görünüyordu. İki ayrı zarar:
///
///   1. Kullanıcı sayıyı TÜİK'in açıkladığı rakamla karşılaştırıyor ve
///      tutmadığını görüyor — rozetin varlık sebebi doğrulanabilir olmak.
///   2. Daha sinsisi: yuvarlama BİR ARIZAYI GİZLEDİ. Enflasyon penceresi
///      bir ay eksik sayıldığı için gelen %27,68 de, doğrusu olan %31,51
///      de tam sayıya yuvarlanınca "makul" görünüyordu. Hata ancak ham
///      sayı tam yazıldığında gözle yakalanabilir.
///
/// `digits: 0` bu yüzeyde bir daha belirmesin diye kaynağa bakılıyor;
/// widget testi kurmak Remote Config + auth + leaderboard sahtesi
/// gerektiriyor ve asıl korunacak şey tek bir sayı: ondalık hane.
void main() {
  /// Kaynağı YORUMSUZ ve boşlukları tekilleştirilmiş hâlde verir.
  ///
  /// İki tuzak birden: `dart format` satır sonlarını değiştirdiğinde test
  /// sahte kırılıyor (boşluk tekilleştirmesi onu çözer), ve yorum METNİ
  /// aranan kalıbı içerebiliyor — bu dosyanın kendi gerekçe yorumunda
  /// `digits: 0` geçiyor ve yasak kontrolü ona takılmıştı.
  String kodu(String yol) {
    final satirlar = File(yol).readAsLinesSync().where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///');
    });
    return satirlar.join(' ').replaceAll(RegExp(r'\s+'), ' ');
  }

  test('reel getiri şeridi TÜFE ve nominali iki ondalıkla yazar', () {
    final src = kodu('lib/widgets/real_return_strip.dart');

    // İfadenin ADINA değil, BİÇİMİNE bakılır: `veri.inflation` 2026-09-15'te
    // `inflation` oldu (görsel gövde `RealReturnBadge`'e ayrıldı) ve
    // isme bağlı kalıp davranış hiç değişmediği hâlde testi kırdı.
    // Korunacak şey tek: o iki sayının iki ondalıkla yazılması.
    expect(
      src.contains(RegExp(r'fmtNum\([\w.]*inflation, digits: 2\)')),
      isTrue,
      reason: 'TÜFE yuvarlanmamalı — TÜİK rakamıyla karşılaştırılabilmeli.',
    );
    expect(
      src.contains(RegExp(r'fmtNum\([\w.]*nominal, digits: 2\)')),
      isTrue,
      reason: 'Nominal getiri TÜFE ile aynı hassasiyette olmalı.',
    );
    expect(
      src.contains('digits: 0'),
      isFalse,
      reason: 'Şeritte tam sayıya yuvarlama YOK — bir arızayı gizlemişti.',
    );
  });

  test('puan farkı da yuvarlanmaz — çıkarma elle doğrulanabilmeli', () {
    final src = kodu('lib/widgets/real_return_strip.dart');

    // Kullanıcı "nominal − TÜFE = puan farkı" çıkarmasını yapıyor; üç sayı
    // aynı hassasiyette olmazsa çıkarma tutmuyor.
    expect(src.contains('fmtNum(puan.abs(), digits: 2)'), isTrue);
  });
}
