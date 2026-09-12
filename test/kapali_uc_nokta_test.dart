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

  test('"ŞİMDİ" etiketi kapalıyken de doğru', () {
    // Ölçüt takvim değil geometri — seri bugüne uzandığı için sağ uç
    // gerçekten şu anı gösteriyor.
    expect(kaynak.contains('ucNoktaSimdiMi'), isTrue);
    expect(kaynak.contains('final bugunMu ='), isFalse,
        reason: 'Gün eşitliği koşulu geri gelmiş.');
  });
}
