import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `_IndicatorRow` çip yerleşimi — "ÖNERİLEN" ve "PREMIUM" rozetleri.
///
/// Denetimde (2026-08-10) iki sorun bulundu:
///
/// 1. Çip rengi sabit `Colors.green` idi; temayı takip etmiyordu ve light
///    yüzeyde 2.78:1 veriyordu (AA eşiği 4.5:1). Palet `gain`i 5.37:1.
/// 2. "ÖNERİLEN" bloğu premium/normal dalları için BİREBİR iki kez
///    yazılmıştı. Dallar karşılıklı dışlayıcı olduğu için görsel bir hata
///    üretmiyordu ama kopya kod, birinde yapılan düzeltmenin diğerinde
///    unutulmasına açıktı — nitekim renk düzeltmesinde tam olarak bu riske
///    girildi.
///
/// Birleştirme sırasında asıl risk **boşluk**tur: iki çip yan yana
/// göründüğünde araya tek `SizedBox(width: 6)` girmeli. Bu test o
/// değişmezi kaynak üzerinden kilitler.
///
/// `_IndicatorRow` private olduğu için widget testiyle kurulamaz; ekranın
/// tamamını ayağa kaldırmak ise Supabase + provider zinciri ister. Bu yüzden
/// denetim kaynak taraması olarak yapılır.
void main() {
  late String src;

  setUpAll(() {
    // Yorumlar çıkarılır: bu dosyadaki açıklama notları "ÖNERİLEN" ve
    // `Colors.green` sözcüklerini bilerek anıyor ve ham metin taraması
    // onları gerçek kullanım sanıyordu.
    src = File('lib/screens/signal_settings_screen.dart')
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
  });

  test('"ÖNERİLEN" çipi tek yerde kurulur', () {
    final count = 'ÖNERİLEN'.allMatches(src).length;
    expect(count, 1,
        reason: 'Çip iki dalda kopyalanmış olabilir. Kopya kod, renk/erişim '
            'düzeltmelerinin yalnızca birine uygulanmasına yol açar.');
  });

  test('çipler arasında çift boşluk bırakılmaz', () {
    // Boşluğu yalnızca PREMIUM tarafı sahiplenir; "ÖNERİLEN" tarafına da
    // eklenirse ikisi birlikte göründüğünde araya 12pt girer.
    final spacers = RegExp(
      r'if \(showPremiumChip && recommended\) const SizedBox\(width: 6\)',
    ).allMatches(src).length;
    expect(spacers, 1,
        reason: 'Çipler arası boşluk tek bir koşuldan gelmeli.');

    expect(
      src.contains(
          'if (IndicatorId.premium.contains(id)) const SizedBox(width: 6)'),
      isFalse,
      reason: '"ÖNERİLEN" tarafına eklenen boşluk, PREMIUM tarafındaki '
          'boşlukla toplanıp çift aralık üretir.',
    );
  });

  test('çip renkleri palet token\'ından gelir', () {
    // Ham `Colors.green` geri gelirse yakala. Genel tarama
    // light_mode_contrast_test içinde; bu, ekrana özel ikinci bir kilit.
    expect(src.contains('Colors.green'), isFalse,
        reason: 'Anlamsal renk `context.c.gain` olmalı — sabit ton temayı '
            'takip etmez ve light modda okunmaz.');
    expect(src.contains('context.c.gain'), isTrue);
  });
}
