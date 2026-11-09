import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/abd_hisseleri.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/history_service.dart'
    show FiyatKaynagi;
import 'package:portfoy_takip/services/remote_config_service.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Küresel endeksler ve tema ETF'leri (yasin, 2026-10-23: *"Endeksleri
/// ekle, US100 falan da nasdaq da olsun … Tema Space Innovators ETF gibi
/// varlıkları da içermeliyiz"*).
///
/// Kilitlenen kararlar:
///  · Endeks PUAN'dır: USD/TRY ile çevrilmez (`FiyatKaynagi.cevrimsiz`).
///    Çevrilseydi Nasdaq 100 "₺ 900.000" diye görünürdü.
///  · Kullanıcının bildiği kısa adlar (US100, DE40, US30) bulunur.
///  · Tema ETF'leri ABD kataloğunda, Türkçe tema kelimesiyle bulunur.
void main() {
  final svc = SymbolSearchService.instance;

  setUp(SymbolSearchService.clearCacheForTest);
  tearDown(() => RemoteConfigService.testAcik = {});

  group('endeks tanıma', () {
    test('^ ile başlayan sembol küresel endekstir', () {
      expect(kureselEndeksMi('^NDX'), isTrue);
      expect(kureselEndeksMi(' ^GDAXI '), isTrue);
      expect(kureselEndeksMi('NDX'), isFalse);
      expect(kureselEndeksMi('AAPL'), isFalse);
    });

    test('endeksMi BIST endekslerini de kapsar', () {
      expect(endeksMi('XU100.IS'), bistEndeksiMi('XU100.IS'));
      expect(endeksMi('^GSPC'), isTrue);
      expect(endeksMi('THYAO.IS'), isFalse);
    });

    test('küresel endeks çevrilmez, ABD hissesi çevrilir', () {
      for (final s in ['^NDX', '^GSPC', '^DJI', '^GDAXI', '^N225', '^VIX']) {
        expect(FiyatKaynagi.cevrimsiz(s), isTrue, reason: s);
      }
      expect(FiyatKaynagi.cevrimsiz('AAPL'), isFalse);
      expect(FiyatKaynagi.cevrimsiz('NASA'), isFalse);
    });
  });

  group('endeks araması (bayraksız, yerleşik liste)', () {
    test('US100 Nasdaq 100\'ü bulur', () {
      final r = svc.yerelAra('us100');
      expect(r.map((h) => h.ticker), contains('^NDX'));
    });

    test('Nasdaq yazınca hem 100 hem bileşik çıkar', () {
      final t = svc.yerelAra('nasdaq').map((h) => h.ticker).toList();
      expect(t, containsAll(['^NDX', '^IXIC']));
    });

    test('kısa adlar: DE40 → DAX, US30 → Dow Jones', () {
      expect(svc.yerelAra('de40').map((h) => h.ticker), contains('^GDAXI'));
      expect(svc.yerelAra('us30').map((h) => h.ticker), contains('^DJI'));
    });

    test('S&P 500 ve Nikkei bulunur', () {
      expect(svc.yerelAra('s&p').map((h) => h.ticker), contains('^GSPC'));
      expect(svc.yerelAra('nikkei').map((h) => h.ticker), contains('^N225'));
    });
  });

  group('tema ETF\'leri (abd_hisse kataloğu)', () {
    test('katalogda tema ETF\'leri var', () {
      for (final s in ['NASA', 'ARKX', 'UFO', 'BOTZ', 'ICLN', 'LIT', 'URA']) {
        expect(abdHisseleri, contains(s), reason: s);
      }
    });

    test('"uzay" yazınca NASA çıkar', () {
      RemoteConfigService.testAcik = {'abd_hisse'};
      final t = svc.yerelAra('uzay').map((h) => h.ticker).toList();
      expect(t, containsAll(['NASA', 'ARKX']));
    });

    test('"robot" yazınca robotik ETF\'leri çıkar', () {
      RemoteConfigService.testAcik = {'abd_hisse'};
      expect(svc.yerelAra('robot').map((h) => h.ticker), contains('BOTZ'));
    });

    test('bayrak kapalıyken ETF aramada görünmez', () {
      expect(svc.yerelAra('uzay').map((h) => h.ticker), isNot(contains('NASA')));
    });
  });
}
