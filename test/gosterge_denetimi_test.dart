import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/services/notification_service.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';
import 'package:portfoy_takip/utils/mum_turetici.dart';

/// Gösterge tutarlılık denetimi (2026-10-11) bulgularının kilitleri.
/// Rapor: https://claude.ai/artifact/PtmrdPz5fDLBKmnx9SrReC
void main() {
  // Bağımsız Wilder RSI (TradingView `ta.rsi` tanımı).
  double wilder(List<double> p, int n) {
    double g = 0, l = 0;
    for (var i = 1; i <= n; i++) {
      final d = p[i] - p[i - 1];
      if (d > 0) {
        g += d;
      } else {
        l -= d;
      }
    }
    g /= n;
    l /= n;
    for (var i = n + 1; i < p.length; i++) {
      final d = p[i] - p[i - 1];
      g = (g * (n - 1) + (d > 0 ? d : 0)) / n;
      l = (l * (n - 1) + (d < 0 ? -d : 0)) / n;
    }
    return l == 0 ? 100 : 100 - 100 / (1 + g / l);
  }

  final dalga = [for (var i = 0; i < 120; i++) 100 + 8 * math.sin(i / 5) + i * 0.1];

  group('bulgu 4 · RSI', () {
    test('Wilder RSI ile aynı değer (TradingView tanımı)', () {
      final r = TechnicalAnalysisService.rsi(dalga, AssetType.hisse);
      expect(r.value, closeTo(wilder(dalga, 14), 1e-9));
    });

    test('eşik her türde 70/30', () {
      // 40 gün yatay, 12 gün kesintisiz düşüş → RSI 30'un altında.
      final p = [
        for (var i = 0; i < 40; i++) 100 + (i.isEven ? 1.0 : -1.0),
        for (var i = 1; i <= 12; i++) 100 - i * 1.5,
      ];
      for (final t in [AssetType.hisse, AssetType.altin, AssetType.fon]) {
        final r = TechnicalAnalysisService.rsi(p, t);
        expect(r.value < 30, isTrue);
        expect(r.signal, SignalType.buy, reason: '${t.name} 30 altı');
      }
    });
  });

  group('bulgu 1 · aşırılık trend diye etiketlenmez', () {
    test('sert düşüşte "al" oyu dönüş göstergelerinden → donus', () {
      final p = [
        for (var i = 0; i < 60; i++) 100 + (i.isEven ? 0.5 : -0.5),
        for (var i = 1; i <= 10; i++) 100 * math.pow(0.98, i).toDouble(),
      ];
      final inds = TechnicalAnalysisService.analyzeSeries(p, AssetType.hisse,
          enabledIds: {IndicatorId.rsi, IndicatorId.macd, IndicatorId.bollinger});
      final s = TechnicalAnalysisService.summarize(inds);
      expect(s.signal, isNot(SignalType.sell));
      if (s.signal == SignalType.buy) expect(s.donus, isTrue);
    });

    test('trend göstergeleri çoğunluktaysa donus false', () {
      TechnicalIndicator g(String id, SignalType s) => TechnicalIndicator(
          id: id, name: id, value: 0, signal: s, description: '');
      final s = TechnicalAnalysisService.summarize([
        g(IndicatorId.macd, SignalType.buy),
        g(IndicatorId.ema, SignalType.buy),
        g(IndicatorId.rsi, SignalType.buy),
      ]);
      expect(s.signal, SignalType.buy);
      expect(s.donus, isFalse);
    });
  });

  group('bulgu 5 · W%R ikinci oy değil', () {
    test('Stokastik açıkken W%R sayılmaz; panel ikisini de gösterir', () {
      final inds = TechnicalAnalysisService.analyzeSeries(
        dalga,
        AssetType.hisse,
        enabledIds: {IndicatorId.stochastic, IndicatorId.williamsR},
        izinli: IndicatorId.all.toSet(),
      );
      expect(inds, hasLength(2));
      expect(TechnicalAnalysisService.summarize(inds).toplam, 1);
    });
  });

  group('bulgu 6 · trend gücü adı', () {
    test('ADX diye etiketlenmez', () {
      final r = TechnicalAnalysisService.adx(dalga, AssetType.hisse);
      expect(r.name, startsWith('Trend Gücü'));
      expect(IndicatorId.labelOf(IndicatorId.adx), isNot(contains('ADX')));
    });
  });

  group('bulgu 7 · güven paydası', () {
    test('push metni tüm göstergeleri payda alır', () {
      final m = NotificationService.buildSignalMessage(
        assetName: 'Türk Hava Yolları',
        ticker: 'THYAO.IS',
        signal: SignalType.buy,
        buyCount: 2,
        sellCount: 0,
        toplam: 3,
      );
      expect(m.body, startsWith('2/3 gösterge yukarı · güven %67.'));
    });

    test('aşırılık bildirimi yön değil bölge yazar', () {
      final m = NotificationService.buildSignalMessage(
        assetName: 'Türk Hava Yolları',
        ticker: 'THYAO.IS',
        signal: SignalType.buy,
        buyCount: 2,
        sellCount: 0,
        toplam: 3,
        donus: true,
      );
      expect(m.title, '▼ THYAO · aşırı satım bölgesinde');
      expect(m.title, isNot(contains('yukarı')));
    });
  });

  group('bulgu 12 · MACD açıklaması yüzde', () {
    test('ucuz varlıkta "+0,00" yazmaz', () {
      final ucuz = [for (final v in dalga) v / 80]; // ~₺1,25
      final r = TechnicalAnalysisService.macd(ucuz, AssetType.fon);
      expect(r.description, contains('%'));
      expect(r.description, isNot(contains('0,00)')));
    });
  });

  group('bulgu 9 · eksen bandı', () {
    double doluluk(double fiyat) {
      final mn = fiyat * 0.985, mx = fiyat * 1.015;
      final b = gorunurYBandi(
        dataMinY: mn,
        dataMaxY: mx,
        avgY: fiyat,
        asgariBantOrani: 0.02,
        asgariAralik: fiyatAsgariAraligi(log: false, ortalama: fiyat),
      );
      return (mx - mn) / (b.maxY - b.minY);
    }

    test('%3 hareket ucuz ve pahalı varlıkta benzer yükseklik', () {
      final pahali = doluluk(250);
      for (final f in [10.0, 1.2345, 0.05]) {
        expect(doluluk(f), closeTo(pahali, 0.2),
            reason: '₺$f grafiği düzleşiyor');
      }
    });

    test('LOG\'da ₺1 altı fiyat bandın içinde kalır', () {
      // log10(0,485) ≈ −0,314; log10(0,515) ≈ −0,288.
      const mn = -0.3142, mx = -0.2882;
      final b = gorunurYBandi(
        dataMinY: mn,
        dataMaxY: mx,
        avgY: (mn + mx) / 2,
        asgariBantOrani: 0,
        asgariAralik: fiyatAsgariAraligi(log: true, ortalama: 0),
      );
      expect(b.minY, lessThanOrEqualTo(mn));
      expect(b.maxY, greaterThanOrEqualTo(mx));
    });

    test('pozitif veride alt sınır yine 0\'ın altına inmez', () {
      final b = gorunurYBandi(
          dataMinY: 0.1, dataMaxY: 100, avgY: 50, asgariBantOrani: 0.02);
      expect(b.minY, greaterThanOrEqualTo(0));
    });
  });

  group('bulgu 13 · para akışı mumun gövdesine yazılmaz', () {
    const gun = 24 * 60 * 60 * 1000.0;
    final t0 = DateTime(2026, 10, 5).millisecondsSinceEpoch.toDouble();

    test('alım günü büyük yeşil mum olmaz, kapanış gerçek değer', () {
      // Gün 0: 10.000; gün 1: 50.000 TL alım (+%1 piyasa) → 60.100.
      final spots = [FlSpot(t0, 10000), FlSpot(t0 + gun, 60100)];
      final mumlar =
          mumlariTuret(spots, kovaMs: gun, akislar: {t0 + gun: 50000});
      final m = mumlar.last;
      expect(m.kapanis, 60100);
      expect(m.kapanis - m.acilis, closeTo(100, 1e-6),
          reason: 'gövde yalnız piyasa hareketi');
    });

    test('akışsız seride mumlar birebir eskisi', () {
      final spots = [
        FlSpot(t0, 100),
        FlSpot(t0 + gun / 2, 104),
        FlSpot(t0 + gun, 102),
      ];
      final eski = mumlariTuret(spots, kovaMs: gun);
      final yeni = mumlariTuret(spots, kovaMs: gun, akislar: const {});
      expect([for (final m in yeni) m.acilis],
          [for (final m in eski) m.acilis]);
      expect([for (final m in yeni) m.kapanis],
          [for (final m in eski) m.kapanis]);
    });
  });

  group('bulgu 8 · parametre sınırları pencereye sığar', () {
    test('EMA uzun ≤ 100, MACD yavaş+sinyal ≤ 110', () {
      final ema = GostergeParametreleri.tanimlar[IndicatorId.ema]!;
      final macd = GostergeParametreleri.tanimlar[IndicatorId.macd]!;
      expect(ema.firstWhere((p) => p.anahtar == 'uzun').enCok, 100);
      final yavas = macd.firstWhere((p) => p.anahtar == 'yavas').enCok;
      final sinyal = macd.firstWhere((p) => p.anahtar == 'sinyal').enCok;
      expect(yavas + sinyal, lessThanOrEqualTo(110));
    });
  });
}
