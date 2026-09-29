import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/grafik_stili.dart';

import 'helpers/kaynak.dart';

/// Grafik eksen etiketleri TEK SATIR kalır — aşağı sarkmaz, kaymaz.
///
/// ## Kullanıcı sorusu (2026-09-29)
/// "Tüm chart/graph gösterimlerinde labellar aşağı sarkmamalı, kaymamalı;
/// bunu garanti altına aldık mı?" — Almamıştık. X ekseni yalnızca
/// Performans'ta ve varlık detayında korunuyordu; Y ekseni hiçbir grafikte,
/// takip listesi kıyas grafiğinin iki ekseni de korumasızdı. 52pt'lik Y
/// bandında "₺12,5 Mn" büyük yazıda ikinci satıra kırılıyordu.
///
/// ## Garanti iki katmanlı
///   1. YAPISAL: `lib/` altındaki HER `getTitlesWidget` ya hiçbir şey
///      çizmez (`SizedBox.shrink`) ya da `GrafikStili.yEtiketi` /
///      `xEtiketi`'nden geçer. Yeni bir grafik kendi `Text`'ini yazarsa
///      bu test kırılır — korumayı hatırlamak geliştiriciye kalmaz.
///   2. ÖLÇÜM: iki bileşen dar kutuda ve büyük yazı ölçeğinde gerçekten
///      tek satır yüksekliğinde kalır.
void main() {
  group('yapısal — her eksen etiketi ortak bileşenden geçer', () {
    final dosyalar = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => !f.path.replaceAll('\\', '/').contains('/generated/'))
        .toList();

    // Bir `getTitlesWidget:` bloğu, ondan sonraki ilk eksen/grafik
    // alanına kadar sürer. Kaba ama yeterli: fl_chart'ın bu alanları
    // `titlesData` içinde art arda yazılır.
    const sinirlar = [
      'getTitlesWidget:',
      'sideTitles:',
      'AxisTitles(',
      'lineTouchData:',
      'gridData:',
      'borderData:',
      'extraLinesData:',
      'lineBarsData:',
      'barGroups:',
    ];

    final bloklar = <String, String>{};
    for (final f in dosyalar) {
      final kaynak = ekranKaynagiSync(f.path).replaceAll('\r\n', '\n');
      var i = kaynak.indexOf('getTitlesWidget:');
      var n = 0;
      while (i >= 0) {
        var son = kaynak.length;
        for (final s in sinirlar) {
          final j = kaynak.indexOf(s, i + 'getTitlesWidget:'.length);
          if (j >= 0 && j < son) son = j;
        }
        bloklar['${f.path} #${++n}'] = kaynak.substring(i, son);
        i = kaynak.indexOf('getTitlesWidget:', i + 1);
      }
    }

    test('en az bir eksen bulundu (tarayıcı körleşmedi)', () {
      // 2026-09-29: 4 dosyada 9 blok (performans, varlık detayı, fiyat
      // grafiği, takip listesi kıyası). Sayı düşerse tarayıcı bozulmuş
      // olabilir; artması serbest.
      expect(bloklar.length, greaterThanOrEqualTo(9));
    });

    for (final e in bloklar.entries) {
      test(e.key, () {
        final blok = e.value;
        final bosCizer = RegExp(r'getTitlesWidget:\s*\([^)]*\)\s*=>\s*const\s+SizedBox\.shrink\(\)')
            .hasMatch(blok);
        final ortak = blok.contains('GrafikStili.yEtiketi(') ||
            blok.contains('GrafikStili.xEtiketi(');
        expect(bosCizer || ortak, isTrue,
            reason: 'Eksen etiketi `GrafikStili.yEtiketi`/`xEtiketi` '
                'dışında çiziliyor — sarma/kayma koruması yok.');
        // Ortak bileşenin YANINDA ham `Text(` de olmasın (ör. bir dalda
        // bileşen, başka dalda çıplak metin).
        expect(blok.contains('Text('), isFalse,
            reason: 'Blokta ham `Text(` var: ${e.key}');
      });
    }
  });

  group('ölçüm — dar kutu + büyük yazı', () {
    const stil = TextStyle(fontSize: 11);

    Future<double> yukseklik(WidgetTester tester, Widget etiket,
        {double genislik = 52, double olcek = 2.0}) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(olcek)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              // İç `Align`: fl_chart etiket widget'ına GEVŞEK kısıt verir;
              // sıkı kısıt `xEtiketi`'nin sabit kutusunu zorla genişletirdi.
              child: SizedBox(
                  width: genislik,
                  child: Align(alignment: Alignment.topLeft, child: etiket)),
            ),
          ),
        ),
      ));
      return tester.getSize(find.byType(Text)).height;
    }

    testWidgets('Y etiketi uzun değerde tek satır, küçülür ama kırpılmaz',
        (tester) async {
      final tek = await yukseklik(
          tester, GrafikStili.yEtiketi('₺1', stil: stil));
      final uzun = await yukseklik(tester,
          GrafikStili.yEtiketi('₺12.345.678,90 Mn', stil: stil));
      // FittedBox içindeki Text kendi doğal boyunda ölçülür: tek satırlık
      // metinle aynı yükseklik = ikinci satıra kırılmadı.
      expect(uzun, tek);
      // Metin tam — "…" yok.
      expect(find.text('₺12.345.678,90 Mn'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('X etiketi uzun tarihte tek satır, sabit genişlik',
        (tester) async {
      final tek = await yukseklik(
          tester, GrafikStili.xEtiketi('1', stil: stil),
          genislik: 200);
      final uzun = await yukseklik(
          tester,
          GrafikStili.xEtiketi('11 Eylül 2026 Perşembe 04:00', stil: stil),
          genislik: 200);
      expect(uzun, tek);
      // Kutu metne göre büyümez: tick'e ortalı etiket kaymaz.
      expect(
          tester.getSize(find.ancestor(
              of: find.byType(Text), matching: find.byType(SizedBox)).first).width,
          74);
      expect(tester.takeException(), isNull);
    });
  });
}
