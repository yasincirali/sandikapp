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

  // 2026-10-08: eski ana ekran şeridi (`RealReturnStrip`/`RealReturnBadge`)
  // 2026-09-21'den beri çağrılmıyordu ve silindi; aynı iki sayı artık
  // Bugün kartında yazılır, kural oraya taşındı. 2026-10-09 benchmark
  // düzeni: blok `_AlimGucuKutusu` — ana satır "100 liran bugün 81 lira"
  // bilinçli TAM SAYI (okunurluk; yüzde değil, lira), iki yüzde alt satırda
  // iki ondalıkla; doğrulanabilirlik o iki yüzdeyle sağlanır.
  String kiyasBlogu() {
    final src = kodu('lib/widgets/bugun_karti.dart');
    final i = src.indexOf('class _AlimGucuKutusu');
    expect(i, greaterThanOrEqualTo(0));
    final j = src.indexOf('class ', i + 1);
    return src.substring(i, j < 0 ? src.length : j);
  }

  test('Bugün kartı TÜFE ve nominali iki ondalıkla yazar', () {
    final blok = kiyasBlogu();
    // Ayrıntı satırı `fmtPct` (varsayılan 2 hane) ile yazılır; ekran
    // okuyucu metni de aynı iki sayıyı aynı biçimle okur.
    expect(blok.contains('fmtPct(reel.nominal)'), isTrue,
        reason: 'TÜFE yuvarlanmamalı — TÜİK rakamıyla karşılaştırılabilmeli.');
    expect(blok.contains('fmtPct(reel.inflation)'), isTrue);
    expect(blok.contains('digits: 0'), isFalse,
        reason: 'Yüzdede tam sayıya yuvarlama YOK — bir arızayı gizlemişti.');
    expect(RegExp(r'fmtNum\(reel\.(nominal|inflation)').hasMatch(blok), isFalse,
        reason: 'İki yüzde fmtPct ile, hane düşürülmeden.');
  });
}
