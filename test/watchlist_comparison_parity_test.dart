import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Takip listesi ile Karşılaştır ekranı aynı dili konuşmalı.**
///
/// İkisi de "dönem başına göre yüzde" çizen kıyas ekranları ama iki ayrı
/// kopya olarak büyüdüler ve ayrıştılar. Kullanıcı bulgusu: "watchlist ekranı
/// karşılaştır ekranıyla aynı olmalı çoğu özellik olarak."
///
/// Bu test paylaşılan yüzeyleri kilitler. Kopya çizim, kopya hata demek:
/// eksen düzeltmesi bir kez takipte yapılmış, Karşılaştır'da unutulmuştu.
///
/// ## Kapsam dışı
/// "Ekstre" sekmesi kullanıcının isteğiyle atlandı.
String _yorumsuz(String src) => src
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    })
    .join('\n');

Future<String> _oku(String yol) async =>
    _yorumsuz(await File(yol).readAsString());

void main() {
  group('ortak grafik motoru', () {
    test('iki ekran da PercentComparisonChart çiziyor', () async {
      expect(
          (await _oku('lib/screens/comparison_screen.dart'))
              .contains('PercentComparisonChart('),
          isTrue);
      expect(
          (await _oku('lib/widgets/watchlist_chart.dart'))
              .contains('PercentComparisonChart('),
          isTrue);
    });

    test('normalize motoru da ortak', () async {
      // İkinci bir normalize implementasyonu, aynı veriyi iki ekranda farklı
      // göstermek demekti.
      final saglayici = await _oku('lib/providers/watchlist_provider.dart');
      final karsilastir = await _oku('lib/screens/comparison_screen.dart');
      expect(saglayici.contains('normalizeSeries'), isTrue);
      expect(karsilastir.contains('normalizeSeries'), isTrue);
    });
  });

  group('Ortaklar sekmesi', () {
    late String karsilastir;

    setUpAll(() async {
      karsilastir = await _oku('lib/screens/comparison_screen.dart');
    });

    test('arama sayfasında gerçek bir sekme var', () {
      expect(karsilastir.contains('class _SheetTabs'), isTrue);
      expect(karsilastir.contains("'Varlıklar', 'Ortaklar'"), isTrue);
    });

    test('ortak portföyleri artık sorguya BAĞLI DEĞİL', () {
      // Eski davranış: portföyler yalnızca arama kutusu boşken görünüyordu;
      // kullanıcı bir harf yazar yazmaz kayboluyorlardı.
      expect(karsilastir.contains('bool get _showPortfolio'), isFalse,
          reason: 'sorgu boşluğuna bağlı görünürlük kaldırıldı');
      expect(karsilastir.contains('_tab == 0'), isTrue,
          reason: 'görünürlük artık sekmeye bağlı');
    });

    test('sekme tek seçenekliyse çizilmez', () {
      // Karar verecek bir şey sunmayan seçici yalnızca yer kaplar — takip
      // ekranındaki ortak seçicisiyle aynı kural.
      expect(karsilastir.contains('if (widget.portfolioOptions.isNotEmpty)'),
          isTrue);
    });

    test('ortak portföyü bir seri olarak kıyasa girer', () {
      expect(karsilastir.contains('PortfolioSeries.partnerPrefix'), isTrue);
      expect(karsilastir.contains('PortfolioSeries.together'), isTrue);
    });
  });

  group('satır eylemleri', () {
    test('takip satırından portföye eklenebilir', () async {
      // Takip listesinin varlık sebebi "almayı düşündüğüm şey"; almaya karar
      // verince kullanıcıyı arama ekranına geri göndermek gereksizdi.
      final takip = await _oku('lib/screens/watchlist_screen.dart');
      expect(takip.contains('AddAssetScreen('), isTrue);
      expect(takip.contains('prefillTicker: item.ticker'), isTrue,
          reason: 'aynı varlığı ikinci kez aratmamalı');
    });

    test('takip satırında Al/Sat YOK — bilinçli fark', () async {
      // Takip edilen varlık tanımı gereği portföyde değildir; iki küme
      // yapısal olarak ayrık (bkz. watchlist_isolation_test). Sahip
      // olunmayan bir varlığı "satmak" tanımsızdır. Bu bir eksiklik değil,
      // korunması gereken bir kural.
      final takip = await _oku('lib/screens/watchlist_screen.dart');
      expect(takip.contains('QuickAdjustMode'), isFalse,
          reason: 'sahip olunmayan varlıkta al/sat tanımsız');
    });
  });
}
