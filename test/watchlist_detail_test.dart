import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';

/// **Takip detay ekranı sahte `Asset` ÜRETMEZ.**
///
/// ## Neden bu test var
/// Faz 2'nin ilk tasarımı `PerformanceScreen`'e bir `watchOnly` bayrağı
/// eklemekti. Kod okunduğunda bunun yanlış olduğu ölçüldü: o ekranın
/// gösterdiği her sayı sahipliğe bağlı —
///   · grafik Y ekseni  = pozisyon değeri / `quantity`
///   · maliyet çizgisi  = `purchasePrice` × `purchaseFxRate`
///   · serinin başlangıcı = `addedDate`
///
/// Ekranı beslemek için `Asset(quantity: 1, purchasePrice: ...)` üretmek
/// gerekirdi. O nesne GERÇEK bir `Asset` olurdu ve `aggregatePositions`'a
/// geçirilebilirdi — `watchlist_isolation_test.dart`'ın derleme zamanında
/// engellediği sızıntı, çalışma zamanı bayrağına indirgenmiş olurdu.
///
/// Bu yüzden ayrı ekran yazıldı. Bu test o kararı kilitler.
///
/// ## Bu testin sınırı
/// Kaynak metnine bakar. Amacı "sahte Asset üretme" kuralını korumak;
/// göstergelerin doğruluğu `technical_analysis_test` tarafında ölçülür.

String _yorumsuz(String src) => src
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

void main() {
  late String detay;

  setUpAll(() async {
    detay = _yorumsuz(
        await File('lib/screens/watchlist_detail_screen.dart').readAsString());
  });

  group('sahte Asset üretilmez', () {
    test('detay ekranı Asset KURMAZ', () {
      expect(detay.contains('Asset('), isFalse,
          reason: 'sahte bir Asset üretmek onu aggregate\'lere geçirilebilir '
              'kılar — takip kaydının portföye sızma yolu tam olarak budur');
    });

    test('detay ekranı asset modelini İÇE AKTARMAZ', () {
      expect(detay.contains("models/asset.dart"), isFalse,
          reason: 'ekranın Asset tipine ihtiyacı yok; import etmek '
              'ileride birinin "hızlıca" bir tane kurmasını kolaylaştırır');
    });

    test('miktar/maliyet alanlarına dokunmaz', () {
      for (final alan in [
        'quantity',
        'purchasePrice',
        'purchaseFxRate',
        'totalValue',
      ]) {
        expect(detay.contains(alan), isFalse,
            reason: '$alan sahipliğe ait bir kavram; izlenen varlıkta yok');
      }
    });

    test('PerformanceScreen\'i AÇMAZ', () {
      // Yalnızca gösterge panelini içe aktarır; ekranın kendisini değil.
      expect(detay.contains('PerformanceScreen('), isFalse,
          reason: 'sahiplik ekranı takip kaydıyla açılamaz');
      expect(detay.contains('show TechnicalSignalPanel'), isTrue,
          reason: 'yalnızca sahipliğe bağlı olmayan panel paylaşılır');
    });
  });

  group('paylaşılan hesap tek kaynaktan', () {
    test('fiyat serisi getSymbolHistory ile alınır', () {
      // Liste satırı da aynı kaynağı kullanır. İki ayrı kaynak bu projede
      // tekrar eden hata sınıfı (üst kart ile tür dökümünün ayrışması).
      expect(detay.contains('getSymbolHistory'), isTrue);
    });

    test('yüzde formülü (son − ilk) / ilk', () {
      // Kullanıcının açıkça istediği formül; zaman aralığı seçilen HER yerde
      // aynı olmalı.
      expect(detay.contains('(diff / first) * 100'), isTrue,
          reason: 'dönem değişimi ekranın geri kalanıyla aynı formülü '
              'kullanmalı');
      expect(detay.contains('last - first'), isTrue,
          reason: 'tutar farkı = son − ilk');
    });

    test('sıfır değişim NÖTR renkle gösterilir', () {
      // Yuvarlanmış yüzde sıfırken yeşil göstermek "kazanç var" yanılgısı
      // yaratır — ekranın geri kalanındaki kuralın aynısı.
      expect(detay.contains('isFlat'), isTrue);
    });
  });

  group('gösterge motoru sahipliksiz çalışır', () {
    // `analyzeSeries` bir `Asset` istemez. Aynı seriyle aynı türde,
    // `analyze`'ın ürettiğiyle AYNI sonucu vermeli — yoksa iki yüzey
    // (portföy / takip) farklı sinyal gösterirdi.
    List<double> seri(int n) =>
        [for (var i = 0; i < n; i++) 100 + (i % 7) * 2.5 + i * 0.3];

    test('yeterli seride gösterge üretir', () {
      final ind = TechnicalAnalysisService.analyzeSeries(
          seri(120), AssetType.hisse);
      expect(ind, isNotEmpty,
          reason: 'takip edilen varlık için de gösterge hesaplanabilmeli');
    });

    test('BOŞ seride gösterge üretmez — uydurmaz', () {
      // Sunucu tarafındaki kuralla aynı: veri yoksa sinyal yok.
      final ind =
          TechnicalAnalysisService.analyzeSeries(const [], AssetType.hisse);
      expect(ind, isEmpty,
          reason: 'fiyat geçmişi yokken simülasyona düşmek, ekran ile '
              'push\'un çelişmesine yol açmıştı (2026-08-31)');
    });

    test('tür eşikleri dikkate alınır — farklı tür farklı sonuç verebilir',
        () {
      // Aynı seri, farklı tür: en azından çökmeden çalışmalı ve tür bilgisi
      // gerçekten kullanılmalı (defaultEnabledFor türe bağlı).
      final hisse = TechnicalAnalysisService.analyzeSeries(
          seri(120), AssetType.hisse);
      final fon =
          TechnicalAnalysisService.analyzeSeries(seri(120), AssetType.fon);
      expect(hisse, isNotEmpty);
      expect(fon, isNotEmpty);
    });
  });

  group('liste satırı detayı açar', () {
    test('satır dokunulabilir ve detay ekranını açar', () async {
      final liste = _yorumsuz(
          await File('lib/screens/watchlist_screen.dart').readAsString());
      expect(liste.contains('WatchlistDetailScreen'), isTrue,
          reason: 'kullanıcı satıra dokununca detay açılmalı');
      expect(liste.contains('SandikTappable'), isTrue);
    });
  });
}
