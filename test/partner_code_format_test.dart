// Ortaklık kodu giriş biçimlendirmesi.
//
// Regresyon: Kod alanında inputFormatters yoktu; tire kullanıcıdan
// bekleniyordu. Tiresiz ya da boşluklu girilen DOĞRU bir kod,
// istemcideki ^([A-Z2-9]{5}-[A-Z2-9]{5})$ kontrolüne takılıp
// "Geçersiz kod formatı" hatası veriyordu.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/partner_code_formatter.dart';

/// auth_service.submitPartnerCode içindeki doğrulamayla aynı desen.
final _serverPattern = RegExp(r'^([A-Z2-9]{5}-[A-Z2-9]{5})$');

void main() {
  group('format', () {
    test('tire otomatik eklenir — asıl hata buydu', () {
      expect(PartnerCodeInputFormatter.format('ABCDE62345'), 'ABCDE-62345');
    });

    test('küçük harf büyütülür', () {
      expect(PartnerCodeInputFormatter.format('abcde62345'), 'ABCDE-62345');
    });

    test('boşluk ve noktalama süzülür', () {
      expect(PartnerCodeInputFormatter.format('ABCDE 62345'), 'ABCDE-62345');
      expect(PartnerCodeInputFormatter.format(' ABCDE-62345 '), 'ABCDE-62345');
      expect(PartnerCodeInputFormatter.format('ABCDE—62345'), 'ABCDE-62345');
    });

    test('alfabede olmayan 0/1/I/O düşürülür (tahmini düzeltme yapılmaz)', () {
      // 0,1,I,O üretim alfabesinde yok; sessizce O/1'e çevirmek yanlış
      // koda yol açabilirdi. Düşürmek hatayı görünür bırakır.
      expect(PartnerCodeInputFormatter.sanitize('AB0CDE'), 'ABCDE');
      expect(PartnerCodeInputFormatter.sanitize('ABIOCDE1'), 'ABCDE');
    });

    test('10 karakterden fazlası kırpılır', () {
      expect(PartnerCodeInputFormatter.format('ABCDE62345XYZ'), 'ABCDE-62345');
    });

    test('kısmi girdi tire eklemeden kalır', () {
      expect(PartnerCodeInputFormatter.format('ABC'), 'ABC');
      expect(PartnerCodeInputFormatter.format('ABCDE'), 'ABCDE');
      expect(PartnerCodeInputFormatter.format('ABCDEF'), 'ABCDE-F');
    });

    test('boş girdi boş kalır', () {
      expect(PartnerCodeInputFormatter.format(''), '');
      expect(PartnerCodeInputFormatter.format('!!!'), '');
    });
  });

  group('sunucu deseniyle uyum', () {
    test('tiresiz girilen tam kod, biçimlendirmeden sonra deseni geçer', () {
      final formatted = PartnerCodeInputFormatter.format('ABCDE62345');
      expect(_serverPattern.hasMatch(formatted), isTrue,
          reason: 'Biçimlendirilmiş kod sunucu desenini geçmeli');
    });

    test('kullanıcının yazabileceği bozuk varyantlar da deseni geçer', () {
      for (final girdi in [
        'abcde62345',
        'ABCDE 62345',
        'ABCDE-62345',
        '  abcde - 62345  ',
      ]) {
        final formatted = PartnerCodeInputFormatter.format(girdi);
        expect(_serverPattern.hasMatch(formatted), isTrue,
            reason: '"$girdi" biçimlendirildikten sonra geçerli olmalı');
      }
    });
  });

  group('formatEditUpdate — imleç davranışı', () {
    TextEditingValue uygula(String eski, String yeni, int imlec) {
      return PartnerCodeInputFormatter().formatEditUpdate(
        TextEditingValue(text: eski),
        TextEditingValue(
          text: yeni,
          selection: TextSelection.collapsed(offset: imlec),
        ),
      );
    }

    test('5. karakterden sonra tire eklenir, imleç tirenin sağına geçer', () {
      final sonuc = uygula('ABCD', 'ABCDE', 5);
      expect(sonuc.text, 'ABCDE');
      expect(sonuc.selection.baseOffset, 5);

      final sonuc2 = uygula('ABCDE', 'ABCDEF', 6);
      expect(sonuc2.text, 'ABCDE-F');
      // İmleç F'nin sağında olmalı (tire atlanmış).
      expect(sonuc2.selection.baseOffset, 7);
    });

    test('imleç metnin sonuna zorla atlamaz (ortadan düzenleme)', () {
      // "ABCDE-62345" içinde 2. karakterden sonra X yazılıyor.
      // Geçerli karakterler: A B X C D E 6 2 3 4 (10 sınırı, son 5 düşer)
      final sonuc = uygula('ABCDE-62345', 'ABXCDE-62345', 3);
      expect(sonuc.text, 'ABXCD-E6234');
      // İmleç yazılan X'in hemen sağında (3 geçerli karakter sonrası).
      expect(sonuc.selection.baseOffset, 3);
      expect(sonuc.selection.baseOffset, lessThan(sonuc.text.length));
    });

    test('tam kod yapıştırıldığında biçim korunur', () {
      final sonuc = uygula('', 'abcde62345', 10);
      expect(sonuc.text, 'ABCDE-62345');
      expect(sonuc.selection.baseOffset, sonuc.text.length);
    });
  });
}
