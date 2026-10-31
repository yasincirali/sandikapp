@Tags(['gorsel'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/disa_aktarim/aylik_rapor_belgesi.dart';
import 'package:portfoy_takip/services/disa_aktarim/pdf_yazici.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgeleri.dart';
import 'package:portfoy_takip/services/disa_aktarim/yorum_notu_pdf.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/services/yillik_rapor.dart';
import 'package:portfoy_takip/services/yorum_notu.dart';

/// PDF raporlarının GÖRSEL önizlemesi (yasin 2026-10-30: "rapor pdf olarak
/// verdiğimiz analizler güzel tasarımla, sandık logosu, göze güzel gelen
/// veri sunumu, yorumlar; Premium'a özel ekstra dikkat"). Assert etmez;
/// `build/gorsel/pdf/` altına dört PDF döker:
///   flutter test --run-skipped test/pdf_rapor_gorsel_test.dart
///   `pdftoppm -png -r 80 build/gorsel/pdf/AD.pdf build/gorsel/pdf/AD`
///
/// Veriler DEMO (`store_listing/DEMO_PORTFOY.md` ailesi), kişi değil.

Asset _lot(String id, String ad, String ticker, AssetType tur,
        {required double miktar,
        required double alis,
        required double guncel,
        AssetKind kind = AssetKind.buy,
        double? satis,
        double temettu = 0,
        String para = 'TRY',
        required DateTime tarih}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ad,
      ticker: ticker,
      type: tur,
      quantity: miktar,
      purchasePrice: alis,
      currentPrice: guncel,
      currency: para,
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: satis,
      dividendAmount: temettu,
      addedDate: tarih,
    );

final _lotlar = [
  _lot('1', 'Türk Hava Yolları', 'THYAO.IS', AssetType.hisse,
      miktar: 400, alis: 248.5, guncel: 300, tarih: DateTime(2025, 3, 12)),
  _lot('2', 'Koç Holding', 'KCHOL.IS', AssetType.hisse,
      miktar: 620, alis: 151.2, guncel: 199.2, tarih: DateTime(2025, 9, 26)),
  _lot('3', 'Hacı Ömer Sabancı Holding', 'SAHOL.IS', AssetType.hisse,
      miktar: 550, alis: 82.4, guncel: 93.5, tarih: DateTime(2025, 10, 10)),
  _lot('4', 'Gram Altın', 'ALTIN_GRAM', AssetType.altin,
      miktar: 40, alis: 3920, guncel: 5980, tarih: DateTime(2025, 2, 3)),
  _lot('5', 'Amerikan Doları', 'USDTRY=X', AssetType.doviz,
      miktar: 2200, alis: 38.5, guncel: 42.1, tarih: DateTime(2025, 10, 3)),
  _lot('6', 'Ak Portföy Kısa Vadeli Borçlanma Araçları Fonu', 'TEFAS:AK3',
      AssetType.fon,
      miktar: 15000, alis: 4.12, guncel: 5.31, tarih: DateTime(2025, 1, 20)),
  _lot('7', 'Türk Hava Yolları', 'THYAO.IS', AssetType.hisse,
      miktar: 100, alis: 248.5, guncel: 300,
      kind: AssetKind.sell, satis: 312.0, tarih: DateTime(2025, 11, 18)),
  _lot('8', 'Koç Holding', 'KCHOL.IS', AssetType.hisse,
      miktar: 620, alis: 0, guncel: 199.2,
      kind: AssetKind.dividend, temettu: 3348, tarih: DateTime(2025, 5, 6)),
  _lot('9', 'Hacı Ömer Sabancı Holding', 'SAHOL.IS', AssetType.hisse,
      miktar: 200, alis: 82.4, guncel: 93.5,
      kind: AssetKind.sell, satis: 79.9, tarih: DateTime(2025, 12, 2)),
  _lot('10', 'Türk Hava Yolları', 'THYAO.IS', AssetType.hisse,
      miktar: 400, alis: 0, guncel: 300,
      kind: AssetKind.dividend, temettu: 1530, tarih: DateTime(2025, 6, 12)),
];

Uint8List _logo() => File('assets/images/sandik_icon.png').readAsBytesSync();

ByteData _oku(String yol) => ByteData.sublistView(File(yol).readAsBytesSync());

const _olcumler = [
  YorumOlcumu('getiri', 'Dönem getirisi', '+%9,8'),
  YorumOlcumu('tufe', 'Son açıklanan aylarda TÜFE (Tem-Eyl)', '%7,9'),
  YorumOlcumu('reel_getiri',
      'Aynı aylarda enflasyondan arındırılmış (reel) getiri', '+%1,6'),
  YorumOlcumu('kiyas_altin',
      'Aynı paralar aynı günlerde gram altın yatırılsaydı getiri', '+%14,1'),
  YorumOlcumu('kiyas_altin_fark',
      'Portföyün gram altın kıyasına göre farkı', '−4,3 puan'),
  YorumOlcumu('kiyas_bist100',
      'Aynı paralar aynı günlerde BIST 100 yatırılsaydı getiri', '+%6,2'),
  YorumOlcumu('en_buyuk_pay', 'Dönem sonunda en büyük pay: THYAO', '%38,5'),
  YorumOlcumu('en_derin_dusus', 'Dönem içindeki en derin geri çekilme', '−%7,4'),
];

PortfoyYorumu _yorum() => PortfoyYorumu(
      tur: YorumTuru.secili,
      baslangic: DateTime(2026, 7, 14),
      bitis: DateTime(2026, 10, 14),
      parmakIzi: 'v1:a',
      baslik: 'Portföyün son üç ayda +%9,8 ile enflasyonun önünde kaldı, ama '
          'gram altının gerisinde.',
      maddeler: const [
        (
          metin: 'Tem-Eyl aylarında TÜFE %7,9 iken reel getirin +%1,6: alım '
              'gücün korunmuş, üstüne az da olsa eklenmiş.',
          konu: 'Alım gücü',
          kanit: ['tufe', 'reel_getiri'],
        ),
        (
          metin: 'Aynı paralar aynı günlerde gram altına konsaydı getiri '
              '+%14,1 olurdu; portföyün bu kıyasın −4,3 puan gerisinde. BIST '
              '100 kıyası +%6,2 ile portföyün altında kaldı.',
          konu: 'Kıyas',
          kanit: ['kiyas_altin', 'kiyas_altin_fark', 'kiyas_bist100'],
        ),
        (
          metin: 'Getirinin yükünü %38,5 payla THYAO taşıdı; dönem içindeki '
              'en derin geri çekilme −%7,4 oldu.',
          konu: 'Yoğunlaşma',
          kanit: ['en_buyuk_pay', 'en_derin_dusus'],
        ),
      ],
      olcumler: _olcumler,
      olusturuldu: DateTime(2026, 10, 14, 14, 32),
    );

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));
  final dir = Directory('build/gorsel/pdf')..createSync(recursive: true);
  final duz = _oku('assets/fonts/DMSans-Regular.ttf');
  final kalin = _oku('assets/fonts/DMSans-Bold.ttf');

  test('yıllık rapor', () async {
    final r = yillikRapor(
        lotlar: _lotlar, userId: 'u1', yil: 2025, bistStopajOrani: 0.15);
    final b = yillikRaporBelgesi(r,
        kim: 'demo', olusturma: DateTime(2026, 1, 5, 21, 4),
        bistStopajOrani: 0.15);
    File('${dir.path}/yillik.pdf')
        .writeAsBytesSync(
            await pdfYaz(b, duz: duz, kalin: kalin, logo: _logo()));
  });

  test('portföy dökümü', () async {
    final b = portfoyBelgesi(
        lotlar: _lotlar,
        tlYap: (t, p) => p == 'USD' ? t * 42.1 : t,
        kim: 'demo',
        olusturma: DateTime(2026, 10, 30, 21, 4));
    File('${dir.path}/portfoy.pdf')
        .writeAsBytesSync(
            await pdfYaz(b, duz: duz, kalin: kalin, logo: _logo()));
  });

  test('AI değerlendirme notu', () async {
    final b = await yorumNotuPdf(
      YorumNotu.kur(_yorum(),
          kapsam: YorumKapsami.portfoy,
          donemAdi: YorumNotu.donemAdiOf(YorumTuru.secili, '3A')),
      duz: duz,
      kalin: kalin,
      logo: File('assets/images/sandik_icon.png').readAsBytesSync(),
    );
    File('${dir.path}/yorum_notu.pdf').writeAsBytesSync(b);
  });

  // Aylık rapor (2026-10-31): TÜFE henüz açıklanmamış hâl (ayın 1'i).
  test('aylık rapor', () async {
    final b = aylikRaporBelgesi(
      donem: DateTime(2026, 10),
      notlar: const [
        AylikRaporNotu(
          kod: 'THYAO',
          rozet: 'Alıcı istekli',
          baslik: 'Ay boyunca alıcılar baskındı; fiyat ayı yükselişle kapattı.',
          maddeler: [
            'İşlem hacmi ayın son iki haftasında 3 aylık ortalamanın %62 üstündeydi.',
            'Kapanış fiyatı ay başına göre %8,4 yukarıda; en yüksek gün 24 Ekim.',
            'Günlük oynaklık önceki aya göre azaldı.',
          ],
        ),
        AylikRaporNotu(
          kod: 'TTE',
          rozet: 'Büyük giriş',
          baslik: 'Fona ay içinde belirgin para girişi oldu.',
          maddeler: [
            'Toplam giriş fon büyüklüğünün %4,1\'i kadar.',
            'Yatırımcı sayısı ay başına göre 2.300 kişi arttı.',
          ],
        ),
        AylikRaporNotu(
          kod: 'BTC',
          baslik: 'Sakin bir ay; fiyat dar bir bantta kaldı.',
          maddeler: ['Ay içi en yüksek ile en düşük arasındaki fark %6.'],
        ),
      ],
      ozetCumlesi: 'Notu çıkan 3 varlığından 2 tanesinde ay boyunca belirgin '
          'hareket oldu.',
      eksikCumlesi: 'AFT için bu ay not çıkmadı; sayıları kendi sayfalarında.',
      kim: 'demo',
      olusturma: DateTime(2026, 11, 1, 9, 12),
      getiriPct: 3.42,
    );
    File('${dir.path}/aylik.pdf')
        .writeAsBytesSync(
            await pdfYaz(b, duz: duz, kalin: kalin, logo: _logo()));
  });
}
