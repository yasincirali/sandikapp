import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart'
    show ResolutionTier;
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:portfoy_takip/utils/hareketli_ortalama.dart';
import 'package:portfoy_takip/utils/mum_turetici.dart';

/// EMA50/EMA200 ve log mum hesapları (varlık detayı, 2026-10-10).
void main() {
  group('emaSeries', () {
    test('ilk period-1 eleman NaN, tohum basit ortalama', () {
      final e = TechnicalAnalysisService.emaSeries([1, 2, 3, 4, 5], 3);
      expect(e[0].isNaN, isTrue);
      expect(e[1].isNaN, isTrue);
      expect(e[2], closeTo(2, 1e-12)); // (1+2+3)/3
      // k = 2/(3+1) = 0.5 → 4*0.5 + 2*0.5 = 3; 5*0.5 + 3*0.5 = 4
      expect(e[3], closeTo(3, 1e-12));
      expect(e[4], closeTo(4, 1e-12));
    });

    test('sabit seride EMA sabit', () {
      final e = TechnicalAnalysisService.emaSeries(List.filled(300, 7.5), 200);
      for (var i = 199; i < 300; i++) {
        expect(e[i], closeTo(7.5, 1e-9));
      }
    });

    test('yetersiz veri → tamamı NaN (uydurma yok)', () {
      final e = TechnicalAnalysisService.emaSeries([1, 2, 3], 50);
      expect(e.every((v) => v.isNaN), isTrue);
    });

    test('EMA yükselen seride SMA\'dan hızlı tepki verir', () {
      final p = [for (var i = 0; i < 120; i++) i < 100 ? 10.0 : 20.0];
      final ema = TechnicalAnalysisService.emaSeries(p, 50);
      final sma = TechnicalAnalysisService.smaSeries(p, 50);
      expect(ema.last, greaterThan(sma.last));
    });
  });

  group('emaNoktalari', () {
    final seri = [for (var i = 0; i < 30; i++) FlSpot(i.toDouble(), 100.0 + i)];

    test('ısınma yoksa ve seri kısaysa çizgi yok', () {
      expect(emaNoktalari(seri, periyot: 50), isEmpty);
    });

    test('ısınma serisiyle çizgi dönemin İLK noktasından başlar', () {
      final on = [
        for (var i = -60; i < 5; i++) FlSpot(i.toDouble(), 90.0),
      ];
      final e = emaNoktalari(seri, periyot: 50, onSeri: on);
      expect(e.first.x, 0);
      expect(e.length, seri.length);
      // Örtüşen kısım (x ≥ 0) grafiğin KENDİ noktalarından: ısınma
      // serisinin 0..4'teki 90'ları kullanılmaz.
      final yalnizOn = emaNoktalari(seri,
          periyot: 50, onSeri: [for (var i = -60; i < 0; i++) FlSpot(i.toDouble(), 90.0)]);
      expect(e.last.y, closeTo(yalnizOn.last.y, 1e-9));
    });

    test('sıfır/negatif ısınma noktası (verisiz kova) atlanır', () {
      final on = [
        for (var i = -60; i < 0; i++) FlSpot(i.toDouble(), i.isEven ? 0 : 90),
      ];
      final e = emaNoktalari(seri, periyot: 50, onSeri: on);
      // 30 geçerli ön nokta + 30 seri = 60 ≥ 50 → çizilir, 0'lar ortalamayı
      // aşağı çekmez.
      expect(e, isNotEmpty);
      expect(e.first.y, greaterThan(89));
    });
  });

  group('emaGeriBakisGunu', () {
    test('katmana göre en az 200 çubuk kapsar', () {
      expect(emaGeriBakisGunu(ResolutionTier.weekly, 200),
          greaterThanOrEqualTo(200 * 7));
      expect(emaGeriBakisGunu(ResolutionTier.daily, 200),
          greaterThanOrEqualTo(280)); // 200 işlem günü ≈ 280 takvim günü
      expect(emaGeriBakisGunu(ResolutionTier.hourly, 200),
          greaterThanOrEqualTo(35));
    });

    test('gün içi (5 dk) için geri bakış yok', () {
      expect(emaGeriBakisGunu(ResolutionTier.fiveMin, 200), 0);
    });
  });

  group('mumlariDonustur (log mum)', () {
    test('log10 monoton: yön ve uçların sırası korunur', () {
      const m = Mum(
          x: 0,
          kovaMs: 1,
          acilis: 100,
          enYuksek: 1000,
          enDusuk: 10,
          kapanis: 500,
          noktaSayisi: 4);
      final l = mumlariDonustur([m], log10Fiyat).single;
      expect(l.acilis, closeTo(2, 1e-12));
      expect(l.enYuksek, closeTo(3, 1e-12));
      expect(l.enDusuk, closeTo(1, 1e-12));
      expect(l.yukselen, isTrue);
      expect(l.enDusuk <= l.acilis && l.kapanis <= l.enYuksek, isTrue);
      expect(l.merkezX, m.merkezX);
    });

    test('sıfır fiyat log\'da patlamaz', () {
      expect(log10Fiyat(0).isFinite, isTrue);
    });
  });
}
