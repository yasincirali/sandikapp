import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/config/magaza.dart';
import 'package:portfoy_takip/services/disa_aktarim/aylik_rapor_belgesi.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_marka.dart';
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
    expect(b.dosyaAdi, 'sandık Yıllık Rapor 2025');
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
    // Anlık belge: saat de adda (aynı gün iki döküm üst üste yazılmaz).
    expect(b.dosyaAdi, 'sandık Portföy Dökümü 2026-01-05 00.00');
  });

  test('pdf: gömülü DM Sans ile üretilir', () async {
    ByteData oku(String yol) =>
        ByteData.sublistView(File(yol).readAsBytesSync());
    final baytlar = await pdfYaz(_belge(),
        duz: oku('assets/fonts/DMSans-Regular.ttf'),
        kalin: oku('assets/fonts/DMSans-Bold.ttf'),
        logo: File('assets/images/sandik_icon.png').readAsBytesSync());
    expect(ascii.decode(baytlar.sublist(0, 5)), '%PDF-');
    expect(baytlar.length, greaterThan(1000));
  });

  // Tasarım turu (yasin 2026-10-30: "yorumları da eklenmeli, data göze
  // güzel gelecek şekilde"): öne çıkanlar ve grafikler belgeyle aynı
  // sayılardan; iç anahtar (ALTIN_GRAM) cümlede ad olarak okunur.
  group('öne çıkanlar ve grafikler', () {
    Asset lot(String id, String ad, String ticker, AssetType tur, double alis,
            double guncel) =>
        Asset(
          id: id,
          userId: 'u1',
          name: ad,
          ticker: ticker,
          type: tur,
          quantity: 10,
          purchasePrice: alis,
          currentPrice: guncel,
          currency: 'TRY',
          notes: '',
          isManualPrice: false,
          addedDate: DateTime(2025, 1, 2),
        );

    test('portföy: en büyük pay, en çok kazandıran, toplam kâr/zarar', () {
      final b = portfoyBelgesi(
        lotlar: [
          lot('a', 'Gram Altın', 'ALTIN_GRAM', AssetType.altin, 100, 300),
          lot('t', 'Türk Hava Yolları', 'THYAO.IS', AssetType.hisse, 100, 90),
        ],
        tlYap: (t, _) => t,
        kim: 'demo',
        olusturma: DateTime(2026, 10, 30),
      );
      expect(b.belgeTuru, 'Portföy dökümü');
      expect(
          b.oneCikanlar.join(' | '),
          allOf(
            contains('En büyük pay Altın: %76,9'),
            contains('En çok kazandıran Gram Altın (+%200,0), en zayıf THYAO '
                '(\u2212%10,0)'),
            contains('+₺1.900'),
          ));
      expect(b.oneCikanlar.join(), isNot(contains('ALTIN_GRAM')));
      final dagilim =
          b.grafikler.firstWhere((g) => g.tur == RaporGrafikTuru.dagilim);
      expect(dagilim.kalemler.fold(0.0, (t, k) => t + k.$2), 3900);
      final kar = b.grafikler.firstWhere((g) => g.tur == RaporGrafikTuru.cubuk);
      expect(kar.kalemler, [('Gram Altın', 2000.0), ('THYAO', -100.0)]);
    });

    test('yıllık: satış ve temettü cümleleri, Excel Özet sayfasında', () {
      final b = _belge();
      expect(b.oneCikanlar.first,
          '2025 yılında 1 satışın gerçekleşen kâr/zararı +₺300.');
      expect(b.oneCikanlar, contains('Temettüden net ₺85 geldi.'));
      expect(_ac(xlsxYaz(b))['xl/worksheets/sheet1.xml'],
          contains('Öne çıkanlar'));
    });

    test('teknik sembol PDF\'te adın altına yazılmaz', () {
      expect(teknikSembolMu('ALTIN_GRAM'), isTrue);
      expect(teknikSembolMu('USDTRY=X'), isTrue);
      expect(teknikSembolMu('THYAO'), isFalse);
    });
  });

  test('iki Premium PDF aynı kimlikte: üst bant, sayfa başı, dipnot', () {
    for (final yol in [
      'lib/services/disa_aktarim/pdf_yazici.dart',
      'lib/services/disa_aktarim/yorum_notu_pdf.dart',
    ]) {
      final k = File(yol).readAsStringSync();
      for (final parca in [
        'ustBantIcerigi(',
        'ilkSayfaArkaPlani',
        'sayfaBasi(',
        'sayfaSonu(',
      ]) {
        expect(k, contains(parca), reason: '$yol $parca kullanmalı');
      }
    }
  });

  // Aylık rapor PDF'i (2026-10-31, müşteri raporu 31 Eki #1).
  group('aylık rapor belgesi', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));

    RaporBelgesi aylik({double? getiri = 2.5, double? tufe}) =>
        aylikRaporBelgesi(
          donem: DateTime(2026, 10),
          notlar: const [
            AylikRaporNotu(
                kod: 'THYAO',
                baslik: 'Ay boyunca alıcılar baskındı.',
                rozet: 'Alıcı istekli',
                maddeler: ['Hacim ortalamanın iki katı.', 'Fiyat %8 arttı.']),
            AylikRaporNotu(kod: 'TTE', baslik: 'Sakin bir ay geçti.'),
          ],
          ozetCumlesi: 'Notu çıkan 2 varlığından 1 tanesinde belirgin hareket.',
          eksikCumlesi: 'AFT için bu ay not çıkmadı.',
          kim: 'yasin',
          olusturma: DateTime(2026, 11, 1, 9),
          getiriPct: getiri,
          tufePct: tufe,
        );

    test('TÜFE açıklanmadıysa kutu açıklanacağı günü yazar; reel yok', () {
      final b = aylik();
      final ozet = {for (final (k, v) in b.ozet) k: v};
      expect(ozet["Ayın TÜFE'si"], "3 Kasım'da açıklanır");
      expect(ozet['Ayın getirisi'], '+%2,50');
      expect(ozet.containsKey('Reel getiri'), isFalse);
    });

    test('TÜFE varsa reel getiri (1+n)/(1+e)−1', () {
      final ozet = {for (final (k, v) in aylik(tufe: 2.0).ozet) k: v};
      expect(ozet["Ayın TÜFE'si"], '%2,00');
      expect(ozet['Reel getiri'], '+%0,49');
    });

    test('getiri hesaplanamadıysa getiri ve reel kutusu çıkmaz', () {
      final ozet = {for (final (k, _) in aylik(getiri: null, tufe: 2).ozet) k};
      expect(ozet, isNot(contains('Ayın getirisi')));
      expect(ozet, isNot(contains('Reel getiri')));
    });

    test('notlar bölüm, sıra korunur; eksikler ve hareket öne çıkanlarda', () {
      final b = aylik();
      expect([for (final m in b.bolumler) m.baslik], ['THYAO', 'TTE']);
      expect(b.bolumler.first.maddeler, hasLength(2));
      expect(
          b.oneCikanlar, contains('Belirgin hareket: THYAO (alıcı istekli).'));
      expect(b.oneCikanlar, contains('AFT için bu ay not çıkmadı.'));
      expect(b.kampanya, 'aylik_rapor');
      expect(b.dosyaAdi, 'sandık Aylık Rapor 2026-10 (Ekim)');
    });

    test('pdf ve xlsx yazılır; Excel\'de Notlar sayfası', () async {
      ByteData oku(String yol) =>
          ByteData.sublistView(File(yol).readAsBytesSync());
      final pdf = await pdfYaz(aylik(tufe: 2),
          duz: oku('assets/fonts/DMSans-Regular.ttf'),
          kalin: oku('assets/fonts/DMSans-Bold.ttf'),
          logo: File('assets/images/sandik_icon.png').readAsBytesSync());
      expect(ascii.decode(pdf.sublist(0, 5)), '%PDF-');
      final d = _ac(xlsxYaz(aylik()));
      expect(d['xl/workbook.xml'], contains('name="Notlar"'));
    });
  });

  // Dipnot bağlantısı (2026-10-31, müşteri raporu 31 Eki #2): üç PDF de
  // sessiz "sandık ile hazırlandı" bağlantısını taşır, tek kaynak `Magaza`.
  test('PDF dipnotunda sandık ile hazırlandı bağlantısı, kanal etiketli', () {
    expect(hazirlandiMetni, 'sandık ile hazırlandı');
    for (final yol in [
      'lib/services/disa_aktarim/pdf_yazici.dart',
      'lib/services/disa_aktarim/yorum_notu_pdf.dart',
    ]) {
      final k = File(yol).readAsStringSync();
      expect(k, contains('baglanti: Magaza.indirBaglantisi('),
          reason: '$yol dipnot bağlantısı');
      expect(k, contains("kaynak: 'pdf_rapor'"), reason: yol);
    }
    final url =
        Magaza.indirBaglantisi(kaynak: 'pdf_rapor', kampanya: 'aylik_rapor');
    expect(url, contains('utm_source=pdf_rapor'));
    expect(url, contains('utm_campaign=aylik_rapor'));
  });
}
