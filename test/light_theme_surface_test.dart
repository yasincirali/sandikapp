import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// **Stok Material yüzeyleri iki temada da GÖRÜNÜR olmalı.**
///
/// ## Ölçülen hata
/// `_buildTheme` paleti (`p`) parametre olarak alıyor ama dört yerde sabit
/// `Colors.white` yazıyordu:
///
///   kart kenarlığı   beyaz %5
///   input dolgusu    beyaz %5
///   chip zemini      beyaz %5
///   ayraç            beyaz %7
///
/// Dördü de İKİ TEMADA DA beyazdı. Koyu temada doğru görünüyordu; açık
/// temada (`background #F4F1EA`, `surface1 #FBFAF6`) beyaz %5 pratikte
/// görünmezdir — kartların kenarlığı yok oluyor, listeler ayraçsız tek blok
/// hâline geliyor, metin alanlarının dolgusu kayboluyordu. Kullanıcı
/// bulgusu: "tema dark mode light mode konusu da çalışmıyor".
///
/// ## Neden kaynak metni denetleniyor
/// `_buildTheme` özel bir metot ve `ThemeData` üretmek için tüm uygulamayı
/// ayağa kaldırmak gerekir. Asıl değişmez zaten sözdizimseldir: **tema
/// renkleri paletten (`p`) gelmeli**, moddan bağımsız bir sabitten değil.
/// Bunu doğrudan kaynakta ifade etmek, üretilen `ThemeData`'yı dolaylı
/// yoldan yoklamaktan hem daha kesin hem daha okunur.
void main() {
  group('_buildTheme moddan bağımsız sabit renk kullanmaz', () {
    /// `_buildTheme` gövdesi — brace eşlemesiyle çıkarılır.
    ///
    /// Kapsam daraltmak ZORUNLU: aynı dosyadaki yapılandırma hatası ekranı
    /// sabit koyu kırmızı bir zemin üstünde meşru olarak beyaz metin
    /// kullanıyor. Dosyanın tamamını taramak onu da yakalar ve testi
    /// gürültüye boğardı.
    String buildThemeBody() {
      final src = File('lib/main.dart').readAsStringSync();
      final start = src.indexOf('ThemeData _buildTheme(');
      expect(start, isNot(-1),
          reason: '_buildTheme bulunamadı — yeniden adlandırıldıysa bu test '
              'de güncellenmeli, silinmemeli');

      final open = src.indexOf('{', start);
      var depth = 0;
      for (var i = open; i < src.length; i++) {
        if (src[i] == '{') depth++;
        if (src[i] == '}') {
          depth--;
          if (depth == 0) return src.substring(open, i + 1);
        }
      }
      fail('_buildTheme gövdesi kapanmadı');
    }

    test('gövdede Colors.white / Colors.black geçmez', () {
      final body = buildThemeBody();
      // Yorum satırları hariç: açıklamalar eski hatayı ANLATIYOR ve içinde
      // "beyaz" geçebilir; denetlenen şey koddur.
      //
      // `scrim` ve `shadow` MEŞRU istisnadır ve elenir: ikisi de gerçekten
      // moddan bağımsızdır. Gölge açık temada da siyahtır (yalnızca opaklığı
      // değişir, rengi değil) ve modal perdesi iki temada da siyah zemindir.
      // Bunları palete taşımak olmayan bir ayrımı taklit etmek olurdu.
      // Kural yüzey/kenarlık/dolgu renkleri içindir — orada moddan bağımsız
      // bir sabit iki temadan birinde kaçınılmaz olarak yanlıştır.
      final kod = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .where((l) => !RegExp(r'^\s*(scrim|shadow):').hasMatch(l))
          .join('\n');

      final sizinti = RegExp(r'Colors\.(white|black)\w*')
          .allMatches(kod)
          .map((m) => m.group(0)!)
          .toSet();

      expect(sizinti, isEmpty,
          reason: 'tema rengi paletten (`p`) gelmeli. Moddan bağımsız bir '
              'sabit, iki temadan birinde kaçınılmaz olarak yanlış olur — '
              'beyaz %5 açık zeminde görünmez. Karşılığı yoksa '
              'sandik.dart\'a token ekle.');
    });

    test('dört yüzey slotu paletten besleniyor', () {
      // Yukarıdaki test "sabit yok" der; bu test "doğru token VAR" der.
      // İkisi ayrı: slot tamamen silinseydi ilk test yine geçerdi.
      final body = buildThemeBody();

      for (final beklenen in const [
        'side: BorderSide(color: p.hairline', // kart kenarlığı
        'fillColor: p.overlay', // input dolgusu
        'backgroundColor: p.overlay', // chip zemini
        'color: p.hairline', // ayraç
      ]) {
        expect(body, contains(beklenen),
            reason: '$beklenen kayboldu — yüzey slotu paletten beslenmiyor');
      }
    });
  });

  group('palet yönü', () {
    /// Kompozit alfa sonrası gerçek parlaklık — bir rengin "görünür mü"
    /// sorusu zemine bağlıdır, tek başına alfaya değil.
    double lumOver(Color c, Color zemin) {
      final a = c.a;
      return Color.from(
        alpha: 1,
        red: c.r * a + zemin.r * (1 - a),
        green: c.g * a + zemin.g * (1 - a),
        blue: c.b * a + zemin.b * (1 - a),
      ).computeLuminance();
    }

    test('hairline zeminden AYRIŞIR — iki temada da', () {
      // Asıl kusur buydu: açık temada beyaz bir hairline, açık zeminle
      // aynı parlaklığa oturuyor ve çizgi yok oluyordu.
      for (final (ad, p) in [
        ('dark', SandikPalette.dark),
        ('light', SandikPalette.light),
      ]) {
        final zemin = p.surface1;
        final fark =
            (lumOver(p.hairline, zemin) - zemin.computeLuminance()).abs();

        expect(fark, greaterThan(0.01),
            reason: '$ad: hairline yüzeyden ayrışmıyor — ayraç ve kart '
                'kenarlığı görünmez olur');
      }
    });

    test('light hairline KOYULAŞTIRIR, dark hairline AÇAR', () {
      // Yön testi. Açık temaya beyaz bir hairline konursa yukarıdaki eşik
      // sınırda geçebilir ama çizgi yine yanlış yöndedir.
      expect(
        lumOver(SandikPalette.light.hairline, SandikPalette.light.surface1),
        lessThan(SandikPalette.light.surface1.computeLuminance()),
        reason: 'açık temada ayraç zeminden KOYU olmalı',
      );
      expect(
        lumOver(SandikPalette.dark.hairline, SandikPalette.dark.surface1),
        greaterThan(SandikPalette.dark.surface1.computeLuminance()),
        reason: 'koyu temada ayraç zeminden AÇIK olmalı',
      );
    });
  });
}
