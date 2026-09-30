import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/metin_cozucu.dart';
import 'package:portfoy_takip/services/ekstre/pdf_tablo.dart';
import 'package:portfoy_takip/services/ekstre/tablo_anlama.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// Evrensel ekstre motoru — biçim ne olursa olsun aynı sonuç.
///
/// Kullanıcı (2026-10-01): "tüm formattakiler .pdf, .xlsx, .csv hepsini
/// çözüp uygulamaya dahil edebilmeli, farklı kolon yapıları olmasına
/// rağmen." Her senaryo gerçek kurum çıktılarında görülen bir tuzağı taklit
/// eder; kurum başına kural YOK, aynı motor hepsini çözmeli.
void main() {
  final bugun = DateTime(2026, 10, 1);

  CsvImportResult uc(List<EkstreTablosu> tablolar) {
    final a = tablolariAnla(tablolar);
    expect(a, isNotEmpty, reason: 'tablo anlaşılamadı');
    return CsvImportService.parse(a.first.kanonikMetin(), today: bugun);
  }

  group('ayrılmış metin', () {
    test('Windows-1254 ; ayraçlı işlem ekstresi: satış, temettü, toplam', () {
      const metin = 'XYZ Yatırım Menkul Değerler A.Ş.\r\n'
          'Hesap Ekstresi 01.09.2026 - 30.09.2026\r\n'
          '\r\n'
          'İşlem Tarihi;Menkul Kıymet;İşlem Türü;Adet;Fiyat;Tutar\r\n'
          '03.09.2026;THYAO.E;ALIŞ;100;312,40;31.240,00\r\n'
          '10.09.2026;THYAO.E;SATIŞ;40;330,00;13.200,00\r\n'
          '15.09.2026;ASELS.E;Temettü;;;1.250,00\r\n'
          ';;;;Toplam;45.690,00\r\n';
      final bayt = Uint8List.fromList([
        for (final r in metin.runes)
          switch (r) {
            0x130 => 0xDD, 0x131 => 0xFD, 0x15E => 0xDE, 0x15F => 0xFE,
            0x11E => 0xD0, 0x11F => 0xF0, 0xFC => 0xFC, 0xF6 => 0xF6,
            0xE7 => 0xE7, 0xC7 => 0xC7, 0xD6 => 0xD6, 0xDC => 0xDC,
            _ => r,
          },
      ]);
      expect(metneCevir(bayt), contains('İşlem Türü'));
      final r = uc(tablolariOku(bayt));
      expect(r.errors, isEmpty);
      expect(r.rows.map((x) => (x.ticker, x.quantity, x.satis)), [
        ('THYAO.IS', 100.0, false),
        ('THYAO.IS', 40.0, true),
      ]);
      expect(r.rows.first.price, 312.40);
      expect(r.rows.first.addedDate, DateTime(2026, 9, 3));
    });

    test('İngilizce CSV: 1,234.56 sayılar, ABD tarih, eksi adet = satış', () {
      const metin = 'Date,Symbol,Quantity,Price,Amount\n'
          '09/13/2026,GARAN,"1,000",112.50,"112,500.00"\n'
          '09/20/2026,GARAN,-250,118.00,"-29,500.00"\n';
      final r = uc(tablolariOku(Uint8List.fromList(utf8.encode(metin))));
      expect(r.errors, isEmpty);
      expect(r.rows.length, 2);
      expect(r.rows[0].quantity, 1000);
      expect(r.rows[0].price, 112.5);
      expect(r.rows[0].addedDate, DateTime(2026, 9, 13));
      expect(r.rows[1].satis, isTrue);
      expect(r.rows[1].quantity, 250);
    });

    test('başlıksız tablo: roller içerikten ve adet×fiyat≈tutar\'dan', () {
      const metin = 'THYAO\t12.09.2026\t100\t45,20\t4.520,00\n'
          'ASELS\t13.09.2026\t25\t60,00\t1.500,00\n'
          'TCD\t14.09.2026\t1.000\t2,50\t2.500,00\n';
      final a = tablolariAnla(tablolariOku(Uint8List.fromList(utf8.encode(metin)))).first;
      expect(a.roller[EkstreRol.sembol], 0);
      expect(a.roller[EkstreRol.tarih], 1);
      expect(a.roller[EkstreRol.adet], 2);
      expect(a.roller[EkstreRol.fiyat], 3);
      expect(a.roller[EkstreRol.tutar], 4);
      final r = CsvImportService.parse(a.kanonikMetin(), today: bugun);
      expect(r.errors, isEmpty);
      expect(r.rows.map((x) => x.quantity), [100, 25, 1000]);
    });

    test('ISIN sembol bilinen koda çevrilir', () {
      const metin = 'ISIN;Nominal;Ortalama Maliyet\nTRATHYAO91M5;50;300,00\n';
      final r = uc(tablolariOku(Uint8List.fromList(utf8.encode(metin))));
      expect(r.rows.single.ticker, 'THYAO.IS');
    });
  });

  group('HTML "Excel" (.xls uzantılı tablo)', () {
    test('unvan satırları üstte; Son Fiyat maliyet sanılmaz', () {
      const html = '<html><body><table>'
          '<tr><td colspan="5">ABC Yatırım — Portföy Dökümü</td></tr>'
          '<tr><td>Müşteri No</td><td>12345</td></tr>'
          '<tr><th>Menkul Kıymet</th><th>Bakiye</th><th>Son Fiyat</th>'
          '<th>Ortalama Maliyet</th><th>Piyasa Değeri</th></tr>'
          '<tr><td>EREGL - Ereğli Demir Çelik</td><td>200</td><td>48,10</td>'
          '<td>41,75</td><td>9.620,00</td></tr>'
          '<tr><td>AFT</td><td>3.500</td><td>1,95</td><td>1,60</td><td>6.825,00</td></tr>'
          '<tr><td>Genel Toplam</td><td></td><td></td><td></td><td>16.445,00</td></tr>'
          '</table></body></html>';
      final bayt = Uint8List.fromList(utf8.encode(html));
      expect(bicimiSez(bayt), EkstreBicimi.html);
      final r = uc(tablolariOku(bayt));
      expect(r.errors, isEmpty);
      expect(r.rows.map((x) => (x.ticker, x.quantity, x.price)), [
        ('EREGL.IS', 200.0, 41.75),
        // TEFAS fon kodu uygulamanın fon saklama biçimine çevrilir.
        ('TEFAS:AFT', 3500.0, 1.60),
      ]);
    });
  });

  group('XLSX', () {
    Uint8List xlsx() {
      String xml(String s) => '<?xml version="1.0" encoding="UTF-8"?>$s';
      final dosyalar = {
        'xl/workbook.xml': xml('<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
            'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
            '<sheets><sheet name="Hareketler" sheetId="1" r:id="rId1"/></sheets></workbook>'),
        'xl/_rels/workbook.xml.rels': xml('<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
            '<Relationship Id="rId1" Type="worksheet" Target="worksheets/sheet1.xml"/></Relationships>'),
        'xl/sharedStrings.xml': xml('<sst><si><t>Valör</t></si><si><t>Enstrüman</t></si>'
            '<si><t>Yön</t></si><si><t>Miktar</t></si><si><t>İşlem Fiyatı</t></si>'
            '<si><t>KCHOL</t></si><si><t>Alış</t></si><si><t>Satış</t></si></sst>'),
        'xl/styles.xml': xml('<styleSheet><cellXfs count="2"><xf numFmtId="0"/><xf numFmtId="14"/></cellXfs></styleSheet>'),
        'xl/worksheets/sheet1.xml': xml('<worksheet><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c>'
            '<c r="D1" t="s"><v>3</v></c><c r="E1" t="s"><v>4</v></c></row>'
            // 46270 = 05.09.2026
            '<row r="2"><c r="A2" s="1"><v>46270</v></c><c r="B2" t="s"><v>5</v></c><c r="C2" t="s"><v>6</v></c>'
            '<c r="D2"><v>30</v></c><c r="E2"><v>210.35</v></c></row>'
            '<row r="3"><c r="A3" s="1"><v>46280</v></c><c r="B3" t="s"><v>5</v></c><c r="C3" t="s"><v>7</v></c>'
            '<c r="D3"><v>10</v></c><c r="E3"><v>1234.5</v></c></row>'
            '</sheetData></worksheet>'),
      };
      final arsiv = Archive();
      dosyalar.forEach((ad, icerik) {
        final b = utf8.encode(icerik);
        arsiv.addFile(ArchiveFile(ad, b.length, b));
      });
      return Uint8List.fromList(ZipEncoder().encode(arsiv));
    }

    test('paylaşılan metin, tarih stili ve ondalık sayı doğru okunur', () {
      final b = xlsx();
      expect(bicimiSez(b), EkstreBicimi.xlsx);
      final t = tablolariOku(b).single;
      expect(t.kaynak, 'Hareketler');
      expect(t.satirlar[1], ['05.09.2026', 'KCHOL', 'Alış', '30', '210,35']);
      final r = uc([t]);
      expect(r.errors, isEmpty);
      expect(r.rows.map((x) => (x.quantity, x.price, x.satis)), [
        (30.0, 210.35, false),
        (10.0, 1234.5, true),
      ]);
    });
  });

  group('PDF geometrisi', () {
    // Sütunlar x=[20..80] sembol, [120..160] adet (sağa yaslı), [200..260]
    // fiyat. İkinci veri satırında adet BOŞ — sütun kaymamalı.
    List<PdfKarakter> satir(double y, List<(String, double)> parcalar) => [
          for (final (metin, x) in parcalar)
            for (var i = 0; i < metin.length; i++)
              PdfKarakter(metin[i], x + i * 6, x + i * 6 + 5, y + 10, y),
        ];

    test('boş hücre sütunu kaydırmaz, çok kelimeli hücre bölünmez', () {
      final k = [
        ...satir(700, [('Menkul', 20), ('Adet', 130), ('Fiyat', 200)]),
        ...satir(680, [('THYAO', 20), ('100', 142), ('45,20', 200)]),
        ...satir(660, [('GRAM ALTIN', 20), ('4.250,00', 200)]),
      ];
      // "Menkul" ile "Adet" arası geniş; "GRAM" ile "ALTIN" arası tek boşluk.
      final s = sayfadanSatirlar(k);
      expect(s, [
        ['Menkul', 'Adet', 'Fiyat'],
        ['THYAO', '100', '45,20'],
        ['GRAM ALTIN', '', '4.250,00'],
      ]);
    });
  });

  group('güven ve hata', () {
    test('eski ikili .xls dürüstçe reddedilir', () {
      final b = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]);
      expect(() => tablolariOku(b), throwsA(isA<EkstreOkumaHatasi>()));
    });

    test('sembol olmayan tablo anlaşılmaz (uydurma eşleme yok)', () {
      const metin = 'Ay;Gelir;Gider\nOcak;1000;800\nŞubat;1200;900\n';
      expect(tablolariAnla(tablolariOku(Uint8List.fromList(utf8.encode(metin)))), isEmpty);
    });

    test('kullanıcı düzeltmesi eşlemeyi değiştirir ve güveni 1 yapar', () {
      const metin = 'THYAO\t100\t45,20\nASELS\t20\t60,00\n';
      final a = tablolariAnla(tablolariOku(Uint8List.fromList(utf8.encode(metin)))).first;
      final d = a.yeniRollerle({EkstreRol.sembol: 0, EkstreRol.adet: 2, EkstreRol.fiyat: 1});
      expect(d.guven, 1);
      final r = CsvImportService.parse(d.kanonikMetin(), today: bugun);
      expect(r.rows.first.quantity, 45.2);
    });
  });
}
