import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/arama_gruplari.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/varlik_kimligi.dart';
import 'package:portfoy_takip/screens/add_watchlist_screen.dart';
import 'package:portfoy_takip/services/price_service.dart';

VarlikKimligi _k(String t, AssetType tur, {String cur = 'TRY'}) =>
    VarlikKimligi(ticker: t, name: t, type: tur, currency: cur);

/// Arama sonuç gruplaması ve satır fiyat metni (arama tasarımı, 2026-09-28).
void main() {
  group('aramaGrupla', () {
    final sonuc = [
      _k('ALTIN_GRAM', AssetType.altin),
      _k('ALTIN_CEYREK', AssetType.altin),
      _k('ALTIN_YARIM', AssetType.altin),
      _k('ALTIN_TAM', AssetType.altin),
      _k('ALTNY.IS', AssetType.hisse),
      _k('TEFAS:AAL', AssetType.fon),
    ];

    test('grup sırası ilk görünüş sırasıdır (servisin alaka sırası)', () {
      final g = aramaGrupla(sonuc);
      expect(g.map((e) => e.tur),
          [AssetType.altin, AssetType.hisse, AssetType.fon]);
    });

    test('grup başına 3 satır; toplam ve kısaltma bilgisi korunur', () {
      final altin = aramaGrupla(sonuc).first;
      expect(altin.ogeler.length, aramaGrupSiniri);
      expect(altin.toplam, 4);
      expect(altin.kisaltildi, isTrue);
    });

    test('tür seçiliyken yalnızca o tür döner ve KESİLMEZ', () {
      final g = aramaGrupla(sonuc, filtre: AssetType.altin);
      expect(g, hasLength(1));
      expect(g.single.ogeler.length, 4);
      expect(g.single.kisaltildi, isFalse);
    });

    test('çip türleri sonuçtaki sırayla, tekrarsız', () {
      expect(aramaTurleri(sonuc),
          [AssetType.altin, AssetType.hisse, AssetType.fon]);
    });
  });

  group('satır fiyatı — uydurma sayı yok', () {
    test('fiyat bilinmiyorsa metin yok', () {
      expect(aramaFiyatMetni(_k('THYAO.IS', AssetType.hisse), null), isNull);
      expect(
          aramaFiyatMetni(_k('THYAO.IS', AssetType.hisse),
              const YahooQuote(symbol: 'THYAO.IS', regularMarketPrice: 0)),
          isNull);
    });

    test('endeks puan olarak, simgesiz ve kuruşsuz', () {
      final m = aramaFiyatMetni(_k('XU100.IS', AssetType.hisse),
          const YahooQuote(symbol: 'XU100.IS', regularMarketPrice: 11482.4));
      expect(m, '11.482');
    });

    test('hisse ₺ ile', () {
      final m = aramaFiyatMetni(_k('THYAO.IS', AssetType.hisse),
          const YahooQuote(symbol: 'THYAO.IS', regularMarketPrice: 312.5));
      expect(m, contains('₺'));
      expect(m, contains('312,50'));
    });

    test('yüzde bilinmiyorsa null', () {
      expect(
          aramaGunlukYuzde(_k('THYAO.IS', AssetType.hisse),
              const YahooQuote(symbol: 'THYAO.IS', regularMarketPrice: 1)),
          isNull);
      expect(
          aramaGunlukYuzde(
              _k('THYAO.IS', AssetType.hisse),
              const YahooQuote(
                  symbol: 'THYAO.IS',
                  regularMarketPrice: 1,
                  regularMarketChangePercent: 1.25)),
          1.25);
    });
  });

  group('satırın sembol etiketi adı tekrar etmez', () {
    test('altın: yok; kur: USD; emtia: yok; hisse: kısa kod', () {
      expect(aramaSembolEtiketi(_k('ALTIN_CEYREK', AssetType.altin)), isNull);
      expect(aramaSembolEtiketi(_k('USDTRY=X', AssetType.doviz)), 'USD');
      expect(aramaSembolEtiketi(_k('BZ=F', AssetType.emtia)), isNull);
      expect(aramaSembolEtiketi(_k('THYAO.IS', AssetType.hisse)), 'THYAO');
      expect(aramaSembolEtiketi(_k('TEFAS:AFA', AssetType.fon)), 'AFA');
    });
  });
}
