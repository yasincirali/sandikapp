import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_categories.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/models/watchlist_item.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Varlık kimliği — varlık sayfasının dört giriş noktası aynı varlık için
/// AYNI kimliği üretmeli. Ayrışırsa "takipte" durumu bir yerde doğru, başka
/// yerde yanlış görünür ya da aynı varlık iki ayrı takip kaydı olur.
void main() {
  VarlikKimligi hit(String t, String n) =>
      VarlikKimligi.fromSymbolHit(SymbolHit(ticker: t, name: n, source: ''))!;

  group('sembolden tür', () {
    test('BIST hissesi ve endeks', () {
      expect(hit('THYAO.IS', 'THY').type, AssetType.hisse);
      expect(hit('XU100.IS', 'BIST 100').type, AssetType.hisse);
    });

    test('fon, kripto, altın, döviz, emtia', () {
      expect(hit('TEFAS:AFA', 'AFA').type, AssetType.fon);
      expect(hit(kriptoSembolu('btc'), 'Bitcoin').type, AssetType.kripto);
      final altin = hit('ALTIN_CEYREK', 'Çeyrek Altın');
      expect(altin.type, AssetType.altin);
      expect(altin.subCategory, 'Çeyrek Altın');
      final usd = hit('USDTRY=X', 'Amerikan Doları');
      expect(usd.type, AssetType.doviz);
      expect(usd.subCategory, 'USD');
      expect(usd.currency, 'TRY');
      final brent = hit('BZ=F', 'Brent');
      expect(brent.type, AssetType.emtia);
      expect(brent.currency, 'USD');
    });

    test('portföy serileri ve TÜFE varlık DEĞİL', () {
      for (final t in [
        PortfolioSeries.mine,
        PortfolioSeries.together,
        TufeSeries.ticker,
      ]) {
        expect(
            VarlikKimligi.fromSymbolHit(
                SymbolHit(ticker: t, name: t, source: '')),
            isNull,
            reason: t);
      }
    });
  });

  group('anahtar tek kural', () {
    test('takip kaydının anahtarıyla aynı', () {
      final k = hit('ALTIN_CEYREK', 'Çeyrek Altın');
      final w = k.toWatchlistItem(userId: 'u1');
      expect(w.key, k.key);
      expect(VarlikKimligi.fromWatchlistItem(w).key, k.key);
    });

    test('seçici kimlikleri aramadakiyle aynı', () {
      expect(VarlikKimligi.hisse('THYAO.IS', 'THY').key,
          hit('THYAO.IS', 'Türk Hava Yolları').key);
      expect(VarlikKimligi.fon('AFA', 'Ak Portföy').key,
          hit('TEFAS:AFA', 'Ak Portföy').key);
      expect(VarlikKimligi.kripto('btc', 'Bitcoin').key,
          hit(kriptoSembolu('BTC'), 'Bitcoin').key);
    });

    test('altın seçicisinin her türü aramadaki yerleşik altınla eşleşir', () {
      final arama = {
        for (final e in goldTickerMap.entries) hit(e.value, e.key).key,
      };
      for (final g in GoldSubCategory.values) {
        final k = VarlikKimligi.fromGold(g);
        if (k == null) continue; // haritada olmayan tür (kaynak yok)
        expect(arama, contains(k.key), reason: g.label);
      }
    });
  });

  group('kısa etiket', () {
    test('kaynak önekleri gösterilmez', () {
      expect(hit('THYAO.IS', 'THY').kisaEtiket, 'THYAO');
      expect(hit('TEFAS:AFA', 'AFA').kisaEtiket, 'AFA');
    });

    test('altında sembol değil ad gösterilir', () {
      expect(hit('ALTIN_CEYREK', 'Çeyrek Altın').kisaEtiket, 'Çeyrek Altın');
    });
  });

  test('WatchlistItem alanları eksiksiz taşınır', () {
    final w = WatchlistItem(
      id: 'x',
      userId: 'u1',
      ticker: 'EURTRY=X',
      name: 'Euro',
      type: AssetType.doviz,
      subCategory: 'EUR',
      currency: 'TRY',
      addedAt: DateTime(2026),
    );
    final k = VarlikKimligi.fromWatchlistItem(w);
    expect(
        [k.ticker, k.name, k.type, k.subCategory, k.currency],
        ['EURTRY=X', 'Euro', AssetType.doviz, 'EUR', 'TRY']);
  });
}
