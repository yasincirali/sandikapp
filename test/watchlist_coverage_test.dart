import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// **Takip listesine, portföye eklenebilen HER varlık eklenebilmeli.**
///
/// ## Neden bu test var
/// Takip ekranı kendi arama listesini tutuyordu (`bist100StocksMap` +
/// TEFAS + `goldTickerMap` + elle yazılmış üç döviz). Karşılaştırma ekranı
/// ise `SymbolSearchService` kullanıyordu. İki liste ayrışmıştı; ölçüldü:
///
///   takip ekranında ÇIKMAYAN:
///     · endeksler  → XU100.IS, XU030.IS
///     · emtia      → GC=F (ons altın), SI=F (gümüş),
///                    BZ=F / CL=F (petrol), NG=F (doğalgaz)
///     · TEFAS'ın liste API'sinde görünmeyen kurucu-only fonlar (ALE, YLB)
///
/// Artık iki ekran da AYNI servisi kullanıyor. Bu test ayrışmayı engeller.

String _yorumsuz(String src) => src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    }).join('\n');

void main() {
  setUp(SymbolSearchService.clearCacheForTest);

  group('eskiden eksik olan varlıklar artık bulunuyor', () {
    // Bu semboller yerleşik listede — ağ gerektirmez.
    const beklenen = {
      'XU100': 'XU100.IS',
      'XU030': 'XU030.IS',
      'GC=F': 'GC=F',
      'SI=F': 'SI=F',
      'BZ=F': 'BZ=F',
      'CL=F': 'CL=F',
      'NG=F': 'NG=F',
    };

    for (final e in beklenen.entries) {
      test('${e.key} aranabiliyor', () async {
        final r = await SymbolSearchService.instance.search(e.key);
        expect(r.map((h) => h.ticker), contains(e.value),
            reason: '${e.key} takip listesine eklenebilmeli');
      });
    }

    test('emtia adıyla da bulunuyor', () async {
      final r = await SymbolSearchService.instance.search('Petrol');
      expect(r.any((h) => h.source == 'Emtia'), isTrue,
          reason: 'kullanıcı ticker değil ad yazar');
    });

    test('endeks adıyla da bulunuyor', () async {
      final r = await SymbolSearchService.instance.search('BIST 100');
      expect(r.any((h) => h.ticker == 'XU100.IS'), isTrue);
    });
  });

  group('eskiden çalışanlar BOZULMADI', () {
    const regresyon = {
      'THYAO': 'THYAO.IS',
      'ALTIN_GRAM': 'ALTIN_GRAM',
      'USDTRY': 'USDTRY=X',
      'EURTRY': 'EURTRY=X',
      'GBPTRY': 'GBPTRY=X',
    };

    for (final e in regresyon.entries) {
      test('${e.key} hâlâ bulunuyor', () async {
        final r = await SymbolSearchService.instance.search(e.key);
        expect(r.map((h) => h.ticker), contains(e.value));
      });
    }
  });

  group('iki ekran AYNI kaynağı kullanır', () {
    test('takip ekleme ekranı SymbolSearchService kullanır', () async {
      final src = _yorumsuz(
          await File('lib/screens/add_watchlist_screen.dart').readAsString());
      expect(src.contains('SymbolSearchService.instance.search'), isTrue,
          reason: 'kendi listesini tutmak iki ekranın ayrışmasına yol açar');
      // Kendi kataloglarını YENİDEN kurmamalı.
      expect(src.contains('bist100StocksMap'), isFalse,
          reason: 'katalog servisin sorumluluğu');
      expect(src.contains('goldTickerMap'), isFalse);
      expect(src.contains('fetchAllFunds'), isFalse,
          reason: 'fon araması servisin içinde, önbellekli');
    });

    test('karşılaştırma ekranı da aynı servisi kullanır', () async {
      final src = _yorumsuz(
          await File('lib/screens/comparison_screen.dart').readAsString());
      expect(src.contains('SymbolSearchService'), isTrue);
    });
  });

  group('portföy serileri takip edilemez', () {
    // `PORTFOLIO:MINE` gibi sanal tickerlar karşılaştırma ekranına özgüdür;
    // piyasada kote değiller, takip kaydı olamazlar.
    test('sanal ticker tanınıyor', () {
      expect(PortfolioSeries.isPortfolio('PORTFOLIO:MINE'), isTrue);
      expect(PortfolioSeries.isPortfolio('THYAO.IS'), isFalse);
    });

    test('takip ekranı bunları ELER', () async {
      final src = _yorumsuz(
          await File('lib/screens/add_watchlist_screen.dart').readAsString());
      expect(src.contains('PortfolioSeries.isPortfolio'), isTrue,
          reason: 'sanal ticker takip listesine girerse fiyatı çekilemez');
    });
  });

  group('tür ve para birimi eşlemesi', () {
    // Yanlış tür, varlığın portföy dökümünde yanlış kategoriye düşmesine
    // yol açar. Eşleme ticker biçiminden yapılıyor; kuralları kilitliyoruz.
    test('eşleme kuralları kaynakta tanımlı', () async {
      final src = _yorumsuz(
          await File('lib/screens/add_watchlist_screen.dart').readAsString());
      // TEFAS → fon
      expect(src.contains("t.startsWith('TEFAS:')"), isTrue);
      expect(src.contains('AssetType.fon'), isTrue);
      // ALTIN_ → altın
      expect(src.contains("t.startsWith('ALTIN_')"), isTrue);
      expect(src.contains('AssetType.altin'), isTrue);
      // =F → emtia (YENİ)
      expect(src.contains("t.endsWith('=F')"), isTrue);
      expect(src.contains('AssetType.emtia'), isTrue,
          reason: 'emtia türü eklenmezse ons altın/petrol hisse sayılırdı');
      // TRY=X → döviz
      expect(src.contains("t.endsWith('TRY=X')"), isTrue);
      expect(src.contains('AssetType.doviz'), isTrue);
    });

    test('ons altın USD olarak işaretlenir', () async {
      // Yahoo XAUUSD=X ve GC=F USD kote döner; TRY demek fiyatı ~40× yanlış
      // gösterirdi.
      final src = _yorumsuz(
          await File('lib/screens/add_watchlist_screen.dart').readAsString());
      expect(src.contains("t == 'XAUUSD=X'"), isTrue);
      expect(src.contains("currency: 'USD'"), isTrue);
    });
  });
}
