import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/disa_aktarim/hareket_dokumu.dart';
import 'package:portfoy_takip/services/disa_aktarim/xlsx_yazici.dart';

/// "Verilerimi indir › Excel (tüm hareketler)" (Ar-Ge 7 Kas 20:30 #1).
///
/// Kilitler: ham defter (kapanmış pozisyon dahil, silinmiş hariç), eskiden
/// yeniye; varlık adı hareket listesindeki ad (ham sembol eki yok);
/// maliyeti bilinmeyen alışta fiyat boş; temettü net tutarı "Tutar"da;
/// kapsam aralığı ilk satırda ve dosya adında.
Asset _lot(
  String id,
  AssetKind kind, {
  String ticker = 'THYAO.IS',
  String ad = 'Türk Hava Yolları',
  AssetType tur = AssetType.hisse,
  double miktar = 10,
  double fiyat = 100,
  double? satis,
  double temettu = 0,
  double komisyon = 0,
  String not = '',
  DateTime? tarih,
  DateTime? silindi,
  bool? maliyetYok,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ad,
      ticker: ticker,
      type: tur,
      quantity: miktar,
      purchasePrice: fiyat,
      currency: 'TRY',
      notes: not,
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      dividendAmount: temettu,
      commission: komisyon,
      deletedAt: silindi,
      addedDate: tarih ?? DateTime(2025, 6, 1),
    )..maliyetBilinmiyor = maliyetYok;

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  final olusturma = DateTime(2026, 11, 7, 20, 30);

  test('hiç hareket yoksa belge yok (boş dosya paylaşılmaz)', () {
    expect(
        hareketDokumuBelgesi(defter: const [], kim: 'y', olusturma: olusturma),
        isNull);
    // Yalnız silinmiş kayıt da "hareket yok" demek.
    expect(
        hareketDokumuBelgesi(defter: [
          _lot('x', AssetKind.buy, silindi: DateTime(2025, 7, 1)),
        ], kim: 'y', olusturma: olusturma),
        isNull);
  });

  test('ham defter: silinmiş ve mezar taşı hariç, kapanmış pozisyon dahil', () {
    final h = dokumHareketleri([
      _lot('s', AssetKind.sell, satis: 130, tarih: DateTime(2025, 3, 4)),
      _lot('b', AssetKind.buy, tarih: DateTime(2025, 1, 2)),
      _lot('sil', AssetKind.buy,
          tarih: DateTime(2025, 2, 1), silindi: DateTime(2025, 2, 2)),
      _lot('log', AssetKind.deleteLog, tarih: DateTime(2025, 2, 3)),
    ]);
    // 10 alıp 10 satılmış (kapanmış) pozisyonun iki hareketi de girer,
    // eskiden yeniye.
    expect([for (final a in h) a.id], ['b', 's']);
  });

  test('satır üretici: sütun sırası, ad, fiyat, tutar, komisyon, not', () {
    final alis = hareketSatiri(_lot('b', AssetKind.buy,
        komisyon: 2.5, not: ' ilk alım ', tarih: DateTime(2025, 1, 2)));
    expect(alis, [
      DateTime(2025, 1, 2),
      'THYAO', // `.IS` eki yok
      'Hisse',
      'Alış',
      10.0,
      100.0,
      1000.0,
      2.5,
      'TRY',
      'ilk alım',
    ]);
    expect(alis.length, hareketSutunlari.length);

    final satis =
        hareketSatiri(_lot('s', AssetKind.sell, miktar: 4, satis: 130));
    expect(satis[3], 'Satış');
    expect(satis[5], 130.0);
    expect(satis[6], 520.0);
    expect(satis[7], isNull, reason: 'sıfır komisyon boş hücre');
    expect(satis[9], isNull, reason: 'boş not boş hücre');

    final temettu = hareketSatiri(_lot('d', AssetKind.dividend, temettu: 85));
    expect(temettu[3], 'Temettü');
    expect(temettu[4], isNull);
    expect(temettu[5], isNull);
    expect(temettu[6], 85.0, reason: 'ele geçen net tutar');
  });

  test('maliyeti bilinmeyen alışta fiyat ve tutar boş (uydurma yok)', () {
    final r = hareketSatiri(_lot('b', AssetKind.buy, maliyetYok: true));
    expect(r[5], isNull);
    expect(r[6], isNull);
  });

  test('kodu gösterilmeyen varlıkta ad, fonda TEFAS öneki yok', () {
    expect(
        hareketVarlikAdi(_lot('a', AssetKind.buy,
            ticker: 'ALTIN_GRAM', ad: 'Gram altın', tur: AssetType.altin)),
        'Gram altın');
    expect(
        hareketVarlikAdi(_lot('f', AssetKind.buy,
            ticker: 'TEFAS:AFT', ad: 'Ak Portföy', tur: AssetType.fon)),
        'AFT');
  });

  test('kapsam: başlıkta (ilk satır), kapsam satırında ve dosya adında', () {
    final b = hareketDokumuBelgesi(defter: [
      _lot('b', AssetKind.buy, tarih: DateTime(2023, 3, 3)),
      _lot('s', AssetKind.sell, satis: 130, tarih: DateTime(2025, 3, 4)),
    ], kim: 'yasin', olusturma: olusturma)!;
    expect(b.baslik, contains('3 Mart 2023 - 7 Kasım 2026'));
    expect(b.kapsam, 'Kapsam: 3 Mart 2023 - 7 Kasım 2026');
    expect(b.dosyaAdi, 'sandık Tüm Hareketler 2023-03-03 - 2026-11-07');
    expect(b.dosyaAdi, isNot(matches(RegExp('[\u2013\u2014/\\\\:]'))));
    expect(b.tablolar.single.satirlar.length, 2);
  });

  test('xlsx: ilk satır aralığı taşır, tutarlar sayı hücresi', () {
    final b = hareketDokumuBelgesi(defter: [
      _lot('b', AssetKind.buy, tarih: DateTime(2023, 3, 3)),
    ], kim: 'yasin', olusturma: olusturma)!;
    final zip = ZipDecoder().decodeBytes(xlsxYaz(b));
    String sayfa(String ad) =>
        utf8.decode(zip.files.firstWhere((f) => f.name == ad).content);
    final ozet = sayfa('xl/worksheets/sheet1.xml');
    final ilkSatir = RegExp(r'<row r="1">.*?</row>').firstMatch(ozet)![0]!;
    expect(ilkSatir, contains('3 Mart 2023 - 7 Kasım 2026'));
    final hareketler = sayfa('xl/worksheets/sheet2.xml');
    // F2 birim fiyat (100), G2 tutar (1000): metin değil sayı.
    expect(hareketler, contains('<c r="F2" s="0"><v>100</v></c>'));
    expect(hareketler, contains('<c r="G2" s="0"><v>1000</v></c>'));
  });
}
