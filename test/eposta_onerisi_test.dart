import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/eposta_onerisi.dart';

void main() {
  group('ePostaYazimOnerisi', () {
    test('sık yazım hataları düzeltilir', () {
      expect(ePostaYazimOnerisi('ahmet@gmial.com'), 'ahmet@gmail.com');
      expect(ePostaYazimOnerisi('ahmet@gmai.com'), 'ahmet@gmail.com');
      expect(ePostaYazimOnerisi('ahmet@gmail.con'), 'ahmet@gmail.com');
      expect(ePostaYazimOnerisi('ahmet@gmail.co'), 'ahmet@gmail.com');
      expect(ePostaYazimOnerisi('ayse@hotmial.com'), 'ayse@hotmail.com');
      expect(ePostaYazimOnerisi('ayse@hotmail.cmo'), 'ayse@hotmail.com');
      expect(ePostaYazimOnerisi('ayse@outlok.com'), 'ayse@outlook.com');
      expect(ePostaYazimOnerisi('ayse@icloud.co'), 'ayse@icloud.com');
      expect(ePostaYazimOnerisi('ayse@hotmail.com.t'), 'ayse@hotmail.com.tr');
    });

    test('çift hata: sağlayıcı ve son ek birlikte', () {
      expect(ePostaYazimOnerisi('ahmet@gmial.con'), 'ahmet@gmail.com');
    });

    test('yerel kısım korunur, alan adı küçülür', () {
      expect(ePostaYazimOnerisi(' Ali.Veli@GMIAL.com '), 'Ali.Veli@gmail.com');
    });

    test('doğru ve gerçek benzer adreslere öneri çıkmaz', () {
      for (final e in [
        'a@gmail.com',
        'a@hotmail.com.tr',
        'a@ymail.com',
        'a@mail.com',
        'a@me.com',
        'a@gmx.de',
        'a@yahoo.com.tr',
        'a@sirket.com.tr',
        'a@murphysoft.app',
        'a@boun.edu.tr',
      ]) {
        expect(ePostaYazimOnerisi(e), isNull, reason: e);
      }
    });

    test('tanınmayan alan adında yalnız son ek düzelir', () {
      expect(ePostaYazimOnerisi('a@sirket.con'), 'a@sirket.com');
      // .co ve .om gerçek ülke uzantısı: kendi başına dokunulmaz.
      expect(ePostaYazimOnerisi('a@sirket.co'), isNull);
    });

    test('eksik / bozuk girdi', () {
      expect(ePostaYazimOnerisi(''), isNull);
      expect(ePostaYazimOnerisi('ahmet'), isNull);
      expect(ePostaYazimOnerisi('@gmial.com'), isNull);
      expect(ePostaYazimOnerisi('ahmet@'), isNull);
    });
  });
}
