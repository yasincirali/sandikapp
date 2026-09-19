import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Paylaşım çağrıları TEK kapıdan (`ShareCardService`) geçer.
///
/// İki üretim raporu aynı kökten geldi: share_plus, iOS'ta paylaşım sayfasını
/// `UIActivityViewController` ile açıyor ve popover sunan cihazlarda (iPad,
/// "iPad için tasarlandı" modunda Mac) **kaynak dikdörtgen verilmezse**
/// `FlutterError` fırlatıyor. Hata yakalanmazsa zone handler'ına düşüp
/// Crashlytics'e ÇÖKME olarak yazılıyor:
/// `StandardMethodCodec.decodeEnvelope → MethodChannelShare.share`.
///
/// 2026-09-16'da kart paylaşımı düzeltildi ama iki çağrı yeri gözden kaçtı
/// (ortak daveti, veri dışa aktarımı) — çünkü kural koda değil, o iki metoda
/// yazılmıştı. Bu test kuralı YERE bağlar: `Share.` yalnızca serviste
/// görünür, servisteki her çağrı dikdörtgeni iletir, her çağıran hatayı
/// raporlar.
void main() {
  const servisYolu = 'lib/services/share_card_service.dart';

  test('`Share.` çağrısı yalnızca ShareCardService içinde', () {
    final rx = RegExp(r'\bShare\.(share|shareXFiles|shareUri)\(');
    final sucustu = <String>[];
    for (final dosya in _dartDosyalari('lib')) {
      if (dosya.path.replaceAll(r'\', '/') == servisYolu) continue;
      final satirlar = dosya.readAsLinesSync();
      for (var i = 0; i < satirlar.length; i++) {
        if (_yorum(satirlar[i])) continue;
        if (rx.hasMatch(satirlar[i])) {
          sucustu.add('${dosya.path}:${i + 1}  ${satirlar[i].trim()}');
        }
      }
    }
    expect(
      sucustu,
      isEmpty,
      reason: 'Doğrudan çağrı `sharePositionOrigin` kuralını atlar ve iPad\'de '
          'çöker. `ShareCardService.shareText/shareImage/shareFile` kullan.',
    );
  });

  test('servisteki her Share. çağrısı sharePositionOrigin taşır', () {
    final kaynak = File(servisYolu)
        .readAsLinesSync()
        .where((l) => !_yorum(l))
        .join('\n');
    final cagriSayisi =
        RegExp(r'\bShare\.(share|shareXFiles|shareUri)\(').allMatches(kaynak).length;
    final dikdortgenSayisi =
        'sharePositionOrigin: origin'.allMatches(kaynak).length;
    expect(cagriSayisi, greaterThanOrEqualTo(3),
        reason: 'metin, görsel ve dosya yolları');
    expect(
      dikdortgenSayisi,
      cagriSayisi,
      reason: 'dikdörtgensiz kalan her çağrı iPad\'de fırlatır',
    );
  });

  test('paylaşımı başlatan EKRAN hatayı yakalar, raporlar ve söyler', () {
    // Kapsam ekran/widget: hatayı kullanıcıya söyleyecek olan yüzeydir.
    // `data_export_service` gibi ara servisler hatayı YUKARI verir (yutmaz);
    // mesaj ve rapor, paylaşımı başlatan ekranın işidir — dışa aktarımda
    // `settings_screen`, davet kodunda `profile_screen`.
    final rx = RegExp(
      r'(ShareCardService\.share(Text|Image|File)|exportAndShare)\(',
    );
    for (final dosya in [
      ..._dartDosyalari('lib/screens'),
      ..._dartDosyalari('lib/widgets'),
    ]) {
      final kaynak = dosya.readAsStringSync();
      if (!rx.hasMatch(kaynak)) continue;
      expect(
        kaynak.contains('CrashReporter.report('),
        isTrue,
        reason: '${dosya.path}: paylaşım hatası Crashlytics\'e bildirilmeli',
      );
      expect(
        kaynak.contains('friendlyError(') || kaynak.contains('showAppError('),
        isTrue,
        reason: '${dosya.path}: kullanıcıya ham hata gösterilmez',
      );
    }
  });

  test('veri dışa aktarımı dikdörtgeni çağırandan alır', () {
    final servis =
        File('lib/services/data_export_service.dart').readAsStringSync();
    expect(servis.contains('Rect? paylasimKaynagi'), isTrue);
    expect(servis.contains('origin: paylasimKaynagi'), isTrue);
    final ekran = File('lib/screens/settings_screen.dart').readAsStringSync();
    expect(
      ekran.contains('exportAndShare(paylasimKaynagi:'),
      isTrue,
      reason: 'ekran dokunulan karonun dikdörtgenini iletmeli',
    );
  });
}

bool _yorum(String satir) {
  final t = satir.trimLeft();
  return t.startsWith('//') || t.startsWith('*') || t.startsWith('/*');
}

Iterable<File> _dartDosyalari(String kok) sync* {
  for (final e in Directory(kok).listSync(recursive: true)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
