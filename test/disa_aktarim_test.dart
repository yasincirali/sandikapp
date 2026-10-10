import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_yazici.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgeleri.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgesi.dart';
import 'package:portfoy_takip/services/disa_aktarim/xlsx_yazici.dart';
import 'package:portfoy_takip/services/yillik_rapor.dart';

/// Premium dışa aktarım (2026-10-10): aynı belge iki biçime yazılır.
///
/// Kilitler: .xlsx geçerli bir zip ve Excel'in zorunlu parçalarını taşır,
/// tutar SAYI olarak yazılır (müşavir toplayabilsin), Türkçe metin bozulmaz,
/// PDF gömülü DM Sans ile üretilir; belge içeriği yıllık raporla aynı
/// sayıları taşır.
Asset _lot(String id, AssetKind kind,
        {double? satis, double temettu = 0, DateTime? tarih}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      dividendAmount: temettu,
      addedDate: tarih ?? DateTime(2025, 6, 1),
    );

RaporBelgesi _belge() {
  final r = yillikRapor(
    lotlar: [
      _lot('b', AssetKind.buy, tarih: DateTime(2025, 1, 2)),
      _lot('s', AssetKind.sell, satis: 130, tarih: DateTime(2025, 3, 4)),
      _lot('d', AssetKind.dividend, temettu: 85),
    ],
    userId: 'u1',
    yil: 2025,
    bistStopajOrani: 0.15,
  );
  return yillikRaporBelgesi(r,
      kim: 'yasin', olusturma: DateTime(2026, 1, 5), bistStopajOrani: 0.15);
}

Map<String, String> _ac(Uint8List xlsx) {
  final a = ZipDecoder().decodeBytes(xlsx);
  return {
    for (final f in a.files)
      if (f.isFile) f.name: utf8.decode(f.content as List<int>),
  };
}

void main() {
  test('xlsx: zorunlu parçalar, sayfa başına bir dosya', () {
    final d = _ac(xlsxYaz(_belge()));
    expect(
        d.keys,
        containsAll([
          '[Content_Types].xml',
          '_rels/.rels',
          'xl/workbook.xml',
          'xl/_rels/workbook.xml.rels',
          'xl/styles.xml',
          'xl/worksheets/sheet1.xml',
          'xl/worksheets/sheet2.xml',
          'xl/worksheets/sheet3.xml',
        ]));
    expect(d['xl/workbook.xml'], contains('name="Özet"'));
    expect(d['xl/workbook.xml'], contains('name="Satışlar"'));
  });

  test('xlsx: tutar sayı hücresi, metin Türkçe ve kaçışlı', () {
    final d = _ac(xlsxYaz(_belge()));
    final satis = d['xl/worksheets/sheet2.xml']!;
    // Kâr 300 TL sayı olarak (s="1" = #,##0.00), metin olarak değil.
    expect(satis, contains('<v>300</v>'));
    expect(satis, contains('Türk Hava Yolları'));
    // Tarih Excel seri günüyle.
    expect(satis, contains('<v>${excelSeriGunu(DateTime(2025, 3, 4))}</v>'));
  });

  test('sütun harfi ve seri gün', () {
    expect(sutunHarfi(0), 'A');
    expect(sutunHarfi(25), 'Z');
    expect(sutunHarfi(26), 'AA');
    expect(excelSeriGunu(DateTime(2025, 1, 1)), 45658);
    expect(xmlKacis('A & <B>'), 'A &amp; &lt;B&gt;');
  });

  test('belge özeti yıllık raporla aynı sayılar', () {
    final b = _belge();
    final ozet = {for (final (k, v) in b.ozet) k: v};
    expect(ozet['Gerçekleşen kâr/zarar (satışlar)'], const TlTutar(300));
    expect(ozet['Temettü (net, ele geçen)'], const TlTutar(85));
    expect((ozet['Temettü stopajı'] as TlTutar).deger, closeTo(15, 1e-9));
    expect(b.dipnotlar.first, contains('vergi tavsiyesi değildir'));
  });

  test('portföy belgesi: pozisyon değeri TL, işlem listesi yeniden eskiye', () {
    final b = portfoyBelgesi(
      lotlar: [
        _lot('b', AssetKind.buy, tarih: DateTime(2025, 1, 2)),
        _lot('d', AssetKind.dividend, temettu: 5, tarih: DateTime(2025, 2, 2)),
      ],
      tlYap: (t, _) => t,
      kim: 'yasin',
      olusturma: DateTime(2026, 1, 5),
    );
    final varliklar = b.tablolar.first;
    expect(varliklar.satirlar, hasLength(1));
    expect(varliklar.satirlar.single[7], const TlTutar(1000));
    final islemler = b.tablolar.last;
    expect(islemler.satirlar.first[1], 'Temettü');
    expect(sadeSembol('TEFAS:AFT'), 'AFT');
  });

  test('pdf: gömülü DM Sans ile üretilir', () async {
    ByteData oku(String yol) =>
        ByteData.sublistView(File(yol).readAsBytesSync());
    final baytlar = await pdfYaz(_belge(),
        duz: oku('assets/fonts/DMSans-Regular.ttf'),
        kalin: oku('assets/fonts/DMSans-Bold.ttf'));
    expect(ascii.decode(baytlar.sublist(0, 5)), '%PDF-');
    expect(baytlar.length, greaterThan(1000));
  });
}
