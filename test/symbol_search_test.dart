import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Sembol arama — yerleşik liste katmanı.
///
/// Yahoo katmanı ağ gerektirdiği için burada test EDİLMEZ; o katman zaten
/// hata yutup boş liste döner (serbest arama bonus, yerleşik listeler asıl
/// yol). Test edilen şey: kullanıcının aradığını yerel listede bulabilmesi
/// ve sonuçların makul sırada gelmesi.

void main() {
  final svc = SymbolSearchService.instance;

  setUp(SymbolSearchService.clearCacheForTest);

  group('yerleşik listede arama', () {
    test('ticker ile bulunur', () async {
      final r = await svc.search('THYAO');
      expect(r.map((h) => h.ticker), contains('THYAO.IS'));
    });

    test('şirket adı ile bulunur', () async {
      final r = await svc.search('Garanti');
      expect(r.map((h) => h.ticker), contains('GARAN.IS'));
    });

    test('küçük/büyük harf farketmez', () async {
      final lower = await svc.search('thyao');
      expect(lower.map((h) => h.ticker), contains('THYAO.IS'));
    });

    test('Türkçe karakterli ad ile bulunur', () async {
      final r = await svc.search('Çeyrek');
      expect(r.map((h) => h.ticker), contains('ALTIN_CEYREK'));
    });
  });

  group('sıralama', () {
    test('ticker ile başlayan sonuçlar öne gelir', () async {
      final r = await svc.search('AK');
      final idxAkbnk = r.indexWhere((h) => h.ticker == 'AKBNK.IS');
      expect(idxAkbnk, isNonNegative, reason: 'AKBNK bulunmalı');

      // Ticker'ı "AK" ile BAŞLAMAYAN ama adında "ak" geçen bir sonuç
      // varsa, AKBNK ondan önce gelmeli.
      final idxOther =
          r.indexWhere((h) => !h.ticker.startsWith('AK'));
      if (idxOther >= 0) {
        expect(idxAkbnk, lessThan(idxOther));
      }
    });
  });

  group('kıyas noktaları', () {
    test('endeksler aranabilir — "BIST\'i yendim mi?" sorusu için', () async {
      final r = await svc.search('BIST 100');
      expect(r.map((h) => h.ticker), contains('XU100.IS'));
    });

    test('döviz aranabilir', () async {
      final r = await svc.search('Dolar');
      expect(r.map((h) => h.ticker), contains('USDTRY=X'));
    });

    test('altın ürünleri ters haritadan doğru çevrilir', () async {
      // `goldTickerMap` isim→kod yönünde; yanlış çevrilse ticker olarak
      // "22 Ayar Gram Altın" gibi bir metin dönerdi.
      final r = await svc.search('Gram Altın');
      final hit = r.firstWhere((h) => h.ticker == 'ALTIN_GRAM');
      expect(hit.name, contains('Gram'));
      expect(hit.source, 'Altın');
    });
  });

  group('boş sorgu', () {
    test('öneri listesi döner (boş değil)', () async {
      final r = await svc.search('');
      expect(r, isNotEmpty);
      expect(r.map((h) => h.ticker), contains('XU100.IS'));
    });

    test('yalnızca boşluk da boş sorgu sayılır', () async {
      final r = await svc.search('   ');
      expect(r, isNotEmpty);
    });
  });

  group('kapsam: yalnızca Türkiye', () {
    test('emtia referansları KALIR — yerel varlığın dayandığı fiyat', () async {
      // Ons altın gram altının, Brent akaryakıtın referansı. TR'de kote
      // değiller ama kıyas noktası olarak anlamlılar.
      final altin = await svc.search('Ons');
      expect(altin.map((h) => h.ticker), contains('GC=F'));

      final petrol = await svc.search('Brent');
      expect(petrol.map((h) => h.ticker), contains('BZ=F'));
    });

    test('emtia sonuçları "Emtia" etiketiyle gelir', () async {
      final r = await svc.search('Gümüş');
      final hit = r.firstWhere((h) => h.ticker == 'SI=F');
      expect(hit.source, 'Emtia');
    });
  });

  group('sonuç bulunamayan sorgu', () {
    test('anlamsız sorgu boş liste döner, patlamaz', () async {
      // Yerleşikte yok; 6 karakterden uzun olduğu için fon lookup'ı da
      // denenmez → boş.
      final r = await svc.search('ZZZQQQXYZ123');
      expect(r, isEmpty);
    });

    test('yabancı hisse LİSTELENMEZ — kapsam TR ile sınırlı', () async {
      // Yahoo serbest araması kaldırıldı: kullanıcı portföye ekleyemeyeceği
      // bir varlığa yönlendirilmemeli. Bu test kapsamı kilitler; Yahoo
      // araması geri gelirse kırılır.
      for (final q in ['AAPL', 'TESLA', 'NVIDIA']) {
        final r = await svc.search(q);
        expect(
          r.where((h) => h.ticker == q || h.ticker.startsWith('$q.')),
          isEmpty,
          reason: '$q sonuçlarda çıkmamalı',
        );
      }
    });
  });

  group('portföy serisi sanal ticker\'ları', () {
    test('portföy serileri tanınır', () {
      expect(PortfolioSeries.isPortfolio(PortfolioSeries.mine), isTrue);
      expect(PortfolioSeries.isPortfolio(PortfolioSeries.together), isTrue);
      expect(
        PortfolioSeries.isPortfolio('${PortfolioSeries.partnerPrefix}abc-123'),
        isTrue,
      );
    });

    test('gerçek semboller portföy serisi SAYILMAZ', () {
      // Yanlış sınıflandırma, hisseyi portföy hesabına sokardı.
      expect(PortfolioSeries.isPortfolio('THYAO.IS'), isFalse);
      expect(PortfolioSeries.isPortfolio('TEFAS:AFA'), isFalse);
      expect(PortfolioSeries.isPortfolio('ALTIN_GRAM'), isFalse);
    });

    test('ortak id\'si önekten doğru çıkarılır', () {
      expect(
        PortfolioSeries.partnerIdOf('${PortfolioSeries.partnerPrefix}u-42'),
        'u-42',
      );
    });

    test('ortak olmayan seriden id çıkmaz', () {
      expect(PortfolioSeries.partnerIdOf(PortfolioSeries.mine), isNull);
      expect(PortfolioSeries.partnerIdOf('THYAO.IS'), isNull);
    });
  });

  group('SymbolHit eşitliği', () {
    test('ticker üzerinden eşitlik — kopya eleme buna dayanır', () {
      const a = SymbolHit(ticker: 'AAPL', name: 'Apple', source: 'NASDAQ');
      const b =
          SymbolHit(ticker: 'AAPL', name: 'Apple Inc.', source: 'BIST');
      expect(a, equals(b), reason: 'aynı ticker aynı varlıktır');
      expect({a, b}.length, 1);
    });
  });
}
