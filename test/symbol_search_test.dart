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

  group('sonuç bulunamayan sorgu', () {
    test('anlamsız sorgu boş liste döner, patlamaz', () async {
      // Yerleşikte yok → Yahoo denenir → testte ağ yok → boş.
      final r = await svc.search('ZZZQQQXYZ123');
      expect(r, isEmpty);
    });
  });

  group('SymbolHit eşitliği', () {
    test('ticker üzerinden eşitlik — kopya eleme buna dayanır', () {
      const a = SymbolHit(ticker: 'AAPL', name: 'Apple', source: 'NASDAQ');
      const b = SymbolHit(
          ticker: 'AAPL', name: 'Apple Inc.', source: 'Yahoo', builtIn: false);
      expect(a, equals(b), reason: 'aynı ticker aynı varlıktır');
      expect({a, b}.length, 1);
    });
  });
}
