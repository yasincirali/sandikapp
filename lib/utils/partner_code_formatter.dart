import 'package:flutter/services.dart';

/// Ortaklık kodu giriş biçimlendiricisi (XXXXX-XXXXX).
///
/// Sorun: Kod alanında hiçbir `inputFormatters` yoktu. Kullanıcıdan
/// tireyi kendisinin yazması bekleniyordu; yazmadığında ya da boşluk
/// bıraktığında istemci tarafındaki
/// `RegExp(r'^([A-Z2-9]{5}-[A-Z2-9]{5})$')` kontrolü kodu reddedip
/// "Geçersiz kod formatı" gösteriyordu — kod aslında doğruyken.
///
/// Ayrıca üretim alfabesi karışabilecek karakterleri (0, 1, I, O)
/// bilerek dışlıyor — yani geçerli bir kod bunları asla içermez.
/// Kullanıcı yine de yazarsa bu karakterler **düşürülür**; otomatik
/// bir düzeltme (0→O gibi) YAPILMAZ, çünkü alfabede ne 0 ne O var:
/// hangisinin kastedildiği tahmin edilemez ve yanlış tahmin sessizce
/// bozuk bir kod üretir. Düşürmek, hatanın kullanıcıya görünür
/// kalmasını sağlar.
///
/// Davranış:
///   - Küçük harf → büyük harf,
///   - Alfabe dışı her karakter (0, 1, I, O, boşluk, noktalama) düşer,
///   - 5. karakterden sonra tire otomatik eklenir,
///   - En fazla 10 karakter (tire hariç) kabul edilir,
///   - İmleç metnin sonuna taşınmaz; kullanıcının düzenlediği yerde kalır.
class PartnerCodeInputFormatter extends TextInputFormatter {
  /// auth_service.dart `generatePartnerCode` ile aynı alfabe.
  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  static const _groupLength = 5;
  static const _maxChars = 10;

  /// Ham girdiden yalnızca geçerli kod karakterlerini süzer.
  static String sanitize(String input) {
    final buffer = StringBuffer();
    var count = 0;
    for (final ch in input.toUpperCase().split('')) {
      if (count >= _maxChars) break;
      if (_alphabet.contains(ch)) {
        buffer.write(ch);
        count++;
      }
    }
    return buffer.toString();
  }

  /// Süzülmüş karakterleri XXXXX-XXXXX biçimine sokar.
  static String format(String input) {
    final clean = sanitize(input);
    if (clean.length <= _groupLength) return clean;
    return '${clean.substring(0, _groupLength)}-${clean.substring(_groupLength)}';
  }

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = format(newValue.text);

    // İmleci, kullanıcının yazdığı konuma göre yeniden hesapla:
    // imlecin SOLUNDA kalan geçerli karakter sayısını koru, sonra
    // biçimlenmiş metinde o kadar geçerli karaktere denk gelen
    // konuma yerleş. Böylece ortadan düzenlemede imleç sona atlamaz.
    final selectionEnd = newValue.selection.end;
    final charsBeforeCursor =
        sanitize(newValue.text.substring(0, selectionEnd.clamp(0, newValue.text.length)))
            .length;

    var cursor = 0;
    var seen = 0;
    while (cursor < formatted.length && seen < charsBeforeCursor) {
      if (formatted[cursor] != '-') seen++;
      cursor++;
    }
    // Tam grup sınırındaysak tireyi de atla ki imleç tirenin solunda takılmasın.
    if (cursor < formatted.length && formatted[cursor] == '-' && seen == charsBeforeCursor) {
      cursor++;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: cursor),
    );
  }
}
