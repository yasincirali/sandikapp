import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/daily_summary.dart';

import 'helpers/kaynak.dart';

/// Ana sayfa "Bugün" ile Performans › Günlük (grafik + Özet) nabızda
/// dönüşümlü ayrışıyordu (kullanıcı bildirimi, 2026-09-24):
/// *"bir süre farklı değerler gösteriliyor sonra aynı değere geliyorlar
/// sonra bir daha farklılaşıyorlar"*.
///
/// Nabız 30 sn'de bir atar ama dinleyiciler fiyat turu BİTİNCE çağrılır;
/// tur süresi oynadığı için iki çağrı arası 29,x sn olabiliyor. Bugün kartı
/// önbelleği `azamiYas: 30 sn` ile istiyordu ve `>` kapısı o nabızda
/// geçilmiyordu: kart eski seride kalıyor, Performans yeniden çekiyordu.
void main() {
  // Tarih sabit: önbelleğin "gün değişti" kuralı testin saatine bağlı kalmasın.
  final simdi = DateTime(2026, 9, 24, 14, 0, 0);
  const eski = {1: 100.0, 2: 101.0};

  setUp(() => IntradaySeriesCache.instance.clear());
  tearDown(() => IntradaySeriesCache.instance.clear());

  test('REGRESYON: 30 sn\'den kısa aralıkla gelen nabız yaş kapısında takılır',
      () async {
    IntradaySeriesCache.instance.seedForTest(
        series: eski,
        fetchedAt: simdi.subtract(const Duration(seconds: 29, milliseconds: 400)));
    final s = await IntradaySeriesCache.instance.get(const PortfolioState(),
        now: simdi, azamiYas: const Duration(seconds: 30));
    // Arızanın kendisi: yaş kapısı bu nabzı atlar — nabız yolu bu yüzden
    // `zorla` ile çağırır (aşağıdaki test).
    expect(s, eski);
  });

  test('nabız (zorla) yaşa bakmadan yeniden çeker', () async {
    IntradaySeriesCache.instance.seedForTest(
        series: eski,
        fetchedAt: simdi.subtract(const Duration(seconds: 29, milliseconds: 400)));
    final s = await IntradaySeriesCache.instance.get(const PortfolioState(),
        now: simdi, azamiYas: const Duration(seconds: 30), zorla: true);
    // Boş defterin serisi boştur; eski seri dönmemeli.
    expect(s, isNot(eski));
  });

  test('Bugün kartı nabızda zorla tazeler', () {
    final src = ekranKaynagiSync('lib/widgets/bugun_karti.dart')
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(src.contains('await _seriYukle(nabiz: true)'), isTrue,
        reason: 'nabız dinleyicisi önbelleği yaşa bakmadan tazelemeli');
    expect(src.contains('zorla: nabiz'), isTrue,
        reason: 'bayrak önbelleğe iletilmeli');
  });
}
