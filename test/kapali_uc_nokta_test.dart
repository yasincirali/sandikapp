import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Piyasa kapalıyken kesikli kuyruk AÇTIĞIMIZ ANA kadar uzanmalı ve
/// "şu an" noktası o ucun üstünde, GRİ durmalı.
///
/// ## Yakaladığı hata (kullanıcı bildirimi 2026-09-12, ekran görüntüsüyle)
/// "Piyasa kapandıktan sonrasında da grafiği açtığımız ana kadar kesikli
/// çizgi gelmeli; şu an noktası piyasa kapalı andaysa gri şekilde kesikli
/// çizginin ucunda ve şu ana karşılık gelen time izdüşümünde
/// konumlanmalı."
///
/// Görselde "ŞİMDİ" dikey çizgisi Cuma KAPANIŞINDA duruyordu, kuyruk
/// boyunca uzanmıyordu.
///
/// ## Kök sebep
/// `gunIciSonNoktaDk` — yani "ŞİMDİ" çizgisinin ve sağ uç payının
/// dayandığı değer — `primarySeg.spots.last.x` okuyordu.
///
/// `primarySeg` "en KALIN segment" olarak seçilir. Seans segmenti 3.5,
/// piyasa kapalı kuyruğu 2.5 kalınlıkta; yani kuyruk hiç görülmüyordu.
/// Aynı sınıf hata crosshair'de de yaşanmıştı (bkz.
/// `kapali_bolge_dokunma_test.dart`) — `primarySeg` Y ekseni için doğru
/// kaynak ama "serinin sağ ucu" sorusu için yanlış.
void main() {
  final kaynak = File('lib/screens/portfolio_performance_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('sağ uç TÜM segmentlerden', () {
    test('`gunIciSonNoktaDk` primarySeg okumaz', () {
      expect(
        kaynak.contains('(primarySeg.spots.isEmpty ? 0.0 : primarySeg.spots.last.x)'),
        isFalse,
        reason: '"ŞİMDİ" çizgisi kuyruğu görmüyor — kapanışta kalır.',
      );
    });

    test('tüm segmentlerin en sağdaki noktası alınır', () {
      final tek = kaynak.replaceAll(RegExp(r'\s+'), ' ');
      expect(
        tek.contains(
            'segments .expand((s) => s.spots) .fold<double>(0.0, (m, s) => s.x > m ? s.x : m)'),
        isTrue,
        reason: 'Sağ uç hesabı tüm segmentleri kapsamıyor.',
      );
    });

    test('`primarySeg` Y ekseni için KORUNUR', () {
      // Birleşik listeyi Y sınırlarında kullanmak yanlış olurdu: passive
      // segment (0 çizgisi) min'i 0'a çeker ve aktif değerler ezilir.
      expect(kaynak.contains('segments.reduce((a, b) =>'), isTrue,
          reason: 'primarySeg seçimi kaldırılmış — Y ekseni bozulur.');
    });
  });

  group('uç nokta rengi', () {
    test('piyasa kapalıyken GRİ', () {
      expect(kaynak.contains('final kapali = seg.piyasaKapali;'), isTrue,
          reason: 'Kuyruk bilgisi okunmuyor.');
      expect(
        kaynak.contains('color: kapali ? context.c.text36 : context.c.gain'),
        isTrue,
        reason: 'Kapalı uçta yeşil nokta "şu anda işlem görüyor" der — '
            'oysa son kapanış taşınıyor.',
      );
    });

    test('piyasa AÇIKKEN yeşil KALIR', () {
      // Regresyon kapısı: canlı seansta vurgu değişmemeli.
      expect(kaynak.contains('context.c.gain'), isTrue);
    });
  });

  test('kuyruk çizgisi KESİKLİ kalır', () {
    // Uç nokta düzeltmesi kuyruk desenini bozmamalı.
    expect(kaynak.contains('dashArray: seg.piyasaKapali'), isTrue);
  });

  group('dikey "ŞİMDİ" çizgisi KALDIRILDI', () {
    // Kullanıcı isteği (2026-09-12): "şimdi çizgisine gerek yok, x ekseni
    // labellarıyla çakışıyor."
    //
    // Bilgi kaybı yok: serinin ucundaki nokta (kapalıyken gri) konumu
    // gösteriyor, üstteki kart da "11 Eyl → bugün · PİYASA KAPALI"
    // yazıyor.
    test('gün içi dalda dikey çizgi yok', () {
      expect(kaynak.contains('const ExtraLinesData(verticalLines: [])'), isTrue,
          reason: 'Gün içi dikey çizgi geri gelmiş — etiketlerle çakışır.');
    });

    test('eski "ŞİMDİ"/"KAPANIŞ" etiketi de kalkmış', () {
      expect(kaynak.contains("ucNoktaSimdiMi ? 'ŞİMDİ' : 'KAPANIŞ'"), isFalse,
          reason: 'Çizgi yokken etiket mantığı ölü kod.');
    });

    test('non-intraday "ŞİMDİ" çizgisi KORUNUR', () {
      // Orada X ekseni etiketleri seyrek (5 tick) ve çakışma yok.
      expect(kaynak.contains("labelResolver: (_) => 'ŞİMDİ'"), isTrue,
          reason: 'Gün dışı dönemlerdeki işaret de silinmiş.');
    });
  });

  group('kapalı kuyruk DÜZ kalır', () {
    // Kullanıcı bildirimi: "piyasa kapalı olmasına rağmen fiyat değişimi
    // olmuş; piyasa kapalı dedik ama fiyatı değişen bir varlık var."
    //
    // Sebep: kuyruğun ucuna CANLI toplam yazılıyordu. Kapanış fiyatından
    // farklıysa kuyruk yukarı/aşağı kırılıyor ve "piyasa kapalı" yazan
    // grafikte fiyat oynamış görünüyordu.
    test('canlı toplam kapalı kuyrukta UYGULANMAZ', () {
      expect(kaynak.contains('final kapaliKuyrukVar = piyasaKapaliBaslangicTs != null;'),
          isTrue,
          reason: 'Kapalı kuyruk kontrolü yok.');
      expect(kaynak.contains('!kapaliKuyrukVar &&'), isTrue,
          reason: 'Canlı toplam kapalı bölgede de yazılıyor — kuyruk '
              'kırılır.');
    });

    test('kuyruk son ÇİZİLEN değeri taşır', () {
      expect(kaynak.contains('final sonY = spots.last.y;'), isTrue,
          reason: 'Kuyruk düz kalmıyor.');
    });
  });
}
