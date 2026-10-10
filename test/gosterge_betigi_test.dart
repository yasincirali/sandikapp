import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/gosterge_betigi/betik.dart';
import 'package:portfoy_takip/services/gosterge_betigi/katalog.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';

/// Kendi göstergeni yaz — dilin doğruluğu ve güvenlik sınırları.
BetikVerisi _veri(int n) {
  final kap = [
    for (var i = 0; i < n; i++) 100 + 10 * math.sin(i / 7) + i * 0.1,
  ];
  return BetikVerisi.yalnizKapanis(
      [for (var i = 0; i < n; i++) i.toDouble()], kap);
}

BetikHatasi _hataAl(String kod, [BetikVerisi? v]) {
  try {
    GostergeBetigi.calistir(kod, v ?? _veri(50));
  } on BetikHatasi catch (e) {
    return e;
  }
  fail('Hata bekleniyordu: $kod');
}

void main() {
  group('hesap paritesi', () {
    final v = _veri(300);
    test('sma/ema TechnicalAnalysisService ile aynı', () {
      final s = GostergeBetigi.calistir(
          'plot(sma(close, 20))\nplot(ema(close, 50))', v);
      final sma = TechnicalAnalysisService.smaSeries(v.kapanis, 20);
      final ema = TechnicalAnalysisService.emaSeries(v.kapanis, 50);
      for (var i = 0; i < v.uzunluk; i++) {
        expect(s.cizgiler[0].degerler[i].isNaN, sma[i].isNaN);
        expect(s.cizgiler[1].degerler[i].isNaN, ema[i].isNaN);
        if (!sma[i].isNaN) {
          expect(s.cizgiler[0].degerler[i], closeTo(sma[i], 1e-9));
        }
        if (!ema[i].isNaN) {
          expect(s.cizgiler[1].degerler[i], closeTo(ema[i], 1e-9));
        }
      }
    });

    test('rsi 0–100 aralığında, sabit artışta 100', () {
      final s = GostergeBetigi.calistir('plot(rsi(close, 14))', v);
      final degerler = s.cizgiler.first.degerler.where((x) => !x.isNaN);
      expect(degerler, isNotEmpty);
      expect(degerler.every((x) => x >= 0 && x <= 100), isTrue);
      final artan = BetikVerisi.yalnizKapanis(
          [for (var i = 0; i < 30; i++) i.toDouble()],
          [for (var i = 0; i < 30; i++) 10.0 + i]);
      final r = GostergeBetigi.calistir('plot(rsi(close, 14))', artan);
      expect(r.cizgiler.first.degerler.last, 100);
    });

    test('geçmiş indeksi ve crossover', () {
      final d = BetikVerisi.yalnizKapanis(
          [0, 1, 2, 3, 4], [1, 2, 3, 2, 4]);
      final s = GostergeBetigi.calistir(
          'plot(close[1])\nplotshape(crossover(close, 2.5))', d);
      expect(s.cizgiler.first.degerler.first.isNaN, isTrue);
      expect(s.cizgiler.first.degerler.sublist(1), [1, 2, 3, 2]);
      expect(s.isaretler.first.indeksler, [2, 4]);
    });

    test('koşul, mantık ve Türkçe takma adlar', () {
      final d = BetikVerisi.yalnizKapanis([0, 1, 2], [1, 5, 3]);
      final s = GostergeBetigi.calistir(
          'buyuk = kapanis > 2 ve not (kapanis == 5)\n'
          'ciz(buyuk ? kapanis : 0, "x", renk.yesil)',
          d);
      expect(s.cizgiler.first.degerler, [0, 0, 3]);
      expect(s.cizgiler.first.renk, 'yesil');
      expect(s.cizgiler.first.ad, 'x');
    });

    test('ta. ve math. önekleri, sıfıra bölme na', () {
      final d = BetikVerisi.yalnizKapanis([0, 1], [0, 4]);
      final s = GostergeBetigi.calistir(
          'plot(math.sqrt(close) + ta.sma(close, 1))\nplot(1 / close)', d);
      expect(s.cizgiler[0].degerler, [0, 6]);
      expect(s.cizgiler[1].degerler.first.isNaN, isTrue);
    });

    test('indicator overlay=false ayrı panel + hline', () {
      final s = GostergeBetigi.calistir(
          'indicator("RSI", overlay=false)\nplot(rsi(close,14))\nhline(70)',
          v);
      expect(s.fiyatUstunde, isFalse);
      expect(s.baslik, 'RSI');
      expect(s.yataylar.single.deger, 70);
    });
  });

  group('eksik veri dürüstçe söylenir', () {
    test('yalnız kapanış varken high/volume na ve eksikVeri dolu', () {
      final s = GostergeBetigi.calistir(
          'plot(atr(14))\nplot(sma(volume, 5))', _veri(40));
      expect(s.cizgiler.every((c) => c.degerler.every((x) => x.isNaN)),
          isTrue);
      expect(s.eksikVeri, containsAll(['yuksek', 'hacim']));
      expect(s.bos, isTrue);
    });

    test('OHLC gelince atr çizilir', () {
      const n = 40;
      final v = BetikVerisi(
        x: [for (var i = 0; i < n; i++) i.toDouble()],
        acilis: [for (var i = 0; i < n; i++) 100.0 + i],
        yuksek: [for (var i = 0; i < n; i++) 102.0 + i],
        dusuk: [for (var i = 0; i < n; i++) 99.0 + i],
        kapanis: [for (var i = 0; i < n; i++) 101.0 + i],
        hacim: [for (var i = 0; i < n; i++) 1000.0],
      );
      final s = GostergeBetigi.calistir('plot(atr(14))', v);
      expect(s.eksikVeri, isEmpty);
      expect(s.cizgiler.first.degerler.last, closeTo(3, 1e-9));
    });
  });

  group('güvenlik: dil kaçamaz, sınırlar tutar', () {
    for (final kod in [
      'for i = 0 to 10\nplot(close)',
      'while true\nplot(close)',
      'if close > 1\nplot(close)',
      'import foo\nplot(close)',
      'x = request.security("THYAO", "D", close)\nplot(x)',
      'strategy.entry("al")',
      'def f(): pass',
    ]) {
      test('reddedilir: ${kod.split('\n').first}', () {
        expect(_hataAl(kod).mesaj, isNotEmpty);
      });
    }

    test('çok uzun kod', () {
      expect(_hataAl('plot(close)\n${'// x\n' * 1000}').mesaj,
          contains('uzun'));
    });

    test('dev pencere reddedilir', () {
      expect(_hataAl('plot(sma(close, 100000))').mesaj, contains('arasında'));
    });

    test('uzunluk sabit olmalı', () {
      expect(_hataAl('plot(sma(close, close))').mesaj, contains('sabit'));
    });

    test('çok iç içe ifade', () {
      expect(_hataAl('plot(${'(' * 200}1${')' * 200})').mesaj,
          contains('iç içe'));
    });

    test('çizgi sayısı sınırı', () {
      expect(_hataAl(List.filled(9, 'plot(close)').join('\n')).mesaj,
          contains('çizgi'));
    });

    test('ağır betik bütçede durur', () {
      final kod = [
        for (var i = 0; i < 60; i++) 'a$i = stdev(close, 500)',
        'plot(a0)',
      ].join('\n');
      expect(_hataAl(kod, _veri(5000)).mesaj, contains('ağır'));
    });

    test('çok çubuk sondan kırpılır', () {
      final s = GostergeBetigi.calistir('plot(close)', _veri(8000));
      expect(s.x.length, kBetikAzamiCubuk);
      expect(s.x.last, 7999);
    });
  });

  group('yardımcı hata mesajları', () {
    test('yazım hatasına öneri', () {
      final h = _hataAl('plot(smaa(close, 3))');
      expect(h.mesaj, contains("'sma'"));
      expect(h.satir, 1);
    });
    test('satır/sütun', () {
      final h = _hataAl('x = 1\nplot(close +)');
      expect(h.satir, 2);
    });
    test('plot yoksa', () {
      expect(_hataAl('x = sma(close, 5)').mesaj, contains('plot'));
    });
    test('yeniden tanım', () {
      expect(_hataAl('x = 1\nx = 2\nplot(x)').mesaj, contains('zaten'));
    });
    test('yerleşik adı ezme', () {
      expect(_hataAl('close = 1\nplot(close)').mesaj, contains('yerleşik'));
    });
    test('İngilizce mesaj da var', () {
      expect(_hataAl('plot(foo)').mesajEn, contains('Undefined'));
    });
  });

  test('bütün şablonlar derlenir ve bir şey çizer', () {
    for (final s in kBetikSablonlari) {
      final r = GostergeBetigi.calistir(s.kod, _veri(300));
      expect(r.bos, isFalse, reason: s.kimlik);
    }
  });
}
