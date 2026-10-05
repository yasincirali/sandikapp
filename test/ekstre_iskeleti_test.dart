import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_ice_aktarma.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_iskeleti.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// Tanılama iskeleti (2026-10-05): tanınmayan ekstrenin yapısı görünür,
/// kişisel içeriği görünmez. Belge cihazdan çıkmaz; kullanıcı yalnız bu
/// metni gönderir — sızıntı kontrolü bu testin asıl işi.
void main() {
  group('hücre maskesi', () {
    test('kişisel veri maskelenir, biçim korunur', () {
      expect(iskeletHucresi('Yasin Dirali'), 'Aaaaa Aaaaaa');
      expect(iskeletHucresi('12345678901'), '99999999999');
      expect(iskeletHucresi('TR12 0006 4000'), 'AA99 9999 9999');
      expect(iskeletHucresi('1.739,18'), '9.999,99');
      expect(iskeletHucresi('05.10.2026'), '99.99.9999');
      expect(iskeletHucresi('Atatürk Cad. No:12'), 'Aaaaaaa Aaa. Aa:99');
    });

    test('başlık ve genel finans kelimeleri kalır', () {
      expect(iskeletHucresi('Yatırım Fonu İsmi'), 'Yatırım Fonu İsmi');
      expect(iskeletHucresi('Pay Adedi'), 'Pay Adedi');
      expect(iskeletHucresi('Birim Pay Fiyatı'), 'Birim Pay Fiyatı');
      expect(iskeletHucresi('Vadeli Mevduat Hesapları'),
          'Vadeli Mevduat Hesapları');
      expect(iskeletHucresi('Toplam'), 'Toplam');
    });

    test('bilinen BIST ve döviz kodu kalır, bilinmeyen kod maskelenir', () {
      expect(iskeletHucresi('THYAO'), 'THYAO');
      expect(iskeletHucresi('USD'), 'USD');
      expect(iskeletHucresi('QWXZ'), 'AAAA');
    });
  });

  test('iskelet tablo düzenini ve motorun kararını taşır', () {
    const tablo = EkstreTablosu(kaynak: 'PDF', satirlar: [
      ['Müşteri', 'Yasin Dirali'],
      ['Yatırım Fonu İsmi', 'Pay Adedi', 'Birim Pay Fiyatı', 'Tutar'],
      ['ZXQ PORTFÖY PARA PİYASASI FONU', '1.000,00', '1,50', '1.500,00'],
      ['ZXQ PORTFÖY ALTIN FONU', '200,00', '10,00', '2.000,00'],
    ]);
    final sonuc = ekstreyiAnla(EkstreBicimi.pdf, [tablo], '');
    final iskelet = ekstreIskeleti(sonuc);

    expect(iskelet, contains('biçim: pdf'));
    expect(iskelet, contains('## tablo 1 (PDF) · 4 satır × 4 sütun'));
    expect(iskelet, contains('anlam 1: başlık satırı 1'));
    expect(iskelet,
        contains('1\tYatırım Fonu İsmi\tPay Adedi\tBirim Pay Fiyatı\tTutar'));
    expect(iskelet, contains('AAA PORTFÖY PARA PİYASASI FONU\t9.999,99'));
    // Sızıntı yok: ne ad ne tutar.
    expect(iskelet, isNot(contains('Yasin')));
    expect(iskelet, isNot(contains('Dirali')));
    expect(iskelet, isNot(contains('1.500,00')));
    expect(iskelet, isNot(contains('ZXQ')));
  });

  test('uzun tablo kesilir', () {
    final tablo = EkstreTablosu(kaynak: 'CSV', satirlar: [
      for (var i = 0; i < 100; i++) ['THYAO', '$i'],
    ]);
    final sonuc = ekstreyiAnla(EkstreBicimi.metin, [tablo], '');
    final iskelet = ekstreIskeleti(sonuc, tabloBasinaSatir: 10);
    expect(iskelet, contains('… 90 satır daha'));
  });
}
