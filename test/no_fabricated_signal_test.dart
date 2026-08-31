import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/technical_signal.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';

/// Sinyal UYDURMA fiyattan hesaplanmamalı.
///
/// **Bug (2026-08-31):** Push bildirimi "yukarı yönlü" derken, bildirime
/// tıklayıp açılan ekran aynı varlık için "SAT" gösteriyordu.
///
/// **Kök neden:** `TechnicalAnalysisService.analyze` boş fiyat geçmişi
/// aldığında `_simulate()`'e düşüyordu — `Random` ile UYDURMA bir seri
/// üretir. Üç istemci yüzeyi de `analyze(asset, const [])` çağırıyordu:
///   1. `performance_screen` → teknik sinyal paneli (ekranda görünen)
///   2. `signal_provider.analyzePortfolio` → DB'ye sinyal YAZAN yol
///   3. `portfolio_performance_screen` → portföy sinyal paneli
/// Yani ekrandaki sinyal rastgele veriden geliyordu. Push ise sunucuda
/// GERÇEK piyasa serisinden üretiliyor — iki taraf farklı sayılara bakınca
/// zıt sinyaller çıkıyordu.
///
/// Sunucu tarafında bu kural zaten vardı:
/// `supabase/tests/technical_analysis_test.ts` →
/// "fiyat geçmişi yoksa sinyal üretilmez (simülasyona düşmez)".
/// Bu dosya aynı kuralı istemciye getirir.

Asset _asset() => Asset(
      id: 'a1',
      userId: 'u1',
      name: 'Gram Altın',
      ticker: 'ALTIN_GRAM',
      type: AssetType.altin,
      quantity: 10,
      purchasePrice: 4000,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      purchaseFxRate: 1.0,
      currentPrice: 5000,
      addedDate: DateTime(2026, 1, 15),
    );

void main() {
  group('fiyat geçmişi yoksa sinyal üretilmez', () {
    test('boş seri BOŞ gösterge listesi döndürür', () {
      final inds = TechnicalAnalysisService.analyze(_asset(), const []);
      expect(inds, isEmpty,
          reason: 'uydurma seriden gösterge üretilmemeli');
    });

    test('boş seri → nötr özet, sıfır güven', () {
      final inds = TechnicalAnalysisService.analyze(_asset(), const []);
      final s = TechnicalAnalysisService.summarize(inds);
      expect(s.signal, SignalType.neutral);
      expect(s.confidence, 0.0,
          reason: 'sinyal yokken güven 0 olmalı — eşiği geçmemeli');
    });

    test('aynı varlık için sonuç DETERMİNİSTİK', () {
      // `_simulate` tohumu `ticker.hashCode ^ bugünün tarihi` idi: aynı gün
      // içinde sabit ama gün dönünce DEĞİŞİYORDU. Yani kullanıcı dün "AL"
      // görüp bugün "SAT" görebiliyordu, fiyat hiç oynamasa bile.
      final a = TechnicalAnalysisService.analyze(_asset(), const []);
      final b = TechnicalAnalysisService.analyze(_asset(), const []);
      expect(a.length, b.length);
      expect(a, isEmpty);
    });

    test('GERÇEK seri verilince göstergeler hesaplanır', () {
      // Kuralın diğer yüzü: veri varsa analiz normal çalışmalı.
      final prices = <double>[
        for (int i = 0; i < 120; i++) 4000 + (i * 12).toDouble(),
      ];
      final inds = TechnicalAnalysisService.analyze(_asset(), prices);
      expect(inds, isNotEmpty, reason: 'gerçek seride gösterge üretilmeli');

      final s = TechnicalAnalysisService.summarize(inds);
      // Sinyalin YÖNÜ burada iddia EDİLMEZ. Kesintisiz yükselen bir seri
      // sezgisel olarak "AL" gibi görünür ama RSI/Stochastic aşırı alım
      // bölgesine girip "SAT" üretir — bu göstergelerin doğru davranışıdır.
      // Bu testin konusu yön değil, gerçek seriden HESAPLANIYOR olması.
      expect(s.confidence, greaterThan(0),
          reason: 'gerçek seride güven sıfırdan büyük olmalı');
      expect(s.buyCount + s.sellCount, greaterThan(0),
          reason: 'göstergeler bir yöne oy vermeli');
    });

    test('allowSimulation açıkça istenirse eski davranış korunur', () {
      // Kaçış kapısı duruyor ama VARSAYILAN DEĞİL — demo/önizleme için.
      final inds = TechnicalAnalysisService.analyze(
        _asset(),
        const [],
        allowSimulation: true,
      );
      expect(inds, isNotEmpty);
    });
  });

  group('bağlantı koruması — hiçbir üretim yolu simülasyon açmamalı', () {
    // Birim testi fonksiyonun doğru olduğunu kanıtlar, KULLANILDIĞINI değil.
    // Asıl hata çağrı yerindeydi. Bu yüzden kaynak metni denetlenir.
    test('lib/ içinde allowSimulation: true YOK', () async {
      final dir = Directory('lib');
      final hits = <String>[];
      await for (final f in dir.list(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = await f.readAsString();
        if (src.contains('allowSimulation: true')) hits.add(f.path);
      }
      expect(hits, isEmpty,
          reason: 'Üretim kodunda simülasyon açılmamalı — sinyal uydurma '
              'fiyattan hesaplanır ve push ile çelişir. Bulunan: $hits');
    });

    test('sinyal yazan yol GERÇEK fiyat geçmişi çeker', () async {
      final src =
          await File('lib/providers/signal_provider.dart').readAsString();
      expect(src.contains('getSymbolHistory'), isTrue,
          reason: 'analyzePortfolio gerçek seriyi çekmeli — aksi halde '
              'DB\'ye uydurma sinyal yazılır.');
    });
  });
}
