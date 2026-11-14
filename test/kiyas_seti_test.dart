import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/kiyas_seti.dart';
import 'package:portfoy_takip/services/symbol_search_service.dart';

/// Hatırlanan kıyas seti — kodla/çöz ve açılış sırası (Ar-Ge 14 Kas 22:03).
void main() {
  const thy = SymbolHit(ticker: 'THYAO.IS', name: 'THY', source: 'BIST');
  const altin =
      SymbolHit(ticker: 'ALTIN_GRAM', name: 'Gram altın', source: 'Altın');
  const bist = SymbolHit(ticker: 'XU100.IS', name: 'BIST 100', source: 'Endeks');
  const portfoy =
      SymbolHit(ticker: PortfolioSeries.mine, name: 'Portföyüm', source: 'Portföy');

  test('kodla → çöz sırayı ve adları korur', () {
    final kayit = kiyasSetiKodla([portfoy, altin, thy]);
    final geri = kiyasSetiCoz(kayit, ortakIdleri: const {});
    expect(geri.map((h) => h.ticker),
        [PortfolioSeries.mine, 'ALTIN_GRAM', 'THYAO.IS']);
    expect(geri[1].name, 'Gram altın');
    expect(geri[1].source, 'Altın');
  });

  test('çözülemeyen kayıt sessizce düşer', () {
    final kayit = [
      'bozuk{',
      '"metin"',
      '{"t":""}',
      ...kiyasSetiKodla([
        thy,
        thy, // tekrar
        const SymbolHit(
            ticker: '${PortfolioSeries.partnerPrefix}eski', name: 'Ayşe', source: 'Ortak'),
        const SymbolHit(
            ticker: '${PortfolioSeries.partnerPrefix}p1', name: 'Ali', source: 'Ortak'),
        const SymbolHit(
            ticker: PortfolioSeries.together, name: 'Birlikte', source: 'Portföy'),
      ]),
    ];
    expect(kiyasSetiCoz(kayit, ortakIdleri: {'p1'}).map((h) => h.ticker), [
      'THYAO.IS',
      '${PortfolioSeries.partnerPrefix}p1',
      PortfolioSeries.together,
    ]);
    // Ortak yokken "Birlikte" de düşer.
    expect(kiyasSetiCoz(kayit, ortakIdleri: const {}).map((h) => h.ticker),
        ['THYAO.IS']);
    expect(kiyasSetiCoz(null, ortakIdleri: const {}), isEmpty);
  });

  test('açılış: başlangıç varlığı başta, set arkasında, sınıra kırpılır', () {
    expect(
        kiyasSetiAcilisi(
                baslangic: thy, kayitli: [portfoy, altin, bist], sinir: 3)
            .map((h) => h.ticker),
        ['THYAO.IS', PortfolioSeries.mine, 'ALTIN_GRAM']);
    // Sette zaten varsa tekrar edilmez, başa alınır.
    expect(
        kiyasSetiAcilisi(baslangic: altin, kayitli: [portfoy, altin], sinir: 5)
            .map((h) => h.ticker),
        ['ALTIN_GRAM', PortfolioSeries.mine]);
    expect(kiyasSetiAcilisi(kayitli: [portfoy, altin], sinir: 5).length, 2);
  });
}
