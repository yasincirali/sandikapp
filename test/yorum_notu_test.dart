import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/services/disa_aktarim/dosya_adi.dart';
import 'package:portfoy_takip/services/disa_aktarim/yorum_notu_pdf.dart';
import 'package:portfoy_takip/services/portfoy_yorumu_service.dart';
import 'package:portfoy_takip/services/yorum_notu.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/yorum_notu_sayfasi.dart';
import 'helpers/yazi_olcegi.dart';

/// AI yorumunun "Tamamını oku" sayfası + A4 PDF notu (2026-10-14).
///
/// Kilitlenen: düzen kararı tek yerde ([YorumNotu.kur]); yeni sayı
/// üretilmez (her gösterim ölçümün kendi yazımı); kıyas çubuğu okunamayan
/// gösterimde çizilmez; PDF logolu ve Türkçe karakterli üretilir; sayfa
/// büyük yazıda taşmaz, paylaş düğmesi altta durur.

const _olcumler = [
  YorumOlcumu('getiri', 'Dönem getirisi', '+%11,4'),
  YorumOlcumu('tufe', 'Son açıklanan aylarda TÜFE (Tem-Eyl)', '%7,9'),
  YorumOlcumu('reel_getiri',
      'Aynı aylarda enflasyondan arındırılmış (reel) getiri', '+%3,2'),
  YorumOlcumu(
      'kiyas_dolar',
      'Aynı paralar aynı günlerde Amerikan doları yatırılsaydı getiri',
      '+%4,1'),
  YorumOlcumu('kiyas_dolar_fark',
      'Portföyün Amerikan doları kıyasına göre farkı', '+7,3 puan'),
  YorumOlcumu('kiyas_altin',
      'Aynı paralar aynı günlerde gram altın yatırılsaydı getiri', '+%9,8'),
  YorumOlcumu('kiyas_altin_fark', 'Portföyün gram altın kıyasına göre farkı',
      '+1,6 puan'),
  YorumOlcumu('kiyas_bist100',
      'Aynı paralar aynı günlerde BIST 100 yatırılsaydı getiri', '−%2,0'),
  YorumOlcumu(
      'en_derin_dusus', 'Dönem içindeki en derin geri çekilme', '−%4,6'),
  YorumOlcumu('oynaklik', 'Portföyün yıllıklandırılmış oynaklığı', '%17,8'),
  YorumOlcumu(
      'ilk_uc_pay', 'Dönem sonunda en büyük 3 varlığın toplam payı', '%58,0'),
];

PortfoyYorumu _yorum({List<YorumOlcumu> olcumler = _olcumler}) => PortfoyYorumu(
      tur: YorumTuru.secili,
      baslangic: DateTime(2026, 7, 14),
      bitis: DateTime(2026, 10, 14),
      parmakIzi: 'v1:a',
      baslik:
          'Portföyün son üç ayda +%11,4 ile enflasyonun önünde kaldı; getiri üç kalemde toplandı.',
      maddeler: const [
        (
          metin:
              'Tem-Eyl aylarında TÜFE %7,9 iken reel getirin +%3,2: alım gücün büyüdü.',
          konu: 'Alım gücü',
          kanit: ['tufe', 'reel_getiri'],
        ),
        (
          metin:
              'Amerikan dolarının +7,3 puan, gram altının +1,6 puan önündesin; BIST 100 −%2,0 ile geride kaldı.',
          konu: 'Kıyas',
          kanit: ['kiyas_dolar_fark', 'kiyas_altin_fark', 'kiyas_bist100'],
        ),
        (
          metin:
              'Portföyün %58,0\'ı en büyük üç varlıkta; en derin geri çekilme −%4,6 oldu.',
          konu: null,
          kanit: ['ilk_uc_pay', 'en_derin_dusus'],
        ),
      ],
      olcumler: olcumler,
      olusturuldu: DateTime(2026, 10, 14, 18, 40),
    );

YorumNotu _notu() => YorumNotu.kur(_yorum(),
    kapsam: YorumKapsami.portfoy,
    donemAdi: YorumNotu.donemAdiOf(YorumTuru.secili, '3A'));

void main() {
  group('YorumNotu.kur', () {
    test('manşet, alt satır ve dört gösterge sabit sırada', () {
      final n = _notu();
      expect(n.manset?.anahtar, 'getiri');
      expect(n.mansetAlt?.anahtar, 'reel_getiri');
      expect(n.gostergeler.map((o) => o.anahtar),
          ['getiri', 'reel_getiri', 'en_derin_dusus', 'oynaklik']);
      expect(n.digerleri.any((o) => o.anahtar == 'getiri'), isFalse);
      expect(n.digerleri, hasLength(_olcumler.length - 1));
    });

    test('kıyas: portföy önce, sonra büyükten küçüğe; gösterim aynen', () {
      final k = _notu().kiyaslar;
      expect(k.map((e) => e.ad),
          ['Portföy', 'Gram altın', 'TÜFE', 'Amerikan doları', 'BIST 100']);
      expect(k.first.kendisi, isTrue);
      expect(k.last.deger, -2.0);
      expect(k.last.gosterim, '−%2,0');
      // Gösterimler ölçümlerden birebir (yeni sayı yok).
      final gosterimler = _olcumler.map((o) => o.gosterim).toSet();
      expect(k.every((e) => gosterimler.contains(e.gosterim)), isTrue);
    });

    test('fark ölçümleri ayrı listede', () {
      expect(_notu().farklar.map((o) => o.anahtar),
          ['kiyas_dolar_fark', 'kiyas_altin_fark']);
    });

    test('tek çubuk kalırsa grafik çizilmez; okunamayan gösterim çubuk olmaz',
        () {
      final n = YorumNotu.kur(
        _yorum(olcumler: const [
          YorumOlcumu('getiri', 'Dönem getirisi', '+%1,0'),
          YorumOlcumu('kiyas_altin', 'Gram altın', 'veri yok'),
        ]),
        kapsam: YorumKapsami.portfoy,
        donemAdi: 'Geçen hafta',
      );
      expect(n.kiyaslar, isEmpty);
    });

    test('varlık kapsamında manşet fiyat değişimi, çubuk adı varlığın adı', () {
      final n = YorumNotu.kur(
        _yorum(olcumler: const [
          YorumOlcumu('degisim', 'Dönem içinde fiyat değişimi', '−%3,8'),
          YorumOlcumu(
              'kiyas_bist100', 'Aynı dönemde BIST 100 değişimi', '+%1,2'),
          YorumOlcumu('pozisyon_getirisi', 'Pozisyon getirisi', '+%21,5'),
        ]),
        kapsam: YorumKapsami.varlik,
        varlikAdi: 'THYAO',
        donemAdi: 'Son 1 ay',
      );
      expect(n.manset?.anahtar, 'degisim');
      expect(n.mansetAlt?.anahtar, 'pozisyon_getirisi');
      expect(n.kiyaslar.first.ad, 'THYAO');
      expect(n.kiyaslar.first.deger, -3.8);
    });

    test('dosya adı ve dönem adları', () {
      // Kalıp `belgeDosyaAdi` (2026-10-31): tür + dönem, sıralanabilir.
      expect(_notu().dosyaAdi,
          'sandık Portföy Değerlendirme Notu Son 3 ay 2026-10-14');
      expect(YorumNotu.donemAdiOf(YorumTuru.haftalik, null), 'Geçen hafta');
      expect(YorumNotu.donemAdiOf(YorumTuru.aylik, null), 'Geçen ay');
      expect(YorumNotu.donemAdiOf(YorumTuru.secili, '1Y'), 'Son 1 yıl');
    });
  });

  test('kısa adlar ve Türkçe büyük harf', () {
    expect(YorumNotu.kisaAd(_olcumler[4]), 'Amerikan doları farkı');
    expect(YorumNotu.kisaAd(_olcumler[2]), 'Reel getiri');
    expect(trBuyuk('Para birimi'), 'PARA BİRİMİ');
    expect(trBuyuk('Oynaklık (yıllık)'), 'OYNAKLIK (YILLIK)');
  });

  test('yuzdeDegeri', () {
    expect(yuzdeDegeri('+%11,4'), 11.4);
    expect(yuzdeDegeri('−%4,6'), -4.6);
    expect(yuzdeDegeri('%1.234,5'), 1234.5);
    expect(yuzdeDegeri('412 gün'), isNull);
    expect(yuzdeDegeri('+7,3 puan'), isNull);
  });

  test('PDF: logolu, Türkçe yazı tipiyle üretilir', () async {
    ByteData oku(String yol) =>
        ByteData.sublistView(File(yol).readAsBytesSync());
    final b = await yorumNotuPdf(
      _notu(),
      duz: oku('assets/fonts/DMSans-Regular.ttf'),
      kalin: oku('assets/fonts/DMSans-Bold.ttf'),
      logo: File('assets/images/sandik_icon.png').readAsBytesSync(),
      hazirlanma: DateTime(2026, 10, 14),
    );
    expect(String.fromCharCodes(b.take(5)), '%PDF-');
    // Önizleme için (CI'da zararsız; build/ gitignore'da).
    final d = Directory('build/gorsel')..createSync(recursive: true);
    File('${d.path}/yorum_notu.pdf').writeAsBytesSync(b);
  });

  yaziOlcegiEkseni(() {
    testWidgets(
        'açılır sayfa: konu başlığı, satırlar, paylaş düğmesi; taşma yok',
        (tester) async {
      tester.view.physicalSize = const Size(375 * 3, 812 * 3);
      tester.view.devicePixelRatio = 3.0;
      yaziOlceginiUygula(tester);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          extensions: const [SandikPalette.dark],
        ),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showYorumNotu(context, _notu()),
                child: const Text('aç'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Son 3 ay'), findsOneWidget);
      final liste = find.byType(Scrollable).last;
      await tester.scrollUntilVisible(find.text('+%11,4'), 120,
          scrollable: liste);
      expect(find.text('+%11,4'), findsOneWidget);
      final konu = find.textContaining('Alım gücü. ', findRichText: true);
      await tester.scrollUntilVisible(konu, 120, scrollable: liste);
      expect(konu, findsOneWidget);
      expect(find.text('PDF olarak paylaş'), findsOneWidget);
      expect(find.textContaining('Yatırım tavsiyesi değildir'), findsOneWidget);
    });
  });

  group('belge dosya adı (2026-10-31)', () {
    setUpAll(() => initializeDateFormatting('tr_TR'));

    PortfoyYorumu y(YorumTuru tur, DateTime bas, DateTime bit) => PortfoyYorumu(
          tur: tur,
          baslangic: bas,
          bitis: bit,
          parmakIzi: 'x',
          baslik: 'b',
          maddeler: const [],
          olcumler: const [],
          olusturuldu: bit,
        );

    test('haftalık, aylık ve varlık notu dönemiyle adlanır', () {
      expect(
          YorumNotu.kur(
            y(YorumTuru.haftalik, DateTime(2026, 10, 19),
                DateTime(2026, 10, 25)),
            kapsam: YorumKapsami.portfoy,
            donemAdi: 'Geçen hafta',
          ).dosyaAdi,
          'sandık Portföy Değerlendirme Notu Haftalık 2026-10-19 (19-25 Ekim)');
      expect(
          YorumNotu.kur(
            y(YorumTuru.aylik, DateTime(2026, 9, 1), DateTime(2026, 9, 30)),
            kapsam: YorumKapsami.portfoy,
            donemAdi: 'Geçen ay',
          ).dosyaAdi,
          'sandık Portföy Değerlendirme Notu Aylık 2026-09 (Eylül)');
      expect(
          YorumNotu.kur(
            y(YorumTuru.secili, DateTime(2026, 9, 14), DateTime(2026, 10, 14)),
            kapsam: YorumKapsami.varlik,
            varlikAdi: 'THYAO',
            donemAdi: 'Son 1 ay',
          ).dosyaAdi,
          'sandık Varlık Değerlendirme Notu THYAO Son 1 ay 2026-10-14');
    });

    test('ay taşan hafta iki ayı da yazar; yasak karakter ayıklanır', () {
      expect(haftaDonemi(DateTime(2026, 9, 28), DateTime(2026, 10, 4)),
          '2026-09-28 (28 Eylül-4 Ekim)');
      expect(belgeDosyaAdi('Varlık Notu', '2026-10-14', varlik: 'USD/TRY'),
          'sandık Varlık Notu USD-TRY 2026-10-14');
      expect(anDonemi(DateTime(2026, 10, 31, 9, 5)), '2026-10-31 09.05');
    });

    test('aynı türün adları zaman sırasıyla dizilir', () {
      final adlar = [
        belgeDosyaAdi('Aylık Rapor', ayDonemi(DateTime(2026, 12))),
        belgeDosyaAdi('Aylık Rapor', ayDonemi(DateTime(2026, 2))),
        belgeDosyaAdi('Aylık Rapor', ayDonemi(DateTime(2027, 1))),
      ]..sort();
      expect(adlar, [
        'sandık Aylık Rapor 2026-02 (Şubat)',
        'sandık Aylık Rapor 2026-12 (Aralık)',
        'sandık Aylık Rapor 2027-01 (Ocak)',
      ]);
    });
  });
}
