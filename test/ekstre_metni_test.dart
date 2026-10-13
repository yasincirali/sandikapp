import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_ice_aktarma.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_iskeleti.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// Ekstre METİN yolu (2026-10-13, bayrak `ekstre_metin_yolu`, sunucu 0147).
/// Kelimeler modele açık gider ki sözlük dışı başlık ve fon adı görünsün;
/// RAKAMLAR ve etiketli ad/adres yine cihazda kalır. Sızıntı kontrolü bu
/// testin asıl işi; şablon sağlaması ikinci işi.
void main() {
  group('satır maskesi', () {
    test('rakamlar 9, kelimeler açık', () {
      expect(
        metinSatiri(['İŞ PORTFÖY ALTIN FONU', '1.739,18', '05.10.2026']),
        ['İŞ PORTFÖY ALTIN FONU', '9.999,99', '99.99.9999'],
      );
      expect(metinSatiri(['IBAN', 'TR12 0006 4000 0011']),
          ['IBAN', 'TR99 9999 9999 9999']);
    });

    test('etiketli künye: aynı hücrede ya da yandaki hücrede ad maskelenir',
        () {
      expect(metinSatiri(['Sayın YASİN DİRALİ']), ['Sayın AAAAA AAAAAA']);
      expect(metinSatiri(['Müşteri Adı: Yasin Dirali']),
          ['Müşteri Adı: Aaaaa Aaaaaa']);
      expect(metinSatiri(['Ad Soyad', 'Yasin Dirali', 'Müşteri No', '123']),
          ['Ad Soyad', 'Aaaaa Aaaaaa', 'Müşteri No', '999']);
      expect(metinSatiri(['Adres', 'Atatürk Cad. No:12 Kadıköy']),
          ['Adres', 'Aaaaaaa Aaa. Aa:99 Aaaaaaa']);
      expect(metinSatiri(['İletişim', 'yasin@ornek.com']),
          ['İletişim', 'aaaaa@aaaaa.aaa']);
    });

    test('dar tablo başlığı künye sanılmaz', () {
      expect(metinSatiri(['Adı', 'Adet', 'Tutar']), ['Adı', 'Adet', 'Tutar']);
    });

    test('geniş başlık satırında etiket yandaki sütunu maskelemez', () {
      expect(
        metinSatiri(['Müşteri', 'Fon Unvanı', 'Nominal', 'Fiyat', 'Tutar']),
        ['Müşteri', 'Fon Unvanı', 'Nominal', 'Fiyat', 'Tutar'],
      );
    });
  });

  test('metin: düzen iskeletle aynı, sözlük dışı başlık ve fon adı açık', () {
    const tablo = EkstreTablosu(kaynak: 'PDF', satirlar: [
      ['Müşteri', 'Yasin Dirali'],
      ['Kıymet', 'Nominal Miktar', 'Maliyet Fiyatı', 'Tutar'],
      ['ZXQ PORTFÖY PARA PİYASASI FONU', '1.000,00', '1,50', '1.500,00'],
      ['ZXQ PORTFÖY ALTIN FONU', '200,00', '10,00', '2.000,00'],
    ]);
    final sonuc = ekstreyiAnla(EkstreBicimi.pdf, [tablo], '');
    final m = ekstreMetni(sonuc);

    expect(m.split('\n').first, ekstreMetniIlkSatir);
    expect(m, contains('## tablo 1 (PDF) · 4 satır × 4 sütun'));
    expect(m, contains('1\tKıymet\tNominal Miktar\tMaliyet Fiyatı\tTutar'));
    expect(m, contains('2\tZXQ PORTFÖY PARA PİYASASI FONU\t9.999,99\t9,99'));
    // Sızıntı yok: ne ad ne sayı.
    expect(m, isNot(contains('Yasin')));
    expect(m, isNot(contains('Dirali')));
    for (final satir in m.split('\n').where((l) => l.contains('\t'))) {
      final hucreler = satir.substring(satir.indexOf('\t') + 1);
      expect(hucreler, isNot(contains(RegExp(r'[0-8]'))), reason: satir);
    }
    // Kapalı bayrakta giden v1 iskelet değişmedi.
    expect(ekstreIskeleti(sonuc).split('\n').first,
        'sandık ekstre iskeleti v1');
  });

  test('ilk satır sunucudaki METIN_ILK_SATIR ile aynı', () {
    final ts = File('supabase/functions/_shared/ekstre_esleme.ts')
        .readAsStringSync();
    expect(ts, contains("METIN_ILK_SATIR = '$ekstreMetniIlkSatir'"));
  });

  group('şablon sağlaması', () {
    EkstreOkumaSonucu oku(List<List<String>> satirlar) => ekstreyiAnla(
        EkstreBicimi.pdf,
        [EkstreTablosu(kaynak: 'PDF', satirlar: satirlar)],
        '');
    const yanit = [
      {
        'tablo': 1,
        'baslik_satiri': 0,
        'roller': {'sembol': 0, 'adet': 1, 'fiyat': 2, 'tutar': 3},
      },
    ];

    test('tutan şablon kabul edilir', () {
      final e = oku([
        ['Kıymet', 'Nominal', 'Fiyat', 'Tutar'],
        ['THYAO', '100', '285,40', '28.540,00'],
        ['ASELS', '250', '58,10', '14.525,00'],
      ]);
      final s = e.aiEslemesiyle(yanit, sablondan: true);
      expect(s, isNotNull);
      expect(s!.aiOnerisi, isTrue);
    });

    test('düzeni değişmiş banka: sütun kaymış şablon reddedilir', () {
      // Banka araya "Para Birimi" koydu ama başlık izi aynı kalmış gibi
      // davranıyoruz: adet × fiyat tutmuyor.
      final e = oku([
        ['Kıymet', 'Nominal', 'Fiyat', 'Tutar'],
        ['THYAO', '100', '28.540,00', '285,40'],
        ['ASELS', '250', '14.525,00', '58,10'],
      ]);
      expect(e.aiEslemesiyle(yanit, sablondan: true), isNull);
      // Model eşlemesi (şablon değil) eski kapıyla kalır.
      expect(e.aiEslemesiyle(yanit), isNotNull);
    });

    test('fiyat/tutar yoksa sağlama atlanır, içerik kapısı yeter', () {
      final e = oku([
        ['Fon', 'Pay'],
        ['TTE', '1.500'],
        ['MAC', '40'],
      ]);
      expect(
        e.aiEslemesiyle(const [
          {
            'tablo': 1,
            'baslik_satiri': 0,
            'roller': {'sembol': 0, 'adet': 1},
          },
        ], sablondan: true),
        isNotNull,
      );
    });
  });
}
