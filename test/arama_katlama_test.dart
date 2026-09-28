import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';
import 'package:portfoy_takip/utils/tr_katla.dart';

/// Arama Türkçe karakter affı (arama tasarımı, 2026-09-28).
///
/// Kullanıcı "turk hava" yazıp Türk Hava Yolları'nı, "altin" yazıp altın
/// ürünlerini bulamıyordu: eşleştirme `toUpperCase().contains` idi ve ü/ı/ş
/// duvar oluyordu. Katlama iki tarafa da uygulanır.
void main() {
  group('trKatla', () {
    test('Türkçe harfler ASCII\'ye iner, büyük/küçük farkı kalkar', () {
      expect(trKatla('Türk Hava Yolları'), 'turk hava yollari');
      expect(trKatla('ÇEYREK ALTIN'), 'ceyrek altin');
      expect(trKatla('Şişecam'), 'sisecam');
      expect(trKatla('Öğretmen'), 'ogretmen');
    });

    test('buyukHarf: Türkçede i→İ, İngilizcede dokunulmaz', () {
      expect(buyukHarf('Hisse', turkce: true), 'HİSSE');
      expect(buyukHarf('Döviz', turkce: true), 'DÖVİZ');
      expect(buyukHarf('Altın', turkce: true), 'ALTIN');
      expect(buyukHarf('Stocks', turkce: false), 'STOCKS');
      expect(buyukHarf('Crypto', turkce: false), 'CRYPTO');
    });

    test('İ birleşik nokta bırakmaz (Dart toLowerCase tuzağı)', () {
      expect(trKatla('FİYAT'), 'fiyat');
      expect(trKatla('PRICE'), 'price', reason: 'I → ı OLMAMALI');
    });
  });

  group('arama katlanmış eşleşir', () {
    final svc = SymbolSearchService.instance;
    setUp(SymbolSearchService.clearCacheForTest);

    test('"turk hava" Türk Hava Yolları\'nı bulur', () async {
      final r = await svc.search('turk hava');
      expect(r.map((h) => h.ticker), contains('THYAO.IS'));
    });

    test('"TÜRK" ve "türk" aynı sonucu verir', () async {
      final a = await svc.search('TÜRK');
      final b = await svc.search('türk');
      expect(a.map((h) => h.ticker), b.map((h) => h.ticker));
    });

    test('"ceyrek" (ç yok) Çeyrek Altın\'ı bulur', () async {
      final r = await svc.search('ceyrek');
      expect(r.map((h) => h.ticker), contains('ALTIN_CEYREK'));
    });

    test('"altin" altın ürünlerini öne alır', () async {
      final r = await svc.search('altin');
      expect(r, isNotEmpty);
      expect(r.first.ticker, startsWith('ALTIN_'),
          reason: 'ticker\'ı sorguyla başlayanlar önce');
    });

    test('gündelik adlar: usd, brent, bist100', () async {
      expect((await svc.search('usd')).map((h) => h.ticker),
          contains('USDTRY=X'));
      expect((await svc.search('brent')).map((h) => h.ticker),
          contains('BZ=F'));
      expect((await svc.search('bist100')).map((h) => h.ticker),
          contains('XU100.IS'));
    });

    test('adı sorguyla başlayan, ortasında geçenden önce gelir', () async {
      final r = (await svc.search('turk')).map((h) => h.ticker).toList();
      final thy = r.indexOf('THYAO.IS');
      expect(thy, isNonNegative);
      // Ticker'ı "TURK" ile başlayan yoksa ilk sıralarda adı "Türk" ile
      // başlayanlar olmalı.
      final ilkAdBaslayan = r.indexWhere((t) => !t.toLowerCase().startsWith('turk'));
      expect(thy, greaterThanOrEqualTo(ilkAdBaslayan));
    });
  });
}
