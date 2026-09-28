import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Tüm fiyat/değer grafikleri AYNI görünüşü taşır — "Performans stili"
/// (kullanıcı kararı 2026-09-28: "diğer ekranlardaki grafik tasarımıyla bu
/// neden farklılaşıyor, uygulama tutarlı olmalı"). Kart, çizgi rengi,
/// ızgara, eksen yazısı, dönem başı ve "şimdi" işaretleri
/// `lib/widgets/grafik_stili.dart`'tan gelir; bir ekran kendi kopyasını
/// yazarsa bu test kırılır.
void main() {
  const grafikler = {
    'Performans': 'lib/screens/portfolio_performance_screen.dart',
    'Varlık detayı': 'lib/screens/asset_detail_screen.dart',
    'Varlık sayfası': 'lib/widgets/fiyat_grafigi.dart',
  };

  for (final g in grafikler.entries) {
    group(g.key, () {
      final kaynak = ekranKaynagiSync(g.value);
      for (final parca in [
        'GrafikStili.kart(context)',
        'GrafikStili.izgara(context)',
        'GrafikStili.eksenAyraci(context)',
        'GrafikStili.eksenYazisi(context)',
        'GrafikStili.donemBasi(',
        'GrafikStili.simdiCizgisi(',
        'GrafikStili.simdiNoktasi(',
      ]) {
        test('$parca kullanılır', () {
          expect(kaynak.contains(parca), isTrue,
              reason: '${g.key} grafiği ortak stilden ayrışmış: $parca yok.');
        });
      }
    });
  }

  test('varlık sayfası çizgisi yöne göre boyanmaz (amber, ortak)', () {
    final k = ekranKaynagiSync('lib/widgets/fiyat_grafigi.dart');
    expect(k.contains('color: GrafikStili.cizgi(context)'), isTrue);
    expect(k.contains('final Color renk'), isFalse);
  });

  test('varlık detayında dönem başı dikey işareti ve başlangıç noktası yok',
      () {
    final k = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
    expect(k.contains('x: anchorSpot.x'), isFalse);
    expect(k.contains('// Dönem başı: beyaz halkalı amber.'), isFalse);
  });

  test('dönem başı etiketi tarih ve değeri birlikte yazar (veri kaybı yok)',
      () {
    final stil = ekranKaynagiSync('lib/widgets/grafik_stili.dart');
    expect(stil.contains('l.chartStartLabel('), isTrue);
    expect(stil.contains('l.chartOpenLabel('), isTrue);
    for (final yol in grafikler.values) {
      expect(ekranKaynagiSync(yol).contains('GrafikStili.donemBasiEtiketi('),
          isTrue,
          reason: '$yol dönem başı etiketini ortak biçimle yazmıyor.');
    }
  });
}
