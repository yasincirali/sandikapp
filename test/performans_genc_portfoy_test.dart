import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Performans — portföy seçili dönemden GENÇ olduğunda boş durum.
///
/// İkinci tur (aynı gün): seri iki noktalı da olabiliyor (açılış + canlı uç),
/// ikisi de bugün → karar `_portfoyDonemdenGenc` (ilk nokta bugün mü).
///
/// REGRESYON (2026-09-27, Frankfurt provası, yeni hesap, Pazar): ilk varlık
/// bugün eklenince 1H/1A/6A/1Y serisi tek noktaya iniyordu. Grafik yine de
/// çiziliyordu — yalnız fiyat ekseni, tarih ekseni yok; dönem kartı ve tür
/// dökümü `_periodEndpoints` null döndüğü için sessizce yoktu. Kullanıcı
/// "Performans ekranı düzgün çalışmıyor" diye okudu. Kapalı testteki her yeni
/// kullanıcı ilk gün bu ekranı görür.
///
/// Neden kaynak testi: seri `HistoryService` üzerinden ağdan gelir ve testte
/// sahtelenecek bir sağlayıcı yok; tek noktalı seriyi pompalamak büyük bir
/// düzenek ister. Karar noktası tek bir `else if` — onu ve SIRASINI kilitlemek
/// yeterli; görsel doğrulama emülatörde yapıldı.
void main() {
  final kaynak = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
      .replaceAll(RegExp(r'\s+'), ' ');

  test('genç portföy dalı var ve _portfoyDonemdenGenc kararına bağlı', () {
    expect(
      kaynak.contains(
          'else if (!isIntraday && _portfoyDonemdenGenc(segments, cizimBaslangici))'),
      isTrue,
      reason: 'tek noktalı seri yeniden boş grafik olarak çizilir',
    );
    expect(kaynak.contains('context.l10n.youngPortfolioTitle'), isTrue);
    expect(kaynak.contains('context.l10n.youngPortfolioBody'), isTrue);
  });

  test('dal yükleme ile grafik ARASINDA — boş durumları gölgelemiyor', () {
    final yukleme = kaynak.indexOf('const SandikSkeletonChart(height: 300)');
    final genc = kaynak.indexOf('context.l10n.youngPortfolioTitle');
    final grafik = kaynak.indexOf('builder: (context, _, __) => _buildChartContainer(');
    expect(yukleme, greaterThan(0));
    expect(grafik, greaterThan(0));
    // Önce "varlık yok"/"veri alınamadı"/yükleme karar verir; genç portföy
    // yalnız veri GELDİKTEN sonra, grafikten hemen önce.
    expect(genc, greaterThan(yukleme));
    expect(genc, lessThan(grafik));
  });

  test('GÜNLÜK muaf — gün içi serisi bugünü kapsar', () {
    // `!isIntraday` olmadan ilk gün GÜNLÜK de boş duruma düşerdi — oysa
    // tek dolu görünüm o.
    expect(kaynak.contains('else if (!isIntraday && _portfoyDonemdenGenc('), isTrue);
  });

  test('karar nokta SAYISINA değil serinin BUGÜN başlamasına bakar', () {
    // İlk düzeltme "< 2 nokta"ya bakıyordu; canlı uç gelince seri iki
    // noktalı oldu (ikisi de bugün) ve bozuk görünüm geri döndü.
    final govde = kaynak.substring(kaynak.indexOf('bool _portfoyDonemdenGenc('));
    expect(govde.contains('if (ep == null) return true;'), isTrue);
    expect(govde.contains('DateTime.fromMillisecondsSinceEpoch(ep.firstTs!)'), isTrue);
    expect(govde.contains('ilk.day == simdi.day'), isTrue);
  });
}
