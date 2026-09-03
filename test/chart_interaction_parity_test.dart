import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// **Grafikler click ve swipe olaylarında birebir aynı çalışmalı.**
///
/// ## Ne oluyordu
/// Üç ayrı etkileşim modeli vardı ve hangisini göreceğin hangi ekranda
/// olduğuna bağlıydı:
///
/// | ekran | pinch | pan | crosshair | tap→odak |
/// |---|---|---|---|---|
/// | `portfolio_performance_screen` | ✅ | ✅ | ✅ | ✖ |
/// | `performance_screen`           | ✅ | ✅ | ✅ | ✖ |
/// | `comparison_screen`            | ✖ | ✖ | ✖ | ✖ |
/// | `watchlist_chart`              | ✖ | ✖ | ✖ | ✅ |
/// | `portfolio_detail_screen`      | ✖ | ✖ | ✖ | ✖ |
///
/// Değer okuma jesti bile üç türlüydü: performans ekranlarında 220 ms basılı
/// tutma, takip/karşılaştırmada fl_chart'ın built-in tooltip'i, sparkline'da
/// hiçbiri. Karşılaştır'da beş seri çizilmesine rağmen `touchCallback` hiç
/// yoktu.
///
/// ## Çözüm
/// Karşılaştır ve Takip aynı motoru paylaşıyor
/// (`widgets/percent_comparison_chart.dart`), o da performans ekranlarıyla
/// aynı `ZoomableChart` üzerine kurulu. Bu test kopyaların yeniden
/// ayrışmasını engeller.
///
/// ## Bu testin sınırı
/// Kaynak metnine bakar, jest simüle etmez. `RawGestureDetector` arena
/// davranışı gerçek cihazda doğrulanır; buradaki amaç "bir ekran sessizce
/// kendi grafiğini çizmeye dönmesin".
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
  group('tek motor: ZoomableChart', () {
    test('ortak grafik ZoomableChart üzerine kurulu', () async {
      final ortak = await _oku('lib/widgets/percent_comparison_chart.dart');
      expect(ortak.contains('ZoomableChart('), isTrue,
          reason: 'pinch/pan/crosshair/reset hepsi oradan geliyor');
      expect(ortak.contains('crosshairLabelBuilder:'), isTrue,
          reason: 'uzun basınca değer okunabilmeli');
      expect(ortak.contains('crosshairSnapX:'), isTrue,
          reason: 'crosshair en yakın veri noktasına oturmalı');
    });

    test('Karşılaştır ve Takip AYNI grafiği kullanır', () async {
      final karsilastir = await _oku('lib/screens/comparison_screen.dart');
      final takip = await _oku('lib/widgets/watchlist_chart.dart');

      expect(karsilastir.contains('PercentComparisonChart('), isTrue);
      expect(takip.contains('PercentComparisonChart('), isTrue);
    });

    test('iki ekran da kendi LineChart ını KURMAZ', () async {
      // Kopya çizim, kopya hata demek: eksen düzeltmesi birinde yapılıp
      // ötekinde unutulmuştu.
      final karsilastir = await _oku('lib/screens/comparison_screen.dart');
      final takip = await _oku('lib/widgets/watchlist_chart.dart');

      expect(karsilastir.contains('LineChartData('), isFalse,
          reason: 'grafik ortak widget ta kurulur');
      expect(takip.contains('LineChartData('), isFalse,
          reason: 'grafik ortak widget ta kurulur');
    });
  });

  group('tap → seri odaklama her yerde aynı', () {
    test('ortak grafikte tap-odak var ve yalnızca TAP dinler', () async {
      final ortak = await _oku('lib/widgets/percent_comparison_chart.dart');
      expect(ortak.contains('touchCallback:'), isTrue);
      expect(ortak.contains('FlTapUpEvent'), isTrue,
          reason: 'sürükleme tooltip gezdirmek içindir; her hareket odağı '
              'değiştirseydi grafik okunamaz hale gelirdi');
      expect(ortak.contains('yeniOdak('), isTrue,
          reason: 'aynı seriye tekrar dokunmak odağı KALDIRMALI');
    });

    test('Karşılaştır ekranı odak durumu tutuyor', () async {
      final karsilastir = await _oku('lib/screens/comparison_screen.dart');
      expect(karsilastir.contains('String? _focused'), isTrue,
          reason: 'beş seri çizilirken odaklanamamak asıl eksikti');
      expect(karsilastir.contains('focused: _focused'), isTrue,
          reason: 'durum grafiğe bağlanmalı');
    });
  });

  group('tooltip doğru seriyi gösterir', () {
    test('barIndex ÇİZİLEN seriler üzerinden çözülür', () async {
      final ortak = await _oku('lib/widgets/percent_comparison_chart.dart');
      expect(ortak.contains('ciz.cizilenler[s.barIndex]'), isTrue,
          reason: 'bar lar yalnızca yüklenmiş serilerden kurulur; barIndex i '
              'seçim listesinde aramak yüklenmemiş bir sembol varken YANLIŞ '
              'ticker ve YANLIŞ renk gösteriyordu');
    });

    test('Karşılaştır artık seçim listesinde barIndex aramıyor', () async {
      final karsilastir = await _oku('lib/screens/comparison_screen.dart');
      expect(karsilastir.contains('_selected[s.barIndex'), isFalse,
          reason: 'düzeltilen hata buydu');
    });
  });

  group('çizgi stili tutarlı', () {
    test('hiçbir çizgi grafik eğri interpolasyon kullanmaz', () async {
      // Eğri, veride olmayan tepe ve dip uydurur; fiyat grafiğinde yanıltıcı.
      for (final yol in const [
        'lib/widgets/percent_comparison_chart.dart',
        'lib/screens/portfolio_detail_screen.dart',
        'lib/screens/performance_screen.dart',
        'lib/screens/portfolio_performance_screen.dart',
      ]) {
        final src = await _oku(yol);
        expect(src.contains('isCurved: true'), isFalse,
            reason: '$yol eğri çiziyor — diğerleri düz');
      }
    });
  });

  group('built-in touch iki performans ekranında da aynı kapatılır', () {
    test('enabled ve handleBuiltInTouches birlikte kapalı', () async {
      // `handleBuiltInTouches` yalnızca tooltip i kapatır; dokunma işleme
      // katmani acik kalir. Biri ikisini de veriyordu, oteki vermiyordu.
      for (final yol in const [
        'lib/screens/performance_screen.dart',
        'lib/screens/portfolio_performance_screen.dart',
      ]) {
        final src = await _oku(yol);
        expect(src.contains('enabled: false'), isTrue, reason: yol);
        expect(src.contains('handleBuiltInTouches: false'), isTrue,
            reason: yol);
      }
    });
  });
}
