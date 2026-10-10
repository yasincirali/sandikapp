import 'dart:io';

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

  // 2026-10-10 (TestFlight: "Yapay zekâ eşlemesi şu an yapılamadı"): çok
  // sayfalı PDF'te her sayfa ayrı tablo; tablo başına 60 satırla iskelet
  // `ekstre-esle`nin 40.000 karakter sınırını aşıyor, sunucu 400 `uzun`
  // dönüyordu. İskelet sınıra sığdırılır, tablo numaraları değişmez.
  test('çok sayfalı ekstre sunucu sınırına sığar, tablo sırası korunur', () {
    final tablolar = [
      for (var s = 0; s < 12; s++)
        EkstreTablosu(kaynak: 'PDF', satirlar: [
          ['İşlem Tarihi', 'Menkul Kıymet', 'İşlem', 'Adet', 'Fiyat',
              'Tutar', 'Komisyon', 'Açıklama'],
          for (var i = 0; i < 50; i++)
            ['0${i % 9 + 1}.10.2026', 'THYAO', 'Alış', '1.250', '312,45',
                '390.562,50', '78,11', 'Yatırım hesabı virmanı $i'],
        ]),
    ];
    final sonuc = ekstreyiAnla(EkstreBicimi.pdf, tablolar, '');
    final iskelet = ekstreIskeleti(sonuc);

    expect(iskelet.length, lessThanOrEqualTo(iskeletAzamiUzunluk));
    for (var t = 1; t <= 12; t++) {
      expect(iskelet, contains('## tablo $t (PDF) · 51 satır × 8 sütun'));
    }
    // Başlık satırı her tabloda kalır: model sütunu adından tanır.
    expect('\n0\tİşlem Tarihi'.allMatches(iskelet).length, 12);
    _sunucuKabulEder(iskelet);
  });

  test('satır azaltmak yetmezse sondaki tablolar düşer, numaralar kaymaz', () {
    final tablolar = [
      for (var s = 0; s < 400; s++)
        EkstreTablosu(kaynak: 'PDF', satirlar: [
          ['Menkul Kıymet', 'Adet', 'Fiyat', 'Tutar'],
          for (var i = 0; i < 5; i++)
            ['THYAO', '1.250', '312,45', '390.562,50'],
        ]),
    ];
    final iskelet =
        ekstreIskeleti(ekstreyiAnla(EkstreBicimi.pdf, tablolar, ''));

    expect(iskelet, contains('## tablo 1 (PDF)'));
    expect(iskelet, contains('sığmayan tablo: '));
    expect(iskelet, isNot(contains('## tablo 400 ')));
    _sunucuKabulEder(iskelet);
  });

  test('istemci sınırı sunucununkiyle aynı', () {
    final ts = File('supabase/functions/_shared/ekstre_esleme.ts')
        .readAsStringSync();
    final m = RegExp(r'AZAMI_UZUNLUK = ([\d_]+);').firstMatch(ts);
    expect(m, isNotNull);
    expect(int.parse(m!.group(1)!.replaceAll('_', '')), iskeletAzamiUzunluk);
  });
}

/// `_shared/ekstre_esleme.ts` `iskeletiDogrula`nın Dart karşılığı: uzunluk,
/// ilk satır, tablo sırası, maskesiz rakam. İstemcinin ürettiği iskelet
/// sunucuda 400 almasın.
void _sunucuKabulEder(String iskelet) {
  expect(iskelet.length, lessThanOrEqualTo(iskeletAzamiUzunluk));
  final satirlar = iskelet.split('\n');
  expect(satirlar.first, 'sandık ekstre iskeleti v1');
  final baslik =
      RegExp(r'^## tablo (\d+) \(.*\) · (\d+) satır × (\d+) sütun$');
  final veri = RegExp(r'^(\d+)\t(.*)$');
  var tablo = 0;
  for (final s in satirlar) {
    final b = baslik.firstMatch(s);
    if (b != null) {
      expect(int.parse(b.group(1)!), ++tablo);
      continue;
    }
    final v = veri.firstMatch(s);
    if (v == null) continue;
    expect(tablo, greaterThan(0));
    expect(RegExp('[0-8]').hasMatch(v.group(2)!), isFalse, reason: s);
  }
  expect(tablo, greaterThan(0));
}
