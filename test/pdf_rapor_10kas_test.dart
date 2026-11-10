import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/disa_aktarim/aylik_rapor_belgesi.dart';
import 'package:portfoy_takip/services/disa_aktarim/hareket_dokumu.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_yazici.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgeleri.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgesi.dart';
import 'package:portfoy_takip/services/disa_aktarim/xlsx_yazici.dart';
import 'package:portfoy_takip/services/yillik_rapor.dart';

import 'helpers/kaynak.dart';

/// PDF rapor düzeltmeleri (2026-11-10). Hepsi YALNIZ PDF görünümü:
/// her testte Excel'in aynı kaldığı da kilitlenir.
///
/// 1. Açıklanmamış TÜFE kutusu PDF'te çizilmez; gün kutuların altında tek
///    cümle; 4 kutu tek sırada 4 sütun.
/// 2. Tümü sıfır TL tutar sütunu (kâr/zarar hariç) gizlenir; komisyon için
///    "Komisyon girilmemiş." notu.
/// 3. Portföy dökümü işlem tablosu PDF'te tek "Tutar (TL)" sütunu.
/// 4. Küçük metin tabanı 7 pt (kaynak taraması).
/// 5. Bant alt satırında tarih bir kez (kapsamda), sonra yalnız kişi adı.
Asset _lot(
  String id,
  AssetKind kind, {
  double miktar = 10,
  double fiyat = 100,
  double? satis,
  double temettu = 0,
  double komisyon = 0,
  double kur = 1,
  double? satisKuru,
  String para = 'TRY',
  DateTime? tarih,
  bool? maliyetYok,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: 'Türk Hava Yolları',
      ticker: 'THYAO.IS',
      type: AssetType.hisse,
      quantity: miktar,
      purchasePrice: fiyat,
      currency: para,
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      sellFxRate: satisKuru,
      purchaseFxRate: kur,
      dividendAmount: temettu,
      commission: komisyon,
      addedDate: tarih ?? DateTime(2025, 6, 1),
    )..maliyetBilinmiyor = maliyetYok;

Map<String, String> _ac(Uint8List xlsx) {
  final a = ZipDecoder().decodeBytes(xlsx);
  return {
    for (final f in a.files)
      if (f.isFile) f.name: utf8.decode(f.content as List<int>),
  };
}

Future<Uint8List> _pdf(RaporBelgesi b) {
  ByteData oku(String yol) => ByteData.sublistView(File(yol).readAsBytesSync());
  return pdfYaz(b,
      duz: oku('assets/fonts/DMSans-Regular.ttf'),
      kalin: oku('assets/fonts/DMSans-SemiBold.ttf'),
      logo: File('assets/images/sandik_icon.png').readAsBytesSync());
}

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('T1 açıklanmamış TÜFE', () {
    RaporBelgesi aylik({double? tufe}) => aylikRaporBelgesi(
          donem: DateTime(2026, 10),
          notlar: const [],
          ozetCumlesi: 'x',
          eksikCumlesi: null,
          kim: 'yasin',
          olusturma: DateTime(2026, 11, 1, 9),
          getiriPct: 2.4,
          tufePct: tufe,
          portfoy: const AyinPortfoyu(
              sonTRY: 501640, katkiTRY: 10000, piyasaTRY: 11640),
        );

    test('PDF: TÜFE kutusu yok, 4 kutu 4 sütun, gün cümlesi altta', () async {
      final b = aylik();
      final kutular = pdfOzeti(b.ozet);
      expect([
        for (final (k, _) in kutular) k
      ], [
        'Ayın getirisi',
        'Ayın kâr/zararı',
        'Ay sonu değer',
        'Yatırdığın net para',
      ]);
      expect(gostergeSutunSayisi(kutular.length), 4);
      expect(b.ozetNotu, "Ekim TÜFE'si 3 Kasım'da açıklanır.");
      // Excel değişmez: "—" satırı Özet'te durur.
      expect(b.ozet, contains(("Ayın TÜFE'si · 3 Kasım'da açıklanır", '—')));
      expect(ascii.decode((await _pdf(b)).sublist(0, 5)), '%PDF-');
    });

    test('TÜFE açıklandıysa not yok; diğer kutu sayıları 3 sütun', () {
      final b = aylik(tufe: 2);
      expect(b.ozetNotu, isNull);
      expect(pdfOzeti(b.ozet), hasLength(6));
      for (final n in [1, 2, 3, 5, 6, 7]) {
        expect(gostergeSutunSayisi(n), 3, reason: '$n kutu');
      }
    });

    test('bulunma eki ayın adına göre', () {
      expect(tufeAciklanmadiCumlesi(DateTime(2026, 11)),
          "Kasım TÜFE'si 3 Aralık'ta açıklanır.");
      expect(tufeAciklanmadiCumlesi(DateTime(2026, 8)),
          "Ağustos TÜFE'si 3 Eylül'de açıklanır.");
      expect(tufeAciklanmadiCumlesi(DateTime(2026, 12)),
          "Aralık TÜFE'si 3 Ocak'ta açıklanır.");
    });
  });

  group('T2 sıfır tutar sütunu', () {
    RaporBelgesi yillik({double komisyon = 0}) => yillikRaporBelgesi(
          yillikRapor(
            lotlar: [
              _lot('b', AssetKind.buy, tarih: DateTime(2025, 1, 2)),
              _lot('s', AssetKind.sell,
                  satis: 100, komisyon: komisyon, tarih: DateTime(2025, 3, 4)),
            ],
            userId: 'u1',
            yil: 2025,
            bistStopajOrani: 0.15,
          ),
          kim: 'yasin',
          olusturma: DateTime(2026, 1, 5),
          bistStopajOrani: 0.15,
        );

    test('komisyonlar 0: sütun gizli + not; sıfır kâr/zarar görünür', () {
      final satislar = yillik().tablolar.first;
      final (:gizli, :notlar) = pdfGizliSutunlar(satislar);
      final gizliAd = {for (final i in gizli) satislar.sutunlar[i]};
      expect(gizliAd, contains('Komisyon (TL)'));
      // Alış 100, satış 100: kâr 0 — sonuç, gizlenmez.
      expect(satislar.satirlar.single[7], const TlTutar(0));
      expect(gizliAd, isNot(contains('Kâr/zarar (TL)')));
      expect(notlar, contains('Komisyon girilmemiş.'));
      // Excel değişmez: sütun ve ₺0 hücresi orada.
      expect(satislar.sutunlar, contains('Komisyon (TL)'));
      expect(_ac(xlsxYaz(yillik()))['xl/worksheets/sheet2.xml'],
          contains('Komisyon (TL)'));
    });

    test('komisyon girilmişse sütun görünür, not yok', () {
      final satislar = yillik(komisyon: 5).tablolar.first;
      final (:gizli, :notlar) = pdfGizliSutunlar(satislar);
      expect({for (final i in gizli) satislar.sutunlar[i]},
          isNot(contains('Komisyon (TL)')));
      expect(notlar, isNot(contains('Komisyon girilmemiş.')));
    });

    test('portföy işlemleri: boş komisyon sütunu da notla anılır', () {
      final b = portfoyBelgesi(
        lotlar: [_lot('b', AssetKind.buy)],
        tlYap: (t, _) => t,
        kim: 'yasin',
        olusturma: DateTime(2026, 1, 5),
      );
      final (:gizli, :notlar) = pdfGizliSutunlar(b.tablolar.last.pdf!);
      expect(notlar, contains('Komisyon girilmemiş.'));
      expect(
          gizli, contains(b.tablolar.last.pdf!.sutunlar.indexOf('Komisyon')));
    });
  });

  group('T3 işlem tablosunda tek Tutar sütunu', () {
    test('alış/satış miktar × fiyat × kur, temettü net TL; Excel aynı', () {
      final b = portfoyBelgesi(
        lotlar: [
          _lot('b', AssetKind.buy,
              para: 'USD', kur: 30, tarih: DateTime(2025, 1, 2)),
          _lot('s', AssetKind.sell,
              miktar: 4,
              satis: 120,
              para: 'USD',
              kur: 30,
              satisKuru: 35,
              tarih: DateTime(2025, 3, 4)),
          _lot('d', AssetKind.dividend,
              temettu: 5, para: 'USD', kur: 34, tarih: DateTime(2025, 2, 2)),
          _lot('e', AssetKind.sell, miktar: 1, tarih: DateTime(2025, 1, 1)),
          _lot('m', AssetKind.buy,
              maliyetYok: true, tarih: DateTime(2024, 12, 1)),
        ],
        tlYap: (t, _) => t,
        kim: 'yasin',
        olusturma: DateTime(2026, 1, 5),
      );
      final excel = b.tablolar.last;
      final pdf = excel.pdf!;
      expect(pdf.sutunlar, isNot(contains('Temettü (net)')));
      expect(pdf.sutunlar.last, 'Tutar (TL)');
      final tutar = {
        for (final r in pdf.satirlar) '${r[1]}-${r[4]}': r.last,
      };
      // Yeniden eskiye: satış, temettü, alış, fiyatsız satış, maliyetsiz alış.
      expect(tutar['Satış-4.0'], const TlTutar(4 * 120 * 35));
      expect(tutar['Temettü-null'], const TlTutar(5 * 34));
      expect(pdf.satirlar[2].last, const TlTutar(10 * 100 * 30));
      // Satış fiyatı kayıtlı değil / maliyet bilinmiyor → boş (uydurma yok).
      expect(pdf.satirlar[3].last, isNull);
      expect(pdf.satirlar[4].last, isNull);
      // Excel ayrı sütunları korur.
      expect(excel.sutunlar.last, 'Temettü (net)');
      expect(excel.satirlar[1].last, 5);
    });
  });

  test('T4 küçük metin tabanı 7 pt: 7 altı punto yok', () {
    final kaynak =
        ekranKaynagiSync('lib/services/disa_aktarim/pdf_yazici.dart');
    final boylar = RegExp(r'fontSize:\s*([0-9.]+)')
        .allMatches(kaynak)
        .map((m) => double.parse(m.group(1)!));
    expect(boylar.where((b) => b < 7), isEmpty);
  });

  group('T5 bant alt satırında tarih bir kez', () {
    test('portföy dökümü: kapsam + kişi adı; Excel altBaslik aynı', () {
      final b = portfoyBelgesi(
        lotlar: [_lot('b', AssetKind.buy, tarih: DateTime(2025, 1, 2))],
        tlYap: (t, _) => t,
        kim: 'demo',
        olusturma: DateTime(2026, 10, 30, 21, 4),
      );
      final alt = pdfBantAltSatiri(b);
      expect(alt, endsWith(' · demo'));
      expect(RegExp('21[:.]04').allMatches(alt), hasLength(1));
      expect(b.altBaslik, 'demo · 30.10.2026 21:04 itibarıyla');
    });

    test('hareket dökümü: kapsam + kişi adı', () {
      final b = hareketDokumuBelgesi(
        defter: [_lot('b', AssetKind.buy, tarih: DateTime(2025, 1, 2))],
        kim: 'demo',
        olusturma: DateTime(2026, 10, 30, 21, 4),
      )!;
      expect(pdfBantAltSatiri(b), '${b.kapsam} · demo');
      expect(b.altBaslik, 'demo · 30.10.2026 21:04 itibarıyla');
    });

    test('bantAlt yoksa eski davranış (yıllık: oluşturma anı kalır)', () {
      final b = yillikRaporBelgesi(
        yillikRapor(
            lotlar: const [], userId: 'u1', yil: 2025, bistStopajOrani: 0.15),
        kim: 'yasin',
        olusturma: DateTime(2026, 1, 5, 9),
        bistStopajOrani: 0.15,
      );
      expect(pdfBantAltSatiri(b), '${b.kapsam} · ${b.altBaslik}');
    });
  });
}
