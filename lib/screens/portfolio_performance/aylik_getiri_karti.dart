part of '../portfolio_performance_screen.dart';

/// Aylık getiri tablosunun Performans'taki yuvası (2026-11-11, Premium).
///
/// Kart ve hesabı ekrandan ayrı (`widgets/aylik_getiri_karti.dart`,
/// `services/aylik_getiri_tablosu.dart`); burada yalnız Özet'le AYNI
/// girdiler bağlanır: seri `chartAssets`'ten, akış `targetAssets`'ten
/// (`_buildOzetSekmesi` ile aynı ikili). İstek anahtarı Özet belleğinin
/// kapsamı + defter imzası: kapsam/tür/portföy ya da defter değişince
/// tablo yeniden hesaplanır, dönem çipi değişince değişmez (tablo dönemden
/// bağımsız).
///
/// Simülasyonda yok: o mod "bugünkü portföyü hep tutsaydım" senaryosu,
/// akış yok — "hangi ay kazandım" sorusunun cevabı değil.
extension _AylikGetiriYuvasi on _PortfolioPerformanceScreenState {
  List<Widget> _aylikGetiriBlogu(
      List<Asset> chartAssets, List<Asset> targetAssets) {
    if (_simulate || chartAssets.isEmpty) return const [];
    return [
      AylikGetiriKarti(
        istek: AylikGetiriIstegi(
          anahtar: 'aylik|$_ozetKapsami|${_OzetBellek.imza(chartAssets)}'
              '|${_OzetBellek.imza(targetAssets)}',
          seriLotlari: chartAssets,
          hesapLotlari: targetAssets,
        ),
      ),
    ];
  }
}
